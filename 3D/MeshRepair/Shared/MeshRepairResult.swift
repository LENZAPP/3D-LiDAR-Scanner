//
//  MeshRepairResult.swift
//  3D
//
//  Result structure for mesh repair operations
//

import Foundation
import ModelIO

public struct MeshRepairResult {
    public let mesh: MDLMesh
    public let method: MeshRepairMethod
    public let processingTime: TimeInterval
    public let memoryUsed: Int  // Bytes
    public let qualityScore: Double  // 0.0-1.0
    public let isWatertight: Bool
    public let metrics: RepairMetrics
    public let warnings: [String]

    public init(
        mesh: MDLMesh,
        method: MeshRepairMethod,
        processingTime: TimeInterval,
        memoryUsed: Int,
        qualityScore: Double,
        isWatertight: Bool,
        metrics: RepairMetrics,
        warnings: [String] = []
    ) {
        self.mesh = mesh
        self.method = method
        self.processingTime = processingTime
        self.memoryUsed = memoryUsed
        self.qualityScore = qualityScore
        self.isWatertight = isWatertight
        self.metrics = metrics
        self.warnings = warnings
    }
}

public struct RepairMetrics {
    public let vertexCount: Int
    public let triangleCount: Int
    public let volume: Double  // cm³
    public let boundaryEdges: Int
    public let holesFilledCount: Int

    public init(
        vertexCount: Int = 0,
        triangleCount: Int = 0,
        volume: Double,
        boundaryEdges: Int = 0,
        holesFilledCount: Int = 0
    ) {
        self.vertexCount = vertexCount
        self.triangleCount = triangleCount
        self.volume = volume
        self.boundaryEdges = boundaryEdges
        self.holesFilledCount = holesFilledCount
    }
}

public enum MeshRepairMethod: String {
    case voxel = "Voxel (Fast)"
    case poisson = "Poisson (High Quality)"
    case neural = "Neural (AI)"
    case hybrid = "Hybrid"
    case auto = "Automatic"

    public var displayName: String {
        return self.rawValue
    }
}
