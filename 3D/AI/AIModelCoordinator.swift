//
//  AIModelCoordinator.swift
//  3D
//
//  Central coordinator for all AI/ML models
//  Manages model loading, caching, and inference
//

import Foundation
import CoreML
import Vision
import UIKit

/// Central coordinator for AI model management
@MainActor
class AIModelCoordinator: ObservableObject {

    // MARK: - Singleton

    static let shared = AIModelCoordinator()

    // MARK: - Published Properties

    @Published var isLoading = false
    @Published var loadedModels: Set<ModelType> = []
    @Published var error: AIError?

    // MARK: - Components

    let objectRecognition = ObjectRecognition()
    let materialDetector = SmartMaterialDetector()

    // MARK: - Model Types

    enum ModelType: String, CaseIterable {
        // Apple's Pre-trained Models (Ready to use)
        case yolov3 = "YOLOv3"              // Object Detection
        case deeplabv3 = "DeepLabV3"         // Semantic Segmentation
        case resnet50 = "ResNet50"           // Image Classification

        // Custom Models (Require download/conversion)
        case pointCloudCompletion = "PCN"    // Point Cloud Completion Network
        case pointNet = "PointNet++"         // Point Cloud Processing
        case meshRefinement = "MeshRefiner"  // Neural Mesh Refinement

        var displayName: String {
            switch self {
            case .yolov3: return "Object Detection (YOLOv3)"
            case .deeplabv3: return "Background Removal (DeepLabV3)"
            case .resnet50: return "Image Classification (ResNet50)"
            case .pointCloudCompletion: return "Point Cloud Completion"
            case .pointNet: return "Point Cloud Processing"
            case .meshRefinement: return "Mesh Refinement"
            }
        }

        var isAvailable: Bool {
            switch self {
            case .yolov3, .deeplabv3, .resnet50:
                return true  // Apple models always available
            case .pointCloudCompletion, .pointNet, .meshRefinement:
                return false  // Require download
            }
        }

        var modelFileName: String {
            switch self {
            case .yolov3: return "YOLOv3"
            case .deeplabv3: return "DeepLabV3"
            case .resnet50: return "ResNet50"
            case .pointCloudCompletion: return "PointCloudCompletion"
            case .pointNet: return "PointNetPlusPlus"
            case .meshRefinement: return "NeuralMeshRefiner"
            }
        }

        var downloadURL: String? {
            switch self {
            case .yolov3:
                return "https://ml-assets.apple.com/coreml/models/Image/ObjectDetection/YOLOv3/YOLOv3.mlmodel"
            case .deeplabv3:
                return "https://ml-assets.apple.com/coreml/models/Image/Segmentation/DeepLabV3/DeepLabV3.mlmodel"
            case .resnet50:
                return "https://ml-assets.apple.com/coreml/models/Image/ImageClassification/ResNet50/ResNet50.mlmodel"
            default:
                return nil  // Custom models need manual download
            }
        }
    }

    // MARK: - Model Cache

    private var modelCache: [ModelType: MLModel] = [:]

    // MARK: - Initialization

    private init() {
        print("🤖 AI Model Coordinator initialized")
    }

    // MARK: - Model Loading

    /// Load a specific model
    func loadModel(_ type: ModelType) async throws -> MLModel {
        // Check cache first
        if let cached = modelCache[type] {
            print("✅ Using cached model: \(type.displayName)")
            return cached
        }

        isLoading = true
        defer { isLoading = false }

        print("📦 Loading model: \(type.displayName)...")

        // Check if model file exists in bundle
        guard let modelURL = Bundle.main.url(
            forResource: type.modelFileName,
            withExtension: "mlmodelc"
        ) else {
            // Try .mlmodel extension
            if let mlmodelURL = Bundle.main.url(
                forResource: type.modelFileName,
                withExtension: "mlmodel"
            ) {
                return try await loadFromMLModel(url: mlmodelURL, type: type)
            }

            throw AIError.modelNotFound(type.displayName)
        }

        // Load compiled model
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine  // Use Neural Engine if available

        do {
            let model = try await MLModel.load(contentsOf: modelURL, configuration: configuration)

            // Cache model
            modelCache[type] = model
            loadedModels.insert(type)

            print("✅ Model loaded: \(type.displayName)")
            print("   Compute units: CPU + Neural Engine")

            return model
        } catch {
            print("❌ Failed to load model: \(error.localizedDescription)")
            throw AIError.loadingFailed(type.displayName, error.localizedDescription)
        }
    }

    /// Load from uncompiled .mlmodel file
    private func loadFromMLModel(url: URL, type: ModelType) async throws -> MLModel {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine

        // Compile first
        let compiledURL = try await MLModel.compileModel(at: url)

        let model = try await MLModel.load(contentsOf: compiledURL, configuration: configuration)

        // Cache
        modelCache[type] = model
        loadedModels.insert(type)

        print("✅ Model compiled and loaded: \(type.displayName)")
        return model
    }

    /// Preload commonly used models
    func preloadModels() async {
        let commonModels: [ModelType] = [.yolov3, .deeplabv3]

        for modelType in commonModels where modelType.isAvailable {
            do {
                _ = try await loadModel(modelType)
            } catch {
                print("⚠️ Failed to preload \(modelType.displayName): \(error)")
            }
        }
    }

