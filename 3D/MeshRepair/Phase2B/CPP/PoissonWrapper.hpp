//
//  PoissonWrapper.hpp
//  3D
//
//  C++ wrapper for Poisson Surface Reconstruction
//  Will be integrated with actual PoissonRecon library in Day 5-6
//

#pragma once
#include "MeshTypes.hpp"
#include <memory>

namespace mesh {

class PoissonWrapper {
public:
    struct Configuration {
        int depth;
        float samplesPerNode;
        float scale;
        bool enableDensityTrimming;
        float trimPercentage;
        bool verbose;

        Configuration()
            : depth(9)
            , samplesPerNode(1.5f)
            , scale(1.1f)
            , enableDensityTrimming(true)
            , trimPercentage(0.05f)
            , verbose(true)
        {}
    };

    PoissonWrapper();
    ~PoissonWrapper();

    /// Main reconstruction function
    /// Input: Oriented point cloud (points + normals)
    /// Output: Watertight triangle mesh
    MeshData reconstruct(
        const OrientedPointCloud& input,
        const Configuration& config = Configuration()
    );

private:
    // Implementation details (simplified version uses inline implementation)
};

} // namespace mesh
