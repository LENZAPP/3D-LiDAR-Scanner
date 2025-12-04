//
//  CalibrationGuidance.swift
//  3D
//
//  Rule-based guidance system for calibration
//

import Foundation
import Vision
import simd
import SwiftUI

/// Rule-based guidance system
class CalibrationGuidance {

    // MARK: - Configuration

    struct Config {
        // ULTRA RELAXED thresholds for maximum success rate (90%+ target!)
        var idealDistance: Float = 0.30          // 30cm ideal
        var distanceTolerance: Float = 0.10      // ±10cm - VERY RELAXED (was ±5cm)
        var alignmentTolerance: Float = 0.26     // ~15° - VERY FORGIVING (was ~8°)
        var centeringTolerance: CGFloat = 0.40   // 40% of screen - VERY FLEXIBLE (was 25%)
        var maxJitter: Float = 0.15              // 15% movement - VERY PERMISSIVE (was 8%)
        var aspectRatioTolerance: CGFloat = 0.50 // ±50% - VERY TOLERANT (was ±35%)
    }

    private let config: Config
    private let referenceObject: ReferenceObject

    init(referenceObject: ReferenceObject, config: Config = Config()) {
        self.referenceObject = referenceObject
        self.config = config
    }

    // MARK: - Quality Analysis

    /// Analyze detection quality and provide feedback
    func analyzeQuality(frame: DetectionFrame, previousFrame: DetectionFrame?) -> DetectionQuality {

        // 1. Distance Quality
        let distanceQuality = DistanceQuality(
            currentDistance: frame.depth,
            idealDistance: config.idealDistance,
            tolerance: config.distanceTolerance
        )

        // 2. Alignment Quality
        let alignmentQuality = AlignmentQuality(
            deviceNormal: frame.deviceNormal,
            targetNormal: SIMD3<Float>(0, 1, 0),
            tolerance: config.alignmentTolerance
        )

        // 3. Centering Quality
        let centeringQuality = CenteringQuality(
            detectedCenter: frame.center,
            screenCenter: CGPoint(x: 0.5, y: 0.5),
            tolerance: config.centeringTolerance
        )

        // 4. Stability Quality (requires previous frame)
        var jitter: Float = 0
        if let prev = previousFrame {
            let dx = Float(frame.center.x - prev.center.x)
            let dy = Float(frame.center.y - prev.center.y)
            jitter = sqrt(dx * dx + dy * dy)
        }
        let stabilityQuality = StabilityQuality(
            jitter: jitter,
            maxJitter: config.maxJitter
        )

        // 5. Size Match Quality
        let sizeMatchQuality = SizeMatchQuality(
            detectedAspectRatio: frame.aspectRatio,
            expectedAspectRatio: referenceObject.aspectRatio,
            tolerance: config.aspectRatioTolerance
        )

        return DetectionQuality(
            distance: distanceQuality,
            alignment: alignmentQuality,
            centering: centeringQuality,
            stability: stabilityQuality,
            sizeMatch: sizeMatchQuality
        )
    }

    // MARK: - Validation

    /// Check if detection meets minimum quality requirements (RELAXED for better success)
    func isValidDetection(quality: DetectionQuality) -> Bool {
        return quality.distance.score > 0.3 &&     // Reasonable distance (was 0.5 - LOWERED)
               quality.alignment.score > 0.3 &&    // Reasonably parallel (was 0.5 - LOWERED)
               quality.centering.score > 0.3 &&    // Reasonably centered (was 0.4 - LOWERED)
               quality.sizeMatch.score > 0.3       // Card properly detected (was 0.4 - LOWERED)
    }

    /// Check if detection is perfect (ready for capture)
    func isPerfectDetection(quality: DetectionQuality) -> Bool {
        return quality.isPerfect
    }

    // MARK: - Feedback Generation

