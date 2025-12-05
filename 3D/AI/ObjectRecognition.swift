//
//  ObjectRecognition.swift
//  3D
//
//  AI-powered object recognition using Vision Framework
//  Identifies scanned objects and suggests appropriate settings
//

import Foundation
import Vision
import CoreImage
import UIKit

/// AI-powered object recognition for scanned objects
@MainActor
class ObjectRecognition: ObservableObject {

    // MARK: - Published Properties

    @Published var recognizedObject: RecognizedObject?
    @Published var isProcessing = false
    @Published var confidence: Float = 0.0

    // MARK: - Recognition Result

    struct RecognizedObject {
        let name: String
        let category: ObjectCategory
        let confidence: Float
        let suggestedMaterial: MaterialType
        let estimatedDensity: Float
        let tips: [String]

        enum ObjectCategory: String, CaseIterable {
            case food = "Food & Beverage"
            case electronics = "Electronics"
            case toy = "Toy"
            case container = "Container"
            case tool = "Tool"
            case household = "Household Item"
            case office = "Office Supply"
            case other = "Other"

            var emoji: String {
                switch self {
                case .food: return "🍎"
                case .electronics: return "📱"
                case .toy: return "🧸"
                case .container: return "📦"
                case .tool: return "🔧"
                case .household: return "🏠"
                case .office: return "📎"
                case .other: return "❓"
                }
            }
        }
    }

    // MARK: - Material Types

    enum MaterialType: String, CaseIterable {
        case aluminum = "Aluminum"
        case steel = "Steel"
        case plastic = "Plastic"
        case wood = "Wood"
        case glass = "Glass"
        case cardboard = "Cardboard"
        case ceramic = "Ceramic"
        case rubber = "Rubber"

        var density: Float {
            switch self {
            case .aluminum: return 2.70
            case .steel: return 7.85
            case .plastic: return 1.05
            case .wood: return 0.65
            case .glass: return 2.50
            case .cardboard: return 0.70
            case .ceramic: return 2.40
            case .rubber: return 1.15
            }
        }

        var emoji: String {
            switch self {
            case .aluminum: return "🥫"
            case .steel: return "🔩"
            case .plastic: return "🧴"
            case .wood: return "🪵"
            case .glass: return "🍾"
            case .cardboard: return "📦"
            case .ceramic: return "🏺"
            case .rubber: return "⚫"
            }
        }
    }

    // MARK: - Recognition

    /// Recognize object from image
    func recognizeObject(from image: CGImage) async throws -> RecognizedObject {
        isProcessing = true
        defer { isProcessing = false }

        return try await withCheckedThrowingContinuation { continuation in
            // Create Vision request
            let request = VNRecognizeObjectsRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedObjectObservation],
                      let topResult = observations.first else {
                    continuation.resume(throwing: RecognitionError.noObjectsFound)
                    return
                }

                // Get best classification
                guard let classification = topResult.labels.first else {
                    continuation.resume(throwing: RecognitionError.noClassification)
                    return
                }

                let recognizedObject = self.createRecognizedObject(
                    from: classification.identifier,
                    confidence: classification.confidence
                )

                continuation.resume(returning: recognizedObject)
            }

            // Configure request
            request.imageCropAndScaleOption = .scaleFill

            // Perform request
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Recognize object from multiple images (more accurate)
    func recognizeObjectFromMultipleImages(_ images: [CGImage]) async throws -> RecognizedObject {
        var results: [RecognizedObject] = []

        for image in images.prefix(5) {  // Use max 5 images
            if let result = try? await recognizeObject(from: image) {
                results.append(result)
            }
        }

        guard !results.isEmpty else {
            throw RecognitionError.noObjectsFound
        }

        // Find most common category
        let categoryCount = Dictionary(grouping: results, by: { $0.category })
            .mapValues { $0.count }

        guard let mostCommon = categoryCount.max(by: { $0.value < $1.value }) else {
            return results.first!
        }

        // Return result with highest confidence from most common category
        let bestResult = results
            .filter { $0.category == mostCommon.key }
            .max(by: { $0.confidence < $1.confidence })!

        return bestResult
    }

    // MARK: - Object Classification

