//
//  MeshTypes.hpp
//  3D
//
//  Shared C++ types for mesh processing
//

#pragma once
#include <vector>
#include <cstdint>
#include <cmath>

namespace mesh {

// ============================================================
// Basic 3D Types
// ============================================================

struct Point3D {
    float x, y, z;

    Point3D() : x(0), y(0), z(0) {}
    Point3D(float x_, float y_, float z_) : x(x_), y(y_), z(z_) {}

    // Vector operations
    Point3D operator+(const Point3D& other) const {
        return Point3D(x + other.x, y + other.y, z + other.z);
    }

    Point3D operator-(const Point3D& other) const {
        return Point3D(x - other.x, y - other.y, z - other.z);
    }

    Point3D operator*(float scalar) const {
        return Point3D(x * scalar, y * scalar, z * scalar);
    }

    Point3D operator/(float scalar) const {
        return Point3D(x / scalar, y / scalar, z / scalar);
    }

    float dot(const Point3D& other) const {
        return x * other.x + y * other.y + z * other.z;
    }

    Point3D cross(const Point3D& other) const {
        return Point3D(
            y * other.z - z * other.y,
            z * other.x - x * other.z,
            x * other.y - y * other.x
        );
    }

    float length() const {
        return std::sqrt(x*x + y*y + z*z);
    }

    Point3D normalized() const {
        float len = length();
        return (len > 1e-6f) ? (*this / len) : Point3D(0, 1, 0);
    }
};

struct Triangle {
    uint32_t i0, i1, i2;

    Triangle() : i0(0), i1(0), i2(0) {}
    Triangle(uint32_t a, uint32_t b, uint32_t c) : i0(a), i1(b), i2(c) {}
};

// ============================================================
// Mesh Data Container
// ============================================================

struct MeshData {
    std::vector<float> vertices;    // Flat array: [x0,y0,z0, x1,y1,z1, ...]
    std::vector<uint32_t> indices;  // Triangle indices: [i0,i1,i2, ...]
    std::vector<float> normals;     // Per-vertex normals (optional)

    MeshData() = default;
    ~MeshData() = default;

    // Helper: Get point at index
    Point3D getVertex(size_t index) const {
        size_t offset = index * 3;
        if (offset + 2 < vertices.size()) {
            return Point3D(vertices[offset], vertices[offset+1], vertices[offset+2]);
        }
        return Point3D();
    }

    // Helper: Set point at index
    void setVertex(size_t index, const Point3D& p) {
        size_t offset = index * 3;
        if (offset + 2 < vertices.size()) {
            vertices[offset] = p.x;
            vertices[offset+1] = p.y;
            vertices[offset+2] = p.z;
        }
    }

    // Helper: Add vertex
    void addVertex(const Point3D& p) {
        vertices.push_back(p.x);
        vertices.push_back(p.y);
        vertices.push_back(p.z);
    }

    // Helper: Get vertex count
    size_t vertexCount() const {
        return vertices.size() / 3;
    }

    // Helper: Get triangle count
    size_t triangleCount() const {
        return indices.size() / 3;
    }

    // Helper: Get triangle
    Triangle getTriangle(size_t index) const {
        size_t offset = index * 3;
        if (offset + 2 < indices.size()) {
            return Triangle(indices[offset], indices[offset+1], indices[offset+2]);
        }
        return Triangle();
    }

    // Helper: Add triangle
    void addTriangle(uint32_t i0, uint32_t i1, uint32_t i2) {
        indices.push_back(i0);
        indices.push_back(i1);
        indices.push_back(i2);
    }

    // Clear all data
    void clear() {
        vertices.clear();
        indices.clear();
        normals.clear();
    }

    // Check if valid
    bool isValid() const {
        return !vertices.empty() &&
               !indices.empty() &&
               (vertices.size() % 3 == 0) &&
               (indices.size() % 3 == 0);
    }
};

// ============================================================
// Oriented Point Cloud
// ============================================================

struct OrientedPointCloud {
    std::vector<Point3D> points;
    std::vector<Point3D> normals;

    OrientedPointCloud() = default;
    ~OrientedPointCloud() = default;

    void addPoint(const Point3D& point, const Point3D& normal) {
        points.push_back(point);
        normals.push_back(normal);
    }

    size_t size() const {
        return points.size();
    }

    bool isValid() const {
        return points.size() == normals.size() && !points.empty();
    }

    void clear() {
        points.clear();
        normals.clear();
    }
};

} // namespace mesh
