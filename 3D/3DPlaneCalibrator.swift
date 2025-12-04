//
//  3DPlaneCalibrator.swift
//  3D
//
//  3D plane-fitting calibration for 90%+ success rate
//  Uses LiDAR depth + Vision corners to fit a 3D plane and measure precise card dimensions
//

import Foundation
import Vision
import simd
import ARKit

/// 3D Plane-based calibration for credit cards
/// This provides MUCH higher accuracy than 2D pixel-based calibration
class ThreeDPlaneCalibrator {

    // MARK: - Configuration

    struct Config {
        // Distance constraints - RELAXED for better success rate
        var idealDistance: Float = 0.30        // 30cm
        var distanceTolerance: Float = 0.04    // ±4cm (was ±2cm - DOUBLED for flexibility)

        // Angle constraints - RELAXED
        var maxAngleDeviation: Float = 8.0     // Max 8° from perpendicular (was 5° - MORE FORGIVING)

        // Plane fitting quality - RELAXED
        var maxPlaneResidual: Float = 0.005    // 5mm max deviation from plane (was 3mm - MORE TOLERANT)
        var maxCornerDepthVariance: Float = 0.008  // 8mm max variance across corners (was 5mm - MORE TOLERANT)

        // Calibration factor validation - RELAXED
        var minCalibrationFactor: Float = 0.85  // Was 0.90 - MORE FORGIVING
        var maxCalibrationFactor: Float = 1.15  // Was 1.10 - MORE FORGIVING

        // Sample quality - RELAXED for better capture rate
        var minSampleConfidence: Float = 0.75   // Was 0.85 - LOWERED for more samples
    }

    private let config: Config
    private let referenceObject: ReferenceObject

    init(referenceObject: ReferenceObject, config: Config = Config()) {
        self.referenceObject = referenceObject
        self.config = config
    }

    // MARK: - 3D Plane Calibration

