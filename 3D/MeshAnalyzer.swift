//
//  MeshAnalyzer.swift
//  3D
//
//  Precise mesh analysis for dimensions and volume calculation
//

import Foundation
import RealityKit
import ModelIO
import SceneKit
import MetalKit

@MainActor
class MeshAnalyzer: ObservableObject {

    // MARK: - Published Properties

    @Published var dimensions: Dimensions?
    @Published var volume: Double?
    @Published var boundingBox: BoundingBox?
    @Published var meshQuality: MeshQuality?
    @Published var simplifiedMesh: MDLMesh?

    // MARK: - Mesh Simplification

    private let meshSimplifier = MeshSimplifier()

    // MARK: - Models

    struct Dimensions {
        let width: Double   // X-axis (cm)
        let height: Double  // Y-axis (cm)
        let depth: Double   // Z-axis (cm)

        var description: String {
            """
            Breite: \(String(format: "%.2f", width)) cm
            Höhe: \(String(format: "%.2f", height)) cm
            Tiefe: \(String(format: "%.2f", depth)) cm
            """
        }
    }

    struct BoundingBox {
        let min: SIMD3<Float>
        let max: SIMD3<Float>
        let center: SIMD3<Float>

        var size: SIMD3<Float> {
            max - min
        }
    }

    struct MeshQuality {
        let vertexCount: Int
        let triangleCount: Int
        let surfaceArea: Double // cm²
        let watertight: Bool
        let confidence: Double // 0.0 - 1.0

        var qualityScore: String {
            switch confidence {
            case 0.9...1.0: return "Ausgezeichnet"
            case 0.7..<0.9: return "Gut"
            case 0.5..<0.7: return "Akzeptabel"
            default: return "Niedrig"
            }
        }
    }

    // MARK: - Calibration

    private var calibrationScale: Float = 1.0

    func setCalibration(realWorldSize: Float, measuredSize: Float) {
        calibrationScale = realWorldSize / measuredSize
        print("📏 Calibration set: \(calibrationScale)x")
    }

    // MARK: - Analysis

    func analyzeMesh(from url: URL) async throws {
        print("🔍 Loading USDZ from: \(url.lastPathComponent)")

        // Try multiple loading strategies for better compatibility
        var mesh: MDLMesh?

        // Strategy 1: Try MDLAsset directly
        let asset = MDLAsset(url: url)
        print("   Asset object count: \(asset.count)")

        if asset.count > 0 {
            // Try to get first object as mesh
            if let mdlMesh = asset.object(at: 0) as? MDLMesh {
                mesh = mdlMesh
                print("   ✅ Loaded as MDLMesh directly")
            }
            // Try to get as transform container (some USDZ files use this)
            else if let transform = asset.object(at: 0) as? MDLObject {
                print("   Found MDLObject, searching for child meshes...")
                mesh = findFirstMesh(in: transform)
            }
        }

        // Strategy 2: Try SceneKit as fallback
        if mesh == nil {
            print("   Trying SceneKit loader...")
            if let scnMesh = try? loadMeshViaSceneKit(url: url) {
                mesh = scnMesh
                print("   ✅ Loaded via SceneKit")
            }
        }

        guard let finalMesh = mesh else {
            print("   ❌ Could not load mesh from USDZ")
            throw AnalysisError.invalidMesh
        }

        print("   ✅ Mesh loaded successfully")
        print("   Vertices: \(finalMesh.vertexCount)")
        print("   Submeshes: \(finalMesh.submeshes?.count ?? 0)")

        await analyzeMDLMesh(finalMesh)
    }

    /// Recursively search for first mesh in object hierarchy
    private func findFirstMesh(in object: MDLObject) -> MDLMesh? {
        if let mesh = object as? MDLMesh {
            return mesh
        }

        // Check children container
        let children = object.children.objects
        for i in 0..<children.count {
            if let child = children[i] as? MDLObject {
                if let mesh = findFirstMesh(in: child) {
                    return mesh
                }
            }
        }

        return nil
    }

