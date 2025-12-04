//
//  CalibrationModels.swift
//  3D
//
//  Data models for credit card calibration
//

import Foundation
import simd
import Vision

// MARK: - Reference Objects

/// Standard reference objects for calibration
enum ReferenceObject {
    case creditCard
    case euroCoins  // Future: 1€ coin support

    var realSize: CGSize {
        switch self {
        case .creditCard:
            // ISO/IEC 7810 ID-1 standard (in meters)
            return CGSize(width: 0.08560, height: 0.05398)
        case .euroCoins:
            // 1-Euro coin diameter (in meters)
            return CGSize(width: 0.02325, height: 0.02325)
        }
    }

    var displayName: String {
        switch self {
        case .creditCard: return "Kreditkarte"
        case .euroCoins: return "1-Euro-Münze"
        }
    }

    var aspectRatio: CGFloat {
        return realSize.width / realSize.height
    }

    var icon: String {
        switch self {
        case .creditCard: return "creditcard.fill"
        case .euroCoins: return "eurosign.circle.fill"
        }
    }
}

// MARK: - Calibration State

/// Current state of the calibration process
enum CalibrationState: Equatable {
    case notStarted
    case detecting
    case analyzing(DetectionQuality)
    case calibrated(CalibrationResult)
    case failed(CalibrationError)

    var description: String {
        switch self {
        case .notStarted:
            return "Bereit für Kalibrierung"
        case .detecting:
            return "Suche Kreditkarte..."
        case .analyzing(let quality):
            return quality.description
        case .calibrated:
            return "✓ Kalibriert"
        case .failed(let error):
            return "⚠️ \(error.localizedDescription)"
        }
    }

    // Equatable conformance
    static func == (lhs: CalibrationState, rhs: CalibrationState) -> Bool {
        switch (lhs, rhs) {
        case (.notStarted, .notStarted):
            return true
        case (.detecting, .detecting):
            return true
        case (.analyzing, .analyzing):
            return true  // We don't compare DetectionQuality
        case (.calibrated, .calibrated):
            return true  // We don't compare CalibrationResult
        case (.failed, .failed):
            return true  // We don't compare CalibrationError
        default:
            return false
        }
    }
}

// MARK: - Detection Quality

/// Quality metrics for detected reference object
struct DetectionQuality {
    let distance: DistanceQuality
    let alignment: AlignmentQuality
    let centering: CenteringQuality
    let stability: StabilityQuality
    let sizeMatch: SizeMatchQuality

    var overallScore: Float {
        return (distance.score + alignment.score + centering.score + stability.score + sizeMatch.score) / 5.0
    }

    var isPerfect: Bool {
        // ULTRA RELAXED: Make green frame VERY easy to achieve!
        return overallScore > 0.50  // Was 0.60 → NOW 0.50 (SUPER easy!)
    }

    var isGood: Bool {
        // ULTRA RELAXED: Make orange frame trivial to achieve
        return overallScore > 0.30  // Was 0.40 → NOW 0.30 (SUPER easy!)
    }

    var description: String {
        if isPerfect {
            return "🎯 Perfekt!"
        } else if isGood {
            return "✓ Gut positioniert"
        } else {
            return getFeedback()
        }
    }

    /// Get highest priority feedback
    func getFeedback() -> String {
        let qualities: [(String, Float)] = [
            (distance.feedback, distance.priority),
            (alignment.feedback, alignment.priority),
            (centering.feedback, centering.priority),
            (stability.feedback, stability.priority),
            (sizeMatch.feedback, sizeMatch.priority)
        ]

        let sorted = qualities.sorted { $0.1 > $1.1 }
        return sorted.first?.0 ?? "Ausrichtung anpassen"
    }
}

// MARK: - Individual Quality Metrics

struct DistanceQuality {
    let currentDistance: Float  // in meters
    var idealDistance: Float
    var tolerance: Float

    var score: Float {
        let diff = abs(currentDistance - idealDistance)
        return max(0, 1.0 - (diff / tolerance))
    }

