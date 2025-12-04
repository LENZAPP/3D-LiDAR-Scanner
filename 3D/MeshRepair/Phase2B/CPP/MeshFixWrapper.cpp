//
//  MeshFixWrapper.cpp
//  3D
//
//  Implementation of simplified MeshFix
//

#include "MeshFixWrapper.hpp"
#include <algorithm>
#include <queue>
#include <iostream>

namespace mesh {

MeshFixWrapper::MeshFixWrapper() {}
MeshFixWrapper::~MeshFixWrapper() {}

// ============================================================
// Main Repair Function
// ============================================================

MeshData MeshFixWrapper::repair(const MeshData& input, const Configuration& config) {
    if (!input.isValid()) {
        if (config.verbose) {
            std::cerr << "MeshFix: Invalid input mesh" << std::endl;
        }
        return input;
    }

    MeshData output = input;

    if (config.verbose) {
        std::cout << "MeshFix: Starting repair..." << std::endl;
        std::cout << "  Input: " << output.vertexCount() << " vertices, "
                  << output.triangleCount() << " triangles" << std::endl;
    }

    // Step 1: Remove non-manifold edges
    if (config.removeNonManifold) {
        removeNonManifoldEdges(output);
        if (config.verbose) {
            std::cout << "  After manifold repair: " << output.triangleCount() << " triangles" << std::endl;
        }
    }

    // Step 2: Detect and fill holes
    auto holes = detectHoles(output);
    if (config.verbose) {
        std::cout << "  Detected " << holes.size() << " holes" << std::endl;
    }

    int filledCount = 0;
    for (const auto& hole : holes) {
        if (static_cast<int>(hole.boundaryVertices.size()) <= config.maxHoleSize) {
            fillHole(output, hole);
            filledCount++;
        }
    }

    if (config.verbose && filledCount > 0) {
        std::cout << "  Filled " << filledCount << " holes" << std::endl;
    }

    // Step 3: Remove small disconnected components
    if (config.removeSmallComponents) {
        removeSmallComponents(output, config.minComponentSize);
        if (config.verbose) {
            std::cout << "  After component cleanup: " << output.vertexCount() << " vertices" << std::endl;
        }
    }

    if (config.verbose) {
        std::cout << "MeshFix: Repair complete!" << std::endl;
        std::cout << "  Output: " << output.vertexCount() << " vertices, "
                  << output.triangleCount() << " triangles" << std::endl;
    }

    return output;
}

// ============================================================
// Edge Map Building
// ============================================================

std::unordered_map<MeshFixWrapper::Edge, int, MeshFixWrapper::EdgeHash>
MeshFixWrapper::buildEdgeMap(const MeshData& mesh) {
    std::unordered_map<Edge, int, EdgeHash> edgeCount;

    for (size_t i = 0; i < mesh.triangleCount(); ++i) {
        auto tri = mesh.getTriangle(i);

        edgeCount[Edge(tri.i0, tri.i1)]++;
        edgeCount[Edge(tri.i1, tri.i2)]++;
        edgeCount[Edge(tri.i2, tri.i0)]++;
    }

    return edgeCount;
}

// ============================================================
// Non-Manifold Edge Removal
// ============================================================

void MeshFixWrapper::removeNonManifoldEdges(MeshData& mesh) {
    auto edgeCount = buildEdgeMap(mesh);

    // Find edges that are shared by more than 2 triangles (non-manifold)
    std::set<Edge> nonManifoldEdges;
    for (const auto& [edge, count] : edgeCount) {
        if (count > 2) {
            nonManifoldEdges.insert(edge);
        }
    }

    if (nonManifoldEdges.empty()) {
        return;
    }

    // Remove triangles that contain non-manifold edges
    std::vector<uint32_t> newIndices;
    for (size_t i = 0; i < mesh.triangleCount(); ++i) {
        auto tri = mesh.getTriangle(i);

        bool hasNonManifold =
            nonManifoldEdges.count(Edge(tri.i0, tri.i1)) > 0 ||
            nonManifoldEdges.count(Edge(tri.i1, tri.i2)) > 0 ||
            nonManifoldEdges.count(Edge(tri.i2, tri.i0)) > 0;

        if (!hasNonManifold) {
            newIndices.push_back(tri.i0);
            newIndices.push_back(tri.i1);
            newIndices.push_back(tri.i2);
        }
    }

    mesh.indices = newIndices;
}

// ============================================================
// Hole Detection
// ============================================================

std::vector<MeshFixWrapper::Hole> MeshFixWrapper::detectHoles(const MeshData& mesh) {
    auto edgeCount = buildEdgeMap(mesh);

    // Find boundary edges (shared by only 1 triangle)
    std::vector<Edge> boundaryEdges;
    for (const auto& [edge, count] : edgeCount) {
        if (count == 1) {
            boundaryEdges.push_back(edge);
        }
    }

    if (boundaryEdges.empty()) {
        return {};
    }

    // Group boundary edges into holes (connected components)
    std::unordered_map<uint32_t, std::vector<uint32_t>> adjacency;
    for (const auto& edge : boundaryEdges) {
        adjacency[edge.v0].push_back(edge.v1);
        adjacency[edge.v1].push_back(edge.v0);
    }

    std::vector<Hole> holes;
    std::set<uint32_t> visited;

    for (const auto& [startVertex, _] : adjacency) {
        if (visited.count(startVertex)) continue;

        // BFS to find connected boundary vertices
        std::vector<uint32_t> hole;
        std::queue<uint32_t> queue;
        queue.push(startVertex);
        visited.insert(startVertex);

        while (!queue.empty()) {
            uint32_t v = queue.front();
            queue.pop();
            hole.push_back(v);

            for (uint32_t neighbor : adjacency[v]) {
                if (!visited.count(neighbor)) {
                    visited.insert(neighbor);
                    queue.push(neighbor);
                }
            }
        }

        if (!hole.empty()) {
            Hole h;
            h.boundaryVertices = hole;

            // Compute hole center
            Point3D center(0, 0, 0);
            for (uint32_t v : hole) {
                center = center + mesh.getVertex(v);
            }
            h.center = center / static_cast<float>(hole.size());
            h.area = 0.0f; // TODO: compute actual area

            holes.push_back(h);
        }
    }

    return holes;
}

// ============================================================
// Hole Filling
// ============================================================

void MeshFixWrapper::fillHole(MeshData& mesh, const Hole& hole) {
    if (hole.boundaryVertices.size() < 3) {
        return;
    }

    triangulateHole(mesh, hole.boundaryVertices);
}

void MeshFixWrapper::triangulateHole(MeshData& mesh, const std::vector<uint32_t>& boundary) {
    if (boundary.size() < 3) {
        return;
    }

    // Simple fan triangulation from first vertex
    // For production: use ear-clipping or Delaunay triangulation
    uint32_t centerIdx = boundary[0];

    for (size_t i = 1; i + 1 < boundary.size(); ++i) {
        mesh.addTriangle(centerIdx, boundary[i], boundary[i + 1]);
    }
}

// ============================================================
// Connected Components
// ============================================================

std::vector<std::vector<uint32_t>> MeshFixWrapper::findConnectedComponents(const MeshData& mesh) {
    // Build vertex adjacency from triangles
    std::unordered_map<uint32_t, std::vector<uint32_t>> adjacency;

    for (size_t i = 0; i < mesh.triangleCount(); ++i) {
        auto tri = mesh.getTriangle(i);

        adjacency[tri.i0].push_back(tri.i1);
        adjacency[tri.i0].push_back(tri.i2);
        adjacency[tri.i1].push_back(tri.i0);
        adjacency[tri.i1].push_back(tri.i2);
        adjacency[tri.i2].push_back(tri.i0);
        adjacency[tri.i2].push_back(tri.i1);
    }

    std::vector<std::vector<uint32_t>> components;
    std::set<uint32_t> visited;

    for (const auto& [vertex, _] : adjacency) {
        if (visited.count(vertex)) continue;

        std::vector<uint32_t> component;
        std::queue<uint32_t> queue;
        queue.push(vertex);
        visited.insert(vertex);

        while (!queue.empty()) {
            uint32_t v = queue.front();
            queue.pop();
            component.push_back(v);

            for (uint32_t neighbor : adjacency[v]) {
                if (!visited.count(neighbor)) {
                    visited.insert(neighbor);
                    queue.push(neighbor);
                }
            }
        }

        components.push_back(component);
    }

    return components;
}

void MeshFixWrapper::removeSmallComponents(MeshData& mesh, int minSize) {
    auto components = findConnectedComponents(mesh);

    if (components.size() <= 1) {
        return; // Only one component
    }

    // Find largest component
    size_t largestIdx = 0;
    size_t largestSize = 0;
    for (size_t i = 0; i < components.size(); ++i) {
        if (components[i].size() > largestSize) {
            largestSize = components[i].size();
            largestIdx = i;
        }
    }

    // Keep only vertices in largest component
    std::set<uint32_t> keepVertices(
        components[largestIdx].begin(),
        components[largestIdx].end()
    );

    // Filter triangles
    std::vector<uint32_t> newIndices;
    for (size_t i = 0; i < mesh.triangleCount(); ++i) {
        auto tri = mesh.getTriangle(i);

        if (keepVertices.count(tri.i0) &&
            keepVertices.count(tri.i1) &&
            keepVertices.count(tri.i2)) {
            newIndices.push_back(tri.i0);
            newIndices.push_back(tri.i1);
            newIndices.push_back(tri.i2);
        }
    }

    mesh.indices = newIndices;
}

} // namespace mesh
