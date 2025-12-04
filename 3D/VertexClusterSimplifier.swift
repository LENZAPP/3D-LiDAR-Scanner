//
//  VertexClusterSimplifier.swift
//  3D
//
//  Fast mesh simplification using vertex clustering
//  Trade-off: Speed over quality (good for real-time preview)
//

import Foundation
import simd
import ModelIO

/// Fast vertex clustering simplification
class VertexClusterSimplifier {

    // MARK: - Configuration

    struct Config {
        /// Grid resolution for clustering (lower = more aggressive simplification)
        var gridResolution: Int = 32

        /// Minimum cluster size to prevent over-simplification
        var minClusterSize: Int = 1

        init(gridResolution: Int = 32, minClusterSize: Int = 1) {
            self.gridResolution = gridResolution
            self.minClusterSize = minClusterSize
        }

        /// Preset configurations
        static let aggressive = Config(gridResolution: 16, minClusterSize: 1)
        static let balanced = Config(gridResolution: 32, minClusterSize: 1)
        static let conservative = Config(gridResolution: 64, minClusterSize: 2)
    }

    // MARK: - Data Structures

    struct Cluster {
        var vertices: [Int] = []
        var centroid: SIMD3<Double> = .zero

        mutating func addVertex(_ index: Int, position: SIMD3<Double>) {
            vertices.append(index)
            // Running average for centroid
            let count = Double(vertices.count)
            centroid = (centroid * (count - 1.0) + position) / count
        }
    }

    // MARK: - Simplification

    /// Simplify mesh using vertex clustering
    func simplify(mesh: MDLMesh, config: Config = .balanced, progress: ((Double) -> Void)? = nil) -> MDLMesh? {
        guard let vertexBuffer = mesh.vertexBuffers.first else { return nil }
        guard let layout = mesh.vertexDescriptor.layouts.object(at: 0) as? MDLVertexBufferLayout else { return nil }

        let strideValue = layout.stride
        let vertexCount = vertexBuffer.length / strideValue

        print("⚡️ Vertex Clustering: \(vertexCount) vertices, grid: \(config.gridResolution)³")

        // Extract vertices and faces
        let vertices = extractVertices(from: mesh)
        let faces = extractFaces(from: mesh)

        guard !vertices.isEmpty && !faces.isEmpty else { return nil }

        progress?(0.2)

        // Compute bounding box
        let bbox = computeBoundingBox(vertices: vertices)
        let gridSize = (bbox.max - bbox.min) / Double(config.gridResolution)

        progress?(0.3)

        // Assign vertices to grid cells
        var grid: [SIMD3<Int>: Cluster] = [:]

        for (index, vertex) in vertices.enumerated() {
            let gridCoord = computeGridCoordinate(position: vertex, bbox: bbox, gridSize: gridSize)
            grid[gridCoord, default: Cluster()].addVertex(index, position: vertex)
        }

        print("📊 Created \(grid.count) clusters from \(vertexCount) vertices")
        progress?(0.5)

        // Create vertex mapping (old index -> new index)
        var vertexMapping: [Int: Int] = [:]
        var newVertices: [SIMD3<Double>] = []

        for cluster in grid.values {
            guard cluster.vertices.count >= config.minClusterSize else { continue }

            let newIndex = newVertices.count
            newVertices.append(cluster.centroid)

            for oldIndex in cluster.vertices {
                vertexMapping[oldIndex] = newIndex
            }
        }

        progress?(0.7)

        // Remap faces
        var newFaces: [[Int]] = []

        for face in faces {
            guard face.count == 3 else { continue }

            guard let i0 = vertexMapping[face[0]],
                  let i1 = vertexMapping[face[1]],
                  let i2 = vertexMapping[face[2]] else {
                continue
            }

            // Skip degenerate triangles
            if i0 != i1 && i1 != i2 && i0 != i2 {
                newFaces.append([i0, i1, i2])
            }
        }

        progress?(0.9)

        print("✅ Clustered mesh: \(newVertices.count) vertices, \(newFaces.count) faces")

        // Rebuild mesh
        let result = rebuildMesh(vertices: newVertices, faces: newFaces, originalMesh: mesh)
        progress?(1.0)

        return result
    }

