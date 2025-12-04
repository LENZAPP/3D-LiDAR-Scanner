//
//  QuadricErrorMetrics.swift
//  3D
//
//  High-quality mesh simplification using Quadric Error Metrics (QEM)
//  Based on Garland & Heckbert's "Surface Simplification Using Quadric Error Metrics"
//

import Foundation
import simd
import ModelIO

/// Quadric Error Metrics for high-quality mesh simplification
class QuadricErrorMetrics {

    // MARK: - Data Structures

    /// Symmetric 4x4 matrix representing quadric error
    struct Quadric {
        var q: [Double] // 10 unique values for symmetric 4x4 matrix

        init() {
            q = Array(repeating: 0.0, count: 10)
        }

        init(plane: SIMD4<Double>) {
            q = Array(repeating: 0.0, count: 10)
            // Q = plane * plane^T (symmetric matrix)
            let a = plane.x, b = plane.y, c = plane.z, d = plane.w
            q[0] = a * a  // q11
            q[1] = a * b  // q12
            q[2] = a * c  // q13
            q[3] = a * d  // q14
            q[4] = b * b  // q22
            q[5] = b * c  // q23
            q[6] = b * d  // q24
            q[7] = c * c  // q33
            q[8] = c * d  // q34
            q[9] = d * d  // q44
        }

        /// Add two quadrics
        static func + (left: Quadric, right: Quadric) -> Quadric {
            var result = Quadric()
            for i in 0..<10 {
                result.q[i] = left.q[i] + right.q[i]
            }
            return result
        }

        /// Calculate error for a vertex position
        func error(at position: SIMD3<Double>) -> Double {
            let x = position.x, y = position.y, z = position.z
            return q[0] * x * x + 2 * q[1] * x * y + 2 * q[2] * x * z + 2 * q[3] * x +
                   q[4] * y * y + 2 * q[5] * y * z + 2 * q[6] * y +
                   q[7] * z * z + 2 * q[8] * z +
                   q[9]
        }
    }

    /// Edge collapse candidate
    struct EdgeCollapse: Comparable {
        let vertexIndex1: Int
        let vertexIndex2: Int
        let error: Double
        let newPosition: SIMD3<Double>

        static func < (lhs: EdgeCollapse, rhs: EdgeCollapse) -> Bool {
            return lhs.error < rhs.error
        }
    }

    // MARK: - Simplification

