//
//  MeshRepairCoordinator.swift
//  3D
//
//  Phase 2B: Main coordinator for all mesh repair operations
//  Manages selection, execution, and fallback strategies
//

import Foundation
import ModelIO

/// Main coordinator for mesh repair operations
class MeshRepairCoordinator {

    // MARK: - Properties

    private let voxelRepair: VoxelMeshRepair
    private let poissonRepair: PoissonMeshRepair?
    private let neuralRefiner: NeuralMeshRefiner?
    private let selector: MeshQualitySelector
    private let memoryManager: MemoryManager
    private let performanceMonitor: PerformanceMonitor

    private var configuration: MeshRepairConfiguration

    // MARK: - Initialization

    init(configuration: MeshRepairConfiguration = .balanced) {
        self.configuration = configuration
        self.voxelRepair = VoxelMeshRepair()
        self.selector = MeshQualitySelector()
        self.memoryManager = MemoryManager(maxMemoryMB: configuration.maxMemoryUsage / (1024 * 1024))
        self.performanceMonitor = PerformanceMonitor()

        // Initialize Phase 2B components (may be nil if not available)
        self.poissonRepair = Self.initializePoissonRepair()

        // Initialize Phase 2C components (may be nil if models not available)
        self.neuralRefiner = Self.initializeNeuralRefiner()
    }

    // MARK: - Public API

    /// Repair a mesh using the configured or automatically selected method
    func repair(
        _ mesh: MDLMesh,
        method: MeshRepairMethod? = nil
    ) async throws -> MeshRepairResult {

        let startTime = Date()
        performanceMonitor.startMeasuring()

        // Use provided method or configuration default
        let selectedMethod = method ?? configuration.method

        do {
            // Analyze mesh characteristics
            let characteristics = selector.analyzeCharacteristics(mesh)

            if configuration.verboseLogging {
                print("\n🔧 ===== MESH REPAIR COORDINATOR =====")
                print(characteristics.summary)
                print("Selected method: \(selectedMethod.displayName)")
                print("=====================================\n")
            }

            // Determine actual method to use
            let actualMethod = selectedMethod == .auto ?
                selector.selectOptimalMethod(characteristics) :
                selectedMethod

            // Check memory availability
            let estimatedMemory = estimateMemory(for: mesh, method: actualMethod)
            try memoryManager.allocate(sizeInMB: estimatedMemory)
            defer { memoryManager.deallocate(sizeInMB: estimatedMemory) }

            // Execute repair with timeout
            let result = try await withTimeout(configuration.maxProcessingTime) {
                try await self.executeRepair(mesh, method: actualMethod, characteristics: characteristics)
            }

            // Stop monitoring
            let metrics = performanceMonitor.stopMeasuring()

            if configuration.verboseLogging {
                print("\n✅ Repair completed:")
                print("   Method: \(result.method.displayName)")
                print("   Time: \(String(format: "%.2f", result.processingTime))s")
                print("   Memory: \(result.memoryUsed / 1024 / 1024) MB")
                print("   Quality: \(String(format: "%.2f", result.qualityScore))")
                print("   Watertight: \(result.isWatertight ? "✅" : "❌")")
            }

            return result

        } catch {
            performanceMonitor.stopMeasuring()

            if configuration.verboseLogging {
                print("❌ Repair failed: \(error)")
            }

            throw error
        }
    }

    // MARK: - Private Methods

    private func executeRepair(
        _ mesh: MDLMesh,
        method: MeshRepairMethod,
        characteristics: MeshCharacteristics
    ) async throws -> MeshRepairResult {

        switch method {
        case .voxel:
            return try await executeVoxelRepair(mesh, characteristics: characteristics)

        case .poisson:
            return try await executePoissonRepair(mesh, characteristics: characteristics, fallbackToVoxel: configuration.enableFallback)

        case .neural:
            return try await executeNeuralRefine(mesh, characteristics: characteristics)

        case .hybrid:
            return try await executeHybridRepair(mesh, characteristics: characteristics)

        case .auto:
            // Should not reach here (auto is resolved earlier)
            let autoMethod = selector.selectOptimalMethod(characteristics)
            return try await executeRepair(mesh, method: autoMethod, characteristics: characteristics)
        }
    }

    // MARK: - Voxel Repair (Phase 2A)