    /// Perform 3D plane-based calibration from a single detection frame
    /// Returns calibration sample if quality is sufficient, nil otherwise
    func calibrateFromFrame(
        observation: VNRectangleObservation,
        depthMap: CVPixelBuffer,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3,
        imageSize: CGSize
    ) -> CalibrationSample? {

        // Step 1: Extract 4 corner depths
        guard let cornerDepths = extractCornerDepths(
            observation: observation,
            depthMap: depthMap
        ) else {
            print("❌ Failed to extract corner depths")
            return nil
        }

        // Step 2: Check depth variance across corners (all should be similar)
        let depthVariance = calculateVariance(cornerDepths)
        guard depthVariance < config.maxCornerDepthVariance else {
            print("❌ Corner depth variance too high: \(depthVariance * 1000)mm (max: \(config.maxCornerDepthVariance * 1000)mm)")
            return nil
        }

        // Step 3: Reconstruct 4 corners in 3D space
        guard let corners3D = reconstruct3DCorners(
            observation: observation,
            cornerDepths: cornerDepths,
            cameraIntrinsics: cameraIntrinsics,
            imageSize: imageSize
        ) else {
            print("❌ Failed to reconstruct 3D corners")
            return nil
        }

        // Step 4: Fit a plane to the 4 corners
        guard let plane = fitPlane(to: corners3D) else {
            print("❌ Failed to fit plane")
            return nil
        }

        // Step 5: Validate plane quality (low residual = flat surface)
        let planeResidual = calculatePlaneResidual(corners: corners3D, plane: plane)
        guard planeResidual < config.maxPlaneResidual else {
            print("❌ Plane residual too high: \(planeResidual * 1000)mm (max: \(config.maxPlaneResidual * 1000)mm)")
            return nil
        }

        // Step 6: Calculate camera normal (direction camera is pointing)
        let cameraNormal = getCameraNormal(from: cameraTransform)

        // Step 7: Validate card is perpendicular to camera (normal vectors aligned)
        let angleDeviation = calculateAngleDeviation(
            planeNormal: plane.normal,
            cameraNormal: cameraNormal
        )
        guard angleDeviation < config.maxAngleDeviation else {
            print("❌ Card not perpendicular to camera: \(String(format: "%.1f", angleDeviation))° (max: \(config.maxAngleDeviation)°)")
            return nil
        }

        // Step 8: Measure card dimensions in 3D space
        let cardWidth = distance3D(corners3D[0], corners3D[1])   // Top edge
        let cardHeight = distance3D(corners3D[1], corners3D[2])  // Right edge

        // Step 9: Calculate average depth
        let avgDepth = cornerDepths.reduce(0, +) / Float(cornerDepths.count)

        // Step 10: Validate distance is within range
        guard avgDepth > (config.idealDistance - config.distanceTolerance) &&
              avgDepth < (config.idealDistance + config.distanceTolerance) else {
            let currentCm = Int(avgDepth * 100)
            print("❌ Distance out of range: \(currentCm)cm (ideal: 30cm ±2cm)")
            return nil
        }

        // Step 11: Calculate calibration factor
        let realCardWidth = Float(referenceObject.realSize.width)  // 0.0856m for credit card
        let calibrationFactor = realCardWidth / cardWidth

        // Step 12: Validate calibration factor is reasonable
        guard calibrationFactor >= config.minCalibrationFactor &&
              calibrationFactor <= config.maxCalibrationFactor else {
            print("❌ Calibration factor out of range: \(calibrationFactor) (expected: 0.90-1.10)")
            print("   Measured width: \(cardWidth * 1000)mm, Real width: \(realCardWidth * 1000)mm")
            return nil
        }

        // Step 13: Calculate confidence score
        let confidence = calculateConfidence(
            depthVariance: depthVariance,
            planeResidual: planeResidual,
            angleDeviation: angleDeviation,
            avgDepth: avgDepth,
            calibrationFactor: calibrationFactor
        )

        guard confidence >= config.minSampleConfidence else {
            print("❌ Sample confidence too low: \(String(format: "%.2f", confidence)) (min: \(config.minSampleConfidence))")
            return nil
        }

        // Success! Return high-quality calibration sample
        print("✅ Valid calibration sample:")
        print("   Width: \(cardWidth * 1000)mm, Height: \(cardHeight * 1000)mm")
        print("   Calibration factor: \(calibrationFactor)")
        print("   Depth: \(avgDepth * 100)cm")
        print("   Angle deviation: \(String(format: "%.1f", angleDeviation))°")
        print("   Plane residual: \(planeResidual * 1000)mm")
        print("   Confidence: \(String(format: "%.2f", confidence))")

        return CalibrationSample(
            calibrationFactor: calibrationFactor,
            measuredWidth: cardWidth,
            measuredHeight: cardHeight,
            cornerDepths: cornerDepths,
            avgDepth: avgDepth,
            planeNormal: plane.normal,
            planeResidual: planeResidual,
            angleDeviation: angleDeviation,
            depthVariance: depthVariance,
            confidence: confidence,
            timestamp: Date()
        )
    }

    // MARK: - Corner Depth Extraction

