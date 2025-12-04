//
//  WatertightChecker.swift
//  3D
//
//  Enhanced Watertight Mesh Topology Checker
//  Uses Edge Manifold Test + Euler Characteristic for accurate diagnosis
//

import Foundation
import ModelIO

/// Advanced watertight mesh checker using topology analysis
class WatertightChecker {

    /// Edge representation with normalized vertex ordering
    struct Edge: Hashable {
        let v0: UInt32
        let v1: UInt32

        /// Initialize edge with automatic normalization (smaller index first)
        init(_ a: UInt32, _ b: UInt32) {
            if a < b {
                (v0, v1) = (a, b)
            } else {
                (v0, v1) = (b, a)
            }
        }
    }

    /// Result of watertight analysis
    struct WatertightResult {
        let isWatertight: Bool
        let boundaryEdgeCount: Int
        let estimatedHoleCount: Int
        let eulerCharacteristic: Int
        let qualityScore: Double

        var description: String {
            """
            🔍 Mesh Topology Analysis:
            - Watertight: \(isWatertight ? "✅ YES" : "❌ NO")
            - Boundary Edges: \(boundaryEdgeCount)
            - Estimated Holes: \(estimatedHoleCount)
            - Euler Characteristic: \(eulerCharacteristic) (expected: 2 for sphere-like)
            - Quality Score: \(String(format: "%.2f", qualityScore))
            """
        }
    }

    /// Performs comprehensive watertight analysis on mesh
    /// - Parameter mesh: MDLMesh to analyze
    /// - Returns: WatertightResult with detailed topology information
    func analyze(_ mesh: MDLMesh) -> WatertightResult {
        var edgeCount: [Edge: Int] = [:]
        var totalTriangles = 0

        // Count edges across all submeshes
        for submesh in mesh.submeshes ?? [] {
            guard let submesh = submesh as? MDLSubmesh else { continue }

            let indexBuffer = submesh.indexBuffer
            let indexData = indexBuffer.map().bytes
            let indexCount = submesh.indexCount

            // Process each triangle
            for i in stride(from: 0, to: indexCount, by: 3) {
                // Read triangle indices
                let idx0 = indexData.advanced(by: i * MemoryLayout<UInt32>.size)
                    .assumingMemoryBound(to: UInt32.self).pointee
                let idx1 = indexData.advanced(by: (i + 1) * MemoryLayout<UInt32>.size)
                    .assumingMemoryBound(to: UInt32.self).pointee
                let idx2 = indexData.advanced(by: (i + 2) * MemoryLayout<UInt32>.size)
                    .assumingMemoryBound(to: UInt32.self).pointee

                // Count each edge of the triangle
                edgeCount[Edge(idx0, idx1), default: 0] += 1
                edgeCount[Edge(idx1, idx2), default: 0] += 1
                edgeCount[Edge(idx2, idx0), default: 0] += 1

                totalTriangles += 1
            }
        }

        // Analyze edge manifold property
        // In a watertight mesh, every edge should be shared by exactly 2 faces
        let boundaryEdges = edgeCount.values.filter { $0 == 1 }.count
        let nonManifoldEdges = edgeCount.values.filter { $0 > 2 }.count

        // Estimate hole count (rough heuristic: boundary edges / 4)
        let estimatedHoles = boundaryEdges > 0 ? max(1, boundaryEdges / 4) : 0

        // Calculate Euler Characteristic: V - E + F = 2 (for sphere-like closed mesh)
        let vertexCount = Int(mesh.vertexCount)
        let edgeTotal = edgeCount.count
        let faceCount = totalTriangles
        let eulerChar = vertexCount - edgeTotal + faceCount

        // Determine if mesh is watertight
        let isWatertight = (boundaryEdges == 0) && (nonManifoldEdges == 0)

        // Calculate quality score (0.0 = poor, 1.0 = perfect)
        let qualityScore: Double
        if isWatertight {
            // Perfect watertight mesh
            qualityScore = 1.0
        } else {
            // Quality degrades with boundary edges
            let edgeRatio = Double(boundaryEdges) / Double(vertexCount)
            let nonManifoldPenalty = Double(nonManifoldEdges) / Double(edgeTotal)
            qualityScore = max(0.0, 1.0 - (edgeRatio * 10) - (nonManifoldPenalty * 5))
        }

        return WatertightResult(
            isWatertight: isWatertight,
            boundaryEdgeCount: boundaryEdges,
            estimatedHoleCount: estimatedHoles,
            eulerCharacteristic: eulerChar,
            qualityScore: qualityScore
        )
    }
}