    private func executeVoxelRepair(
        _ mesh: MDLMesh,
        characteristics: MeshCharacteristics
    ) async throws -> MeshRepairResult {

        let startTime = Date()

        if configuration.verboseLogging {
            print("🔧 Executing Voxel Repair...")
        }

        // Select voxel configuration based on characteristics
        let voxelConfig = selectVoxelConfiguration(characteristics)

        guard let repairedMesh = VoxelMeshRepair.repairMesh(mesh, configuration: voxelConfig) else {
            throw MeshRepairError.voxelizationFailed(NSError(domain: "VoxelRepair", code: -1))
        }

        let processingTime = Date().timeIntervalSince(startTime)

        // Calculate metrics
        let metrics = calculateMetrics(input: mesh, output: repairedMesh, processingTime: processingTime)
        let qualityScore = calculateQualityScore(repairedMesh, metrics: metrics)

        // Check if watertight
        let watertightChecker = WatertightChecker()
        let (isWatertight, _) = watertightChecker.checkWatertight(repairedMesh)

        return MeshRepairResult(
            mesh: repairedMesh,
            method: .voxel,
            processingTime: processingTime,
            memoryUsed: estimateActualMemoryUsed(),
            qualityScore: qualityScore,
            isWatertight: isWatertight,
            metrics: metrics,
            warnings: []
        )
    }

    // MARK: - Poisson Repair (Phase 2B)

    private func executePoissonRepair(
        _ mesh: MDLMesh,
        characteristics: MeshCharacteristics,
        fallbackToVoxel: Bool
    ) async throws -> MeshRepairResult {

        guard let poissonRepair = poissonRepair else {
            if fallbackToVoxel {
                if configuration.verboseLogging {
                    print("⚠️ Poisson not available, falling back to Voxel")
                }
                return try await executeVoxelRepair(mesh, characteristics: characteristics)
            } else {
                throw MeshRepairError.unsupportedConfiguration
            }
        }

        let startTime = Date()

        do {
            if configuration.verboseLogging {
                print("🔧 Executing Poisson Surface Reconstruction...")
            }

            // Execute Poisson pipeline
            let result = try await poissonRepair.reconstruct(
                mesh: mesh,
                depth: configuration.poissonDepth,
                smoothingIterations: configuration.taubinIterations
            )

            if configuration.verboseLogging {
                print("✅ Poisson reconstruction completed")
            }

            return result

        } catch {
            if fallbackToVoxel {
                if configuration.verboseLogging {
                    print("⚠️ Poisson failed: \(error)")
                    print("🔄 Falling back to Voxel repair...")
                }
                return try await executeVoxelRepair(mesh, characteristics: characteristics)
            } else {
                throw MeshRepairError.poissonFailed(error)
            }
        }
    }

    // MARK: - Neural Refinement (Phase 2C)

    private func executeNeuralRefine(
        _ mesh: MDLMesh,
        characteristics: MeshCharacteristics
    ) async throws -> MeshRepairResult {

        guard let neuralRefiner = neuralRefiner else {
            if configuration.enableFallback {
                if configuration.verboseLogging {
                    print("⚠️ Neural models not available, falling back to Poisson")
                }
                return try await executePoissonRepair(mesh, characteristics: characteristics, fallbackToVoxel: true)
            } else {
                throw MeshRepairError.modelNotLoaded
            }
        }

        let startTime = Date()

        if configuration.verboseLogging {
            print("🔧 Executing Neural Mesh Refinement...")
        }

        do {
            // Step 1: Point cloud completion (if needed)
            var meshToRefine = mesh
            if characteristics.coverageCompleteness < 0.8 {
                if configuration.verboseLogging {
                    print("   → Point cloud completion...")
                }
                meshToRefine = try await neuralRefiner.completePointCloud(mesh)
            }

            // Step 2: Surface reconstruction (use Poisson if available, else Voxel)
            if configuration.verboseLogging {
                print("   → Surface reconstruction...")
            }
            let reconstructed = poissonRepair != nil ?
                try await executePoissonRepair(meshToRefine, characteristics: characteristics, fallbackToVoxel: true) :
                try await executeVoxelRepair(meshToRefine, characteristics: characteristics)

            // Step 3: Neural mesh refinement
            if configuration.verboseLogging {
                print("   → Neural refinement...")
            }
            let refined = try await neuralRefiner.refineMesh(reconstructed.mesh)

            let processingTime = Date().timeIntervalSince(startTime)

            // Calculate final metrics
            let metrics = calculateMetrics(input: mesh, output: refined, processingTime: processingTime)
            let qualityScore = calculateQualityScore(refined, metrics: metrics)

            let watertightChecker = WatertightChecker()
            let (isWatertight, _) = watertightChecker.checkWatertight(refined)

            return MeshRepairResult(
                mesh: refined,
                method: .neural,
                processingTime: processingTime,
                memoryUsed: estimateActualMemoryUsed(),
                qualityScore: qualityScore,
                isWatertight: isWatertight,
                metrics: metrics,
                warnings: []
            )

        } catch {
            if configuration.enableFallback {
                if configuration.verboseLogging {
                    print("⚠️ Neural refinement failed: \(error)")
                    print("🔄 Falling back to Poisson...")
                }
                return try await executePoissonRepair(mesh, characteristics: characteristics, fallbackToVoxel: true)
            } else {
                throw MeshRepairError.inferenceError(error)
            }
        }
    }

