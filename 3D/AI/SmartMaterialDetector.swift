//
//  SmartMaterialDetector.swift
//  3D
//
//  AI-powered material detection using visual analysis
//  Analyzes surface properties to suggest material type
//

import Foundation
import Vision
import CoreImage
import UIKit
import simd

/// Smart material detection using visual analysis
@MainActor
class SmartMaterialDetector: ObservableObject {

    // MARK: - Published Properties

    @Published var detectedMaterial: MaterialAnalysis?
    @Published var isAnalyzing = false
    @Published var confidence: Float = 0.0

    // MARK: - Material Analysis Result

    struct MaterialAnalysis {
        let material: MaterialType
        let confidence: Float
        let properties: SurfaceProperties
        let suggestedDensity: Float
        let alternativeMaterials: [(MaterialType, Float)]  // (material, confidence)

        enum MaterialType: String, CaseIterable {
            case metal = "Metall"
            case plastic = "Plastik"
            case wood = "Holz"
            case glass = "Glas"
            case cardboard = "Karton"
            case ceramic = "Keramik"
            case fabric = "Stoff"
            case rubber = "Gummi"
            case paper = "Papier"
            case stone = "Stein"

            var density: Float {
                switch self {
                case .metal: return 7.85      // Steel average
                case .plastic: return 1.05
                case .wood: return 0.65
                case .glass: return 2.50
                case .cardboard: return 0.70
                case .ceramic: return 2.40
                case .fabric: return 0.80
                case .rubber: return 1.15
                case .paper: return 0.80
                case .stone: return 2.65
                }
            }

            var emoji: String {
                switch self {
                case .metal: return "🔩"
                case .plastic: return "🧴"
                case .wood: return "🪵"
                case .glass: return "🍾"
                case .cardboard: return "📦"
                case .ceramic: return "🏺"
                case .fabric: return "🧵"
                case .rubber: return "⚫"
                case .paper: return "📄"
                case .stone: return "🪨"
                }
            }

            var color: String {
                switch self {
                case .metal: return "#8B8B8B"
                case .plastic: return "#4A90E2"
                case .wood: return "#8B4513"
                case .glass: return "#87CEEB"
                case .cardboard: return "#D2691E"
                case .ceramic: return "#F5DEB3"
                case .fabric: return "#DDA0DD"
                case .rubber: return "#2F4F4F"
                case .paper: return "#FFFACD"
                case .stone: return "#808080"
                }
            }
        }

        struct SurfaceProperties {
            let reflectivity: Float      // 0.0 - 1.0
            let roughness: Float          // 0.0 - 1.0
            let transparency: Float       // 0.0 - 1.0
            let colorVariation: Float     // 0.0 - 1.0
            let textureComplexity: Float  // 0.0 - 1.0
        }
    }

    // MARK: - Material Detection

    /// Analyze material from image
    func detectMaterial(from image: CGImage) async throws -> MaterialAnalysis {
        isAnalyzing = true
        defer { isAnalyzing = false }

        // Extract surface properties
        let properties = analyzeSurfaceProperties(image: image)

        // Classify material based on properties
        let materialScores = calculateMaterialScores(properties: properties)

        // Get best match
        guard let bestMatch = materialScores.max(by: { $0.score < $1.score }) else {
            throw MaterialDetectionError.analysisFailed
        }

        // Get alternatives (top 3)
        let alternatives = materialScores
            .filter { $0.material != bestMatch.material }
            .sorted { $0.score > $1.score }
            .prefix(3)
            .map { ($0.material, $0.score) }

        let analysis = MaterialAnalysis(
            material: bestMatch.material,
            confidence: bestMatch.score,
            properties: properties,
            suggestedDensity: bestMatch.material.density,
            alternativeMaterials: Array(alternatives)
        )

        // Already on MainActor, no need for DispatchQueue
        self.detectedMaterial = analysis
        self.confidence = bestMatch.score

        return analysis
    }

