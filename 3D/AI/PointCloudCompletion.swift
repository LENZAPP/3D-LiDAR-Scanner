//
//  PointCloudCompletion.swift
//  3D
//
//  Point Cloud Completion using PCN (Point Completion Network)
//  Fills holes and missing regions in point clouds
//
//  MODEL SOURCE: https://github.com/wentaoyuan/pcn
//  STATUS: Prepared for CoreML model integration
//

import Foundation
import CoreML
import simd

/// Point Cloud Completion using neural networks
@MainActor
class PointCloudCompletion: ObservableObject {

    // MARK: - Published Properties

    @Published var isProcessing = false
    @Published var progress: Double = 0.0

    // MARK: - Model

    private var model: MLModel?
    private let modelName = "PointCloudCompletion"

    // Model input/output names (from our generated model)
    private let inputName = "partial_point_cloud"
    private let outputName = "completed_point_cloud"

    // MARK: - Configuration

    struct Config {
        let inputPointCount: Int = 2048      // PCN expects 2048 input points
        let outputPointCount: Int = 16384    // PCN generates 16384 output points
        let useNeuralEngine: Bool = true

        static let `default` = Config()
    }

    private let config: Config

    // MARK: - Initialization

    init(config: Config = .default) {
        self.config = config
        print("🔷 Point Cloud Completion initialized")
        print("   Input: \(config.inputPointCount) points")
        print("   Output: \(config.outputPointCount) points")
    }

    // MARK: - Model Loading

    /// Load PCN model
    func loadModel() async throws {
        print("📦 Loading PCN model...")

        // Try to load from bundle (support both .mlmodelc and .mlpackage)
        var modelURL: URL?

        // Try compiled model first
        if let url = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
            modelURL = url
        }
        // Try mlpackage
        else if let url = Bundle.main.url(forResource: modelName, withExtension: "mlpackage") {
            modelURL = url
        }

        guard let url = modelURL else {
            // Model not in bundle yet
            print("⚠️ PCN model not found in bundle")
            print("   To use this feature:")
            print("   1. Run: python3 create_pcn_model.py")
            print("   2. Drag PointCloudCompletion.mlpackage into Xcode")
            print("   3. Add to target '3D'")
            throw PCNError.modelNotFound
        }

        let configuration = MLModelConfiguration()
        if config.useNeuralEngine {
            configuration.computeUnits = .cpuAndNeuralEngine
        }