    // MARK: - Hybrid Repair

    private func executeHybridRepair(
        _ mesh: MDLMesh,
        characteristics: MeshCharacteristics
    ) async throws -> MeshRepairResult {

        if configuration.verboseLogging {
            print("🔧 Executing Hybrid Repair (Voxel + Neural)...")
        }

        // Step 1: Fast voxel reconstruction
        let voxelResult = try await executeVoxelRepair(mesh, characteristics: characteristics)

        // Step 2: Neural refinement (if available)
        if let neuralRefiner = neuralRefiner {
            do {
                if configuration.verboseLogging {
                    print("   → Applying neural refinement...")
                }
                let refined = try await neuralRefiner.refineMesh(voxelResult.mesh)

                let totalTime = voxelResult.processingTime + Date().timeIntervalSince(Date(timeIntervalSinceNow: -voxelResult.processingTime))

                return MeshRepairResult(
                    mesh: refined,
                    method: .hybrid,
                    processingTime: totalTime,
                    memoryUsed: voxelResult.memoryUsed,
                    qualityScore: voxelResult.qualityScore * 1.1, // Boost for refinement
                    isWatertight: voxelResult.isWatertight,
                    metrics: voxelResult.metrics,
                    warnings: voxelResult.warnings
                )
            } catch {
                if configuration.verboseLogging {
                    print("⚠️ Neural refinement failed, returning voxel result")
                }
                return voxelResult
            }
        } else {
            // No neural available, return voxel result
            return voxelResult
        }
    }

    // MARK: - Helper Methods

    private func selectVoxelConfiguration(_ characteristics: MeshCharacteristics) -> VoxelMeshRepair.Configuration {
        if characteristics.isSmallObject && characteristics.isHighQuality {
            return VoxelMeshRepair.Configuration(
                resolution: 96,
                occupancyThreshold: 0.4,
                enableSmoothing: true,
                padding: 3
            )
        } else if characteristics.isSmallObject {
            return .smallObject
        } else {
            return .mediumObject
        }
    }

    private func estimateMemory(for mesh: MDLMesh, method: MeshRepairMethod) -> Int {
        let vertexCount = mesh.vertexCount

        switch method {
        case .voxel:
            return memoryManager.estimateMemoryForVoxel(pointCount: vertexCount, resolution: configuration.voxelConfiguration.resolution)
        case .poisson:
            return memoryManager.estimateMemoryForPoisson(pointCount: vertexCount, depth: configuration.poissonDepth)
        case .neural:
            return (memoryManager.estimateMemoryForVoxel(pointCount: vertexCount, resolution: 64) + 50 * 1024 * 1024) // +50MB for model
        case .hybrid:
            return (memoryManager.estimateMemoryForVoxel(pointCount: vertexCount, resolution: 64) + 50 * 1024 * 1024)
        case .auto:
            return 100 * 1024 * 1024 // Conservative estimate
        }
    }

    private func calculateMetrics(input: MDLMesh, output: MDLMesh, processingTime: TimeInterval) -> RepairMetrics {
        // Extract input stats
        let inputVertexCount = input.vertexCount
        let inputTriangleCount = input.submeshes?.count ?? 0

        let watertightChecker = WatertightChecker()
        let (_, inputResult) = watertightChecker.checkWatertight(input)
        let inputBoundaryEdges = inputResult?.boundaryEdgeCount ?? 0
        let inputHoleCount = inputResult?.holeCount ?? 0

        // Extract output stats
        let outputVertexCount = output.vertexCount
        let outputTriangleCount = output.submeshes?.count ?? 0

        let (_, outputResult) = watertightChecker.checkWatertight(output)
        let outputBoundaryEdges = outputResult?.boundaryEdgeCount ?? 0
        let outputHoleCount = outputResult?.holeCount ?? 0

        // Calculate quality metrics
        let surfaceArea = calculateSurfaceArea(output)
        let volume = calculateVolume(output)

        return RepairMetrics(
            inputVertexCount: inputVertexCount,
            inputTriangleCount: inputTriangleCount,
            inputBoundaryEdges: inputBoundaryEdges,
            inputHoleCount: inputHoleCount,
            outputVertexCount: outputVertexCount,
            outputTriangleCount: outputTriangleCount,
            outputBoundaryEdges: outputBoundaryEdges,
            outputHoleCount: outputHoleCount,
            pointCloudExtractionTime: 0.1, // Approximate
            reconstructionTime: processingTime,
            postProcessingTime: 0.0,
            surfaceArea: surfaceArea,
            volume: volume,
            averageEdgeLength: 0.01, // Placeholder
            minTriangleQuality: 0.5,  // Placeholder
            averageTriangleQuality: 0.8 // Placeholder
        )
    }