    /// Clear model cache (free memory)
    func clearCache() {
        modelCache.removeAll()
        loadedModels.removeAll()
        print("🗑️ Model cache cleared")
    }

    // MARK: - Model Status

    /// Check if model is loaded
    func isModelLoaded(_ type: ModelType) -> Bool {
        return modelCache[type] != nil
    }

    /// Get loaded model count
    var loadedModelCount: Int {
        return modelCache.count
    }

    /// Get total cache size (estimated)
    var estimatedCacheSize: String {
        let sizeInMB = modelCache.count * 50  // Rough estimate: 50MB per model
        return "\(sizeInMB) MB"
    }

    // MARK: - High-Level AI Functions

    /// Smart object analysis (combines recognition + material detection)
    func analyzeObject(from image: UIImage) async throws -> ObjectAnalysis {
        guard let cgImage = image.cgImage else {
            throw AIError.invalidImage
        }

        // Run recognition and material detection in parallel
        async let recognitionTask = objectRecognition.recognizeObject(from: cgImage)
        async let materialTask = materialDetector.detectMaterial(from: cgImage)

        let (recognized, material) = try await (recognitionTask, materialTask)

        return ObjectAnalysis(
            object: recognized,
            material: material,
            timestamp: Date()
        )
    }

    /// Analyze from multiple images (more accurate)
    func analyzeObjectFromMultipleImages(_ images: [UIImage]) async throws -> ObjectAnalysis {
        let cgImages = images.compactMap { $0.cgImage }

        guard !cgImages.isEmpty else {
            throw AIError.noImagesProvided
        }

        // Run parallel analysis
        async let recognitionTask = objectRecognition.recognizeObjectFromMultipleImages(cgImages)
        async let materialTask = materialDetector.detectMaterialFromMultipleImages(cgImages)

        let (recognized, material) = try await (recognitionTask, materialTask)

        return ObjectAnalysis(
            object: recognized,
            material: material,
            timestamp: Date()
        )
    }

    // MARK: - Model Download (Future)

    /// Download model from Apple or custom source
    func downloadModel(_ type: ModelType) async throws {
        guard let urlString = type.downloadURL else {
            throw AIError.downloadNotAvailable
        }

        guard let url = URL(string: urlString) else {
            throw AIError.invalidURL
        }

        isLoading = true
        defer { isLoading = false }

        print("⬇️ Downloading model: \(type.displayName)...")
        print("   URL: \(urlString)")

        // Download model
        let (localURL, response) = try await URLSession.shared.download(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AIError.downloadFailed
        }

        // Move to documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationURL = documentsPath.appendingPathComponent("\(type.modelFileName).mlmodel")

        try FileManager.default.moveItem(at: localURL, to: destinationURL)

        print("✅ Model downloaded: \(type.displayName)")
        print("   Location: \(destinationURL.path)")
    }
}

// MARK: - Object Analysis Result

struct ObjectAnalysis {
    let object: ObjectRecognition.RecognizedObject
    let material: SmartMaterialDetector.MaterialAnalysis
    let timestamp: Date

    var summary: String {
        """
        \(object.category.emoji) Objekt: \(object.name)
        \(material.material.emoji) Material: \(material.material.rawValue)
        📊 Konfidenz: \(Int(min(object.confidence, material.confidence) * 100))%
        ⚖️ Dichte: \(String(format: "%.2f", material.suggestedDensity)) g/cm³
        """
    }

    var tips: [String] {
        return object.tips + (material.confidence > 0.7 ? ["Material-Erkennung: \(material.material.rawValue)"] : [])
    }
}

// MARK: - Errors

enum AIError: Error, LocalizedError {
    case modelNotFound(String)
    case loadingFailed(String, String)
    case invalidImage
    case noImagesProvided
    case downloadNotAvailable
    case invalidURL
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            return "ML-Modell nicht gefunden: \(name)"
        case .loadingFailed(let name, let reason):
            return "Laden von \(name) fehlgeschlagen: \(reason)"
        case .invalidImage:
            return "Ungültiges Bild"
        case .noImagesProvided:
            return "Keine Bilder bereitgestellt"
        case .downloadNotAvailable:
            return "Download für dieses Modell nicht verfügbar"
        case .invalidURL:
            return "Ungültige Download-URL"
        case .downloadFailed:
            return "Download fehlgeschlagen"
        }
    }
}

// MARK: - Model Info Extension

extension AIModelCoordinator {
    /// Get information about all models
    func getModelInfo() -> [ModelInfo] {
        return ModelType.allCases.map { type in
            ModelInfo(
                type: type,
                isLoaded: isModelLoaded(type),
                isAvailable: type.isAvailable
            )
        }
    }

    struct ModelInfo {
        let type: ModelType
        let isLoaded: Bool
        let isAvailable: Bool

        var displayName: String { type.displayName }
        var status: String {
            if isLoaded {
                return "✅ Geladen"
            } else if isAvailable {
                return "📦 Verfügbar"
            } else {
                return "⬇️ Download erforderlich"
            }
        }
    }
}