    /// Simplify mesh to target vertex count using QEM
    func simplify(mesh: MDLMesh, targetVertexCount: Int, progress: ((Double) -> Void)? = nil) -> MDLMesh? {
        guard let vertexBuffer = mesh.vertexBuffers.first else { return nil }
        guard let layout = mesh.vertexDescriptor.layouts.object(at: 0) as? MDLVertexBufferLayout else { return nil }

        let strideValue = layout.stride
        let vertexCount = vertexBuffer.length / strideValue

        // Don't simplify if already at or below target
        guard vertexCount > targetVertexCount else { return mesh }

        print("🔧 QEM Simplification: \(vertexCount) → \(targetVertexCount) vertices")

        // Extract vertex data
        var vertices = extractVertices(from: mesh)
        var faces = extractFaces(from: mesh)

        guard !vertices.isEmpty && !faces.isEmpty else { return nil }

        // Step 1: Compute initial quadrics for each vertex
        var quadrics = computeVertexQuadrics(vertices: vertices, faces: faces)

        // Step 2: Select all valid pairs (edges)
        let validPairs = selectValidPairs(vertices: vertices, faces: faces)

        // Step 3: Compute optimal contraction targets
        var heap = computeContractionHeap(pairs: validPairs, quadrics: quadrics, vertices: vertices)

        // Step 4: Iteratively remove pairs of least cost
        let targetRemovals = vertexCount - targetVertexCount
        var removedCount = 0
        var vertexMapping: [Int: Int] = [:] // Maps old vertex index to new

        while removedCount < targetRemovals && !heap.isEmpty {
            let collapse = heap.removeFirst()

            // Check if vertices still exist
            guard vertexMapping[collapse.vertexIndex1] == nil,
                  vertexMapping[collapse.vertexIndex2] == nil else {
                continue
            }

            // Perform collapse
            let v1 = collapse.vertexIndex1
            let v2 = collapse.vertexIndex2

            // Update vertex position
            vertices[v1] = collapse.newPosition

            // Merge quadrics
            quadrics[v1] = quadrics[v1] + quadrics[v2]

            // Mark v2 as removed, mapped to v1
            vertexMapping[v2] = v1

            // Update faces
            updateFaces(faces: &faces, from: v2, to: v1)

            removedCount += 1

            if removedCount % 100 == 0 {
                let progressValue = Double(removedCount) / Double(targetRemovals)
                progress?(progressValue)
            }
        }

        progress?(1.0)

        // Rebuild mesh
        return rebuildMesh(vertices: vertices, faces: faces, vertexMapping: vertexMapping, originalMesh: mesh)
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

    private func computeVertexQuadrics(vertices: [SIMD3<Double>], faces: [[Int]]) -> [Quadric] {
        var quadrics = Array(repeating: Quadric(), count: vertices.count)

        for face in faces {
            guard face.count == 3 else { continue }

            let v0 = vertices[face[0]]
            let v1 = vertices[face[1]]
            let v2 = vertices[face[2]]

            // Compute plane equation: ax + by + cz + d = 0
            let edge1 = v1 - v0
            let edge2 = v2 - v0
            var normal = cross(edge1, edge2)
            let length = simd_length(normal)

            guard length > 0.0001 else { continue }

            normal = normalize(normal)
            let d = -dot(normal, v0)

            let plane = SIMD4<Double>(normal.x, normal.y, normal.z, d)
            let faceQuadric = Quadric(plane: plane)

            // Add to each vertex in the face
            quadrics[face[0]] = quadrics[face[0]] + faceQuadric
            quadrics[face[1]] = quadrics[face[1]] + faceQuadric
            quadrics[face[2]] = quadrics[face[2]] + faceQuadric
        }

        return quadrics
    }

    private func selectValidPairs(vertices: [SIMD3<Double>], faces: [[Int]]) -> Set<Set<Int>> {
        var pairs = Set<Set<Int>>()

        // Add all edges from faces
        for face in faces {
            guard face.count == 3 else { continue }
            pairs.insert(Set([face[0], face[1]]))
            pairs.insert(Set([face[1], face[2]]))
            pairs.insert(Set([face[2], face[0]]))
        }

        return pairs
    }

    private func computeContractionHeap(pairs: Set<Set<Int>>, quadrics: [Quadric], vertices: [SIMD3<Double>]) -> [EdgeCollapse] {
        var candidates: [EdgeCollapse] = []

        for pair in pairs {
            let indices = Array(pair)
            guard indices.count == 2 else { continue }

            let v1 = indices[0]
            let v2 = indices[1]

            let combinedQuadric = quadrics[v1] + quadrics[v2]

            // Simple strategy: use midpoint
            let newPosition = (vertices[v1] + vertices[v2]) / 2.0
            let error = combinedQuadric.error(at: newPosition)

            candidates.append(EdgeCollapse(
                vertexIndex1: v1,
                vertexIndex2: v2,
                error: error,
                newPosition: newPosition
            ))
        }

        return candidates.sorted()
    }

    private func updateFaces(faces: inout [[Int]], from oldIndex: Int, to newIndex: Int) {
        for i in 0..<faces.count {
            for j in 0..<faces[i].count {
                if faces[i][j] == oldIndex {
                    faces[i][j] = newIndex
                }
            }
        }

        // Remove degenerate faces
        faces.removeAll { face in
            face[0] == face[1] || face[1] == face[2] || face[0] == face[2]
        }
    }

    private func rebuildMesh(vertices: [SIMD3<Double>], faces: [[Int]], vertexMapping: [Int: Int], originalMesh: MDLMesh) -> MDLMesh? {
        // Create new vertex buffer with remaining vertices
        var activeVertices: [SIMD3<Float>] = []
        var oldToNewIndex: [Int: Int] = [:]

        for i in 0..<vertices.count {
            if vertexMapping[i] == nil {
                oldToNewIndex[i] = activeVertices.count
                activeVertices.append(SIMD3<Float>(Float(vertices[i].x), Float(vertices[i].y), Float(vertices[i].z)))
            }
        }

        // Remap faces
        var newFaces: [[Int]] = []
        for face in faces {
            var newFace: [Int] = []
            for index in face {
                if let newIndex = oldToNewIndex[index] {
                    newFace.append(newIndex)
                }
            }
            if newFace.count == 3 && newFace[0] != newFace[1] && newFace[1] != newFace[2] && newFace[0] != newFace[2] {
                newFaces.append(newFace)
            }
        }

        print("✅ Simplified mesh: \(activeVertices.count) vertices, \(newFaces.count) faces")

        // Create MDLMesh
        let allocator = MDLMeshBufferDataAllocator()
        let vertexData = activeVertices.withUnsafeBytes { Data($0) }
        let vertexBuffer = allocator.newBuffer(with: vertexData, type: .vertex)

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
        for face in newFaces {
            indices.append(contentsOf: face.map { UInt32($0) })
        }

        let indexData = indices.withUnsafeBytes { Data($0) }
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
            vertexCount: activeVertices.count,
            descriptor: vertexDescriptor,
            submeshes: [submesh]
        )

        return mesh
    }
}
