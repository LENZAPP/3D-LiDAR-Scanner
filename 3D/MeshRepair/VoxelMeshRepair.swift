//
//  VoxelMeshRepair.swift
//  3D
//
//  Voxelization-based mesh repair for LiDAR scans
//  Converts point cloud → voxel grid → watertight mesh
//  Simple, fast, and automatically produces closed surfaces
//

import Foundation
import ModelIO
import simd

/// Triangle representation for mesh (renamed to avoid conflict with SwiftUI Triangle)
public struct MeshTriangle {
    public var a: SIMD3<Float>
    public var b: SIMD3<Float>
    public var c: SIMD3<Float>

    public init(a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>) {
        self.a = a
        self.b = b
        self.c = c
    }
}

/// Voxel-based mesh repair engine
public class VoxelMeshRepair {

    // MARK: - Configuration

    public struct Configuration {
        /// Voxel grid resolution (higher = more detail, more memory)
        public var resolution: Int

        /// Threshold for occupancy (0.0-1.0)
        public var occupancyThreshold: Float

        /// Enable smoothing of voxel mesh
        public var enableSmoothing: Bool

        /// Padding around object (in voxels)
        public var padding: Int

        public static let smallObject = Configuration(
            resolution: 48,              // 48³ voxels = faster, lower memory (110K voxels)
            occupancyThreshold: 0.3,     // Lower = fill more aggressively
            enableSmoothing: true,
            padding: 2                   // 2 voxel padding
        )

        public static let smallObjectHighRes = Configuration(
            resolution: 64,              // 64³ voxels = good quality (262K voxels)
            occupancyThreshold: 0.3,
            enableSmoothing: true,
            padding: 2
        )

        public static let mediumObject = Configuration(
            resolution: 96,              // 96³ voxels = balanced
            occupancyThreshold: 0.4,
            enableSmoothing: true,
            padding: 3
        )

        public static let highQuality = Configuration(
            resolution: 128,             // 128³ voxels = high detail
            occupancyThreshold: 0.5,
            enableSmoothing: true,
            padding: 4
        )
    }

    // MARK: - Public API

    /// Repairs mesh by converting to voxel grid and back
    /// This automatically produces a watertight mesh
    public static func repairMesh(
        _ mesh: MDLMesh,
        configuration: Configuration = .smallObject
    ) -> MDLMesh? {

        print("🔧 Voxel Mesh Repair Started")
        print("   Resolution: \(configuration.resolution)³ voxels")
        print("   Threshold: \(configuration.occupancyThreshold)")

        // Step 1: Extract point cloud from mesh
        guard let pointCloud = extractPointCloud(from: mesh) else {
            print("   ❌ Failed to extract point cloud")
            return nil
        }

        print("   ✅ Extracted \(pointCloud.points.count) points")

        // Step 2: Compute bounding box with padding
        let (bboxMin, bboxMax) = computeBoundingBox(points: pointCloud.points, padding: configuration.padding, resolution: configuration.resolution)

        print("   📦 Bounding Box: \(bboxMin) to \(bboxMax)")

        // Step 3: Create voxel occupancy grid (with memory management)
        let occupancy = autoreleasepool {
            createOccupancyGrid(
                points: pointCloud.points,
                bboxMin: bboxMin,
                bboxMax: bboxMax,
                resolution: configuration.resolution
            )
        }

        print("   ✅ Created occupancy grid")

        // Step 4: Generate watertight mesh from voxels (with memory management)
        let meshTriangles = autoreleasepool {
            meshFromOccupancyGrid(
                occupancy: occupancy,
                dims: (configuration.resolution, configuration.resolution, configuration.resolution),
                bboxMin: bboxMin,
                bboxMax: bboxMax,
                threshold: configuration.occupancyThreshold
            )
        }

        print("   ✅ Generated \(meshTriangles.count) triangles (watertight)")

        // Step 5: Convert triangles back to MDLMesh
        guard let repairedMesh = createMDLMesh(from: meshTriangles) else {
            print("   ❌ Failed to create MDLMesh")
            return nil
        }

        print("✅ Voxel Mesh Repair Complete!")

        return repairedMesh
    }

    // MARK: - Point Cloud Extraction

    private static func extractPointCloud(from mesh: MDLMesh) -> (points: [SIMD3<Float>], normals: [SIMD3<Float>])? {
        var points: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []

        // Get vertex buffer
        guard let vertexBuffer = mesh.vertexBuffers.first else { return nil }
        let vertexData = vertexBuffer.map().bytes

        guard let layout = mesh.vertexDescriptor.layouts.object(at: 0) as? MDLVertexBufferLayout else { return nil }
        let stride = layout.stride

        let vertexCount = mesh.vertexCount

        points.reserveCapacity(vertexCount)
        normals.reserveCapacity(vertexCount)

        // Extract positions
        for i in 0..<vertexCount {
            let offset = i * stride
            let position = vertexData.advanced(by: offset).assumingMemoryBound(to: SIMD3<Float>.self).pointee
            points.append(position)
        }

        // Try to extract normals (optional)
        // For now, we don't need normals for voxelization

        return (points, normals)
    }