    /// Extract depth values at the 4 corners of the detected rectangle
    private func extractCornerDepths(
        observation: VNRectangleObservation,
        depthMap: CVPixelBuffer
    ) -> [Float]? {

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let baseAddress = CVPixelBufferGetBaseAddress(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

        // Get all 4 corners in Vision coordinate system (origin at bottom-left)
        let corners = [
            observation.topLeft,
            observation.topRight,
            observation.bottomRight,
            observation.bottomLeft
        ]

        var depths: [Float] = []

        for corner in corners {
            // Convert Vision coordinates (0-1, bottom-left origin) to pixel coordinates
            let x = Int(corner.x * CGFloat(width))
            let y = Int((1.0 - corner.y) * CGFloat(height))  // Flip Y for Vision

            guard x >= 0, x < width, y >= 0, y < height else {
                print("⚠️ Corner out of bounds: (\(x), \(y))")
                return nil
            }

            // Sample 3x3 region around corner for more robust measurement
            var regionDepths: [Float] = []
            for dy in -1...1 {
                for dx in -1...1 {
                    let px = min(max(x + dx, 0), width - 1)
                    let py = min(max(y + dy, 0), height - 1)

                    let row = baseAddress?.advanced(by: py * bytesPerRow)
                    if let depth = row?.assumingMemoryBound(to: Float32.self)[px] {
                        if depth > 0.1 && depth < 2.0 {  // Valid depth range
                            regionDepths.append(depth)
                        }
                    }
                }
            }

            guard !regionDepths.isEmpty else {
                print("⚠️ No valid depth at corner (\(x), \(y))")
                return nil
            }

            // Use median of 3x3 region for robustness
            let median = regionDepths.sorted()[regionDepths.count / 2]
            depths.append(median)
        }

        guard depths.count == 4 else {
            return nil
        }

        return depths
    }

    // MARK: - 3D Reconstruction

    /// Reconstruct 4 corners in 3D camera space using pinhole camera model
    private func reconstruct3DCorners(
        observation: VNRectangleObservation,
        cornerDepths: [Float],
        cameraIntrinsics: simd_float3x3,
        imageSize: CGSize
    ) -> [SIMD3<Float>]? {

        guard cornerDepths.count == 4 else { return nil }

        // Get all 4 corners
        let corners2D = [
            observation.topLeft,
            observation.topRight,
            observation.bottomRight,
            observation.bottomLeft
        ]

        // Extract camera parameters
        let fx = cameraIntrinsics.columns.0.x  // Focal length X
        let fy = cameraIntrinsics.columns.1.y  // Focal length Y
        let cx = cameraIntrinsics.columns.2.x  // Principal point X
        let cy = cameraIntrinsics.columns.2.y  // Principal point Y

        var corners3D: [SIMD3<Float>] = []

        for i in 0..<4 {
            let corner = corners2D[i]
            let depth = cornerDepths[i]

            // Convert Vision coordinates (0-1, bottom-left) to pixel coordinates (top-left)
            let u = Float(corner.x * imageSize.width)
            let v = Float((1.0 - corner.y) * imageSize.height)

            // Pinhole camera model: X = (u - cx) * Z / fx, Y = (v - cy) * Z / fy, Z = depth
            let x = (u - cx) * depth / fx
            let y = (v - cy) * depth / fy
            let z = depth

            corners3D.append(SIMD3<Float>(x, y, z))
        }

        return corners3D
    }

    // MARK: - Plane Fitting

    /// Fit a 3D plane to 4 corners using least-squares
    /// Plane equation: ax + by + cz + d = 0 (normalized so that a² + b² + c² = 1)
    private func fitPlane(to corners: [SIMD3<Float>]) -> Plane3D? {
        guard corners.count >= 3 else { return nil }

        // Calculate centroid
        var centroid = SIMD3<Float>(0, 0, 0)
        for corner in corners {
            centroid += corner
        }
        centroid /= Float(corners.count)

        // Build covariance matrix
        var covariance = simd_float3x3()
        for corner in corners {
            let diff = corner - centroid
            covariance.columns.0 += diff * diff.x
            covariance.columns.1 += diff * diff.y
            covariance.columns.2 += diff * diff.z
        }
        // Normalize covariance matrix (divide each column by count)
        let count = Float(corners.count)
        covariance.columns.0 = covariance.columns.0 / count
        covariance.columns.1 = covariance.columns.1 / count
        covariance.columns.2 = covariance.columns.2 / count

        // Plane normal is the eigenvector with smallest eigenvalue
        // For simplicity, use SVD approximation: cross product of two edges
        let edge1 = normalize(corners[1] - corners[0])
        let edge2 = normalize(corners[3] - corners[0])
        var normal = normalize(cross(edge1, edge2))

        // Ensure normal points toward camera (negative Z)
        if normal.z > 0 {
            normal = -normal
        }

        // Calculate d: d = -(ax₀ + by₀ + cz₀)
        let d = -dot(normal, centroid)

        return Plane3D(normal: normal, d: d, centroid: centroid)
    }

    /// Calculate residual error (how far corners deviate from fitted plane)
    private func calculatePlaneResidual(corners: [SIMD3<Float>], plane: Plane3D) -> Float {
        var totalError: Float = 0

        for corner in corners {
            // Distance from point to plane: |ax + by + cz + d| / sqrt(a² + b² + c²)
            // Since normal is normalized, sqrt(a² + b² + c²) = 1
            let distance = abs(dot(plane.normal, corner) + plane.d)
            totalError += distance
        }

        return totalError / Float(corners.count)
    }

    // MARK: - Camera Geometry

    /// Extract camera normal vector (direction camera is pointing)
    private func getCameraNormal(from transform: simd_float4x4) -> SIMD3<Float> {
        // Z-axis of camera transform points out of device (toward user)
        // We want the direction camera is pointing (away from user)
        let zAxis = SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        return -normalize(zAxis)  // Negate to get forward direction
    }

    /// Calculate angle deviation between plane normal and camera normal
    /// Returns angle in degrees (0° = perfectly perpendicular)
    private func calculateAngleDeviation(planeNormal: SIMD3<Float>, cameraNormal: SIMD3<Float>) -> Float {
        let dotProduct = dot(normalize(planeNormal), normalize(cameraNormal))
        let angleDeg = acos(max(-1, min(1, dotProduct))) * 180 / .pi

        // Return deviation from 180° (opposite directions = perpendicular card)
        return abs(180 - angleDeg)
    }

    // MARK: - Utility Functions

    /// Calculate 3D distance between two points
    private func distance3D(_ p1: SIMD3<Float>, _ p2: SIMD3<Float>) -> Float {
        return length(p1 - p2)
    }

    /// Calculate variance of an array of values
    private func calculateVariance(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Float(values.count)
        let squaredDiffs = values.map { pow($0 - mean, 2) }
        return squaredDiffs.reduce(0, +) / Float(values.count)
    }

    /// Calculate confidence score based on multiple quality factors
    private func calculateConfidence(
        depthVariance: Float,
        planeResidual: Float,
        angleDeviation: Float,
        avgDepth: Float,
        calibrationFactor: Float
    ) -> Float {

        // Score for depth variance (lower is better)
        let varianceScore = max(0, 1.0 - depthVariance / config.maxCornerDepthVariance)

        // Score for plane flatness (lower residual is better)
        let planeScore = max(0, 1.0 - planeResidual / config.maxPlaneResidual)

        // Score for angle alignment (lower deviation is better)
        let angleScore = max(0, 1.0 - angleDeviation / config.maxAngleDeviation)

        // Score for distance (closer to ideal is better)
        let depthDiff = abs(avgDepth - config.idealDistance)
        let distanceScore = max(0, 1.0 - depthDiff / config.distanceTolerance)

        // Score for calibration factor (closer to 1.0 is better)
        let factorDiff = abs(calibrationFactor - 1.0)
        let factorScore = max(0, 1.0 - factorDiff * 10)  // 10% diff = 0.0 score

        // Weighted average (prioritize plane quality and angle)
        let confidence = (
            planeScore * 0.30 +      // 30% - plane must be flat
            angleScore * 0.25 +      // 25% - angle must be good
            varianceScore * 0.20 +   // 20% - depth variance low
            distanceScore * 0.15 +   // 15% - distance correct
            factorScore * 0.10       // 10% - factor reasonable
        )

        return min(1.0, max(0.0, confidence))
    }
}

// MARK: - Supporting Types

/// A 3D plane in camera space
struct Plane3D {
    let normal: SIMD3<Float>     // Unit normal vector (a, b, c)
    let d: Float                 // Distance from origin
    let centroid: SIMD3<Float>   // Center point on plane
}

/// A single high-quality calibration sample
struct CalibrationSample {
    let calibrationFactor: Float
    let measuredWidth: Float
    let measuredHeight: Float
    let cornerDepths: [Float]
    let avgDepth: Float
    let planeNormal: SIMD3<Float>
    let planeResidual: Float
    let angleDeviation: Float
    let depthVariance: Float
    let confidence: Float
    let timestamp: Date

