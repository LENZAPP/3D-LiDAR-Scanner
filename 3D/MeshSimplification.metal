//
//  MeshSimplification.metal
//  3D
//
//  Metal compute shaders for GPU-accelerated mesh simplification
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Data Structures

struct Vertex {
    float3 position;
    float3 normal;
};

struct GridCell {
    atomic_uint vertexCount;
    float3 centroid;
};

struct BoundingBox {
    float3 min;
    float3 max;
};

// MARK: - Vertex Clustering Shaders

/// Compute grid coordinates for a vertex
kernel void computeGridCoordinates(
    device const Vertex* vertices [[buffer(0)]],
    device int3* gridCoordinates [[buffer(1)]],
    constant BoundingBox& bbox [[buffer(2)]],
    constant int& gridResolution [[buffer(3)]],
    uint vid [[thread_position_in_grid]]
) {
    float3 position = vertices[vid].position;
    float3 size = bbox.max - bbox.min;
    float3 normalized = (position - bbox.min) / size;
    float3 scaled = normalized * float(gridResolution);

    gridCoordinates[vid] = int3(
        clamp(int(scaled.x), 0, gridResolution - 1),
        clamp(int(scaled.y), 0, gridResolution - 1),
        clamp(int(scaled.z), 0, gridResolution - 1)
    );
}

/// Accumulate vertices into grid cells
kernel void accumulateVertices(
    device const Vertex* vertices [[buffer(0)]],
    device const int3* gridCoordinates [[buffer(1)]],
    device atomic_float* gridCentroids [[buffer(2)]],
    device atomic_uint* gridCounts [[buffer(3)]],
    constant int& gridResolution [[buffer(4)]],
    uint vid [[thread_position_in_grid]]
) {
    int3 coord = gridCoordinates[vid];
    int cellIndex = coord.x + coord.y * gridResolution + coord.z * gridResolution * gridResolution;

    float3 position = vertices[vid].position;

    // Atomic add for centroid accumulation
    int baseIndex = cellIndex * 3;
    atomic_fetch_add_explicit(&gridCentroids[baseIndex + 0], position.x, memory_order_relaxed);
    atomic_fetch_add_explicit(&gridCentroids[baseIndex + 1], position.y, memory_order_relaxed);
    atomic_fetch_add_explicit(&gridCentroids[baseIndex + 2], position.z, memory_order_relaxed);

    // Increment count
    atomic_fetch_add_explicit(&gridCounts[cellIndex], 1u, memory_order_relaxed);
}

/// Compute final centroids by averaging
kernel void computeCentroids(
    device float* gridCentroids [[buffer(0)]],
    device const uint* gridCounts [[buffer(1)]],
    constant int& totalCells [[buffer(2)]],
    uint cellId [[thread_position_in_grid]]
) {
    if (cellId >= uint(totalCells)) return;

    uint count = gridCounts[cellId];
    if (count == 0) return;

    int baseIndex = cellId * 3;
    float invCount = 1.0 / float(count);

    gridCentroids[baseIndex + 0] *= invCount;
    gridCentroids[baseIndex + 1] *= invCount;
    gridCentroids[baseIndex + 2] *= invCount;
}

// MARK: - Normal Calculation Shaders

/// Compute face normals for triangles
kernel void computeFaceNormals(
    device const Vertex* vertices [[buffer(0)]],
    device const uint* indices [[buffer(1)]],
    device float3* faceNormals [[buffer(2)]],
    uint faceId [[thread_position_in_grid]]
) {
    uint i0 = indices[faceId * 3 + 0];
    uint i1 = indices[faceId * 3 + 1];
    uint i2 = indices[faceId * 3 + 2];

    float3 v0 = vertices[i0].position;
    float3 v1 = vertices[i1].position;
    float3 v2 = vertices[i2].position;

    float3 edge1 = v1 - v0;
    float3 edge2 = v2 - v0;
    float3 normal = cross(edge1, edge2);

    float len = length(normal);
    if (len > 1e-6) {
        normal /= len;
    }

    faceNormals[faceId] = normal;
}

/// Accumulate normals to vertices (for smooth shading)
kernel void accumulateVertexNormals(
    device const uint* indices [[buffer(0)]],
    device const float3* faceNormals [[buffer(1)]],
    device atomic_float* vertexNormals [[buffer(2)]],
    uint faceId [[thread_position_in_grid]]
) {
    float3 normal = faceNormals[faceId];

    for (int i = 0; i < 3; i++) {
        uint vertexIndex = indices[faceId * 3 + i];
        int baseIndex = vertexIndex * 3;

        atomic_fetch_add_explicit(&vertexNormals[baseIndex + 0], normal.x, memory_order_relaxed);
        atomic_fetch_add_explicit(&vertexNormals[baseIndex + 1], normal.y, memory_order_relaxed);
        atomic_fetch_add_explicit(&vertexNormals[baseIndex + 2], normal.z, memory_order_relaxed);
    }
}