    /// Analyze material from multiple images (more accurate)
    func detectMaterialFromMultipleImages(_ images: [CGImage]) async throws -> MaterialAnalysis {
        var analyses: [MaterialAnalysis] = []

        for image in images.prefix(5) {  // Max 5 images
            if let analysis = try? await detectMaterial(from: image) {
                analyses.append(analysis)
            }
        }

        guard !analyses.isEmpty else {
            throw MaterialDetectionError.noDataAvailable
        }

        // Average the results
        let materialCounts = Dictionary(grouping: analyses, by: { $0.material })
            .mapValues { results in
                (count: results.count, avgConfidence: results.map { $0.confidence }.reduce(0, +) / Float(results.count))
            }

        guard let bestMaterial = materialCounts.max(by: { $0.value.avgConfidence < $1.value.avgConfidence }) else {
            return analyses.first!
        }

        // Return analysis with highest confidence for best material
        return analyses
            .filter { $0.material == bestMaterial.key }
            .max(by: { $0.confidence < $1.confidence })!
    }

    // MARK: - Surface Analysis

    private func analyzeSurfaceProperties(image: CGImage) -> MaterialAnalysis.SurfaceProperties {
        let ciImage = CIImage(cgImage: image)

        // Analyze reflectivity (brightness variation)
        let reflectivity = calculateReflectivity(ciImage: ciImage)

        // Analyze roughness (edge density)
        let roughness = calculateRoughness(ciImage: ciImage)

        // Analyze transparency (alpha channel analysis)
        let transparency = calculateTransparency(image: image)

        // Analyze color variation
        let colorVariation = calculateColorVariation(ciImage: ciImage)

        // Analyze texture complexity
        let textureComplexity = calculateTextureComplexity(ciImage: ciImage)

        return MaterialAnalysis.SurfaceProperties(
            reflectivity: reflectivity,
            roughness: roughness,
            transparency: transparency,
            colorVariation: colorVariation,
            textureComplexity: textureComplexity
        )
    }

    private func calculateReflectivity(ciImage: CIImage) -> Float {
        // High reflectivity = bright spots + dark areas (high contrast)
        guard let filter = CIFilter(name: "CIAreaHistogram") else { return 0.5 }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(256, forKey: "inputCount")

        guard let outputImage = filter.outputImage else { return 0.5 }

        // Analyze histogram for contrast
        let context = CIContext()
        var bitmap = [UInt8](repeating: 0, count: 256 * 4)
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 256 * 4, bounds: outputImage.extent, format: .RGBA8, colorSpace: nil)

        // Calculate standard deviation (proxy for reflectivity)
        let values = stride(from: 0, to: bitmap.count, by: 4).map { Float(bitmap[$0]) / 255.0 }
        let mean = values.reduce(0, +) / Float(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Float(values.count)
        let stdDev = sqrt(variance)

        return min(stdDev * 2.0, 1.0)  // Normalize to 0-1
    }

    private func calculateRoughness(ciImage: CIImage) -> Float {
        // Roughness = edge density (more edges = rougher surface)
        guard let filter = CIFilter(name: "CIEdges") else { return 0.5 }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(2.0, forKey: "inputIntensity")

        guard let edges = filter.outputImage else { return 0.5 }

        // Count non-zero pixels (edges)
        let context = CIContext()
        var bitmap = [UInt8](repeating: 0, count: Int(edges.extent.width * edges.extent.height * 4))
        context.render(edges, toBitmap: &bitmap, rowBytes: Int(edges.extent.width * 4), bounds: edges.extent, format: .RGBA8, colorSpace: nil)

        let edgePixels = bitmap.filter { $0 > 128 }.count
        let totalPixels = bitmap.count / 4
        let edgeDensity = Float(edgePixels) / Float(totalPixels)

        return min(edgeDensity * 5.0, 1.0)  // Normalize
    }

    private func calculateTransparency(image: CGImage) -> Float {
        // Check if image has alpha channel
        let alphaInfo = image.alphaInfo
        if alphaInfo == .none || alphaInfo == .noneSkipLast || alphaInfo == .noneSkipFirst {
            return 0.0  // No transparency
        }

        // Sample alpha values
        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else {
            return 0.0
        }

        let length = CFDataGetLength(data)
        let bytesPerPixel = image.bitsPerPixel / 8
        var alphaSum = 0

        for i in stride(from: 0, to: length, by: bytesPerPixel) {
            if i + bytesPerPixel - 1 < length {
                alphaSum += Int(bytes[i + bytesPerPixel - 1])
            }
        }

        let avgAlpha = Float(alphaSum) / Float(length / bytesPerPixel) / 255.0
        return 1.0 - avgAlpha  // Invert: low alpha = high transparency
    }

