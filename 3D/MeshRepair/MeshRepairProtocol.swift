//
//  MeshRepairProtocol.swift
//  3D
//
//  Phase 2B/2C: Unified interface for all mesh repair methods
//  Allows switching between Voxel, Poisson, and Neural approaches
//

import Foundation
import ModelIO

// MARK: - Mesh Repair Strategy Protocol

/// Unified interface for all mesh repair implementations
protocol MeshRepairStrategy {
    /// Repair a mesh and return the result
    func repair(mesh: MDLMesh) async throws -> MeshRepairResult

    /// Estimate processing time for this mesh
    func estimatedTime(for mesh: MDLMesh) -> TimeInterval

    /// Estimate memory usage for this mesh (in bytes)
    func estimatedMemory(for mesh: MDLMesh) -> Int

    /// Calculate quality score for this mesh (0-1, higher is better)
    func qualityScore(for mesh: MDLMesh) -> Float
}

// MARK: - Repair Methods

/// Available mesh repair methods
enum MeshRepairMethod: String, CaseIterable {
    case voxel      // Phase 2A: Fast, guaranteed watertight
    case poisson    // Phase 2B: Smooth, professional quality
    case neural     // Phase 2C: AI-based refinement
    case hybrid     // Voxel base + Neural refinement
    case auto       // Automatic selection based on mesh characteristics

    var displayName: String {
        switch self {
        case .voxel: return "Voxelization"
        case .poisson: return "Poisson Surface Reconstruction"
        case .neural: return "Neural Refinement"
        case .hybrid: return "Hybrid (Voxel + Neural)"
        case .auto: return "Automatic Selection"
        }
    }

    var description: String {
        switch self {
        case .voxel:
            return "Fast, guaranteed watertight. Best for simple objects."
        case .poisson:
            return "Smooth surfaces. Best for complex geometry."
        case .neural:
            return "AI-powered refinement. Best accuracy but requires trained models."
        case .hybrid:
            return "Combines speed of voxelization with AI refinement."
        case .auto:
            return "Automatically selects the best method for the mesh."
        }
    }
}

// MARK: - Repair Result

/// Result of mesh repair operation
struct MeshRepairResult {
    /// The repaired mesh
    let mesh: MDLMesh

    /// Method that was used
    let method: MeshRepairMethod

    /// Time taken to process (seconds)
    let processingTime: TimeInterval

    /// Memory used during processing (bytes)
    let memoryUsed: Int

    /// Quality score (0-1, higher is better)
    let qualityScore: Float

    /// Whether the mesh is watertight after repair
    let isWatertight: Bool

    /// Additional metrics
    let metrics: RepairMetrics

    /// Any warnings or issues encountered
    let warnings: [String]
}

// MARK: - Repair Metrics

/// Detailed metrics about the repair process
struct RepairMetrics {
    // Input mesh stats
    let inputVertexCount: Int
    let inputTriangleCount: Int
    let inputBoundaryEdges: Int
    let inputHoleCount: Int

    // Output mesh stats
    let outputVertexCount: Int
    let outputTriangleCount: Int
    let outputBoundaryEdges: Int
    let outputHoleCount: Int

    // Processing stats
    let pointCloudExtractionTime: TimeInterval
    let reconstructionTime: TimeInterval
    let postProcessingTime: TimeInterval

    // Quality metrics
    let surfaceArea: Float
    let volume: Float
    let averageEdgeLength: Float
    let minTriangleQuality: Float
    let averageTriangleQuality: Float

    var summary: String {
        """
        📊 Repair Metrics:
        Input:  \(inputVertexCount) vertices, \(inputTriangleCount) triangles, \(inputHoleCount) holes
        Output: \(outputVertexCount) vertices, \(outputTriangleCount) triangles, \(outputHoleCount) holes
        Time:   \(String(format: "%.2f", reconstructionTime))s reconstruction
        Quality: \(String(format: "%.2f", averageTriangleQuality)) avg triangle quality
        Volume: \(String(format: "%.1f", volume)) cm³
        """
    }
}

// MARK: - Mesh Repair Error

/// Errors that can occur during mesh repair
enum MeshRepairError: Error, CustomStringConvertible {
    case invalidInput(String)
    case emptyMesh
    case insufficientPoints(Int)
    case memoryLimitExceeded(Int, Int) // used, limit
    case processingTimeout(TimeInterval)
    case poissonFailed(Error)
    case meshFixFailed(Error)
    case voxelizationFailed(Error)
    case modelNotLoaded
    case modelNotFound(String)
    case inferenceError(Error)
    case unsupportedConfiguration
    case bridgeError(String)

