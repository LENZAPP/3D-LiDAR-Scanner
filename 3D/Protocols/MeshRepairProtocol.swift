//
//  MeshRepairProtocol.swift
//  3D
//
//  Protocol abstractions for mesh repair methods
//  Allows for polymorphic mesh repair strategies
//

import Foundation
import ModelIO

// MARK: - Mesh Repair Result

/// Result of a mesh repair operation
struct MeshRepairResult {
    /// The repaired mesh
    let repairedMesh: MDLMesh

    /// Confidence score (0.0 - 1.0)
    let confidence: Float

    /// Number of holes filled
    let holesFixed: Int

    /// Number of vertices added/modified
    let verticesModified: Int

    /// Processing time in seconds
    let processingTime: TimeInterval

    /// Any warnings or issues encountered
    let warnings: [String]

    /// Method used for repair
    let method: String
}

// MARK: - Mesh Repair Protocol

/// Protocol for mesh repair strategies
/// Implementations: VoxelMeshRepair, PoissonMeshRepair, NeuralMeshRefiner
protocol MeshRepairStrategy {

    /// Name of the repair strategy (e.g., "Voxel", "Poisson", "Neural")
    var strategyName: String { get }

    /// Expected processing time category
    var processingSpeed: ProcessingSpeed { get }

    /// Best use case for this strategy
    var bestUseCase: String { get }

    /// Repair a mesh
    /// - Parameter mesh: Input mesh to repair
    /// - Returns: Repair result with repaired mesh and metadata
    /// - Throws: Error if repair fails
    func repair(mesh: MDLMesh) async throws -> MeshRepairResult

    /// Check if this strategy can handle the given mesh
    /// - Parameter mesh: Mesh to check
    /// - Returns: True if this strategy is suitable
    func canHandle(mesh: MDLMesh) -> Bool

    /// Estimate quality improvement (0.0 - 1.0)
    /// - Parameter mesh: Input mesh
    /// - Returns: Expected quality improvement
    func estimateQualityImprovement(for mesh: MDLMesh) -> Float
}

// MARK: - Processing Speed

enum ProcessingSpeed {
    case fast       // < 1 second
    case medium     // 1-5 seconds
    case slow       // 5-15 seconds
    case verySlow   // > 15 seconds

    var description: String {
        switch self {
        case .fast: return "< 1s"
        case .medium: return "1-5s"
        case .slow: return "5-15s"
        case .verySlow: return "> 15s"
        }
    }
}

// MARK: - Mesh Repair Coordinator

/// Coordinates mesh repair by selecting the best strategy
class MeshRepairCoordinator {

    private var strategies: [MeshRepairStrategy] = []

    /// Register a repair strategy
    func register(strategy: MeshRepairStrategy) {
        strategies.append(strategy)
    }

    /// Select the best strategy for a given mesh
    /// - Parameter mesh: Mesh to repair
    /// - Returns: Best strategy or nil if none suitable
    func selectBestStrategy(for mesh: MDLMesh) -> MeshRepairStrategy? {
        // Filter to strategies that can handle this mesh
        let suitableStrategies = strategies.filter { $0.canHandle(mesh: mesh) }

        // Select strategy with highest estimated quality improvement
        return suitableStrategies.max { a, b in
            a.estimateQualityImprovement(for: mesh) < b.estimateQualityImprovement(for: mesh)
        }
    }

    /// Repair mesh using the best available strategy
    /// - Parameter mesh: Mesh to repair
    /// - Returns: Repair result
    /// - Throws: Error if no suitable strategy or repair fails
    func repairMesh(_ mesh: MDLMesh) async throws -> MeshRepairResult {
        guard let strategy = selectBestStrategy(for: mesh) else {
            throw MeshRepairError.noSuitableStrategy
        }

        print("🔧 Using \(strategy.strategyName) repair strategy")
        print("   Speed: \(strategy.processingSpeed.description)")
        print("   Best for: \(strategy.bestUseCase)")

        return try await strategy.repair(mesh: mesh)
    }

    /// Try multiple strategies and return the best result
    /// - Parameter mesh: Mesh to repair
    /// - Returns: Best repair result
    /// - Throws: Error if all strategies fail
    func repairWithFallback(_ mesh: MDLMesh) async throws -> MeshRepairResult {
        let suitableStrategies = strategies
            .filter { $0.canHandle(mesh: mesh) }
            .sorted { a, b in
                // Try fastest strategies first
                a.processingSpeed.rawValue < b.processingSpeed.rawValue
            }

        guard !suitableStrategies.isEmpty else {
            throw MeshRepairError.noSuitableStrategy
        }

        var lastError: Error?
        var bestResult: MeshRepairResult?

        for strategy in suitableStrategies {
            do {
                let result = try await strategy.repair(mesh: mesh)

                // Keep track of best result so far
                if let best = bestResult {
                    if result.confidence > best.confidence {
                        bestResult = result
                    }
                } else {
                    bestResult = result
                }

                // If confidence is high enough, stop trying
                if result.confidence > 0.85 {
                    break
                }
            } catch {
                lastError = error
                print("⚠️ \(strategy.strategyName) failed: \(error.localizedDescription)")
                continue
            }
        }

        if let result = bestResult {
            return result
        }

        // All strategies failed
        throw lastError ?? MeshRepairError.allStrategiesFailed
    }
}

// MARK: - Processing Speed Comparable

extension ProcessingSpeed: Comparable {
    var rawValue: Int {
        switch self {
        case .fast: return 0
        case .medium: return 1
        case .slow: return 2
        case .verySlow: return 3
        }
    }

    static func < (lhs: ProcessingSpeed, rhs: ProcessingSpeed) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Errors

enum MeshRepairError: Error, LocalizedError {
    case noSuitableStrategy
    case allStrategiesFailed
    case invalidMesh
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSuitableStrategy:
            return "No suitable mesh repair strategy found for this mesh"
        case .allStrategiesFailed:
            return "All mesh repair strategies failed"
        case .invalidMesh:
            return "Invalid mesh: cannot be repaired"
        case .processingFailed(let reason):
            return "Mesh repair processing failed: \(reason)"
        }
    }
}
