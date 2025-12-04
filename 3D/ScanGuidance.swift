//
//  ScanGuidance.swift
//  3D
//
//  Real-time guidance system for 3D scanning
//

import Foundation
import ARKit
import simd

// MARK: - Scan Guidance Types

enum ScanGuidance: Equatable {
    case idle
    case tooClose(distance: Float)      // "Gehen Sie weiter weg"
    case tooFar(distance: Float)        // "Gehen Sie näher heran"
    case goodDistance(distance: Float)  // "✓ Gute Position"
    case movingTooFast(speed: Float)    // "Bewegen Sie das iPhone langsamer"
    case insufficientLight              // "Mehr Licht erforderlich"
    case coverage(percent: Float)       // "45% erfasst"
    case objectNotVisible               // "Objekt nicht sichtbar"

    var message: String {
        switch self {
        case .idle:
            return "Bereit zum Scannen"
        case .tooClose(let distance):
            return "⬆️ Zu nah (\(String(format: "%.1f", distance * 100))cm) - weiter weg"
        case .tooFar(let distance):
            return "⬇️ Zu weit (\(String(format: "%.1f", distance * 100))cm) - näher heran"
        case .goodDistance(let distance):
            return "✅ Perfekte Distanz (\(String(format: "%.1f", distance * 100))cm)"
        case .movingTooFast(let speed):
            return "🐌 Langsamer bewegen (\(String(format: "%.1f", speed))m/s)"
        case .insufficientLight:
            return "💡 Mehr Licht benötigt"
        case .coverage(let percent):
            return "📸 \(Int(percent))% erfasst"
        case .objectNotVisible:
            return "👁️ Objekt nicht sichtbar"
        }
    }

    var color: String {
        switch self {
        case .goodDistance, .coverage:
            return "green"
        case .tooClose, .tooFar, .movingTooFast:
            return "orange"
        case .insufficientLight, .objectNotVisible:
            return "red"
        case .idle:
            return "blue"
        }
    }

    var icon: String {
        switch self {
        case .idle:
            return "viewfinder"
        case .tooClose:
            return "arrow.up"
        case .tooFar:
            return "arrow.down"
        case .goodDistance:
            return "checkmark.circle.fill"
        case .movingTooFast:
            return "hare.fill"
        case .insufficientLight:
            return "lightbulb.fill"
        case .coverage:
            return "chart.bar.fill"
        case .objectNotVisible:
            return "eye.slash.fill"
        }
    }
}

// MARK: - Scan Guidance Engine

class ScanGuidanceEngine {

    // Optimal range for iPhone 15 Pro LiDAR
    private let optimalMinDistance: Float = 0.15  // 15cm
    private let optimalMaxDistance: Float = 2.0   // 2m
    private let goodMinDistance: Float = 0.10     // 10cm
    private let goodMaxDistance: Float = 3.0      // 3m

    // Motion thresholds
    private let maxSpeed: Float = 0.08            // 8cm/s max movement speed

    // Light thresholds
    private let minBrightness: Float = 100.0      // Minimum ambient light

    // Previous frame tracking
    private var previousTransform: simd_float4x4?
    private var previousTimestamp: TimeInterval = 0

    /// Analyze current frame and provide guidance
    func analyze(frame: ARFrame, objectBounds: BoundingBox?) -> ScanGuidance {

        // Check if object is visible
        guard let bounds = objectBounds else {
            return .objectNotVisible
        }

        // Calculate distance to object
        let distance = calculateDistance(cameraTransform: frame.camera.transform, objectBounds: bounds)

        // Check motion
        if let motion = calculateMotion(frame: frame) {
            if motion > maxSpeed {
                return .movingTooFast(speed: motion)
            }
        }

        // Check light conditions
        if let lightEstimate = frame.lightEstimate {
            if Float(lightEstimate.ambientIntensity) < minBrightness {
                return .insufficientLight
            }
        }

        // Check distance
        if distance < optimalMinDistance {
            return .tooClose(distance: distance)
        } else if distance > optimalMaxDistance {
            return .tooFar(distance: distance)
        } else {
            return .goodDistance(distance: distance)
        }
    }

    /// Calculate distance from camera to object center
    private func calculateDistance(cameraTransform: simd_float4x4, objectBounds: BoundingBox) -> Float {
        let cameraPosition = simd_make_float3(cameraTransform.columns.3)
        let objectCenter = objectBounds.center
        return simd_distance(cameraPosition, objectCenter)
    }

    /// Calculate camera motion speed
    private func calculateMotion(frame: ARFrame) -> Float? {
        guard let previousTransform = previousTransform else {
            self.previousTransform = frame.camera.transform
            self.previousTimestamp = frame.timestamp
            return nil
        }

        let currentTransform = frame.camera.transform
        let currentPosition = simd_make_float3(currentTransform.columns.3)
        let previousPosition = simd_make_float3(previousTransform.columns.3)

        let distance = simd_distance(currentPosition, previousPosition)
        let timeDelta = Float(frame.timestamp - previousTimestamp)

        self.previousTransform = currentTransform
        self.previousTimestamp = frame.timestamp

        guard timeDelta > 0 else { return 0 }

        return distance / timeDelta  // m/s
    }

    func reset() {
        previousTransform = nil
        previousTimestamp = 0
    }
}

// NOTE: BoundingBox is defined in CalibratedMeasurements.swift