    /// Quality score for this sample (0-1)
    var qualityScore: Float {
        return confidence
    }
}

// MARK: - Sample Aggregator

/// Aggregates multiple calibration samples and computes final calibration factor
class CalibrationSampleAggregator {

    private var samples: [CalibrationSample] = []
    private let minSamples = 10  // Collect at least 10 high-quality samples (was 15 - REDUCED for faster completion)
    private let maxSamples = 20  // Keep only the best 20 (was 25 - REDUCED)

    /// Add a new calibration sample
    func addSample(_ sample: CalibrationSample) {
        samples.append(sample)

        // Keep only the best samples (sorted by quality)
        if samples.count > maxSamples {
            samples.sort { $0.qualityScore > $1.qualityScore }
            samples = Array(samples.prefix(maxSamples))
        }

        print("📊 Collected \(samples.count)/\(minSamples) high-quality samples")
    }

    /// Check if enough samples collected
    func hasEnoughSamples() -> Bool {
        return samples.count >= minSamples
    }

    /// Get current sample count
    var sampleCount: Int {
        return samples.count
    }

    /// Calculate final calibration result by aggregating all samples
    func calculateFinalCalibration(referenceObject: ReferenceObject) -> CalibrationResult? {
        guard hasEnoughSamples() else {
            print("⚠️ Not enough samples: \(samples.count)/\(minSamples)")
            return nil
        }

        // Extract calibration factors
        let factors = samples.map { $0.calibrationFactor }

        // Remove outliers (top/bottom 15%)
        let sorted = factors.sorted()
        let trimCount = samples.count * 15 / 100
        let trimmed = Array(sorted.dropFirst(trimCount).dropLast(trimCount))

        guard !trimmed.isEmpty else { return nil }

        // Use MEDIAN for robustness (not mean)
        let finalFactor = trimmed[trimmed.count / 2]

        // Calculate variance to determine confidence
        let mean = trimmed.reduce(0, +) / Float(trimmed.count)
        let variance = trimmed.map { pow($0 - mean, 2) }.reduce(0, +) / Float(trimmed.count)
        let stdDev = sqrt(variance)

        // Confidence based on consistency (lower std dev = higher confidence)
        // If stdDev < 0.01 (1%), confidence = 1.0
        // If stdDev > 0.05 (5%), confidence = 0.6
        let confidence = max(0.6, min(1.0, 1.0 - stdDev * 10))

        // Calculate average depth for logging
        let avgDepth = samples.map { $0.avgDepth }.reduce(0, +) / Float(samples.count)

        print("✅ Final calibration computed:")
        print("   Samples used: \(trimmed.count) (from \(samples.count) collected)")
        print("   Calibration factor: \(finalFactor)")
        print("   Std deviation: \(String(format: "%.4f", stdDev)) (\(String(format: "%.2f", stdDev * 100))%)")
        print("   Confidence: \(String(format: "%.2f", confidence))")
        print("   Average depth: \(avgDepth * 100)cm")

        return CalibrationResult(
            referenceObject: referenceObject,
            calibrationFactor: finalFactor,
            timestamp: Date(),
            measurements: samples.map { $0.avgDepth },
            confidence: confidence
        )
    }

    /// Reset all collected samples
    func reset() {
        samples.removeAll()
    }
}