    private func calculateColorVariation(ciImage: CIImage) -> Float {
        // Color variation = diversity of colors
        guard let filter = CIFilter(name: "CIAreaHistogram") else { return 0.5 }
        filter.setValue(ciImage, forKey: kCIInputImageKey)

        // Analyze color distribution
        // Higher variation = more diverse materials (e.g., wood grain)
        return 0.5  // Placeholder - could be enhanced with actual histogram analysis
    }

    private func calculateTextureComplexity(ciImage: CIImage) -> Float {
        // Texture complexity = frequency of patterns
        guard let filter = CIFilter(name: "CIGaborGradients") else { return 0.5 }
        filter.setValue(ciImage, forKey: kCIInputImageKey)

        // Analyze texture patterns
        return 0.6  // Placeholder
    }

    // MARK: - Material Classification

    private func calculateMaterialScores(properties: MaterialAnalysis.SurfaceProperties) -> [(material: MaterialAnalysis.MaterialType, score: Float)] {
        var scores: [(MaterialAnalysis.MaterialType, Float)] = []

        for material in MaterialAnalysis.MaterialType.allCases {
            let score = scoreMaterial(material, properties: properties)
            scores.append((material, score))
        }

        return scores
    }

    private func scoreMaterial(_ material: MaterialAnalysis.MaterialType, properties: MaterialAnalysis.SurfaceProperties) -> Float {
        var score: Float = 0.0

        switch material {
        case .metal:
            score += properties.reflectivity * 0.4        // High reflectivity
            score += (1.0 - properties.roughness) * 0.3   // Smooth surface
            score += (1.0 - properties.transparency) * 0.3 // Opaque

        case .plastic:
            score += properties.reflectivity * 0.2        // Medium reflectivity
            score += (1.0 - properties.roughness) * 0.3   // Smooth
            score += properties.colorVariation * 0.2      // Can be colorful
            score += (1.0 - properties.transparency) * 0.3

        case .wood:
            score += properties.roughness * 0.3           // Textured
            score += properties.textureComplexity * 0.3   // Complex patterns
            score += properties.colorVariation * 0.2      // Grain variation
            score += (1.0 - properties.reflectivity) * 0.2 // Matte

        case .glass:
            score += properties.transparency * 0.5        // Transparent!
            score += properties.reflectivity * 0.3        // Reflective
            score += (1.0 - properties.roughness) * 0.2   // Smooth

        case .cardboard:
            score += properties.roughness * 0.3           // Rough surface
            score += (1.0 - properties.reflectivity) * 0.4 // Matte
            score += properties.textureComplexity * 0.3

        case .ceramic:
            score += (1.0 - properties.roughness) * 0.3   // Smooth
            score += properties.reflectivity * 0.2        // Slightly reflective
            score += (1.0 - properties.transparency) * 0.3
            score += (1.0 - properties.textureComplexity) * 0.2

        case .fabric:
            score += properties.roughness * 0.4           // Very textured
            score += properties.textureComplexity * 0.4   // Complex
            score += (1.0 - properties.reflectivity) * 0.2

        case .rubber:
            score += (1.0 - properties.reflectivity) * 0.4 // Matte
            score += properties.roughness * 0.3           // Textured
            score += (1.0 - properties.transparency) * 0.3

        case .paper:
            score += (1.0 - properties.reflectivity) * 0.4 // Very matte
            score += (1.0 - properties.roughness) * 0.3   // Smooth
            score += properties.textureComplexity * 0.3

        case .stone:
            score += properties.roughness * 0.4           // Rough
            score += properties.textureComplexity * 0.3
            score += (1.0 - properties.reflectivity) * 0.3
        }

        return min(score, 1.0)
    }
}

// MARK: - Errors

enum MaterialDetectionError: Error, LocalizedError {
    case analysisFailed
    case noDataAvailable
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .analysisFailed:
            return "Material-Analyse fehlgeschlagen"
        case .noDataAvailable:
            return "Keine Daten für Analyse verfügbar"
        case .invalidImage:
            return "Ungültiges Bild"
        }
    }
}
