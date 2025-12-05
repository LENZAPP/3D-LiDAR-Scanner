//
//  CompleteScanPipeline.swift
//  3D
//
//  Complete scanning pipeline:
//  1. Object scan (ObjectCapture + LiDAR)
//  2. Calibration scan (Credit card)
//  3. AI processing (Object mask + Card detection)
//  4. Scale calculation
//  5. Volume measurement
//

import Foundation
import ARKit
import RealityKit
import ModelIO
import Vision

@MainActor
class CompleteScanPipeline: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var currentStep: ScanStep = .initial
    @Published var progress: Double = 0.0
    @Published var objectScanComplete = false
    @Published var calibrationScanComplete = false
    @Published var finalResult: ScanResult?

    // MARK: - Scan Steps

    enum ScanStep: String {
        case initial = "Bereit"
        case scanningObject = "Objekt scannen..."
        case scanningCalibration = "Kreditkarte scannen..."
        case aiProcessing = "KI-Verarbeitung..."
        case cardDetection = "Karte erkennen..."
        case scaleCalculation = "Skalierung berechnen..."
        case volumeCalculation = "Volumen berechnen..."
        case completed = "Abgeschlossen"
        case failed = "Fehler"
    }

    // MARK: - Data Models

    struct ScanResult {
        let objectMesh: URL
        let calibrationMesh: URL?
        let objectMask: CIImage?
        let cardDetection: CardDetection?
        let scaleInfo: ScaleInfo
        let measurements: Measurements
        let qualityScore: Double
    }

    struct CardDetection {
        let boundingBox: CGRect
        let corners: [CGPoint]
        let confidence: Float
        let detectedSize: SIMD2<Float> // pixels
        let realWorldSize: SIMD2<Float> // mm
    }

    struct ScaleInfo {
        let pixelsPerMM: Float
        let scaleFactor: Float
        let confidence: Float
        let method: String // "card", "lidar", "manual"
    }

    struct Measurements {
        let dimensions: SIMD3<Float> // mm
        let volume: Float // cm³
        let surfaceArea: Float // cm²
        let boundingBox: BoundingBox
    }

    struct BoundingBox {
        let min: SIMD3<Float>
        let max: SIMD3<Float>
        let center: SIMD3<Float>
        var size: SIMD3<Float> { max - min }
    }

    // MARK: - Internal State

    private var arSession: ARSession?
    private var objectCaptureSession: ObjectCaptureSession?
    private var calibrationCaptureSession: ObjectCaptureSession?

    private var objectImagesDir: URL?
    private var calibrationImagesDir: URL?

    private var objectMeshURL: URL?
    private var calibrationMeshURL: URL?

    private var lidarScale: Float = 1.0
    private var cardScale: Float = 1.0

    // Credit card reference (ISO/IEC 7810 ID-1 format)
    private let creditCardSize = SIMD2<Float>(85.60, 53.98) // mm

    // MARK: - Public API

    /// Start complete pipeline
    /// WICHTIG: Kalibrierung ZUERST, dann Objekt-Scan
    func startCompletePipeline() async throws -> ScanResult {

        // Step 1: ZUERST Kalibrierung mit Kreditkarte
        currentStep = .scanningCalibration
        try await scanCalibrationCard()
        calibrationScanComplete = true
        progress = 0.25

        // Step 2: Karte erkennen und Skalierung berechnen
        currentStep = .cardDetection
        let cardDetection = try await detectCreditCard()
        progress = 0.35

        currentStep = .scaleCalculation
        let scaleInfo = calculateScale(from: cardDetection)
        progress = 0.45

        // Step 3: JETZT Objekt scannen (mit bekannter Skalierung)
        currentStep = .scanningObject
        try await scanObject()
        objectScanComplete = true
        progress = 0.70

        // Step 4: AI Processing (Objekt-Maske extrahieren)
        currentStep = .aiProcessing
        let objectMask = try await extractObjectMask()
        progress = 0.80

        // Step 5: Volumen messen mit korrekter Skalierung
        currentStep = .volumeCalculation

        // Defensive: Verify mesh URLs were set
        guard let meshURL = objectMeshURL else {
            throw PipelineError.invalidMesh
        }

        let measurements = try await measureVolume(
            meshURL: meshURL,
            scale: scaleInfo.scaleFactor,
            mask: objectMask
        )
        progress = 0.95

        // Step 7: Create final result
        let qualityScore = calculateQualityScore(
            cardConfidence: cardDetection.confidence,
            meshQuality: measurements
        )

        let result = ScanResult(
            objectMesh: meshURL,
            calibrationMesh: calibrationMeshURL,
            objectMask: objectMask,
            cardDetection: cardDetection,
            scaleInfo: scaleInfo,
            measurements: measurements,
            qualityScore: Double(qualityScore)
        )

        currentStep = .completed
        progress = 1.0
        finalResult = result

        return result
    }

    // MARK: - Step 1: Scan Object

    private func scanObject() async throws {
        print("📦 Step 1: Scanning object...")

        // Create directories
        let baseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ObjectScan_\(UUID().uuidString)")

        let imagesDir = baseDir.appendingPathComponent("Images")
        let modelsDir = baseDir.appendingPathComponent("Models")

        objectImagesDir = imagesDir  // Store for later use

        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        // Start ARKit session for LiDAR
        startARSession()

        // Start Object Capture
        objectCaptureSession = ObjectCaptureSession()
        objectCaptureSession?.start(imagesDirectory: imagesDir)

        // Wait for user to complete scan
        // (In real app: monitor userCompletedScanPass or photo count)
        try await waitForObjectScan()

        // Process with PhotogrammetrySession
        let meshURL = modelsDir.appendingPathComponent("object.usdz")
        objectMeshURL = meshURL  // Store for later use

        try await runPhotogrammetry(
            input: imagesDir,
            output: meshURL
        )

        // Extract LiDAR scale if available
        if let arScale = extractLiDARScale() {
            lidarScale = arScale
            print("✅ LiDAR scale extracted: \(lidarScale)")
        }

        stopARSession()

        print("✅ Object scan complete")
    }

    private func startARSession() {
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) else {
            print("⚠️ LiDAR not available")
            return
        }

        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .meshWithClassification
        config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]

        arSession = ARSession()
        arSession?.run(config)
    }

    private func stopARSession() {
        arSession?.pause()
        arSession = nil
    }

    private func extractLiDARScale() -> Float? {
        // Extract true scale from ARKit world tracking
        // This gives us real-world coordinates
        return 1.0 // Placeholder - ARKit provides true scale
    }

    // MARK: - Step 2: Scan Calibration Card

    private func scanCalibrationCard() async throws {
        print("💳 Step 2: Scanning credit card for calibration...")

        let baseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CardScan_\(UUID().uuidString)")

        let imagesDir = baseDir.appendingPathComponent("Images")
        let modelsDir = baseDir.appendingPathComponent("Models")

        calibrationImagesDir = imagesDir  // Store for later use

        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        // Start Object Capture for card
        calibrationCaptureSession = ObjectCaptureSession()
        calibrationCaptureSession?.start(imagesDirectory: imagesDir)

        // Wait for card scan (fewer photos needed)
        try await waitForCalibrationScan()

        // Process card mesh
        let meshURL = modelsDir.appendingPathComponent("card.usdz")
        calibrationMeshURL = meshURL  // Store for later use

        try await runPhotogrammetry(
            input: imagesDir,
            output: meshURL,
            detail: .reduced // Card doesn't need high detail
        )

        print("✅ Card scan complete")
    }

    private func waitForObjectScan() async throws {
        // Simulate waiting for user to complete scan
        // In real implementation: monitor ObjectCaptureSession state
        try await Task.sleep(for: .seconds(2))
    }

    private func waitForCalibrationScan() async throws {
        // Simulate waiting for card scan
        try await Task.sleep(for: .seconds(1))
    }

    // MARK: - Step 3: AI Object Mask Extraction

    private func extractObjectMask() async throws -> CIImage? {
        print("🤖 Step 3: Extracting object mask with AI...")

        guard let objectImagesDir = objectImagesDir else {
            throw PipelineError.noImages
        }

        // Get first image for mask extraction
        let images = try FileManager.default.contentsOfDirectory(
            at: objectImagesDir,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension.lowercased() == "heic" || $0.pathExtension.lowercased() == "jpg" }

        guard let firstImage = images.first,
              let ciImage = CIImage(contentsOf: firstImage) else {
            throw PipelineError.invalidImage
        }

        // Use Vision framework for object segmentation
        let mask = try await performSemanticSegmentation(on: ciImage)

        print("✅ Object mask extracted")
        return mask
    }

    private func performSemanticSegmentation(on image: CIImage) async throws -> CIImage {
        // Use Vision's subject lifting or semantic segmentation
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNGenerateForegroundInstanceMaskRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let result = request.results?.first as? VNInstanceMaskObservation else {
                    continuation.resume(throwing: PipelineError.segmentationFailed)
                    return
                }

                // Convert mask to CIImage
                let mask = try? result.generateMaskedImage(
                    ofInstances: result.allInstances,
                    from: request,
                    croppedToInstancesExtent: false
                )

                if let mask = mask {
                    continuation.resume(returning: CIImage(cvPixelBuffer: mask))
                } else {
                    continuation.resume(throwing: PipelineError.segmentationFailed)
                }
            }

            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            try? handler.perform([request])
        }
    }

    // MARK: - Step 4: Detect Credit Card

    private func detectCreditCard() async throws -> CardDetection {
        print("💳 Step 4: Detecting credit card...")

        guard let calibrationImagesDir = calibrationImagesDir else {
            throw PipelineError.noImages
        }

        // Get card image
        let images = try FileManager.default.contentsOfDirectory(
            at: calibrationImagesDir,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension.lowercased() == "heic" || $0.pathExtension.lowercased() == "jpg" }

        guard let cardImage = images.first,
              let ciImage = CIImage(contentsOf: cardImage) else {
            throw PipelineError.invalidImage
        }

        // Detect rectangle (credit card)
        let detection = try await detectRectangle(in: ciImage)

        // Verify it's card-shaped (aspect ratio ~1.586)
        let aspectRatio = detection.detectedSize.x / detection.detectedSize.y
        let expectedRatio: Float = 85.60 / 53.98 // 1.586

        if abs(aspectRatio - expectedRatio) > 0.2 {
            print("⚠️ Detected rectangle aspect ratio \(aspectRatio) doesn't match card (\(expectedRatio))")
        }

        print("✅ Card detected: \(detection.detectedSize) pixels")
        return detection
    }

    private func detectRectangle(in image: CIImage) async throws -> CardDetection {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let result = request.results?.first as? VNRectangleObservation else {
                    continuation.resume(throwing: PipelineError.cardNotDetected)
                    return
                }

                // Calculate size in pixels
                let imageSize = image.extent.size
                let width = Float(result.boundingBox.width * imageSize.width)
                let height = Float(result.boundingBox.height * imageSize.height)

                let detection = CardDetection(
                    boundingBox: result.boundingBox,
                    corners: [
                        result.topLeft,
                        result.topRight,
                        result.bottomRight,
                        result.bottomLeft
                    ],
                    confidence: result.confidence,
                    detectedSize: SIMD2(width, height),
                    realWorldSize: self.creditCardSize
                )

                continuation.resume(returning: detection)
            }

            request.maximumObservations = 1

            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            try? handler.perform([request])
        }
    }

    // MARK: - Step 5: Calculate Scale

    private func calculateScale(from cardDetection: CardDetection) -> ScaleInfo {
        print("📏 Step 5: Calculating scale...")

        // Calculate pixels per mm from card detection
        let widthPPM = cardDetection.detectedSize.x / cardDetection.realWorldSize.x
        let heightPPM = cardDetection.detectedSize.y / cardDetection.realWorldSize.y

        let averagePPM = (widthPPM + heightPPM) / 2.0

        // Scale factor to convert mesh units to mm
        // Assumes mesh was created in arbitrary units
        let scaleFactor = averagePPM / 1000.0 // Convert to meters

        cardScale = scaleFactor

        let scaleInfo = ScaleInfo(
            pixelsPerMM: averagePPM,
            scaleFactor: scaleFactor,
            confidence: cardDetection.confidence,
            method: "card"
        )

        print("✅ Scale calculated: \(averagePPM) pixels/mm, factor: \(scaleFactor)")
        return scaleInfo
    }

    // MARK: - Step 6: Measure Volume

    private func measureVolume(
        meshURL: URL,
        scale: Float,
        mask: CIImage?
    ) async throws -> Measurements {
        print("📊 Step 6: Measuring volume...")

        // Load mesh
        let asset = MDLAsset(url: meshURL)
        guard let mesh = asset.object(at: 0) as? MDLMesh else {
            throw PipelineError.invalidMesh
        }

        // Calculate bounding box
        let bbox = calculateBoundingBox(mesh)

        // Apply scale to get real dimensions in mm
        let dimensions = bbox.size * scale * 1000 // to mm

        // Calculate volume using signed volume method
        let volume = calculateSignedVolume(mesh) * pow(scale, 3) * 1_000_000_000 // to cm³

        // Calculate surface area
        let surfaceArea = calculateSurfaceArea(mesh) * pow(scale, 2) * 1_000_000 // to cm²

        let measurements = Measurements(
            dimensions: dimensions,
            volume: volume,
            surfaceArea: surfaceArea,
            boundingBox: bbox
        )

        print("""
        ✅ Measurements complete:
        - Dimensions: \(dimensions.x) × \(dimensions.y) × \(dimensions.z) mm
        - Volume: \(volume) cm³
        - Surface Area: \(surfaceArea) cm²
        """)

        return measurements
    }

    // MARK: - Helper: Photogrammetry

    private func runPhotogrammetry(
        input: URL,
        output: URL,
        detail: PhotogrammetrySession.Request.Detail = .medium
    ) async throws {
        let session = try PhotogrammetrySession(input: input)
        let request: PhotogrammetrySession.Request = .modelFile(url: output, detail: detail)

        try session.process(requests: [request])

        for try await event in session.outputs {
            switch event {
            case .processingComplete:
                return
            case .requestError(_, let error):
                throw error
            case .processingCancelled:
                throw PipelineError.cancelled
            default:
                break
            }
        }
    }

    // MARK: - Helper: Geometry Calculations

    private func calculateBoundingBox(_ mesh: MDLMesh) -> BoundingBox {
        var minPoint = SIMD3<Float>(Float.infinity, Float.infinity, Float.infinity)
        var maxPoint = SIMD3<Float>(-Float.infinity, -Float.infinity, -Float.infinity)

        guard let vertexBuffer = mesh.vertexBuffers.first as? MDLMeshBuffer else {
            return BoundingBox(min: .zero, max: .zero, center: .zero)
        }

        let vertexData = vertexBuffer.map().bytes
        let stride = mesh.vertexDescriptor.layouts.first?.stride ?? 0

        for i in 0..<mesh.vertexCount {
            let offset = i * stride
            let vertex = vertexData.advanced(by: offset)
                .assumingMemoryBound(to: SIMD3<Float>.self).pointee

            minPoint = min(minPoint, vertex)
            maxPoint = max(maxPoint, vertex)
        }

        let center = (minPoint + maxPoint) / 2

        return BoundingBox(min: minPoint, max: maxPoint, center: center)
    }

    private func calculateSignedVolume(_ mesh: MDLMesh) -> Float {
        var volume: Float = 0.0

        for submesh in mesh.submeshes ?? [] {
            guard let submesh = submesh as? MDLSubmesh else { continue }

            let indexBuffer = submesh.indexBuffer
            let indexData = indexBuffer.map().bytes
            let indexCount = submesh.indexCount

            guard let vertexBuffer = mesh.vertexBuffers.first as? MDLMeshBuffer else { continue }
            let vertexData = vertexBuffer.map().bytes
            let stride = mesh.vertexDescriptor.layouts.first?.stride ?? 0

            for i in stride(from: 0, to: indexCount, by: 3) {
                let idx0 = indexData.advanced(by: i * MemoryLayout<UInt32>.size)
                    .assumingMemoryBound(to: UInt32.self).pointee
                let idx1 = indexData.advanced(by: (i + 1) * MemoryLayout<UInt32>.size)
                    .assumingMemoryBound(to: UInt32.self).pointee
                let idx2 = indexData.advanced(by: (i + 2) * MemoryLayout<UInt32>.size)
                    .assumingMemoryBound(to: UInt32.self).pointee

                let v0 = vertexData.advanced(by: Int(idx0) * stride)
                    .assumingMemoryBound(to: SIMD3<Float>.self).pointee
                let v1 = vertexData.advanced(by: Int(idx1) * stride)
                    .assumingMemoryBound(to: SIMD3<Float>.self).pointee
                let v2 = vertexData.advanced(by: Int(idx2) * stride)
                    .assumingMemoryBound(to: SIMD3<Float>.self).pointee

                volume += dot(v0, cross(v1, v2)) / 6.0
            }
        }

        return abs(volume)
    }

    private func calculateSurfaceArea(_ mesh: MDLMesh) -> Float {
        var area: Float = 0.0

        for submesh in mesh.submeshes ?? [] {
            guard let submesh = submesh as? MDLSubmesh else { continue }

            let indexBuffer = submesh.indexBuffer
            let indexData = indexBuffer.map().bytes
            let indexCount = submesh.indexCount

            guard let vertexBuffer = mesh.vertexBuffers.first as? MDLMeshBuffer else { continue }
            let vertexData = vertexBuffer.map().bytes
            let stride = mesh.vertexDescriptor.layouts.first?.stride ?? 0

            for i in stride(from: 0, to: indexCount, by: 3) {
                let idx0 = indexData.advanced(by: i * MemoryLayout<UInt32>.size)
                    .assumingMemoryBound(to: UInt32.self).pointee
                let idx1 = indexData.advanced(by: (i + 1) * MemoryLayout<UInt32>.size)
                    .assumingMemoryBound(to: UInt32.self).pointee
                let idx2 = indexData.advanced(by: (i + 2) * MemoryLayout<UInt32>.size)
                    .assumingMemoryBound(to: UInt32.self).pointee

                let v0 = vertexData.advanced(by: Int(idx0) * stride)
                    .assumingMemoryBound(to: SIMD3<Float>.self).pointee
                let v1 = vertexData.advanced(by: Int(idx1) * stride)
                    .assumingMemoryBound(to: SIMD3<Float>.self).pointee
                let v2 = vertexData.advanced(by: Int(idx2) * stride)
                    .assumingMemoryBound(to: SIMD3<Float>.self).pointee

                let edge1 = v1 - v0
                let edge2 = v2 - v0
                area += length(cross(edge1, edge2)) / 2.0
            }
        }

        return area
    }

    private func calculateQualityScore(
        cardConfidence: Float,
        meshQuality: Measurements
    ) -> Float {
        // Quality score based on:
        // - Card detection confidence
        // - Mesh vertex count
        // - Bounding box reasonableness

        var score: Float = 0.0

        // Card confidence contributes 50%
        score += cardConfidence * 0.5

        // Mesh quality contributes 50%
        // (assuming good mesh has reasonable dimensions)
        let volumeScore: Float = meshQuality.volume > 0 ? 0.5 : 0.0
        score += volumeScore

        return min(score, 1.0)
    }

    // MARK: - Errors

    enum PipelineError: Error {
        case noImages
        case invalidImage
        case segmentationFailed
        case cardNotDetected
        case invalidMesh
        case cancelled
    }
}

// MARK: - Extensions

extension SIMD3 where Scalar == Float {
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