    private func createRecognizedObject(from identifier: String, confidence: Float) -> RecognizedObject {
        let lowercased = identifier.lowercased()

        // Common objects database
        let objectDatabase: [(keywords: [String], name: String, category: RecognizedObject.ObjectCategory, material: MaterialType)] = [
            // Food & Beverage
            (["can", "soda", "cola", "redbull", "drink"], "Getränkedose", .food, .aluminum),
            (["bottle", "water", "beer"], "Flasche", .food, .plastic),
            (["apple", "fruit"], "Apfel", .food, .cardboard),
            (["cup", "mug", "coffee"], "Tasse", .food, .ceramic),

            // Electronics
            (["phone", "mobile", "iphone"], "Smartphone", .electronics, .aluminum),
            (["remote", "controller"], "Fernbedienung", .electronics, .plastic),
            (["keyboard"], "Tastatur", .electronics, .plastic),
            (["mouse"], "Maus", .electronics, .plastic),

            // Containers
            (["box", "package"], "Box", .container, .cardboard),
            (["jar", "container"], "Behälter", .container, .glass),

            // Tools
            (["hammer", "tool"], "Werkzeug", .tool, .steel),
            (["scissors"], "Schere", .tool, .steel),

            // Household
            (["vase", "pot"], "Vase", .household, .ceramic),
            (["lamp", "light"], "Lampe", .household, .plastic),

            // Office
            (["stapler"], "Hefter", .office, .plastic),
            (["pen", "pencil"], "Stift", .office, .plastic),
        ]

        // Find matching object
        for entry in objectDatabase {
            if entry.keywords.contains(where: { lowercased.contains($0) }) {
                return RecognizedObject(
                    name: entry.name,
                    category: entry.category,
                    confidence: confidence,
                    suggestedMaterial: entry.material,
                    estimatedDensity: entry.material.density,
                    tips: generateTips(for: entry.category, material: entry.material)
                )
            }
        }

        // Default: generic object
        return RecognizedObject(
            name: identifier.capitalized,
            category: .other,
            confidence: confidence,
            suggestedMaterial: .plastic,
            estimatedDensity: 1.0,
            tips: generateTips(for: .other, material: .plastic)
        )
    }

    // MARK: - Smart Tips Generation

    private func generateTips(for category: RecognizedObject.ObjectCategory, material: MaterialType) -> [String] {
        var tips: [String] = []

        // Category-specific tips
        switch category {
        case .food:
            tips.append("Stelle sicher, dass das Objekt sauber und trocken ist")
            tips.append("Bei Dosen: Entferne Etiketten für bessere Ergebnisse")
        case .electronics:
            tips.append("Vermeide direkte Reflexionen auf Bildschirmen")
            tips.append("Schalte das Gerät aus für bessere Ergebnisse")
        case .container:
            tips.append("Leere Behälter sind einfacher zu scannen")
            tips.append("Transparente Objekte langsam scannen")
        case .tool:
            tips.append("Platziere Werkzeug auf kontrastreichem Untergrund")
            tips.append("Glänzende Oberflächen können Probleme verursachen")
        default:
            tips.append("Halte das iPhone ruhig während des Scans")
            tips.append("Scanne aus verschiedenen Winkeln")
        }

        // Material-specific tips
        switch material {
        case .aluminum, .steel:
            tips.append("⚠️ Metallische Oberflächen können reflektieren")
        case .glass:
            tips.append("⚠️ Transparente Objekte sind schwierig zu scannen")
        case .plastic:
            tips.append("✅ Plastik ist ideal für LiDAR-Scans")
        case .wood:
            tips.append("✅ Holz scannt sehr gut mit LiDAR")
        default:
            break
        }

        return tips
    }

    // MARK: - Quick Recognition (Single Image)

    /// Quick recognition from UIImage (convenience)
    func quickRecognize(image: UIImage) async throws -> RecognizedObject {
        guard let cgImage = image.cgImage else {
            throw RecognitionError.invalidImage
        }
        return try await recognizeObject(from: cgImage)
    }
}

// MARK: - Errors

enum RecognitionError: Error, LocalizedError {
    case noObjectsFound
    case noClassification
    case invalidImage
    case processingFailed

    var errorDescription: String? {
        switch self {
        case .noObjectsFound:
            return "Kein Objekt im Bild erkannt"
        case .noClassification:
            return "Objekt konnte nicht klassifiziert werden"
        case .invalidImage:
            return "Ungültiges Bild"
        case .processingFailed:
            return "Bildverarbeitung fehlgeschlagen"
        }
    }
}

// MARK: - Vision Extension

extension VNRecognizeObjectsRequest {
    convenience init(completion: @escaping (VNRequest, Error?) -> Void) {
        self.init(completionHandler: completion)
    }
}
