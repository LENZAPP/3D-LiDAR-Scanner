//
//  MeshQualitySelector.swift
//  3D
//
//  Phase 2B: Automatic selection of optimal mesh repair method
//  Analyzes mesh characteristics and recommends the best approach
//

import Foundation
import ModelIO
import simd

/// Analyzes mesh characteristics and selects optimal repair method
class MeshQualitySelector {

    // MARK: - Public API

    /// Analyze mesh and determine its characteristics
    func analyzeCharacteristics(_ mesh: MDLMesh) -> MeshCharacteristics {

        let points = extractPoints(mesh)

        guard !points.isEmpty else {
            return MeshCharacteristics(
                pointCount: 0,
                pointDensity: 0,
                noiseLevel: 1.0,
                coverageCompleteness: 0,
                geometricComplexity: 0,
                boundingBoxSize: 0,
                surfaceArea: 0,
                hasThinFeatures: false,
                hasLargeHoles: false
            )
        }

        // Calculate all characteristics
        let pointCount = points.count
        let boundingBox = calculateBoundingBox(points)
        let boundingBoxSize = length(boundingBox.max - boundingBox.min)
        let pointDensity = calculatePointDensity(points, boundingBox: boundingBox)
        let noiseLevel = estimateNoiseLevel(points)
        let coverageCompleteness = calculateCoverageCompleteness(points, boundingBox: boundingBox)
        let geometricComplexity = calculateGeometricComplexity(points)
        let surfaceArea = estimateSurfaceArea(points, boundingBox: boundingBox)
        let hasThinFeatures = detectThinFeatures(points)
        let hasLargeHoles = detectLargeHoles(mesh)

        return MeshCharacteristics(
            pointCount: pointCount,
            pointDensity: pointDensity,
            noiseLevel: noiseLevel,
            coverageCompleteness: coverageCompleteness,
            geometricComplexity: geometricComplexity,
            boundingBoxSize: boundingBoxSize,
            surfaceArea: surfaceArea,
            hasThinFeatures: hasThinFeatures,
            hasLargeHoles: hasLargeHoles
        )
    }

    /// Select the optimal repair method based on characteristics
    func selectOptimalMethod(_ characteristics: MeshCharacteristics) -> MeshRepairMethod {

        // Rule 1: Empty or invalid mesh
        if characteristics.pointCount < 100 {
            return .voxel // Default fallback
        }

        // Rule 2: High quality, simple objects → Voxel (fast and reliable)
        if characteristics.isSimple &&
           characteristics.isHighQuality &&
           characteristics.isSmallObject &&
           !characteristics.hasLargeHoles {
            return .voxel
        }

        // Rule 3: Complex geometry with good coverage → Poisson (smooth results)
        if characteristics.geometricComplexity > 0.6 &&
           characteristics.coverageCompleteness > 0.75 &&
           !characteristics.hasThinFeatures {
            return .poisson
        }

        // Rule 4: Incomplete scans → Neural (if available) or Poisson
        if characteristics.coverageCompleteness < 0.7 {
            #if PHASE_2C_AVAILABLE
            return .neural
            #else
            return .poisson
            #endif
        }

        // Rule 5: Thin features → Voxel (Poisson may smooth them out)
        if characteristics.hasThinFeatures {
            return .voxel
        }

        // Rule 6: Large holes → Poisson or Neural
        if characteristics.hasLargeHoles {
            #if PHASE_2C_AVAILABLE
            return .neural
            #else
            return .poisson
            #endif
        }

        // Rule 7: Very high point density → Can afford Poisson
        if characteristics.pointDensity > 1000 {
            return .poisson
        }

        // Rule 8: Noisy data → Poisson (implicit smoothing)
        if characteristics.noiseLevel > 0.3 {
            return .poisson
        }

        // Default: Try Poisson first, will fallback to Voxel if fails
        return .poisson
    }

    // MARK: - Private Methods

    private func extractPoints(_ mesh: MDLMesh) -> [SIMD3<Float>] {
        guard let vertexBuffer = mesh.vertexBuffers.first as? MDLMeshBufferData else {
            return []
        }

        let vertexCount = mesh.vertexCount
        let vertexDescriptor = mesh.vertexDescriptor
        let positionAttribute = vertexDescriptor.attributes[0] as! MDLVertexAttribute

        let stride = positionAttribute.bufferIndex == 0 ?
            mesh.vertexBuffers[0].length / vertexCount : 12

        var points: [SIMD3<Float>] = []
        points.reserveCapacity(vertexCount)

        let data = vertexBuffer.data
        for i in 0..<vertexCount {
            let offset = i * stride + Int(positionAttribute.offset)
            let x = data.load(fromByteOffset: offset, as: Float.self)
            let y = data.load(fromByteOffset: offset + 4, as: Float.self)
            let z = data.load(fromByteOffset: offset + 8, as: Float.self)
            points.append(SIMD3<Float>(x, y, z))
        }

        return points
    }

    private func calculateBoundingBox(_ points: [SIMD3<Float>]) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        guard let first = points.first else {
            return (SIMD3<Float>.zero, SIMD3<Float>.zero)
        }

        var minPoint = first
        var maxPoint = first

        for point in points {
            minPoint = min(minPoint, point)
            maxPoint = max(maxPoint, point)
        }

