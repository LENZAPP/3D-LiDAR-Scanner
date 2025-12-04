//
//  NormalEstimator.swift
//  3D
//
//  Estimates surface normals from point cloud using k-NN + PCA
//

import Foundation
import simd
import Accelerate

public class NormalEstimator {

    /// Estimate normals using PCA on k-nearest neighbors
    public static func estimate(
        points: [SIMD3<Float>],
        kNeighbors: Int = 12
    ) -> [SIMD3<Float>] {

        guard points.count >= kNeighbors else {
            // Fallback: use default normal
            return Array(repeating: SIMD3<Float>(0, 1, 0), count: points.count)
        }

        var normals: [SIMD3<Float>] = []
        normals.reserveCapacity(points.count)

        for i in 0..<points.count {
            let point = points[i]

            // Find k nearest neighbors
            let neighbors = findKNearest(
                point: point,
                in: points,
                k: min(kNeighbors, points.count - 1)
            )

            // Compute normal using PCA
            let normal = computeNormalPCA(neighbors)

            normals.append(normal)
        }

        // Orient normals consistently
        return orientNormals(points: points, normals: normals)
    }

    // MARK: - k-NN Search

    private static func findKNearest(
        point: SIMD3<Float>,
        in points: [SIMD3<Float>],
        k: Int
    ) -> [SIMD3<Float>] {

        // Compute squared distances
        var distances: [(index: Int, distSq: Float)] = []
        distances.reserveCapacity(points.count)

        for (index, other) in points.enumerated() {
            let diff = other - point
            let distSq = dot(diff, diff)
            distances.append((index, distSq))
        }

        // Partial sort (k smallest)
        let sorted = distances.sorted { $0.distSq < $1.distSq }

        // Return k nearest (skip first which is the point itself)
        return sorted[1...min(k, sorted.count-1)].map { points[$0.index] }
    }

    // MARK: - PCA Normal Computation

    private static func computeNormalPCA(_ points: [SIMD3<Float>]) -> SIMD3<Float> {
        guard points.count >= 3 else {
            return SIMD3<Float>(0, 1, 0) // Default normal
        }

        // Compute centroid
        var sum = SIMD3<Float>.zero
        for p in points {
            sum += p
        }
        let centroid = sum / Float(points.count)

        // Center points
        let centered = points.map { $0 - centroid }

        // Build covariance matrix (3x3 symmetric)
        var cov = matrix_float3x3()

        for p in centered {
            // Only compute upper triangle (symmetric)
            cov[0][0] += p.x * p.x
            cov[0][1] += p.x * p.y
            cov[0][2] += p.x * p.z
            cov[1][1] += p.y * p.y
            cov[1][2] += p.y * p.z
            cov[2][2] += p.z * p.z
        }

        // Fill lower triangle (symmetric)
        cov[1][0] = cov[0][1]
        cov[2][0] = cov[0][2]
        cov[2][1] = cov[1][2]

        // Normalize
        let n = Float(points.count)
        cov[0] /= n
        cov[1] /= n
        cov[2] /= n

        // Find smallest eigenvector (normal direction)
        // For speed: use cross product approximation instead of full eigensolve
        let normal = approximateSmallestEigenvector(cov)

        return normalize(normal)
    }

    private static func approximateSmallestEigenvector(_ cov: matrix_float3x3) -> SIMD3<Float> {
        // Use cross product of first two column vectors
        // This approximates the smallest eigenvector for speed
        let v1 = SIMD3<Float>(cov[0][0], cov[1][0], cov[2][0])
        let v2 = SIMD3<Float>(cov[0][1], cov[1][1], cov[2][1])

        var normal = cross(v1, v2)

        // Fallback if cross product is zero
        if length(normal) < 1e-6 {
            normal = SIMD3<Float>(0, 1, 0)
        }

        return normal
    }

    // MARK: - Normal Orientation

    private static func orientNormals(
        points: [SIMD3<Float>],
        normals: [SIMD3<Float>]
    ) -> [SIMD3<Float>] {

        // Compute centroid
        let centroid = points.reduce(SIMD3<Float>.zero, +) / Float(points.count)

        // Orient towards centroid (assumes object is captured from outside)
        return zip(points, normals).map { point, normal in
            let toCenter = centroid - point
            return dot(normal, toCenter) < 0 ? -normal : normal
        }
    }
}