    var priority: Float {
        return 5.0 - score * 4.0  // Higher priority if worse
    }

    /// Current distance in centimeters for display
    var currentDistanceCm: Int {
        return Int(currentDistance * 100)
    }

    /// How far off from ideal (negative = too close, positive = too far)
    var distanceOffsetCm: Int {
        return Int((currentDistance - idealDistance) * 100)
    }

    var feedback: String {
        let currentCm = currentDistanceCm
        let offsetCm = distanceOffsetCm

        if currentDistance > idealDistance + tolerance {
            // Too far away
            let needCloser = abs(offsetCm)
            return "📏 Näher ran! (\(currentCm)cm → 30cm, \(needCloser)cm näher)"
        } else if currentDistance < idealDistance - tolerance {
            // Too close
            let needFarther = abs(offsetCm)
            return "📏 Weiter weg! (\(currentCm)cm → 30cm, \(needFarther)cm weiter)"
        } else {
            return "✓ Distanz perfekt (\(currentCm)cm)"
        }
    }
}

struct AlignmentQuality {
    let deviceNormal: SIMD3<Float>
    var targetNormal: SIMD3<Float>
    var tolerance: Float

    var parallelism: Float {
        return abs(dot(normalize(deviceNormal), targetNormal))
    }

    var score: Float {
        return max(0, (parallelism - (1.0 - tolerance)) / tolerance)
    }

    var priority: Float {
        return 4.0 - score * 3.0
    }

    var feedback: String {
        if parallelism < 0.90 {
            return "📐 iPhone parallel zum Tisch halten"
        } else if parallelism < 0.95 {
            return "📐 Noch etwas gerader"
        } else {
            return "✓ Perfekt ausgerichtet"
        }
    }
}

struct CenteringQuality {
    let detectedCenter: CGPoint
    var screenCenter: CGPoint
    var tolerance: CGFloat

    var offset: CGFloat {
        return hypot(detectedCenter.x - screenCenter.x, detectedCenter.y - screenCenter.y)
    }

    var score: Float {
        return Float(max(0, 1.0 - (offset / tolerance)))
    }

    var priority: Float {
        return 3.0 - score * 2.0
    }

    var feedback: String {
        if offset > tolerance {
            let dx = detectedCenter.x - screenCenter.x
            let dy = detectedCenter.y - screenCenter.y

            if abs(dx) > abs(dy) {
                return dx > 0 ? "← Nach links bewegen" : "→ Nach rechts bewegen"
            } else {
                return dy > 0 ? "↑ Nach oben bewegen" : "↓ Nach unten bewegen"
            }
        } else {
            return "✓ Zentriert"
        }
    }
}

struct StabilityQuality {
    let jitter: Float  // Movement between frames
    var maxJitter: Float

    var score: Float {
        return max(0, 1.0 - (jitter / maxJitter))
    }

    var priority: Float {
        return 2.0 - score * 1.5
    }

    var feedback: String {
        if jitter > maxJitter {
            return "🤚 Ruhiger halten"
        } else {
            return "✓ Stabil"
        }
    }
}

struct SizeMatchQuality {
    let detectedAspectRatio: CGFloat
    let expectedAspectRatio: CGFloat
    var tolerance: CGFloat

    var difference: CGFloat {
        return abs(detectedAspectRatio - expectedAspectRatio)
    }

    var score: Float {
        return Float(max(0, 1.0 - (difference / tolerance)))
    }

    var priority: Float {
        return 1.0 - score
    }

    var feedback: String {
        if difference > tolerance {
            return "🎯 Karte vollständig im Rahmen"
        } else {
            return "✓ Größe korrekt"
        }
    }
}

// MARK: - Calibration Result

struct CalibrationResult {
    let referenceObject: ReferenceObject
    let calibrationFactor: Float
    let timestamp: Date
    let measurements: [Float]  // All measurements taken for averaging
    let confidence: Float

    var averageMeasurement: Float {
        return measurements.reduce(0, +) / Float(measurements.count)
    }

