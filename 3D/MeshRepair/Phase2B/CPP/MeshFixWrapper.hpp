//
//  MeshFixWrapper.hpp
//  3D
//
//  C++ wrapper for MeshFix-style topological repair
//  Simplified implementation focusing on hole filling and manifold repair
//

#pragma once
#include "MeshTypes.hpp"
#include <memory>
#include <unordered_map>
#include <set>

namespace mesh {

class MeshFixWrapper {
public:
    struct Configuration {
        int maxHoleSize;
        bool removeNonManifold;
        bool removeSmallComponents;
        int minComponentSize;
        bool verbose;

        Configuration()
            : maxHoleSize(100)
            , removeNonManifold(true)
            , removeSmallComponents(true)
            , minComponentSize(10)
            , verbose(true)
        {}
    };

    MeshFixWrapper();
    ~MeshFixWrapper();

    /// Main repair function
    MeshData repair(const MeshData& input, const Configuration& config = Configuration());

private:
    // Edge structure for manifold checking
    struct Edge {
        uint32_t v0, v1;

        Edge(uint32_t a, uint32_t b) : v0(std::min(a, b)), v1(std::max(a, b)) {}

        bool operator==(const Edge& other) const {
            return v0 == other.v0 && v1 == other.v1;
        }

        bool operator<(const Edge& other) const {
            if (v0 != other.v0) return v0 < other.v0;
            return v1 < other.v1;
        }
    };

    struct EdgeHash {
        size_t operator()(const Edge& e) const {
            return std::hash<uint32_t>()(e.v0) ^ (std::hash<uint32_t>()(e.v1) << 1);
        }
    };

    // Hole detection and filling
    struct Hole {
        std::vector<uint32_t> boundaryVertices;
        Point3D center;
        float area;
    };

    std::vector<Hole> detectHoles(const MeshData& mesh);
    void fillHole(MeshData& mesh, const Hole& hole);
    void triangulateHole(MeshData& mesh, const std::vector<uint32_t>& boundary);

    // Manifold operations
    void removeNonManifoldEdges(MeshData& mesh);
    std::unordered_map<Edge, int, EdgeHash> buildEdgeMap(const MeshData& mesh);

    // Component operations
    void removeSmallComponents(MeshData& mesh, int minSize);
    std::vector<std::vector<uint32_t>> findConnectedComponents(const MeshData& mesh);
};

} // namespace mesh
