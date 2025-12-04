//
//  PointCloudStreamAdapter.hpp
//  3D
//
//  Adapter for feeding our point cloud data into PoissonRecon library
//  Implements InputOrientedSampleStream interface
//

#ifndef PointCloudStreamAdapter_hpp
#define PointCloudStreamAdapter_hpp

#include "MeshTypes.hpp"
#include "Reconstructors.h"
#include <vector>

namespace mesh {

/// Adapter class that wraps our OrientedPointCloud for PoissonRecon
template< typename Real >
class PointCloudStreamAdapter : public PoissonRecon::Reconstructor::InputOrientedSampleStream< Real , 3 >
{
public:
    /// Constructor from our point cloud
    explicit PointCloudStreamAdapter(const OrientedPointCloud& cloud)
        : _cloud(cloud)
        , _current(0)
    {
    }

    /// Reset stream to beginning
    void reset() override {
        _current = 0;
    }

    /// Read next point and normal
    /// Returns true if data was read, false if end of stream
    bool read(PoissonRecon::Point< Real , 3 > &point,
              PoissonRecon::Point< Real , 3 > &normal) override
    {
        if (_current >= _cloud.size()) {
            return false; // End of stream
        }

        // Get point and normal from our cloud
        const Point3D& p = _cloud.points[_current];
        const Point3D& n = _cloud.normals[_current];

        // Convert to PoissonRecon::Point
        point[0] = static_cast<Real>(p.x);
        point[1] = static_cast<Real>(p.y);
        point[2] = static_cast<Real>(p.z);

        normal[0] = static_cast<Real>(n.x);
        normal[1] = static_cast<Real>(n.y);
        normal[2] = static_cast<Real>(n.z);

        _current++;
        return true;
    }

private:
    const OrientedPointCloud& _cloud;
    size_t _current;
};

} // namespace mesh

#endif /* PointCloudStreamAdapter_hpp */