    var standardDeviation: Float {
        let avg = averageMeasurement
        let variance = measurements.map { pow($0 - avg, 2) }.reduce(0, +) / Float(measurements.count)
        return sqrt(variance)
    }

    var qualityDescription: String {
        switch confidence {
        case 0.95...1.0:
            return "Exzellent (±0.5mm)"
        case 0.85..<0.95:
            return "Sehr gut (±1mm)"
        case 0.75..<0.85:
            return "Gut (±2mm)"
        default:
            return "Akzeptabel (±5mm)"
        }
    }

    /// Apply calibration to a measured value
    func calibrate(_ measuredValue: Float) -> Float {
        return measuredValue * calibrationFactor
    }

    /// Calibrate a 3D size vector
    func calibrate(_ size: SIMD3<Float>) -> SIMD3<Float> {
        return size * calibrationFactor
    }
}

// MARK: - Calibration Error

enum CalibrationError: LocalizedError {
    case noObjectDetected
    case objectTooFar
    case objectTooClose
    case poorAlignment
    case unstable
    case lidarUnavailable
    case cameraPermissionDenied

    var errorDescription: String? {
        switch self {
        case .noObjectDetected:
            return "Keine Kreditkarte erkannt"
        case .objectTooFar:
            return "Karte zu weit entfernt"
        case .objectTooClose:
            return "Karte zu nahe"
        case .poorAlignment:
            return "iPhone nicht parallel zum Tisch"
        case .unstable:
            return "Zu viel Bewegung - ruhiger halten"
        case .lidarUnavailable:
            return "LiDAR-Scanner nicht verfügbar"
        case .cameraPermissionDenied:
            return "Kamera-Berechtigung erforderlich"
        }
    }
}

// MARK: - Detection Data

/// Data from a single detection frame
struct DetectionFrame {
    let observation: VNRectangleObservation
    let depth: Float
    let deviceNormal: SIMD3<Float>
    let timestamp: Date

    var boundingBox: CGRect {
        return observation.boundingBox
    }

    var corners: [CGPoint] {
        return [
            observation.topLeft,
            observation.topRight,
            observation.bottomRight,
            observation.bottomLeft
        ]
    }

    var center: CGPoint {
        return CGPoint(
            x: (observation.topLeft.x + observation.bottomRight.x) / 2,
            y: (observation.topLeft.y + observation.bottomRight.y) / 2
        )
    }

    var aspectRatio: CGFloat {
        return boundingBox.width / boundingBox.height
    }
}

// MARK: - Calibration Session

/// Manages a calibration session with history
class CalibrationSession {
    let referenceObject: ReferenceObject
    let startTime: Date
    var detectionFrames: [DetectionFrame] = []
    var state: CalibrationState = .detecting

    private let maxHistorySize = 30  // Keep last 30 frames

    init(referenceObject: ReferenceObject) {
        self.referenceObject = referenceObject
        self.startTime = Date()
    }

    func addFrame(_ frame: DetectionFrame) {
        detectionFrames.append(frame)

        // Keep only recent frames
        if detectionFrames.count > maxHistorySize {
            detectionFrames.removeFirst()
        }
    }

    var latestFrame: DetectionFrame? {
        return detectionFrames.last
    }

    var stability: Float {
        guard detectionFrames.count >= 2 else { return 0 }

        var totalJitter: Float = 0
        for i in 1..<detectionFrames.count {
            let prev = detectionFrames[i-1]
            let curr = detectionFrames[i]

            let dx = Float(curr.center.x - prev.center.x)
            let dy = Float(curr.center.y - prev.center.y)
            totalJitter += sqrt(dx * dx + dy * dy)
        }

        return totalJitter / Float(detectionFrames.count - 1)
    }

    var averageDepth: Float {
        guard !detectionFrames.isEmpty else { return 0 }
        return detectionFrames.map { $0.depth }.reduce(0, +) / Float(detectionFrames.count)
    }

    func canFinalize() -> Bool {
        return detectionFrames.count >= 10 && stability < 0.01
    }
}