        return (minPoint, maxPoint)
    }

    private func calculatePointDensity(_ points: [SIMD3<Float>], boundingBox: (min: SIMD3<Float>, max: SIMD3<Float>)) -> Float {
        let size = boundingBox.max - boundingBox.min
        let volumeM3 = size.x * size.y * size.z

        guard volumeM3 > 0 else { return 0 }

        // Convert to cm³
        let volumeCm3 = volumeM3 * 1_000_000

        return Float(points.count) / volumeCm3
    }

    private func estimateNoiseLevel(_ points: [SIMD3<Float>]) -> Float {
        // Sample a subset of points and calculate local variance
        let sampleSize = min(1000, points.count)
        let step = max(1, points.count / sampleSize)

        var variances: [Float] = []

        for i in stride(from: 0, to: points.count, by: step) {
            let point = points[i]

            // Find nearest neighbors (simplified: search radius)
            let searchRadius: Float = 0.01 // 1cm
            var neighbors: [SIMD3<Float>] = []

            for j in max(0, i - 10)..<min(points.count, i + 10) {
                if i != j {
                    let dist = distance(point, points[j])
                    if dist < searchRadius {
                        neighbors.append(points[j])
                    }
                }
            }

            if neighbors.count > 3 {
                // Calculate variance of distances
                let distances = neighbors.map { distance(point, $0) }
                let mean = distances.reduce(0, +) / Float(distances.count)
                let variance = distances.map { pow($0 - mean, 2) }.reduce(0, +) / Float(distances.count)
                variances.append(variance)
            }
        }

        guard !variances.isEmpty else { return 0.5 }

        // Average variance normalized to 0-1
        let avgVariance = variances.reduce(0, +) / Float(variances.count)
        return min(1.0, avgVariance * 100) // Scale for visualization
    }

    private func calculateCoverageCompleteness(_ points: [SIMD3<Float>], boundingBox: (min: SIMD3<Float>, max: SIMD3<Float>)) -> Float {
        // Voxelize space and check occupancy
        let resolution = 32
        let size = boundingBox.max - boundingBox.min
        let voxelSize = max(size.x, size.y, size.z) / Float(resolution)

        guard voxelSize > 0 else { return 0 }

        var occupiedVoxels = Set<SIMD3<Int>>()

        for point in points {
            let normalized = (point - boundingBox.min) / voxelSize
            let voxelCoord = SIMD3<Int>(
                Int(normalized.x),
                Int(normalized.y),
                Int(normalized.z)
            )

            if voxelCoord.x >= 0 && voxelCoord.x < resolution &&
               voxelCoord.y >= 0 && voxelCoord.y < resolution &&
               voxelCoord.z >= 0 && voxelCoord.z < resolution {
                occupiedVoxels.insert(voxelCoord)
            }
        }

        // Expected surface voxels (rough estimate: surface of bounding box)
        let surfaceVoxels = 2 * (resolution * resolution * 3) // 6 faces, simplified

        return min(1.0, Float(occupiedVoxels.count) / Float(surfaceVoxels))
    }

    private func calculateGeometricComplexity(_ points: [SIMD3<Float>]) -> Float {
        // Calculate curvature variation as proxy for complexity
        let sampleSize = min(500, points.count)
        let step = max(1, points.count / sampleSize)

        var curvatures: [Float] = []

        for i in stride(from: 0, to: points.count, by: step) {
            let curvature = estimateLocalCurvature(points, index: i)
            curvatures.append(curvature)
        }

        guard !curvatures.isEmpty else { return 0.5 }

        // Calculate variance of curvatures (high variance = complex geometry)
        let mean = curvatures.reduce(0, +) / Float(curvatures.count)
        let variance = curvatures.map { pow($0 - mean, 2) }.reduce(0, +) / Float(curvatures.count)
        let stdDev = sqrt(variance)

        // Normalize to 0-1
        return min(1.0, stdDev * 10)
    }

    private func estimateLocalCurvature(_ points: [SIMD3<Float>], index: Int) -> Float {
        // Simple curvature estimate using neighboring points
        guard index > 0 && index < points.count - 1 else { return 0 }

        let prev = points[max(0, index - 1)]
        let curr = points[index]
        let next = points[min(points.count - 1, index + 1)]

        // Calculate angle between vectors
        let v1 = normalize(curr - prev)
        let v2 = normalize(next - curr)

        let dotProduct = dot(v1, v2)
        let angle = acos(max(-1, min(1, dotProduct)))

        return abs(angle)
    }

    private func estimateSurfaceArea(_ points: [SIMD3<Float>], boundingBox: (min: SIMD3<Float>, max: SIMD3<Float>)) -> Float {
        // Rough estimate based on point density and bounding box
        let size = boundingBox.max - boundingBox.min
        let bboxSurfaceArea = 2 * (size.x * size.y + size.y * size.z + size.z * size.x)

        // Convert to cm²
        return bboxSurfaceArea * 10_000
    }

    private func detectThinFeatures(_ points: [SIMD3<Float>]) -> Bool {
        // Sample points and check for thin structures
        // Thin features: small local radius compared to overall size

        let sampleSize = min(200, points.count)
        let step = max(1, points.count / sampleSize)

        var thinCount = 0

        for i in stride(from: 0, to: points.count, by: step) {
            let point = points[i]

            // Find nearest neighbors within small radius
            let searchRadius: Float = 0.005 // 5mm
            var neighborCount = 0

            for j in max(0, i - 20)..<min(points.count, i + 20) {
                if i != j && distance(point, points[j]) < searchRadius {
                    neighborCount += 1
                }
            }

            // If very few neighbors, might be thin feature
            if neighborCount < 3 {
                thinCount += 1
            }
        }

        // If > 20% of samples have few neighbors, likely has thin features
        return Float(thinCount) / Float(sampleSize) > 0.2
    }

    private func detectLargeHoles(_ mesh: MDLMesh) -> Bool {
        // Use watertight checker to detect holes
        let checker = WatertightChecker()
        let (_, result) = checker.checkWatertight(mesh)

        guard let result = result else { return false }

        // Large holes: > 10 boundary edges or > 2 holes
        return result.boundaryEdgeCount > 10 || result.holeCount > 2
    }
}
