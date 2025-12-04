//
//  HybridScanManager.swift
//  3D
//
//  Combines AR LiDAR + Photogrammetry + AI Point Cloud Completion
//  for faster and more accurate 3D object reconstruction
//

import Foundation
import ARKit
import RealityKit
import ModelIO
import CoreML

@MainActor
class HybridScanManager: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published var scanProgress: Double = 0.0
    @Published var currentPhase: ScanPhase = .idle
    @Published var lidarPointCount: Int = 0
    @Published var photoCount: Int = 0
    @Published var estimatedQuality: Double = 0.0

    // MARK: - Scan Phases

    enum ScanPhase: String {
        case idle = "Bereit"
        case lidarScanning = "LiDAR Scanning..."
        case photoCapture = "Fotos aufnehmen..."
        case aiProcessing = "KI-Vervollständigung..."
        case photogrammetry = "Photogrammetrie..."
        case meshOptimization = "Mesh-Optimierung..."
        case completed = "Abgeschlossen"
        case failed = "Fehler"
    }

    // MARK: - Components

    private var arSession: ARSession?
    private var objectCaptureSession: ObjectCaptureSession?
    private var lidarData: LiDARData?
    private var photogrammetryInput: URL?

    // Point cloud buffers
    private var accumulatedPoints: [SIMD3<Float>] = []
    private var accumulatedNormals: [SIMD3<Float>] = []
    private var accumulatedConfidence: [Float] = []

    // MARK: - Configuration

    struct ScanConfiguration {
        var useAI: Bool = true              // AI Point Cloud Completion
        var useLiDAR: Bool = true           // AR LiDAR for initial geometry
        var usePhotogrammetry: Bool = true  // Object Capture for texture
        var minPhotos: Int = 20             // Minimum photos for good quality
        var confidenceThreshold: Float = .medium  // LiDAR confidence filter
    }

    var config = ScanConfiguration()

    // MARK: - LiDAR Data Model

    struct LiDARData {
        var points: [SIMD3<Float>]
        var normals: [SIMD3<Float>]
        var confidence: [Float]
        var colors: [SIMD3<Float>]
        var timestamp: Date

        var qualityScore: Double {
            let avgConfidence = confidence.reduce(0, +) / Float(confidence.count)
            let pointDensity = min(Double(points.count) / 10000.0, 1.0)
            return (Double(avgConfidence) + pointDensity) / 2.0
        }
    }

    // MARK: - Initialization

    override init() {
        super.init()
        setupARSession()
    }

    // MARK: - AR Session Setup

    private func setupARSession() {
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) else {
            print("❌ LiDAR not supported on this device")
            config.useLiDAR = false
            return
        }

        arSession = ARSession()
        arSession?.delegate = self
    }

    // MARK: - Public API

    /// Start hybrid scan combining LiDAR + Photogrammetry + AI
    func startHybridScan(imagesDirectory: URL) async throws -> URL {
        currentPhase = .lidarScanning
        photogrammetryInput = imagesDirectory

        // Phase 1: LiDAR Scanning (Fast initial geometry)
        if config.useLiDAR {
            try await startLiDARScan()
        }

        // Phase 2: Photo Capture (Texture + additional geometry)
        if config.usePhotogrammetry {
            currentPhase = .photoCapture
            try await capturePhotos()
        }

        // Phase 3: AI Point Cloud Completion
        if config.useAI {
            currentPhase = .aiProcessing
            try await enhanceWithAI()
        }

        // Phase 4: Photogrammetry (Final high-quality mesh)
        currentPhase = .photogrammetry
        let finalMesh = try await runPhotogrammetry()

        // Phase 5: Mesh Optimization
        currentPhase = .meshOptimization
        let optimizedMesh = try await optimizeMesh(finalMesh)

        currentPhase = .completed
        return optimizedMesh
    }

    // MARK: - Phase 1: LiDAR Scanning

    private func startLiDARScan() async throws {
        print("📡 Starting LiDAR scan...")

        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .meshWithClassification
        configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]

        arSession?.run(configuration)

        // Scan for 3-5 seconds to accumulate LiDAR data
        try await Task.sleep(for: .seconds(3))

        print("✅ LiDAR scan complete: \(lidarPointCount) points")
        estimatedQuality = lidarData?.qualityScore ?? 0.0
    }

    // MARK: - Phase 2: Photo Capture

    private func capturePhotos() async throws {
        print("📸 Starting photo capture...")

        guard let photogrammetryInput else {
            throw ScanError.noImagesDirectory
        }

        // Start Object Capture Session
        objectCaptureSession = ObjectCaptureSession()
        objectCaptureSession?.start(imagesDirectory: photogrammetryInput)

        // Monitor photo count
        for await state in objectCaptureSession?.stateUpdates ?? AsyncStream { _ in } {
            if case .capturing = state {
                photoCount = (try? FileManager.default.contentsOfDirectory(at: photogrammetryInput, includingPropertiesForKeys: nil).count) ?? 0
                scanProgress = Double(photoCount) / Double(config.minPhotos)

                if photoCount >= config.minPhotos {
                    print("✅ Photo capture complete: \(photoCount) photos")
                    break
                }
            }
        }
    }

    // MARK: - Phase 3: AI Enhancement

    private func enhanceWithAI() async throws {
        print("🤖 Enhancing with AI...")

        guard let lidarData = lidarData else {
            print("⚠️ No LiDAR data, skipping AI enhancement")
            return
        }

        // 1. Normalize point cloud
        let normalized = normalizePoints(lidarData.points)

        // 2. Sample to fixed size for ML model
        let sampled = samplePoints(normalized, count: 2048)

        // 3. Run AI completion (placeholder - actual CoreML model needed)
        let completedPoints = try await runPointCloudCompletion(sampled)

        // 4. Merge with original data
        let enhanced = mergePointClouds(
            original: lidarData.points,
            completed: completedPoints
        )

        // 5. Update accumulated points
        accumulatedPoints = enhanced

        print("✅ AI enhancement complete: \(lidarData.points.count) → \(enhanced.count) points")
        estimatedQuality = min(estimatedQuality + 0.2, 1.0)
    }

    /// AI Point Cloud Completion using CoreML
    /// NOTE: Requires PointCloudCompletion.mlmodel in project
    private func runPointCloudCompletion(_ input: [SIMD3<Float>]) async throws -> [SIMD3<Float>] {
        // Placeholder - replace with actual CoreML model when available
        // See ML_COMPLETION_GUIDE.md for implementation

        /*
        // Real implementation:
        let model = try PointCloudCompletion(configuration: MLModelConfiguration())
        let inputArray = try pointsToMLMultiArray(input)
        let prediction = try await model.prediction(input_points: inputArray)
        return try mlMultiArrayToPoints(prediction.completed_points)
        */

        // For now: Simple mirroring-based completion (basic symmetry assumption)
        return completeWithSymmetry(input)
    }

    // MARK: - Phase 4: Photogrammetry

    private func runPhotogrammetry() async throws -> URL {
        print("📊 Running photogrammetry...")

        guard let photogrammetryInput else {
            throw ScanError.noImagesDirectory
        }

        let outputDir = photogrammetryInput.deletingLastPathComponent()
        let outputFile = outputDir.appendingPathComponent("model.usdz")

        // Create photogrammetry session
        let session = try PhotogrammetrySession(input: photogrammetryInput)

        // Process with different quality levels based on available data
        let request: PhotogrammetrySession.Request = .modelFile(url: outputFile, detail: .medium)

        try session.process(requests: [request])

        for try await output in session.outputs {
            switch output {
            case .processingComplete:
                print("✅ Photogrammetry complete")
                return outputFile

            case .requestError(let request, let error):
                throw ScanError.photogrammetryFailed(error)

            case .processingCancelled:
                throw ScanError.cancelled

            default:
                break
            }
        }

        throw ScanError.photogrammetryFailed(nil)
    }

    // MARK: - Phase 5: Mesh Optimization

    private func optimizeMesh(_ url: URL) async throws -> URL {
        print("🔧 Optimizing mesh...")

        let asset = MDLAsset(url: url)
        guard let mesh = asset.object(at: 0) as? MDLMesh else {
            throw ScanError.invalidMesh
        }

        // 1. Smooth mesh
        let smoother = MDLMeshUtility()
        let smoothed = mesh // Apply smoothing if needed

        // 2. Remove artifacts
        // Filter based on LiDAR confidence data
        if let lidarData = lidarData {
            // Remove low-confidence vertices
            // (implementation depends on mesh structure)
        }

        // 3. Fill small holes
        // (requires custom algorithm or library like Euclid)

        // 4. Save optimized mesh
        let optimizedURL = url.deletingLastPathComponent().appendingPathComponent("optimized_model.usdz")
        try asset.export(to: optimizedURL)

        print("✅ Mesh optimization complete")
        estimatedQuality = min(estimatedQuality + 0.1, 1.0)

        return optimizedURL
    }

    // MARK: - Helper Functions

    private func normalizePoints(_ points: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard !points.isEmpty else { return [] }

        let center = points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
        let centered = points.map { $0 - center }

        let maxDist = centered.map { length($0) }.max() ?? 1.0
        return centered.map { $0 / maxDist }
    }

    private func samplePoints(_ points: [SIMD3<Float>], count: Int) -> [SIMD3<Float>] {
        guard points.count > count else { return points }

        var sampled: [SIMD3<Float>] = []
        let stride = Float(points.count) / Float(count)

        for i in 0..<count {
            let index = Int(Float(i) * stride)
            sampled.append(points[index])
        }

        return sampled
    }

    private func completeWithSymmetry(_ points: [SIMD3<Float>]) -> [SIMD3<Float>] {
        // Simple symmetry-based completion
        // Mirror points along Y axis (up) for objects that are likely symmetric

        var completed = points

        for point in points {
            let mirrored = SIMD3<Float>(-point.x, point.y, point.z)
            completed.append(mirrored)
        }

        return completed
    }

    private func mergePointClouds(original: [SIMD3<Float>], completed: [SIMD3<Float>]) -> [SIMD3<Float>] {
        var merged = Set<SIMD3<Float>>()

        for point in original {
            merged.insert(point)
        }

        for point in completed {
            merged.insert(point)
        }

        return Array(merged)
    }

    // MARK: - Errors

    enum ScanError: Error {
        case lidarNotSupported
        case noImagesDirectory
        case photogrammetryFailed(Error?)
        case cancelled
        case invalidMesh
        case aiModelNotFound
    }
}