    // MARK: - Helper Methods

    private func extractVertices(from mesh: MDLMesh) -> [SIMD3<Double>] {
        guard let vertexBuffer = mesh.vertexBuffers.first else { return [] }
        guard let layout = mesh.vertexDescriptor.layouts.object(at: 0) as? MDLVertexBufferLayout else { return [] }

        let strideValue = layout.stride
        let vertexCount = vertexBuffer.length / strideValue
        let data = Data(bytes: vertexBuffer.map().bytes, count: vertexBuffer.length)

        var vertices: [SIMD3<Double>] = []

        for i in 0..<vertexCount {
            let offset = i * strideValue
            let x = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Float.self) }
            let y = data.withUnsafeBytes { $0.load(fromByteOffset: offset + 4, as: Float.self) }
            let z = data.withUnsafeBytes { $0.load(fromByteOffset: offset + 8, as: Float.self) }
            vertices.append(SIMD3<Double>(Double(x), Double(y), Double(z)))
        }

        return vertices
    }

    private func extractFaces(from mesh: MDLMesh) -> [[Int]] {
        var faces: [[Int]] = []

        // Safe cast - submeshes might not be [MDLSubmesh]
        guard let submeshes = mesh.submeshes as? [MDLSubmesh] else {
            print("⚠️ Invalid submesh format in extractFaces")
            return []
        }

        for submesh in submeshes {
            let indexBuffer = submesh.indexBuffer
            let indexCount = submesh.indexCount
            let indexType = submesh.indexType

            let data = Data(bytes: indexBuffer.map().bytes, count: indexBuffer.length)

            for i in stride(from: 0, to: indexCount, by: 3) {
                var triangle: [Int] = []

                for j in 0..<3 {
                    let index: Int
                    if indexType == .uint16 {
                        index = Int(data.withUnsafeBytes { $0.load(fromByteOffset: (i + j) * 2, as: UInt16.self) })
                    } else {
                        index = Int(data.withUnsafeBytes { $0.load(fromByteOffset: (i + j) * 4, as: UInt32.self) })
                    }
                    triangle.append(index)
                }

                if triangle[0] != triangle[1] && triangle[1] != triangle[2] && triangle[0] != triangle[2] {
                    faces.append(triangle)
                }
            }
        }

        return faces
    }

    private func computeBoundingBox(vertices: [SIMD3<Double>]) -> (min: SIMD3<Double>, max: SIMD3<Double>) {
        guard let first = vertices.first else {
            return (min: .zero, max: .zero)
        }

        var minBounds = first
        var maxBounds = first

        for vertex in vertices {
            minBounds = simd_min(minBounds, vertex)
            maxBounds = simd_max(maxBounds, vertex)
        }

        return (min: minBounds, max: maxBounds)
    }

    private func computeGridCoordinate(position: SIMD3<Double>, bbox: (min: SIMD3<Double>, max: SIMD3<Double>), gridSize: SIMD3<Double>) -> SIMD3<Int> {
        let normalized = (position - bbox.min) / gridSize
        return SIMD3<Int>(
            Int(floor(normalized.x)),
            Int(floor(normalized.y)),
            Int(floor(normalized.z))
        )
    }

    private func rebuildMesh(vertices: [SIMD3<Double>], faces: [[Int]], originalMesh: MDLMesh) -> MDLMesh? {
        // Convert to Float
        let vertexData = vertices.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) }

        let allocator = MDLMeshBufferDataAllocator()
        let vertexBuffer = allocator.newBuffer(with: Data(bytes: vertexData, count: vertexData.count * MemoryLayout<SIMD3<Float>>.stride), type: .vertex)

        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<SIMD3<Float>>.stride)

        // Create index buffer
        var indices: [UInt32] = []
        for face in faces {
            indices.append(contentsOf: face.map { UInt32($0) })
        }

        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.stride)
        let indexBuffer = allocator.newBuffer(with: indexData, type: .index)

        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: indices.count,
            indexType: .uInt32,
            geometryType: .triangles,
            material: nil
        )

        let mesh = MDLMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: vertexData.count,
            descriptor: vertexDescriptor,
            submeshes: [submesh]
        )

        return mesh
    }
}