    /// Generate user-friendly feedback message
    func generateFeedback(quality: DetectionQuality) -> FeedbackMessage {
        if quality.isPerfect {
            return FeedbackMessage(
                text: "🎯 Perfekt! Halte diese Position...",
                type: .success,
                icon: "checkmark.circle.fill",
                color: .green
            )
        }

        if quality.isGood {
            return FeedbackMessage(
                text: "Fast perfekt! Noch etwas ruhiger halten...",
                type: .warning,
                icon: "hand.raised.fill",
                color: .orange
            )
        }

        // Get highest priority feedback
        let feedback = quality.getFeedback()
        let type: FeedbackType = quality.overallScore > 0.5 ? .info : .error

        return FeedbackMessage(
            text: feedback,
            type: type,
            icon: getFeedbackIcon(for: feedback),
            color: getFeedbackColor(for: type)
        )
    }

    private func getFeedbackIcon(for message: String) -> String {
        if message.contains("Näher") || message.contains("Weiter") {
            return "arrow.up.and.down"
        } else if message.contains("links") || message.contains("rechts") {
            return "arrow.left.and.right"
        } else if message.contains("parallel") || message.contains("gerade") {
            return "level.fill"
        } else if message.contains("Ruhig") {
            return "hand.raised.fill"
        } else {
            return "viewfinder"
        }
    }

    private func getFeedbackColor(for type: FeedbackType) -> Color {
        switch type {
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        case .info: return .blue
        }
    }

    // MARK: - Haptic Feedback

    /// Determine if haptic feedback should be triggered
    func shouldTriggerHaptic(quality: DetectionQuality, previousQuality: DetectionQuality?) -> HapticTrigger? {
        // Trigger on reaching perfect state
        if quality.isPerfect && !(previousQuality?.isPerfect ?? false) {
            return .success
        }

        // Trigger on significant improvement
        if let prev = previousQuality {
            let improvement = quality.overallScore - prev.overallScore
            if improvement > 0.3 {
                return .improvement
            }
        }

        return nil
    }
}

// MARK: - Feedback Types

struct FeedbackMessage {
    let text: String
    let type: FeedbackType
    let icon: String
    let color: Color
}

enum FeedbackType {
    case success
    case warning
    case error
    case info
}

enum HapticTrigger {
    case success     // Perfect alignment reached
    case improvement // Significant quality improvement
    case warning     // Quality degrading
}

// MARK: - Measurement Processor

/// Processes multiple measurements for accurate calibration
class MeasurementProcessor {

    private var measurements: [Float] = []
    private let maxMeasurements = 30
    private let minMeasurements = 10

    /// Add a new measurement
    func addMeasurement(_ depth: Float) {
        measurements.append(depth)

        if measurements.count > maxMeasurements {
            measurements.removeFirst()
        }
    }

    /// Check if enough measurements collected
    func hasEnoughMeasurements() -> Bool {
        return measurements.count >= minMeasurements
    }

    /// Get filtered average (removes outliers)
    func getFilteredAverage() -> Float? {
        guard hasEnoughMeasurements() else { return nil }

        // Sort and remove top/bottom 20%
        let sorted = measurements.sorted()
        let trimCount = measurements.count / 5  // 20%

        let trimmed = Array(sorted.dropFirst(trimCount).dropLast(trimCount))
        guard !trimmed.isEmpty else { return nil }

        return trimmed.reduce(0, +) / Float(trimmed.count)
    }

    /// Calculate measurement confidence based on standard deviation
    func getConfidence() -> Float {
        guard let avg = getFilteredAverage() else { return 0 }

        let variance = measurements.map { pow($0 - avg, 2) }.reduce(0, +) / Float(measurements.count)
        let stdDev = sqrt(variance)

        // Lower std dev = higher confidence
        // If stdDev < 1mm, confidence = 1.0
        // If stdDev > 5mm, confidence = 0.5
        let normalizedStdDev = stdDev * 1000  // Convert to mm
        return max(0.5, min(1.0, 1.0 - (normalizedStdDev / 10)))
    }

    /// Reset measurements
    func reset() {
        measurements.removeAll()
    }

    /// Get current measurement count
    var count: Int {
        return measurements.count
    }
}

// MARK: - Calibration Calculator

/// Calculates final calibration factor using proper 3D measurement
class CalibrationCalculator {

