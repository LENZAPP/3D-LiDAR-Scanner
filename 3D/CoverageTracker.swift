//
//  CoverageTracker.swift
//  3D
//
//  Tracks scan coverage of an object
//

import Foundation
import ARKit
import simd

// MARK: - Coverage Data

struct CoverageData {
    var capturedViews: Set<ViewAngle> = []
    var totalFrames: Int = 0
    var qualityFrames: Int = 0

    var coveragePercent: Float {
        let requiredViews = ViewAngle.allRequiredAngles.count
        let captured = capturedViews.count
        return min(Float(captured) / Float(requiredViews), 1.0) * 100.0
    }

    var isComplete: Bool {
        return coveragePercent >= 80.0  // 80% coverage required
    }

    var description: String {
        return """
        📸 Coverage:
        - Captured: \(capturedViews.count)/\(ViewAngle.allRequiredAngles.count) views
        - Coverage: \(String(format: "%.0f", coveragePercent))%
        - Quality Frames: \(qualityFrames)/\(totalFrames)
        - Status: \(isComplete ? "✅ Complete" : "⏳ In Progress")
        """
    }
}

// MARK: - View Angles

enum ViewAngle: Hashable {
    // Horizontal angles (around Y-axis)
    case front              // 0°
    case frontRight        // 45°
    case right             // 90°
    case backRight         // 135°
    case back              // 180°
    case backLeft          // 225°
    case left              // 270°
    case frontLeft         // 315°

    // Vertical angles
    case top               // Above object
    case topFront          // 45° above front
    case topRight          // 45° above right
    case topBack           // 45° above back
    case topLeft           // 45° above left

    static var allRequiredAngles: [ViewAngle] {
        return [
            // Minimum 8 horizontal views
            .front, .frontRight, .right, .backRight,
            .back, .backLeft, .left, .frontLeft,
            // Plus 4 elevated views
            .topFront, .topRight, .topBack, .topLeft
        ]
    }

    var displayName: String {
        switch self {
        case .front: return "Vorne"
        case .frontRight: return "Vorne Rechts"
        case .right: return "Rechts"
        case .backRight: return "Hinten Rechts"
        case .back: return "Hinten"
        case .backLeft: return "Hinten Links"
        case .left: return "Links"
        case .frontLeft: return "Vorne Links"
        case .top: return "Oben"
        case .topFront: return "Oben Vorne"
        case .topRight: return "Oben Rechts"
        case .topBack: return "Oben Hinten"
        case .topLeft: return "Oben Links"
        }
    }
}

// MARK: - Coverage Tracker

class CoverageTracker: ObservableObject {

    @Published var coverage = CoverageData()

    private var objectCenter: simd_float3?
    private let angleThreshold: Float = 30.0  // degrees tolerance

    /// Update coverage with new frame
    func updateCoverage(frame: ARFrame, objectCenter: simd_float3?) {
        self.objectCenter = objectCenter

        coverage.totalFrames += 1

        guard let objectCenter = objectCenter else {
            return
        }

        // Calculate current view angle
        if let viewAngle = calculateViewAngle(cameraTransform: frame.camera.transform, objectCenter: objectCenter) {
            coverage.capturedViews.insert(viewAngle)
        }

        // Track quality frames
        if isQualityFrame(frame) {
            coverage.qualityFrames += 1
        }
    }

    /// Calculate which angle the camera is viewing from
    private func calculateViewAngle(cameraTransform: simd_float4x4, objectCenter: simd_float3) -> ViewAngle? {

        let cameraPosition = simd_make_float3(cameraTransform.columns.3)

        // Vector from object to camera
        let toCamera = cameraPosition - objectCenter

        // Horizontal angle (azimuth) - project to XZ plane
        let horizontalVector = simd_normalize(simd_float2(toCamera.x, toCamera.z))
        var azimuth = atan2(horizontalVector.y, horizontalVector.x) * 180.0 / .pi

        // Normalize to 0-360
        if azimuth < 0 { azimuth += 360 }

        // Vertical angle (elevation)
        let distance = simd_length(toCamera)
        let elevation = asin(toCamera.y / distance) * 180.0 / .pi

        // Determine view angle based on azimuth and elevation
        if elevation > 30 {
            // Elevated view
            if azimuth >= 315 || azimuth < 45 {
                return .topFront
            } else if azimuth >= 45 && azimuth < 135 {
                return .topRight
            } else if azimuth >= 135 && azimuth < 225 {
                return .topBack
            } else {
                return .topLeft
            }
        } else {
            // Horizontal view
            if azimuth >= 337.5 || azimuth < 22.5 {
                return .front
            } else if azimuth >= 22.5 && azimuth < 67.5 {
                return .frontRight
            } else if azimuth >= 67.5 && azimuth < 112.5 {
                return .right
            } else if azimuth >= 112.5 && azimuth < 157.5 {
                return .backRight
            } else if azimuth >= 157.5 && azimuth < 202.5 {
                return .back
            } else if azimuth >= 202.5 && azimuth < 247.5 {
                return .backLeft
            } else if azimuth >= 247.5 && azimuth < 292.5 {
                return .left
            } else {
                return .frontLeft
            }
        }
    }

    /// Check if frame meets quality criteria
    private func isQualityFrame(_ frame: ARFrame) -> Bool {
        // Check tracking quality
        guard frame.camera.trackingState == .normal else {
            return false
        }

        // Check light estimate
        if let lightEstimate = frame.lightEstimate {
            if lightEstimate.ambientIntensity < 500 {
                return false
            }
        }

        // Check for scene depth availability
        guard frame.sceneDepth != nil else {
            return false
        }

        return true
    }

    /// Get missing view angles
    func getMissingAngles() -> [ViewAngle] {
        return ViewAngle.allRequiredAngles.filter { !coverage.capturedViews.contains($0) }
    }

    /// Get next recommended angle
    func getNextRecommendedAngle() -> ViewAngle? {
        let missing = getMissingAngles()
        return missing.first
    }

    /// Reset coverage tracking
    func reset() {
        coverage = CoverageData()
        objectCenter = nil
    }

    /// Visual feedback message for user
    var guidanceMessage: String {
        if coverage.coveragePercent < 30 {
            return "🔄 Gehe um das Objekt herum"
        } else if coverage.coveragePercent < 60 {
            let missing = getMissingAngles()
            if let next = missing.first {
                return "📍 Noch fehlend: \(next.displayName)"
            }
            return "🔄 Weiter um das Objekt herum"
        } else if coverage.coveragePercent < 80 {
            return "✨ Fast fertig! Noch ein paar Ansichten..."
        } else {
            return "✅ Alle Ansichten erfasst!"
        }
    }
}
