// Simplified MeshFix header
// Basic topological repair functions

#pragma once
#include <vector>
#include <cstdint>

namespace meshfix {

struct Vec3 {
    float x, y, z;
    Vec3() : x(0), y(0), z(0) {}
    Vec3(float x_, float y_, float z_) : x(x_), y(y_), z(z_) {}
};

struct MeshData {
    std::vector<Vec3> vertices;
    std::vector<uint32_t> indices;  // Triangles: i0, i1, i2, ...
};

// Main repair function
MeshData repairMesh(const MeshData& input, int maxHoleSize = 100);

// Individual repair operations
void removeNonManifoldEdges(MeshData& mesh);
void fillHoles(MeshData& mesh, int maxHoleSize);
void removeSmallComponents(MeshData& mesh, int minVertices);
void removeSelfIntersections(MeshData& mesh);

} // namespace meshfix