        model = try await MLModel.load(contentsOf: url, configuration: configuration)
        print("✅ PCN model loaded successfully")
    }

    // MARK: - Point Cloud Completion

    /// Complete a partial point cloud
    func completePointCloud(_ points: [SIMD3<Float>]) async throws -> [SIMD3<Float>] {
        guard let model = model else {
            throw PCNError.modelNotLoaded
        }

        isProcessing = true
        progress = 0.0
        defer {
            isProcessing = false
            progress = 1.0
        }

        print("🔷 Completing point cloud...")
        print("   Input points: \(points.count)")

        // 1. Preprocess: Sample to fixed size
        progress = 0.2
        let sampledPoints = samplePoints(points, count: config.inputPointCount)

        // 2. Normalize points
        progress = 0.3
        let (normalizedPoints, center, scale) = normalizePointCloud(sampledPoints)

        // 3. Convert to ML input format
        progress = 0.4
        let input = try prepareInput(normalizedPoints)

        // 4. Run inference
        progress = 0.6
        let output = try await runInference(model: model, input: input)

        // 5. Denormalize output
        progress = 0.8
        let completedPoints = denormalizePointCloud(output, center: center, scale: scale)

        progress = 1.0
        print("✅ Point cloud completed")
        print("   Output points: \(completedPoints.count)")

        return completedPoints
    }

    // MARK: - Preprocessing

    /// Sample points to fixed count using farthest point sampling
    private func samplePoints(_ points: [SIMD3<Float>], count: Int) -> [SIMD3<Float>] {
        guard points.count > count else {
            // If we have fewer points, duplicate randomly
            var sampled = points
            while sampled.count < count {
                sampled.append(points.randomElement() ?? SIMD3<Float>(0, 0, 0))
            }
            return sampled
        }

        // Farthest point sampling
        var sampled: [SIMD3<Float>] = []
        var remaining = points

        // Start with random point
        if let first = remaining.randomElement() {
            sampled.append(first)
            remaining.removeAll { $0 == first }
        }

        // Iteratively add farthest points
        while sampled.count < count && !remaining.isEmpty {
            var farthest: SIMD3<Float>?
            var maxDistance: Float = 0

            for candidate in remaining {
                // Find minimum distance to sampled points
                let minDist = sampled.map { distance($0, candidate) }.min() ?? 0
                if minDist > maxDistance {
                    maxDistance = minDist
                    farthest = candidate
                }
            }

            if let point = farthest {
                sampled.append(point)
                remaining.removeAll { $0 == point }
            }
        }

        return sampled
    }

    /// Normalize point cloud to unit sphere
    private func normalizePointCloud(_ points: [SIMD3<Float>]) -> ([SIMD3<Float>], center: SIMD3<Float>, scale: Float) {
        // Calculate centroid
        let sum = points.reduce(SIMD3<Float>(0, 0, 0)) { $0 + $1 }
        let center = sum / Float(points.count)

        // Center points
        let centered = points.map { $0 - center }

        // Calculate scale (max distance from center)
        let maxDist = centered.map { length($0) }.max() ?? 1.0
        let scale = maxDist > 0 ? maxDist : 1.0

        // Normalize
        let normalized = centered.map { $0 / scale }

        return (normalized, center, scale)
    }

    /// Denormalize point cloud
    private func denormalizePointCloud(_ points: [SIMD3<Float>], center: SIMD3<Float>, scale: Float) -> [SIMD3<Float>] {
        return points.map { ($0 * scale) + center }
    }

    // MARK: - ML Input/Output

    /// Prepare input for CoreML model
    private func prepareInput(_ points: [SIMD3<Float>]) throws -> MLFeatureProvider {
        // PCN expects input as [N, 3] array
        var flatArray: [Float] = []
        for point in points {
            flatArray.append(point.x)
            flatArray.append(point.y)
            flatArray.append(point.z)
        }

        let shape = [NSNumber(value: points.count), NSNumber(value: 3)]
        let mlArray = try MLMultiArray(shape: shape, dataType: .float32)

        for (index, value) in flatArray.enumerated() {
            mlArray[index] = NSNumber(value: value)
        }

        let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: mlArray])

        return provider
    }

    /// Run model inference
    private func runInference(model: MLModel, input: MLFeatureProvider) async throws -> [SIMD3<Float>] {
        let prediction = try model.prediction(from: input)

        // Extract output
        guard let output = prediction.featureValue(for: outputName)?.multiArrayValue else {
            throw PCNError.invalidOutput
        }

        // Convert MLMultiArray back to point cloud
        var points: [SIMD3<Float>] = []
        let pointCount = output.shape[0].intValue

        for i in 0..<pointCount {
            let x = output[[i, 0] as [NSNumber]].floatValue
            let y = output[[i, 1] as [NSNumber]].floatValue
            let z = output[[i, 2] as [NSNumber]].floatValue
            points.append(SIMD3<Float>(x, y, z))
        }

        return points
    }

    // MARK: - Utilities

    private func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        return length(a - b)
    }
}

// MARK: - Errors

enum PCNError: Error, LocalizedError {
    case modelNotFound
    case modelNotLoaded
    case invalidInput
    case invalidOutput
    case processingFailed

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return """
            PCN-Modell nicht gefunden.

            Installation:
            1. Download: https://github.com/wentaoyuan/pcn
            2. Konvertiere zu CoreML (siehe SETUP_PCN.md)
            3. Füge PointCloudCompletion.mlmodel zu Xcode hinzu
            """
        case .modelNotLoaded:
            return "PCN-Modell nicht geladen. Rufe loadModel() auf."
        case .invalidInput:
            return "Ungültige Input-Daten für PCN"
        case .invalidOutput:
            return "Ungültige Output-Daten von PCN"
        case .processingFailed:
            return "Point Cloud Completion fehlgeschlagen"
        }
    }
}

// MARK: - Setup Instructions

/*
 SETUP ANLEITUNG: PCN Integration

 1. PCN Repository clonen:
    git clone https://github.com/wentaoyuan/pcn
    cd pcn

 2. Pre-trained Modell herunterladen:
    # Modell ist im Repo verfügbar
    # Oder von: https://drive.google.com/...

 3. Python Environment setup:
    pip install torch torchvision
    pip install coremltools
    pip install numpy

 4. Konvertierung zu CoreML:

    ```python
    import torch
    import coremltools as ct

    # Load PCN model
    model = torch.load('pcn_model.pth')
    model.eval()

    # Create example input
    example_input = torch.randn(1, 2048, 3)

    # Trace model
    traced_model = torch.jit.trace(model, example_input)

    # Convert to CoreML
    coreml_model = ct.convert(
        traced_model,
        inputs=[ct.TensorType(name="input", shape=(1, 2048, 3))],
        outputs=[ct.TensorType(name="output")]
    )

    # Save
    coreml_model.save("PointCloudCompletion.mlmodel")
    ```

 5. In Xcode integrieren:
    - Drag & Drop PointCloudCompletion.mlmodel in Xcode
    - Build → Auto-generates Swift code
    - Ready to use!

 6. Testen:
    ```swift
    let pcn = PointCloudCompletion()
    try await pcn.loadModel()
    let completed = try await pcn.completePointCloud(partialCloud)
    ```
 */