    // MARK: - Bounding Box

    private static func computeBoundingBox(
        points: [SIMD3<Float>],
        padding: Int,
        resolution: Int
    ) -> (min: SIMD3<Float>, max: SIMD3<Float>) {

        guard !points.isEmpty else {
            return (SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 1, 1))
        }

        var minP = points[0]
        var maxP = points[0]

        for point in points {
            minP = min(minP, point)
            maxP = max(maxP, point)
        }

        // Add padding
        let size = maxP - minP
        let voxelSize = max(size.x, max(size.y, size.z)) / Float(resolution)
        let paddingSize = voxelSize * Float(padding)

        minP -= SIMD3<Float>(repeating: paddingSize)
        maxP += SIMD3<Float>(repeating: paddingSize)

        return (minP, maxP)
    }

    // MARK: - Voxel Grid Creation

    private static func createOccupancyGrid(
        points: [SIMD3<Float>],
        bboxMin: SIMD3<Float>,
        bboxMax: SIMD3<Float>,
        resolution: Int
    ) -> [Float] {

        let nx = resolution
        let ny = resolution
        let nz = resolution
        let count = nx * ny * nz

        var grid = [Float](repeating: 0.0, count: count)

        let size = bboxMax - bboxMin
        let invScale = SIMD3<Float>(
            Float(nx) / max(1e-6, size.x),
            Float(ny) / max(1e-6, size.y),
            Float(nz) / max(1e-6, size.z)
        )

        func idx(_ x: Int, _ y: Int, _ z: Int) -> Int {
            return z + nz * (y + ny * x)
        }

        // Rasterize points into grid
        for point in points {
            let normalized = (point - bboxMin) * invScale

            let x = Int(normalized.x)
            let y = Int(normalized.y)
            let z = Int(normalized.z)

            // Bounds check
            if x >= 0 && x < nx && y >= 0 && y < ny && z >= 0 && z < nz {
                grid[idx(x, y, z)] += 1.0
            }
        }

        // Normalize to 0-1 range
        let maxVal = grid.max() ?? 1.0
        if maxVal > 0 {
            for i in 0..<count {
                grid[i] /= maxVal
            }
        }

        // Apply dilation to fill small holes
        grid = dilateGrid(grid, dims: (nx, ny, nz), iterations: 1)

        return grid
    }

    /// Morphological dilation to fill small gaps
    private static func dilateGrid(_ grid: [Float], dims: (Int, Int, Int), iterations: Int) -> [Float] {
        let (nx, ny, nz) = dims
        var current = grid

        func idx(_ x: Int, _ y: Int, _ z: Int) -> Int {
            return z + nz * (y + ny * x)
        }

        for _ in 0..<iterations {
            var next = current

            for x in 0..<nx {
                for y in 0..<ny {
                    for z in 0..<nz {
                        if current[idx(x, y, z)] > 0 { continue }

                        // Check 6-connected neighbors
                        var maxNeighbor: Float = 0

                        if x > 0 { maxNeighbor = max(maxNeighbor, current[idx(x-1, y, z)]) }
                        if x < nx-1 { maxNeighbor = max(maxNeighbor, current[idx(x+1, y, z)]) }
                        if y > 0 { maxNeighbor = max(maxNeighbor, current[idx(x, y-1, z)]) }
                        if y < ny-1 { maxNeighbor = max(maxNeighbor, current[idx(x, y+1, z)]) }
                        if z > 0 { maxNeighbor = max(maxNeighbor, current[idx(x, y, z-1)]) }
                        if z < nz-1 { maxNeighbor = max(maxNeighbor, current[idx(x, y, z+1)]) }

                        if maxNeighbor > 0.5 {
                            next[idx(x, y, z)] = maxNeighbor * 0.9
                        }
                    }
                }
            }

            current = next
        }

        return current
    }

    // MARK: - Voxel to Mesh (Marching Cubes style)

    /// Generate watertight triangle mesh from occupancy grid
    /// Uses naive surface extraction (creates cube faces at boundaries)
    private static func meshFromOccupancyGrid(
        occupancy: [Float],
        dims: (Int, Int, Int),
        bboxMin: SIMD3<Float>,
        bboxMax: SIMD3<Float>,
        threshold: Float
    ) -> [MeshTriangle] {

        let (nx, ny, nz) = dims

        guard occupancy.count == nx * ny * nz else { return [] }

        func idx(_ x: Int, _ y: Int, _ z: Int) -> Int {
            return z + nz * (y + ny * x)
        }

        // Voxel size in world coordinates
        let size = bboxMax - bboxMin
        let voxelSize = SIMD3<Float>(
            size.x / Float(nx),
            size.y / Float(ny),
            size.z / Float(nz)
        )

        var triangles: [MeshTriangle] = []
        triangles.reserveCapacity(nx * ny * nz * 2) // Rough estimate

        // For each voxel that is occupied, create faces where neighbors are empty
        for x in 0..<nx {
            for y in 0..<ny {
                for z in 0..<nz {
                    let value = occupancy[idx(x, y, z)]
                    if value < threshold { continue } // Empty voxel

                    // Compute voxel corner in world coords
                    let base = SIMD3<Float>(
                        bboxMin.x + Float(x) * voxelSize.x,
                        bboxMin.y + Float(y) * voxelSize.y,
                        bboxMin.z + Float(z) * voxelSize.z
                    )

                    // 8 corners of voxel cube
                    let p000 = base
                    let p100 = base + SIMD3<Float>(voxelSize.x, 0, 0)
                    let p010 = base + SIMD3<Float>(0, voxelSize.y, 0)
                    let p110 = base + SIMD3<Float>(voxelSize.x, voxelSize.y, 0)
                    let p001 = base + SIMD3<Float>(0, 0, voxelSize.z)
                    let p101 = base + SIMD3<Float>(voxelSize.x, 0, voxelSize.z)
                    let p011 = base + SIMD3<Float>(0, voxelSize.y, voxelSize.z)
                    let p111 = base + SIMD3<Float>(voxelSize.x, voxelSize.y, voxelSize.z)

                    // Check if neighbor is empty/outside
                    func isEmpty(_ nx: Int, _ ny: Int, _ nz: Int) -> Bool {
                        if nx < 0 || ny < 0 || nz < 0 || nx >= dims.0 || ny >= dims.1 || nz >= dims.2 {
                            return true
                        }
                        return occupancy[idx(nx, ny, nz)] < threshold
                    }

                    // -X face
                    if isEmpty(x-1, y, z) {
                        triangles.append(MeshTriangle(a: p000, b: p001, c: p011))
                        triangles.append(MeshTriangle(a: p000, b: p011, c: p010))
                    }

                    // +X face
                    if isEmpty(x+1, y, z) {
                        triangles.append(MeshTriangle(a: p100, b: p110, c: p111))
                        triangles.append(MeshTriangle(a: p100, b: p111, c: p101))
                    }

                    // -Y face
                    if isEmpty(x, y-1, z) {
                        triangles.append(MeshTriangle(a: p000, b: p100, c: p101))
                        triangles.append(MeshTriangle(a: p000, b: p101, c: p001))
                    }

                    // +Y face
                    if isEmpty(x, y+1, z) {
                        triangles.append(MeshTriangle(a: p010, b: p011, c: p111))
                        triangles.append(MeshTriangle(a: p010, b: p111, c: p110))
                    }

                    // -Z face
                    if isEmpty(x, y, z-1) {
                        triangles.append(MeshTriangle(a: p000, b: p010, c: p110))
                        triangles.append(MeshTriangle(a: p000, b: p110, c: p100))
                    }

                    // +Z face
                    if isEmpty(x, y, z+1) {
                        triangles.append(MeshTriangle(a: p001, b: p101, c: p111))
                        triangles.append(MeshTriangle(a: p001, b: p111, c: p011))
                    }
                }
            }
        }

        return triangles
    }

    // MARK: - MDLMesh Creation

    private static func createMDLMesh(from triangles: [MeshTriangle]) -> MDLMesh? {
        guard !triangles.isEmpty else { return nil }

        // Create vertex descriptor
        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<SIMD3<Float>>.size)

        // Build vertex and index arrays
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        vertices.reserveCapacity(triangles.count * 3)
        indices.reserveCapacity(triangles.count * 3)

        for triangle in triangles {
            let baseIndex = UInt32(vertices.count)

            vertices.append(triangle.a)
            vertices.append(triangle.b)
            vertices.append(triangle.c)

            indices.append(baseIndex)
            indices.append(baseIndex + 1)
            indices.append(baseIndex + 2)
        }

        // Create vertex buffer
        let vertexData = Data(bytes: vertices, count: vertices.count * MemoryLayout<SIMD3<Float>>.size)
        let vertexBuffer = MDLMeshBufferData(
            type: .vertex,
            data: vertexData
        )

        // Create index buffer
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.size)
        let indexBuffer = MDLMeshBufferData(
            type: .index,
            data: indexData
        )

        // Create submesh
        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: indices.count,
            indexType: .uInt32,
            geometryType: .triangles,
            material: nil
        )

        // Create mesh
        let mesh = MDLMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: vertices.count,
            descriptor: vertexDescriptor,
            submeshes: [submesh]
        )

        return mesh
    }
}