    /// Calculate calibration factor from Vision detection and LiDAR depth
    /// This computes: realSize / measuredSize where measuredSize is derived from:
    /// - The detected rectangle size in image coordinates
    /// - The LiDAR depth measurement
    /// - Camera intrinsics
    static func calculateCalibrationFactor(
        referenceObject: ReferenceObject,
        measurements: [Float],
        detectedSizes: [Float] = [],  // Measured sizes in meters from 3D calculation
        cameraIntrinsics: simd_float3x3? = nil
    ) -> CalibrationResult? {

        guard !measurements.isEmpty else { return nil }

        // Real size of credit card (width in meters)
        let realSize = Float(referenceObject.realSize.width)  // 0.0856m

        var calibrationFactor: Float = 1.0

        if !detectedSizes.isEmpty {
            // NEW: Use properly calculated 3D sizes
            let processor = MeasurementProcessor()
            detectedSizes.forEach { processor.addMeasurement($0) }

            guard let avgMeasuredSize = processor.getFilteredAverage() else { return nil }

            // Calibration factor: realSize / measuredSize
            // If measured = 0.090m but real = 0.0856m, factor = 0.951
            // All future measurements get multiplied by 0.951 to correct
            calibrationFactor = realSize / avgMeasuredSize

            print("📏 Calibration calculation:")
            print("   Real card size: \(realSize * 1000)mm")
            print("   Measured size: \(avgMeasuredSize * 1000)mm")
            print("   Calibration factor: \(calibrationFactor)")

        } else {
            // FALLBACK: Legacy depth-based calculation
            // This is less accurate but works as fallback
            let processor = MeasurementProcessor()
            measurements.forEach { processor.addMeasurement($0) }

            guard let avgDepth = processor.getFilteredAverage() else { return nil }

            // Estimate based on expected depth vs measured depth
            // At 30cm, card should measure 0.0856m
            // This is approximate and needs proper 3D calculation
            let expectedDepth: Float = 0.30  // 30cm ideal distance
            let depthRatio = expectedDepth / avgDepth
            calibrationFactor = depthRatio

            print("⚠️ Using fallback depth-based calibration:")
            print("   Average depth: \(avgDepth * 100)cm")
            print("   Expected depth: \(expectedDepth * 100)cm")
            print("   Calibration factor: \(calibrationFactor)")
        }

        // Calculate confidence
        let processor = MeasurementProcessor()
        measurements.forEach { processor.addMeasurement($0) }
        let confidence = processor.getConfidence()

        return CalibrationResult(
            referenceObject: referenceObject,
            calibrationFactor: calibrationFactor,
            timestamp: Date(),
            measurements: measurements,
            confidence: confidence
        )
    }

    /// Calculate the real-world size of the detected card using pinhole camera model
    /// size_real = (size_pixels / focal_length) * depth
    static func calculateRealWorldSize(
        boundingBox: CGRect,
        depth: Float,
        imageSize: CGSize,
        intrinsics: simd_float3x3
    ) -> Float {
        // Get focal length from intrinsics (fx is at [0,0])
        let focalLengthPixels = intrinsics.columns.0.x

        // Card width in pixels (bounding box is normalized 0-1)
        let widthPixels = Float(boundingBox.width * imageSize.width)

        // Pinhole camera model: real_size = (pixel_size / focal_length) * depth
        let realWorldWidth = (widthPixels / focalLengthPixels) * depth

        print("📐 3D Size calculation:")
        print("   Bounding box width: \(boundingBox.width) (normalized)")
        print("   Width in pixels: \(widthPixels)")
        print("   Focal length: \(focalLengthPixels)px")
        print("   Depth: \(depth * 100)cm")
        print("   Real-world width: \(realWorldWidth * 1000)mm")

        return realWorldWidth
    }

    /// Validate calibration result
    static func isValidCalibration(_ result: CalibrationResult) -> Bool {
        // Calibration factor should be close to 1.0 if measured correctly
        // Reasonable range: 0.7 to 1.3 (±30%) - widened for LiDAR variance
        let factor = result.calibrationFactor
        let isReasonable = factor > 0.7 && factor < 1.3

        // Confidence should be at least 0.6 (lowered for auto-calibration)
        let hasGoodConfidence = result.confidence > 0.6

        return isReasonable && hasGoodConfidence
    }
}
