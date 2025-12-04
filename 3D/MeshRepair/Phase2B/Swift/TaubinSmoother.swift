//
//  TaubinSmoother.swift
//  3D
//
//  Volume-preserving Taubin smoothing for mesh refinement
//

import Foundation
import ModelIO
import simd

public class TaubinSmoother {

    /// Apply volume-preserving Taubin smoothing to mesh
    ///
    /// - Parameters:
    ///   - mesh: Input mesh to smooth
    ///   - iterations: Number of smoothing iterations (5-10 typical)
    ///   - lambda: Positive smoothing factor (0.5 typical)
    ///   - mu: Negative smoothing factor (should be < -lambda, typically -0.53)
    /// - Returns: Smoothed mesh
    public static func smooth(
        _ mesh: MDLMesh,
        iterations: Int = 5,
        lambda: Float = 0.5,
        mu: Float = -0.53
    ) -> MDLMesh {

        guard iterations > 0 else { return mesh }

        // Extract vertex positions
        var vertices = extractVertices(mesh)
        let adjacency = buildAdjacency(mesh)

        // Apply Taubin iterations
        for _ in 0..<iterations {
            // Positive smoothing pass (shrinks)
            vertices = smoothPass(vertices, adjacency: adjacency, factor: lambda)

            // Negative smoothing pass (expands, compensates shrinkage)
            vertices = smoothPass(vertices, adjacency: adjacency, factor: mu)
        }

        // Update mesh with smoothed vertices
        return updateMeshVertices(mesh, with: vertices)
    }

    // MARK: - Smoothing Pass

    private static func smoothPass(
        _ vertices: [SIMD3<Float>],
        adjacency: [[Int]],
        factor: Float
    ) -> [SIMD3<Float>] {

        var smoothed = vertices

        for i in 0..<vertices.count {
            let neighbors = adjacency[i]
            guard !neighbors.isEmpty else { continue }

            // Compute Laplacian (average neighbor displacement)
            var laplacian = SIMD3<Float>.zero
            for neighborIdx in neighbors {
                laplacian += vertices[neighborIdx] - vertices[i]
            }
            laplacian /= Float(neighbors.count)

            // Update position
            smoothed[i] = vertices[i] + factor * laplacian
        }

        return smoothed
    }

    // MARK: - Adjacency Building

    private static func buildAdjacency(_ mesh: MDLMesh) -> [[Int]] {
        let vertexCount = mesh.vertexCount
        var adjacency = Array(repeating: Set<Int>(), count: vertexCount)

        // Extract triangle indices
        guard let submesh = mesh.submeshes?.object(at: 0) as? MDLSubmesh else {
            return adjacency.map { Array($0) }
        }

        let indexBuffer = submesh.indexBuffer.map()
        let indexType = submesh.indexType

        // Parse indices based on type
        for i in stride(from: 0, to: submesh.indexCount, by: 3) {
            let i0: Int
            let i1: Int
            let i2: Int

            switch indexType {
            case .uInt32:
                let indices = indexBuffer.bytes.assumingMemoryBound(to: UInt32.self)
                i0 = Int(indices[i])
                i1 = Int(indices[i+1])
                i2 = Int(indices[i+2])
            case .uInt16:
                let indices = indexBuffer.bytes.assumingMemoryBound(to: UInt16.self)
                i0 = Int(indices[i])
                i1 = Int(indices[i+1])
                i2 = Int(indices[i+2])
            default:
                continue
            }

            // Add bidirectional edges
            adjacency[i0].insert(i1)
            adjacency[i0].insert(i2)
            adjacency[i1].insert(i0)
            adjacency[i1].insert(i2)
            adjacency[i2].insert(i0)
            adjacency[i2].insert(i1)
        }

        return adjacency.map { Array($0) }
    }

    // MARK: - Vertex Extraction

    private static func extractVertices(_ mesh: MDLMesh) -> [SIMD3<Float>] {
        var vertices: [SIMD3<Float>] = []

        guard let vertexBuffer = mesh.vertexBuffers.first else { return vertices }
        let vertexData = vertexBuffer.map().bytes

        guard let layout = mesh.vertexDescriptor.layouts.object(at: 0) as? MDLVertexBufferLayout else {
            return vertices
        }

        let stride = layout.stride
        let vertexCount = mesh.vertexCount

        vertices.reserveCapacity(vertexCount)

        for i in 0..<vertexCount {
            let offset = i * stride
            let position = vertexData.advanced(by: offset).assumingMemoryBound(to: SIMD3<Float>.self).pointee
            vertices.append(position)
        }

        return vertices
    }

    // MARK: - Mesh Update

    private static func updateMeshVertices(_ mesh: MDLMesh, with vertices: [SIMD3<Float>]) -> MDLMesh {
        // Create new vertex buffer with updated positions
        let vertexData = Data(bytes: vertices, count: vertices.count * MemoryLayout<SIMD3<Float>>.size)
        let vertexBuffer = MDLMeshBufferData(type: .vertex, data: vertexData)

        // Create new mesh with same topology, updated vertices
        let newMesh = MDLMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: vertices.count,
            descriptor: mesh.vertexDescriptor,
            submeshes: mesh.submeshes as? [MDLSubmesh] ?? []
        )

        return newMesh
    }
}