/// Normalize vertex normals
kernel void normalizeVertexNormals(
    device float* vertexNormals [[buffer(0)]],
    constant uint& vertexCount [[buffer(1)]],
    uint vid [[thread_position_in_grid]]
) {
    if (vid >= vertexCount) return;

    int baseIndex = vid * 3;
    float3 normal = float3(
        vertexNormals[baseIndex + 0],
        vertexNormals[baseIndex + 1],
        vertexNormals[baseIndex + 2]
    );

    float len = length(normal);
    if (len > 1e-6) {
        normal /= len;
        vertexNormals[baseIndex + 0] = normal.x;
        vertexNormals[baseIndex + 1] = normal.y;
        vertexNormals[baseIndex + 2] = normal.z;
    }
}

// MARK: - Bounding Box Computation

/// Compute bounding box using parallel reduction
kernel void computeBoundingBox(
    device const Vertex* vertices [[buffer(0)]],
    device atomic_float* minBounds [[buffer(1)]],
    device atomic_float* maxBounds [[buffer(2)]],
    uint vid [[thread_position_in_grid]]
) {
    float3 position = vertices[vid].position;

    // Atomic min/max (emulated with compare-and-swap)
    // For simplicity, we'll use a simple approach
    // In production, use parallel reduction

    atomic_fetch_min_explicit((device atomic_int*)&minBounds[0], as_type<int>(position.x), memory_order_relaxed);
    atomic_fetch_min_explicit((device atomic_int*)&minBounds[1], as_type<int>(position.y), memory_order_relaxed);
    atomic_fetch_min_explicit((device atomic_int*)&minBounds[2], as_type<int>(position.z), memory_order_relaxed);

    atomic_fetch_max_explicit((device atomic_int*)&maxBounds[0], as_type<int>(position.x), memory_order_relaxed);
    atomic_fetch_max_explicit((device atomic_int*)&maxBounds[1], as_type<int>(position.y), memory_order_relaxed);
    atomic_fetch_max_explicit((device atomic_int*)&maxBounds[2], as_type<int>(position.z), memory_order_relaxed);
}

// MARK: - Quadric Error Metrics (Advanced)

struct Quadric {
    float q[10]; // Symmetric 4x4 matrix (only 10 unique values)
};

/// Compute quadric for a face
Quadric computeFaceQuadric(float3 v0, float3 v1, float3 v2) {
    Quadric q;

    // Compute plane equation: ax + by + cz + d = 0
    float3 edge1 = v1 - v0;
    float3 edge2 = v2 - v0;
    float3 normal = normalize(cross(edge1, edge2));
    float d = -dot(normal, v0);

    // Q = plane * plane^T
    float a = normal.x, b = normal.y, c = normal.z;

    q.q[0] = a * a;  // q11
    q.q[1] = a * b;  // q12
    q.q[2] = a * c;  // q13
    q.q[3] = a * d;  // q14
    q.q[4] = b * b;  // q22
    q.q[5] = b * c;  // q23
    q.q[6] = b * d;  // q24
    q.q[7] = c * c;  // q33
    q.q[8] = c * d;  // q34
    q.q[9] = d * d;  // q44

    return q;
}

/// Compute quadric error for a vertex position
float computeQuadricError(Quadric q, float3 position) {
    float x = position.x, y = position.y, z = position.z;

    return q.q[0] * x * x + 2 * q.q[1] * x * y + 2 * q.q[2] * x * z + 2 * q.q[3] * x +
           q.q[4] * y * y + 2 * q.q[5] * y * z + 2 * q.q[6] * y +
           q.q[7] * z * z + 2 * q.q[8] * z +
           q.q[9];
}

/// Compute vertex quadrics from adjacent faces (GPU version)
kernel void computeVertexQuadrics(
    device const Vertex* vertices [[buffer(0)]],
    device const uint* indices [[buffer(1)]],
    device Quadric* vertexQuadrics [[buffer(2)]],
    uint faceId [[thread_position_in_grid]]
) {
    uint i0 = indices[faceId * 3 + 0];
    uint i1 = indices[faceId * 3 + 1];
    uint i2 = indices[faceId * 3 + 2];

    float3 v0 = vertices[i0].position;
    float3 v1 = vertices[i1].position;
    float3 v2 = vertices[i2].position;

    Quadric faceQuadric = computeFaceQuadric(v0, v1, v2);

    // Atomically accumulate to each vertex
    // Note: This is simplified; proper implementation would use atomic operations
    // For now, we accept potential race conditions (minor impact on accuracy)
    for (int j = 0; j < 10; j++) {
        atomic_fetch_add_explicit((device atomic_float*)&vertexQuadrics[i0].q[j], faceQuadric.q[j], memory_order_relaxed);
        atomic_fetch_add_explicit((device atomic_float*)&vertexQuadrics[i1].q[j], faceQuadric.q[j], memory_order_relaxed);
        atomic_fetch_add_explicit((device atomic_float*)&vertexQuadrics[i2].q[j], faceQuadric.q[j], memory_order_relaxed);
    }
}