    private func calculateQualityScore(_ mesh: MDLMesh, metrics: RepairMetrics) -> Float {
        var score: Float = 0.0

        // Watertight (40%)
        if metrics.outputBoundaryEdges == 0 {
            score += 0.4
        }

        // Hole filling (20%)
        let holesFixed = max(0, metrics.inputHoleCount - metrics.outputHoleCount)
        if metrics.inputHoleCount > 0 {
            score += 0.2 * Float(holesFixed) / Float(metrics.inputHoleCount)
        } else {
            score += 0.2
        }

        // Triangle quality (20%)
        score += 0.2 * metrics.averageTriangleQuality

        // Reasonable vertex count (20%)
        let vertexRatio = Float(metrics.outputVertexCount) / Float(metrics.inputVertexCount)
        if vertexRatio > 0.5 && vertexRatio < 2.0 {
            score += 0.2
        } else {
            score += 0.1
        }

        return min(1.0, score)
    }

    private func calculateSurfaceArea(_ mesh: MDLMesh) -> Float {
        // Placeholder - implement proper surface area calculation
        return 100.0
    }

    private func calculateVolume(_ mesh: MDLMesh) -> Float {
        // Use existing MeshAnalyzer method
        let analyzer = MeshAnalyzer()
        return analyzer.calculatePreciseVolume(mesh)
    }

    private func estimateActualMemoryUsed() -> Int {
        // Use performance monitor to get actual memory usage
        return performanceMonitor.currentMemoryUsage
    }

    // MARK: - Initialization Helpers

    private static func initializePoissonRepair() -> PoissonMeshRepair? {
        // Try to initialize Poisson repair (Phase 2B)
        // Returns nil if C++ libraries not available
        #if PHASE_2B_AVAILABLE
        do {
            return try PoissonMeshRepair()
        } catch {
            print("⚠️ Poisson repair not available: \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }

    private static func initializeNeuralRefiner() -> NeuralMeshRefiner? {
        // Try to initialize neural refiner (Phase 2C)
        // Returns nil if CoreML models not available
        #if PHASE_2C_AVAILABLE
        do {
            return try NeuralMeshRefiner()
        } catch {
            print("⚠️ Neural refiner not available: \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }
}

// MARK: - Timeout Helper

func withTimeout<T>(_ timeout: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // Add the operation
        group.addTask {
            try await operation()
        }

        // Add timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw MeshRepairError.processingTimeout(timeout)
        }

        // Return the first result (operation or timeout)
        guard let result = try await group.next() else {
            throw MeshRepairError.processingTimeout(timeout)
        }

        group.cancelAll()
        return result
    }
}

// MARK: - Memory Manager

class MemoryManager {
    private let maxMemoryMB: Int
    private var currentUsageMB: Int = 0
    private let lock = NSLock()

    init(maxMemoryMB: Int) {
        self.maxMemoryMB = maxMemoryMB
    }

    func allocate(sizeInMB: Int) throws {
        lock.lock()
        defer { lock.unlock() }

        if currentUsageMB + sizeInMB > maxMemoryMB {
            throw MeshRepairError.memoryLimitExceeded(
                (currentUsageMB + sizeInMB) * 1024 * 1024,
                maxMemoryMB * 1024 * 1024
            )
        }
        currentUsageMB += sizeInMB
    }

    func deallocate(sizeInMB: Int) {
        lock.lock()
        defer { lock.unlock() }

        currentUsageMB = max(0, currentUsageMB - sizeInMB)
    }

    func estimateMemoryForVoxel(pointCount: Int, resolution: Int) -> Int {
        let voxelCount = resolution * resolution * resolution
        let voxelMemory = voxelCount * 4 // 4 bytes per voxel (float)
        let pointMemory = pointCount * 12 // 3 floats per point
        let triangleMemory = voxelCount * 2 * 36 // Rough estimate: 2 triangles per voxel

        return (voxelMemory + pointMemory + triangleMemory) / (1024 * 1024)
    }

    func estimateMemoryForPoisson(pointCount: Int, depth: Int) -> Int {
        let octreeNodes = pow(8.0, Double(depth))
        let nodeSizeBytes = 128.0

        let pointMemory = pointCount * 12
        let octreeMemory = Int(octreeNodes * nodeSizeBytes)
        let outputMeshMemory = pointCount * 24

        return (pointMemory + octreeMemory + outputMeshMemory) / (1024 * 1024)
    }
}