    /// Load mesh via SceneKit (more robust for various USDZ formats)
    private func loadMeshViaSceneKit(url: URL) throws -> MDLMesh? {
        let scene = try SCNScene(url: url, options: nil)

        // Create MDLAsset from entire scene
        guard let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }

        let allocator = MTKMeshBufferAllocator(device: device)
        let mdlAsset = MDLAsset(url: url, vertexDescriptor: nil, bufferAllocator: allocator)

        // Return first mesh from asset
        if mdlAsset.count > 0, let mdlMesh = mdlAsset.object(at: 0) as? MDLMesh {
            return mdlMesh
        }

        return nil
    }

    func analyzeMDLMesh(_ mesh: MDLMesh) async {
        print("🔍 ========== MESH ANALYSIS STARTED ==========")
        print("   Vertices: \(mesh.vertexCount)")
        print("   Submeshes: \(mesh.submeshes?.count ?? 0)")

        // PHASE 1: Check if mesh is watertight
        let (watertight, watertightResult) = checkWatertight(mesh)

        // Determine which mesh to use for analysis
        var meshToAnalyze = mesh

        // PHASE 2: Repair mesh if needed (using voxelization)
        if !watertight {
            print("""
            🔧 Mesh is NOT watertight - applying Voxel Repair
            - Holes detected: \(watertightResult.estimatedHoleCount)
            - Quality score: \(String(format: "%.2f", watertightResult.qualityScore))
            """)

            // Apply voxel-based repair
            if let repairedMesh = VoxelMeshRepair.repairMesh(mesh, configuration: .smallObject) {
                meshToAnalyze = repairedMesh

                // Verify repair
                let (repairedWatertight, repairedResult) = checkWatertight(repairedMesh)
                if repairedWatertight {
                    print("   ✅ Mesh successfully repaired and is now watertight!")
                } else {
                    print("   ⚠️ Mesh partially repaired (quality: \(String(format: "%.2f", repairedResult.qualityScore)))")
                }
            } else {
                print("   ⚠️ Voxel repair failed, using original mesh")
            }
        } else {
            print("✅ Mesh is watertight, no repair needed")
        }

        // Calculate bounding box (off main thread)
        let bbox = calculateBoundingBox(meshToAnalyze)

        // Calculate dimensions (convert to cm and apply calibration)
        let width = Double(bbox.size.x * calibrationScale * 100)
        let height = Double(bbox.size.y * calibrationScale * 100)
        let depth = Double(bbox.size.z * calibrationScale * 100)

        let dims = Dimensions(
            width: width,
            height: height,
            depth: depth
        )

        // Calculate volume using PRECISE signed volume method (not just bounding box!)
        let volumeCm3 = calculatePreciseVolume(meshToAnalyze)

        print("📐 Volume Calculation:")
        print("   - Bounding Box Volume: \(width * height * depth) cm³ (simplified)")
        print("   - Precise Volume: \(volumeCm3) cm³ (signed volume method)")
        print("   - Calibration Factor Applied: \(calibrationScale)³")

        // Analyze mesh quality
        self.meshQuality = await analyzeMeshQuality(meshToAnalyze)

        // Update published properties
        self.boundingBox = bbox
        self.dimensions = dims
        self.volume = volumeCm3

        print("""
        📊 Mesh Analysis Complete:
        - Dimensions: \(width)×\(height)×\(depth) cm
        - Volume: \(volumeCm3) cm³
        - Quality: \(meshQuality?.qualityScore ?? "Unknown")
        """)

        print("🔍 ========== MESH ANALYSIS FINISHED ==========")
        print("")
    }

    // MARK: - Bounding Box Calculation

    private func calculateBoundingBox(_ mesh: MDLMesh) -> BoundingBox {
        var minPoint = SIMD3<Float>(Float.infinity, Float.infinity, Float.infinity)
        var maxPoint = SIMD3<Float>(-Float.infinity, -Float.infinity, -Float.infinity)

        // Iterate through all vertices
        for submesh in mesh.submeshes ?? [] {
            guard submesh is MDLSubmesh else { continue }

            // Get vertex buffer with safe access
            guard let vertexBuffer = mesh.vertexBuffers.first else { continue }
            let vertexData = vertexBuffer.map().bytes
            let bufferSize = vertexBuffer.length

            let vertexCount = mesh.vertexCount
            guard let layout = mesh.vertexDescriptor.layouts.object(at: 0) as? MDLVertexBufferLayout else { continue }
            let stride = layout.stride

            for i in 0..<vertexCount {
                // Safe memory access with bounds checking
                do {
                    let vertex = try safeLoadVertex(from: vertexData, index: i, stride: stride, bufferSize: bufferSize)
                    minPoint = min(minPoint, vertex)
                    maxPoint = max(maxPoint, vertex)
                } catch {
                    print("⚠️ Warning: Skipping vertex \(i) due to buffer bounds error: \(error)")
                    continue
                }
            }
        }

        let center = (minPoint + maxPoint) / 2

        return BoundingBox(min: minPoint, max: maxPoint, center: center)
    }

    // MARK: - Volume Calculation

    /// Calculate precise volume using signed volume method (divergence theorem)
    /// This is the most accurate method for closed (watertight) meshes
    private func calculatePreciseVolume(_ mesh: MDLMesh) -> Double {
        // Signed volume calculation using divergence theorem
        // For a closed mesh, sum of signed volumes of tetrahedra = mesh volume
        var volume: Double = 0.0

        for submesh in mesh.submeshes ?? [] {
            guard let submesh = submesh as? MDLSubmesh else { continue }

            // Get index buffer with safe access
            let indexBuffer = submesh.indexBuffer
            let indexData = indexBuffer.map().bytes
            let indexBufferSize = indexBuffer.length
            let indexCount = submesh.indexCount

            // Get vertex buffer with safe access
            guard let vertexBuffer = mesh.vertexBuffers.first else { continue }
            let vertexData = vertexBuffer.map().bytes
            let vertexBufferSize = vertexBuffer.length
            guard let layout = mesh.vertexDescriptor.layouts.object(at: 0) as? MDLVertexBufferLayout else { continue }
            let strideValue = layout.stride

            // Calculate signed volume for each triangle
            for i in stride(from: 0, to: indexCount, by: 3) {
                // Safe memory access with bounds checking
                do {
                    let idx0 = try safeLoadIndex(from: indexData, index: i, bufferSize: indexBufferSize)
                    let idx1 = try safeLoadIndex(from: indexData, index: i + 1, bufferSize: indexBufferSize)
                    let idx2 = try safeLoadIndex(from: indexData, index: i + 2, bufferSize: indexBufferSize)

                    let v0 = try safeLoadVertex(from: vertexData, index: Int(idx0), stride: strideValue, bufferSize: vertexBufferSize)
                    let v1 = try safeLoadVertex(from: vertexData, index: Int(idx1), stride: strideValue, bufferSize: vertexBufferSize)
                    let v2 = try safeLoadVertex(from: vertexData, index: Int(idx2), stride: strideValue, bufferSize: vertexBufferSize)

                    // Signed volume of tetrahedron formed by triangle and origin
                    // Formula: V = (1/6) * |a · (b × c)|
                    let signedVolume = Double(dot(v0, cross(v1, v2))) / 6.0
                    volume += signedVolume
                } catch {
                    print("⚠️ Warning: Skipping triangle at index \(i) due to buffer bounds error: \(error)")
                    continue
                }
            }
        }

        // CRITICAL: Apply calibration factor CUBED (volume scales with the cube of linear scale)
        // If calibration = 0.95, volume needs *= 0.95³ = 0.857
        let calibratedVolume = abs(volume) * pow(Double(calibrationScale), 3)

        // Convert from m³ to cm³ (multiply by 1,000,000)
        let volumeCm3 = calibratedVolume * 1_000_000

        print("""
        📊 Volume Calculation:
        - Raw volume: \(abs(volume)) m³
        - Calibration factor: \(calibrationScale) (cubed: \(pow(calibrationScale, 3)))
        - Calibrated volume: \(calibratedVolume) m³
        - Final volume: \(volumeCm3) cm³
        """)

        return volumeCm3
    }

    /// Alternative: Calculate volume using voxelization (for non-watertight meshes)
    /// More robust but slightly less accurate
    /// Performance: O(resolution³ × triangles) - expensive! Default resolution reduced from 128 to 64
    /// TODO: Implement Octree or BVH spatial partitioning for 20-50x speedup
    private func calculateVoxelVolume(_ mesh: MDLMesh, resolution: Int = 64) -> Double {
        guard let bbox = boundingBox else { return 0 }

        let size = bbox.size
        let voxelSize = max(size.x, size.y, size.z) / Float(resolution)

        // Create 3D grid
        var filledVoxels = 0

        // Sample points in 3D grid
        for x in 0..<resolution {
            for y in 0..<resolution {
                for z in 0..<resolution {
                    let point = SIMD3<Float>(
                        bbox.min.x + Float(x) * voxelSize,
                        bbox.min.y + Float(y) * voxelSize,
                        bbox.min.z + Float(z) * voxelSize
                    )

                    if isPointInsideMesh(point, mesh: mesh) {
                        filledVoxels += 1
                    }
                }
            }
        }

        // Calculate volume from voxel count
        let voxelVolume = Double(voxelSize * voxelSize * voxelSize)
        let totalVolume = Double(filledVoxels) * voxelVolume

        // Apply calibration and convert to cm³
        let calibratedVolume = totalVolume * pow(Double(calibrationScale), 3) * 1_000_000

        return calibratedVolume
    }

    /// Check if a point is inside the mesh using ray casting
    private func isPointInsideMesh(_ point: SIMD3<Float>, mesh: MDLMesh) -> Bool {
        // Ray casting algorithm: count intersections with mesh along a ray
        // Odd number of intersections = inside, even = outside
        let rayDirection = SIMD3<Float>(1, 0, 0) // Cast ray along X-axis
        var intersectionCount = 0

        for submesh in mesh.submeshes ?? [] {
            guard let submesh = submesh as? MDLSubmesh else { continue }

            let indexBuffer = submesh.indexBuffer
            let indexData = indexBuffer.map().bytes
            let indexBufferSize = indexBuffer.length
            let indexCount = submesh.indexCount

            guard let vertexBuffer = mesh.vertexBuffers.first else { continue }
            let vertexData = vertexBuffer.map().bytes
            let vertexBufferSize = vertexBuffer.length
            guard let layout = mesh.vertexDescriptor.layouts.object(at: 0) as? MDLVertexBufferLayout else { continue }
            let strideValue = layout.stride

            // Check each triangle with safe memory access
            for i in stride(from: 0, to: indexCount, by: 3) {
                do {
                    let idx0 = try safeLoadIndex(from: indexData, index: i, bufferSize: indexBufferSize)
                    let idx1 = try safeLoadIndex(from: indexData, index: i + 1, bufferSize: indexBufferSize)
                    let idx2 = try safeLoadIndex(from: indexData, index: i + 2, bufferSize: indexBufferSize)

                    let v0 = try safeLoadVertex(from: vertexData, index: Int(idx0), stride: strideValue, bufferSize: vertexBufferSize)
                    let v1 = try safeLoadVertex(from: vertexData, index: Int(idx1), stride: strideValue, bufferSize: vertexBufferSize)
                    let v2 = try safeLoadVertex(from: vertexData, index: Int(idx2), stride: strideValue, bufferSize: vertexBufferSize)

                    if rayIntersectsTriangle(origin: point, direction: rayDirection, v0: v0, v1: v1, v2: v2) {
                        intersectionCount += 1
                    }
                } catch {
                    // Skip this triangle if buffer access fails
                    continue
                }
            }
        }

        return intersectionCount % 2 == 1
    }

    /// Möller-Trumbore ray-triangle intersection algorithm
    private func rayIntersectsTriangle(
        origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        v0: SIMD3<Float>,
        v1: SIMD3<Float>,
        v2: SIMD3<Float>
    ) -> Bool {
        let epsilon: Float = 0.000001

        let edge1 = v1 - v0
        let edge2 = v2 - v0
        let h = cross(direction, edge2)
        let a = dot(edge1, h)

        if abs(a) < epsilon {
            return false // Ray is parallel to triangle
        }

        let f = 1.0 / a
        let s = origin - v0
        let u = f * dot(s, h)

        if u < 0.0 || u > 1.0 {
            return false
        }

        let q = cross(s, edge1)
        let v = f * dot(direction, q)

        if v < 0.0 || u + v > 1.0 {
            return false
        }

        let t = f * dot(edge2, q)

        return t > epsilon // Intersection ahead of ray origin
    }

    // MARK: - Quality Analysis

    private func analyzeMeshQuality(_ mesh: MDLMesh) async -> MeshQuality {
        let vertexCount = mesh.vertexCount
        var triangleCount = 0

        for submesh in mesh.submeshes ?? [] {
            guard let submesh = submesh as? MDLSubmesh else { continue }
            triangleCount += submesh.indexCount / 3
        }

        // Calculate surface area
        let surfaceArea = calculateSurfaceArea(mesh)

        // Check if watertight using enhanced topology analysis
        let (watertight, watertightResult) = checkWatertight(mesh)

        // Calculate confidence based on mesh characteristics
        // Now uses quality score from watertight analysis
        let confidence = calculateConfidence(
            vertexCount: vertexCount,
            triangleCount: triangleCount,
            watertight: watertight,
            qualityScore: watertightResult.qualityScore
        )

        return MeshQuality(
            vertexCount: vertexCount,
            triangleCount: triangleCount,
            surfaceArea: surfaceArea,
            watertight: watertight,
            confidence: confidence
        )
    }

    private func calculateSurfaceArea(_ mesh: MDLMesh) -> Double {
        var totalArea: Double = 0.0

        for submesh in mesh.submeshes ?? [] {
            guard let submesh = submesh as? MDLSubmesh else { continue }

            let indexBuffer = submesh.indexBuffer
            let indexData = indexBuffer.map().bytes
            let indexBufferSize = indexBuffer.length
            let indexCount = submesh.indexCount

            guard let vertexBuffer = mesh.vertexBuffers.first else { continue }
            let vertexData = vertexBuffer.map().bytes
            let vertexBufferSize = vertexBuffer.length
            guard let layout = mesh.vertexDescriptor.layouts.object(at: 0) as? MDLVertexBufferLayout else { continue }
            let strideValue = layout.stride

            // Calculate area for each triangle with safe memory access
            for i in stride(from: 0, to: indexCount, by: 3) {
                do {
                    let idx0 = try safeLoadIndex(from: indexData, index: i, bufferSize: indexBufferSize)
                    let idx1 = try safeLoadIndex(from: indexData, index: i + 1, bufferSize: indexBufferSize)
                    let idx2 = try safeLoadIndex(from: indexData, index: i + 2, bufferSize: indexBufferSize)

                    let v0 = try safeLoadVertex(from: vertexData, index: Int(idx0), stride: strideValue, bufferSize: vertexBufferSize)
                    let v1 = try safeLoadVertex(from: vertexData, index: Int(idx1), stride: strideValue, bufferSize: vertexBufferSize)
                    let v2 = try safeLoadVertex(from: vertexData, index: Int(idx2), stride: strideValue, bufferSize: vertexBufferSize)

                    // Triangle area using cross product
                    let edge1 = v1 - v0
                    let edge2 = v2 - v0
                    let crossProduct = cross(edge1, edge2)
                    let area = Double(length(crossProduct)) / 2.0
                    totalArea += area
                } catch {
                    // Skip this triangle if buffer access fails
                    continue
                }
            }
        }

        // Convert to cm² and apply calibration
        return totalArea * pow(Double(calibrationScale), 2) * 10000
    }

    private func checkWatertight(_ mesh: MDLMesh) -> (watertight: Bool, result: WatertightChecker.WatertightResult) {
        // Use enhanced watertight checker with edge manifold analysis
        let checker = WatertightChecker()
        let result = checker.analyze(mesh)

        // Print detailed diagnostic information
        print(result.description)

        // Show warning if mesh is not watertight
        if !result.isWatertight {
            print("""
            ⚠️ WARNING: Mesh is NOT watertight!
            - This will cause INCORRECT volume calculation
            - Signed Tetrahedron Sum requires closed mesh
            - Recommendation: Use Mesh Repair System
            - Current quality: \(String(format: "%.1f%%", result.qualityScore * 100))
            """)
        }

        return (result.isWatertight, result)
    }

    private func calculateConfidence(vertexCount: Int, triangleCount: Int, watertight: Bool, qualityScore: Double) -> Double {
        var confidence = 0.3

        // More vertices = higher confidence (up to a point)
        if vertexCount > 10000 {
            confidence += 0.2
        } else if vertexCount > 5000 {
            confidence += 0.1
        }

        // Good triangle density
        let ratio = Double(triangleCount) / Double(vertexCount)
        if ratio > 1.5 && ratio < 2.5 {
            confidence += 0.1
        }

        // Use enhanced quality score from watertight analysis (0.0 - 1.0)
        // This is the most important factor - a non-watertight mesh will have poor quality
        confidence += qualityScore * 0.4

        return min(confidence, 1.0)
    }

    // MARK: - Mesh Simplification Methods

    /// Simplify mesh with automatic settings
    func simplifyMeshAuto(_ mesh: MDLMesh) async -> MDLMesh? {
        guard let result = await meshSimplifier.simplifyAuto(mesh: mesh) else {
            print("⚠️ Auto-simplification failed")
            return nil
        }

        self.simplifiedMesh = result.simplifiedMesh
        print(result.summary)
        return result.simplifiedMesh
    }

    /// Simplify mesh with custom settings
    func simplifyMesh(
        _ mesh: MDLMesh,
        targetPercentage: Double,
        method: MeshSimplifier.SimplificationMethod = .balanced
    ) async -> MDLMesh? {
        guard let result = await meshSimplifier.simplify(
            mesh: mesh,
            targetPercentage: targetPercentage,
            method: method
        ) else {
            print("⚠️ Mesh simplification failed")
            return nil
        }

        self.simplifiedMesh = result.simplifiedMesh
        print(result.summary)
        return result.simplifiedMesh
    }

    /// Get simplification progress
    var simplificationProgress: Double {
        meshSimplifier.progress
    }

    /// Check if simplification is in progress
    var isSimplifying: Bool {
        meshSimplifier.isProcessing
    }

    // MARK: - Safe Memory Access Helpers

    /// Safely load a value from unsafe pointer with bounds checking
    private func safeLoad<T>(from pointer: UnsafeRawPointer, offset: Int, as type: T.Type, bufferSize: Int) throws -> T {
        let requiredSize = offset + MemoryLayout<T>.size
        guard requiredSize <= bufferSize else {
            throw AnalysisError.bufferOverflow(required: requiredSize, available: bufferSize)
        }
        return pointer.advanced(by: offset).assumingMemoryBound(to: T.self).pointee
    }

    /// Safely load SIMD3<Float> vertex with stride checking
    private func safeLoadVertex(from pointer: UnsafeRawPointer, index: Int, stride: Int, bufferSize: Int) throws -> SIMD3<Float> {
        let offset = index * stride
        return try safeLoad(from: pointer, offset: offset, as: SIMD3<Float>.self, bufferSize: bufferSize)
    }

    /// Safely load UInt32 index
    private func safeLoadIndex(from pointer: UnsafeRawPointer, index: Int, bufferSize: Int) throws -> UInt32 {
        let offset = index * MemoryLayout<UInt32>.size
        return try safeLoad(from: pointer, offset: offset, as: UInt32.self, bufferSize: bufferSize)
    }

    // MARK: - Errors

    enum AnalysisError: Error {
        case invalidMesh
        case noVertexData
        case calculationFailed
        case bufferOverflow(required: Int, available: Int)
    }
}

// MARK: - SIMD Extensions

extension SIMD3 where Scalar: Comparable {
    static func min(_ a: Self, _ b: Self) -> Self {
        SIMD3(
            Swift.min(a.x, b.x),
            Swift.min(a.y, b.y),
            Swift.min(a.z, b.z)
        )
    }

    static func max(_ a: Self, _ b: Self) -> Self {
        SIMD3(
            Swift.max(a.x, b.x),
            Swift.max(a.y, b.y),
            Swift.max(a.z, b.z)
        )
    }
}