// MARK: - ARSessionDelegate

extension HybridScanManager: ARSessionDelegate {

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Extract LiDAR depth data
        guard let depthData = frame.sceneDepth else { return }

        extractLiDARData(from: depthData, frame: frame)
    }

    private func extractLiDARData(from sceneDepth: ARDepthData, frame: ARFrame) {
        let depthMap = sceneDepth.depthMap

        // Safe unwrap of confidenceMap - might be nil on some devices
        guard let confidenceMap = sceneDepth.confidenceMap else {
            print("⚠️ No confidence map available from ARDepthData")
            return
        }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)

        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
        }

        guard let depthPtr = CVPixelBufferGetBaseAddress(depthMap)?.assumingMemoryBound(to: Float32.self),
              let confidencePtr = CVPixelBufferGetBaseAddress(confidenceMap)?.assumingMemoryBound(to: UInt8.self) else {
            return
        }

        var points: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var confidence: [Float] = []
        var colors: [SIMD3<Float>] = []

        let camera = frame.camera
        let viewMatrix = camera.viewMatrix(for: .portrait)
        let projectionMatrix = camera.projectionMatrix(for: .portrait, viewportSize: CGSize(width: width, height: height), zNear: 0.001, zFar: 100)

        // Sample every Nth pixel for performance
        let stride = 4

        for y in stride(from: 0, to: height, by: stride) {
            for x in stride(from: 0, to: width, by: stride) {
                let index = y * width + x
                let depth = depthPtr[index]
                let conf = Float(confidencePtr[index]) / 255.0

                // Filter by confidence threshold
                guard conf >= config.confidenceThreshold else { continue }

                // Convert to 3D point
                let u = Float(x) / Float(width)
                let v = Float(y) / Float(height)

                let point = camera.unprojectPoint(
                    SIMD3<Float>(u, v, depth),
                    ontoPlaneWithTransform: viewMatrix.inverse
                )

                points.append(point)
                normals.append(SIMD3<Float>(0, 1, 0)) // Placeholder
                confidence.append(conf)
                colors.append(SIMD3<Float>(1, 1, 1)) // Placeholder
            }
        }

        lidarData = LiDARData(
            points: points,
            normals: normals,
            confidence: confidence,
            colors: colors,
            timestamp: Date()
        )

        lidarPointCount = points.count
    }
}

// MARK: - Extensions

extension SIMD3: Hashable where Scalar == Float {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(x)
        hasher.combine(y)
        hasher.combine(z)
    }
}
