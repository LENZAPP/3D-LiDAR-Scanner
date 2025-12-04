//
//  MeshSimplifier.swift
//  3D
//
//  Unified interface for mesh simplification algorithms
//  Supports both fast (vertex clustering) and high-quality (QEM) methods
//

import Foundation
import ModelIO

/// Mesh simplification manager
@MainActor
class MeshSimplifier: ObservableObject {

    // MARK: - Configuration

    enum SimplificationMethod {
        case fast           // Vertex clustering (real-time preview)
        case balanced       // Moderate QEM
        case highQuality    // Aggressive QEM (best quality)

        var description: String {
            switch self {
            case .fast: return "Schnell (Vertex Clustering)"
            case .balanced: return "Ausgewogen (QEM)"
            case .highQuality: return "Hohe Qualität (QEM)"
            }
        }
    }

    struct SimplificationResult {
        let simplifiedMesh: MDLMesh
        let originalVertexCount: Int
        let simplifiedVertexCount: Int
        let originalFaceCount: Int
        let simplifiedFaceCount: Int
        let reductionPercentage: Double
        let processingTime: TimeInterval

        var summary: String {
            """
            🔧 Mesh Simplification

            Original:
            - Vertices: \(originalVertexCount)
            - Faces: \(originalFaceCount)

            Simplified:
            - Vertices: \(simplifiedVertexCount)
            - Faces: \(simplifiedFaceCount)

            Reduction: \(String(format: "%.1f", reductionPercentage))%
            Time: \(String(format: "%.2f", processingTime))s
            """
        }
    }

    // MARK: - Published Properties

    @Published var isProcessing = false
    @Published var progress: Double = 0.0
    @Published var lastResult: SimplificationResult?

    // MARK: - Private Properties

    private let qemSimplifier = QuadricErrorMetrics()
    private let clusterSimplifier = VertexClusterSimplifier()

    // MARK: - Public Methods

    /// Simplify mesh to target percentage of original vertex count
    func simplify(
        mesh: MDLMesh,
        targetPercentage: Double, // 0.0 - 1.0
        method: SimplificationMethod = .balanced
    ) async -> SimplificationResult? {
        guard !isProcessing else {
            print("⚠️ Simplification already in progress")
            return nil
        }

        isProcessing = true
        progress = 0.0

        let startTime = Date()

        // Get current mesh stats
        guard let vertexBuffer = mesh.vertexBuffers.first else {
            isProcessing = false
            return nil
        }
        guard let layout = mesh.vertexDescriptor.layouts.object(at: 0) as? MDLVertexBufferLayout else {
            isProcessing = false
            return nil
        }

        let strideValue = layout.stride
        let originalVertexCount = vertexBuffer.length / strideValue
        let originalFaceCount = countFaces(in: mesh)

        let targetVertexCount = Int(Double(originalVertexCount) * targetPercentage)

        print("🎯 Simplifying mesh: \(originalVertexCount) → \(targetVertexCount) vertices (\(Int(targetPercentage * 100))%)")

        var simplifiedMesh: MDLMesh?

        switch method {
        case .fast:
            // Use vertex clustering
            let config = VertexClusterSimplifier.Config.aggressive
            simplifiedMesh = clusterSimplifier.simplify(mesh: mesh, config: config) { [weak self] p in
                Task { @MainActor in
                    self?.progress = p
                }
            }

        case .balanced:
            // Use QEM with moderate target
            simplifiedMesh = qemSimplifier.simplify(mesh: mesh, targetVertexCount: targetVertexCount) { [weak self] p in
                Task { @MainActor in
                    self?.progress = p
                }
            }

        case .highQuality:
            // Use QEM with conservative target
            let conservativeTarget = max(targetVertexCount, Int(Double(originalVertexCount) * 0.5))
            simplifiedMesh = qemSimplifier.simplify(mesh: mesh, targetVertexCount: conservativeTarget) { [weak self] p in
                Task { @MainActor in
                    self?.progress = p
                }
            }
        }

        guard let simplified = simplifiedMesh else {
            isProcessing = false
            progress = 0.0
            return nil
        }

        // Get simplified mesh stats
        guard let simplifiedVertexBuffer = simplified.vertexBuffers.first else {
            isProcessing = false
            return nil
        }
        guard let simplifiedLayout = simplified.vertexDescriptor.layouts.object(at: 0) as? MDLVertexBufferLayout else {
            isProcessing = false
            return nil
        }

        let simplifiedStrideValue = simplifiedLayout.stride
        let simplifiedVertexCount = simplifiedVertexBuffer.length / simplifiedStrideValue
        let simplifiedFaceCount = countFaces(in: simplified)

        let reductionPercentage = (1.0 - Double(simplifiedVertexCount) / Double(originalVertexCount)) * 100.0
        let processingTime = Date().timeIntervalSince(startTime)

        let result = SimplificationResult(
            simplifiedMesh: simplified,
            originalVertexCount: originalVertexCount,
            simplifiedVertexCount: simplifiedVertexCount,
            originalFaceCount: originalFaceCount,
            simplifiedFaceCount: simplifiedFaceCount,
            reductionPercentage: reductionPercentage,
            processingTime: processingTime
        )

        lastResult = result
        isProcessing = false
        progress = 1.0

        print(result.summary)

        return result
    }

    /// Simplify with automatic quality adjustment based on mesh size
    func simplifyAuto(mesh: MDLMesh) async -> SimplificationResult? {
        guard let vertexBuffer = mesh.vertexBuffers.first else { return nil }
        guard let layout = mesh.vertexDescriptor.layouts.object(at: 0) as? MDLVertexBufferLayout else { return nil }

        let strideValue = layout.stride
        let vertexCount = vertexBuffer.length / strideValue

        // Automatic quality selection based on mesh complexity
        let (targetPercentage, method): (Double, SimplificationMethod)

        switch vertexCount {
        case 0..<1000:
            // Small mesh, don't simplify much
            return nil

        case 1000..<10000:
            // Medium mesh, light simplification
            (targetPercentage, method) = (0.7, .balanced)

        case 10000..<50000:
            // Large mesh, moderate simplification
            (targetPercentage, method) = (0.5, .balanced)

        default:
            // Very large mesh, aggressive simplification
            (targetPercentage, method) = (0.3, .fast)
        }

        print("🤖 Auto-simplification: \(vertexCount) vertices → \(method.description), target: \(Int(targetPercentage * 100))%")

        return await simplify(mesh: mesh, targetPercentage: targetPercentage, method: method)
    }

    // MARK: - Helper Methods

    private func countFaces(in mesh: MDLMesh) -> Int {
        var totalFaces = 0

        // Safe cast - submeshes might not be [MDLSubmesh]
        guard let submeshes = mesh.submeshes as? [MDLSubmesh] else {
            print("⚠️ Invalid submesh format in countFaces")
            return 0
        }

        for submesh in submeshes {
            totalFaces += submesh.indexCount / 3
        }

        return totalFaces
    }
}