    var description: String {
        switch self {
        case .invalidInput(let msg):
            return "Invalid input: \(msg)"
        case .emptyMesh:
            return "Mesh contains no geometry"
        case .insufficientPoints(let count):
            return "Insufficient points for reconstruction: \(count) (need at least 100)"
        case .memoryLimitExceeded(let used, let limit):
            return "Memory limit exceeded: \(used/1024/1024)MB used, \(limit/1024/1024)MB limit"
        case .processingTimeout(let time):
            return "Processing timeout after \(String(format: "%.1f", time))s"
        case .poissonFailed(let error):
            return "Poisson reconstruction failed: \(error.localizedDescription)"
        case .meshFixFailed(let error):
            return "MeshFix failed: \(error.localizedDescription)"
        case .voxelizationFailed(let error):
            return "Voxelization failed: \(error.localizedDescription)"
        case .modelNotLoaded:
            return "CoreML model not loaded"
        case .modelNotFound(let name):
            return "CoreML model not found: \(name).mlmodel"
        case .inferenceError(let error):
            return "Neural inference error: \(error.localizedDescription)"
        case .unsupportedConfiguration:
            return "Unsupported configuration for current device"
        case .bridgeError(let msg):
            return "Objective-C++ bridge error: \(msg)"
        }
    }
}

// MARK: - Mesh Characteristics

/// Characteristics of a mesh used for method selection
struct MeshCharacteristics {
    /// Total number of points in point cloud
    let pointCount: Int

    /// Average points per cubic cm
    let pointDensity: Float

    /// Estimated noise level (0-1)
    let noiseLevel: Float

    /// Coverage completeness (0-1, where 1 is perfect coverage)
    let coverageCompleteness: Float

    /// Geometric complexity (0-1, based on curvature variation)
    let geometricComplexity: Float

    /// Bounding box size (meters)
    let boundingBoxSize: Float

    /// Surface area estimate (cm²)
    let surfaceArea: Float

    /// Whether the object has thin features
    let hasThinFeatures: Bool

    /// Whether the scan has large holes
    let hasLargeHoles: Bool

    var isSimple: Bool {
        geometricComplexity < 0.5 && !hasThinFeatures
    }

    var isHighQuality: Bool {
        coverageCompleteness > 0.85 && noiseLevel < 0.2
    }

    var isSmallObject: Bool {
        boundingBoxSize < 0.3 // < 30cm
    }

    var summary: String {
        """
        📐 Mesh Characteristics:
        - Points: \(pointCount) (\(String(format: "%.1f", pointDensity)) pts/cm³)
        - Size: \(String(format: "%.1f", boundingBoxSize * 100))cm
        - Coverage: \(String(format: "%.0f", coverageCompleteness * 100))%
        - Complexity: \(String(format: "%.0f", geometricComplexity * 100))%
        - Noise: \(String(format: "%.0f", noiseLevel * 100))%
        - Quality: \(isHighQuality ? "High" : "Medium")
        """
    }
}

// MARK: - Configuration

/// Configuration for mesh repair operations
struct MeshRepairConfiguration {
    /// Method to use (or .auto for automatic selection)
    var method: MeshRepairMethod = .auto

    /// Maximum processing time (seconds)
    var maxProcessingTime: TimeInterval = 10.0

    /// Maximum memory usage (bytes)
    var maxMemoryUsage: Int = 200 * 1024 * 1024 // 200 MB

    /// Target quality (0-1, higher requires more processing)
    var targetQuality: Float = 0.8

    /// Enable fallback to simpler methods if primary fails
    var enableFallback: Bool = true

    /// Verbose logging
    var verboseLogging: Bool = true

    // Method-specific configurations
    var voxelConfiguration: VoxelMeshRepair.Configuration = .smallObject
    var poissonDepth: Int = 9
    var meshFixIterations: Int = 10
    var taubinIterations: Int = 5

    static let fast = MeshRepairConfiguration(
        method: .voxel,
        maxProcessingTime: 5.0,
        targetQuality: 0.6,
        voxelConfiguration: VoxelMeshRepair.Configuration(
            resolution: 48,
            occupancyThreshold: 0.3,
            enableSmoothing: true,
            padding: 2
        )
    )

    static let balanced = MeshRepairConfiguration(
        method: .auto,
        maxProcessingTime: 10.0,
        targetQuality: 0.8
    )

    static let highQuality = MeshRepairConfiguration(
        method: .poisson,
        maxProcessingTime: 15.0,
        targetQuality: 0.95,
        poissonDepth: 10,
        taubinIterations: 10
    )

    static let neural = MeshRepairConfiguration(
        method: .neural,
        maxProcessingTime: 12.0,
        targetQuality: 0.95
    )
}
