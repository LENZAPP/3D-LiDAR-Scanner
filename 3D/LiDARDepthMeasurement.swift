//
//  LiDARDepthMeasurement.swift
//  3D
//
//  LiDAR-based depth measurement for calibration
//

import Foundation
import ARKit
import simd

/// LiDAR depth measurement manager
class LiDARDepthMeasurement {

    // MARK: - Properties

    private var latestDepthMap: CVPixelBuffer?
    private var latestFrame: ARFrame?

    // Measurement filtering - INCREASED for more stability
    private var depthHistory: [Float] = []
    private let historySize = 15  // Increased from 10 to 15 for smoother readings

    // MARK: - Initialization

    init() {
        // No longer creates its own ARSession - will use the one from ARSCNView
    }

    // MARK: - Session Management

    /// Start session (deprecated - session is managed by ARSCNView)
    func startSession() {
        print("✅ LiDAR depth measurement ready (using shared ARSession)")
    }

    /// Pause session (deprecated - session is managed by ARSCNView)
    func pauseSession() {
        // No-op
    }

    /// Stop session (deprecated - session is managed by ARSCNView)
    func stopSession() {
        // Just clear state
        latestDepthMap = nil
        latestFrame = nil
        depthHistory.removeAll()
    }

    // MARK: - Depth Measurement

    /// Update with latest AR frame
    func update(with frame: ARFrame) {
        latestFrame = frame
        latestDepthMap = frame.sceneDepth?.depthMap
    }

    /// Measure depth at specific screen point (normalized 0-1)
    func measureDepth(at point: CGPoint) -> Float? {
        guard let depthMap = latestDepthMap else {
            return nil
        }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        // Convert normalized coordinates to pixel coordinates
        let x = Int(point.x * CGFloat(width))
        let y = Int(point.y * CGFloat(height))

        guard x >= 0, x < width, y >= 0, y < height else {
            return nil
        }

        // Get depth value
        let baseAddress = CVPixelBufferGetBaseAddress(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

        let row = baseAddress?.advanced(by: y * bytesPerRow)
        let depth = row?.assumingMemoryBound(to: Float32.self)[x]

        return depth
    }

    /// Measure depth at center of screen
    func measureCenterDepth() -> Float? {
        return measureDepth(at: CGPoint(x: 0.5, y: 0.5))
    }

    /// Measure depth in a region (average)
    func measureRegionDepth(center: CGPoint, radius: CGFloat = 0.05) -> Float? {
        guard let depthMap = latestDepthMap else {
            return nil
        }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        let centerX = Int(center.x * CGFloat(width))
        let centerY = Int(center.y * CGFloat(height))
        let radiusPixels = Int(radius * CGFloat(min(width, height)))

        var depths: [Float] = []

        let baseAddress = CVPixelBufferGetBaseAddress(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

        // Sample points in circular region
        for dy in -radiusPixels...radiusPixels {
            for dx in -radiusPixels...radiusPixels {
                // Check if point is within circle
                if dx * dx + dy * dy > radiusPixels * radiusPixels {
                    continue
                }

                let x = centerX + dx
                let y = centerY + dy

                guard x >= 0, x < width, y >= 0, y < height else {
                    continue
                }

                let row = baseAddress?.advanced(by: y * bytesPerRow)
                if let depth = row?.assumingMemoryBound(to: Float32.self)[x] {
                    if depth > 0.1 && depth < 10.0 {  // Valid range
                        depths.append(depth)
                    }
                }
            }
        }

        guard !depths.isEmpty else { return nil }

        // Return median (more robust than mean)
        let sorted = depths.sorted()
        return sorted[sorted.count / 2]
    }

    /// Get smoothed depth measurement with outlier rejection
    func getSmoothedDepth(at point: CGPoint) -> Float? {
        guard let depth = measureRegionDepth(center: point) else {
            return nil
        }

        // Add to history
        depthHistory.append(depth)
        if depthHistory.count > historySize {
            depthHistory.removeFirst()
        }

        // Need at least 5 measurements for stable reading
        guard depthHistory.count >= 5 else {
            return depth
        }

        // Use MEDIAN instead of average to reject outliers
        let sorted = depthHistory.sorted()
        let median = sorted[sorted.count / 2]

        // Also calculate moving average of recent values (last 60% of history)
        let recentCount = max(3, depthHistory.count * 6 / 10)
        let recentValues = Array(depthHistory.suffix(recentCount))
        let recentAvg = recentValues.reduce(0, +) / Float(recentValues.count)

        // Return weighted average: 70% median + 30% recent average
        return median * 0.7 + recentAvg * 0.3
    }

    // MARK: - Device Orientation

    /// Get device normal vector (direction camera is pointing)
    func getDeviceNormal() -> SIMD3<Float> {
        guard let frame = latestFrame else {
            return SIMD3<Float>(0, 0, -1)  // Default: pointing down
        }

        let transform = frame.camera.transform

        // Extract the 3x3 rotation matrix from the 4x4 transform
        let rotation = simd_float3x3(
            SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
            SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
            SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        )

        // Z-axis of camera (pointing out of device)
        let normal = rotation.columns.2
        return SIMD3<Float>(-normal.x, -normal.y, -normal.z)  // Invert to get pointing direction
    }

    /// Check if device is approximately parallel to a horizontal surface
    func isDeviceHorizontal(tolerance: Float = 0.1) -> Bool {
        let normal = getDeviceNormal()
        let up = SIMD3<Float>(0, 1, 0)

        // Dot product close to 1.0 means parallel to ground
        let parallelism = abs(dot(normalize(normal), up))
        return parallelism > (1.0 - tolerance)
    }

    /// Get tilt angle from horizontal (in degrees)
    func getTiltAngle() -> Float {
        let normal = getDeviceNormal()
        let up = SIMD3<Float>(0, 1, 0)

        let dot = dot(normalize(normal), up)
        let angleRad = acos(max(-1, min(1, dot)))
        return angleRad * 180 / .pi
    }

    // MARK: - Confidence & Quality

    /// Get depth confidence at point
    func getDepthConfidence(at point: CGPoint) -> Float? {
        guard let frame = latestFrame,
              let confidenceMap = frame.sceneDepth?.confidenceMap else {
            return nil
        }

        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) }

        let width = CVPixelBufferGetWidth(confidenceMap)
        let height = CVPixelBufferGetHeight(confidenceMap)

        let x = Int(point.x * CGFloat(width))
        let y = Int(point.y * CGFloat(height))

        guard x >= 0, x < width, y >= 0, y < height else {
            return nil
        }

        let baseAddress = CVPixelBufferGetBaseAddress(confidenceMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(confidenceMap)

        let row = baseAddress?.advanced(by: y * bytesPerRow)
        let confidence = row?.assumingMemoryBound(to: UInt8.self)[x]

        // ARConfidenceLevel: 0 = low, 1 = medium, 2 = high
        // Convert to 0.0-1.0 scale
        if let conf = confidence {
            return Float(conf) / 2.0
        }

        return nil
    }

    /// Check if depth measurement is reliable
    func isDepthReliable(at point: CGPoint) -> Bool {
        guard let confidence = getDepthConfidence(at: point) else {
            return false
        }

        return confidence > 0.5  // At least medium confidence
    }

    // MARK: - Camera Intrinsics

    /// Get camera intrinsics for scaling calculations
    func getCameraIntrinsics() -> simd_float3x3? {
        return latestFrame?.camera.intrinsics
    }

    /// Get camera resolution
    func getCameraResolution() -> CGSize? {
        guard let frame = latestFrame else { return nil }
        return frame.camera.imageResolution
    }

    // MARK: - Utilities

    /// Reset depth history
    func resetHistory() {
        depthHistory.removeAll()
    }

    /// Get current AR tracking state
    func getTrackingState() -> ARCamera.TrackingState? {
        return latestFrame?.camera.trackingState
    }

    /// Check if tracking is normal
    var isTrackingNormal: Bool {
        if case .normal = latestFrame?.camera.trackingState {
            return true
        }
        return false
    }
}

// MARK: - Depth Visualization (Debug)

extension LiDARDepthMeasurement {

    /// Get depth map as UIImage for visualization (debug)
    func getDepthMapImage() -> UIImage? {
        guard let depthMap = latestDepthMap else { return nil }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let baseAddress = CVPixelBufferGetBaseAddress(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

        let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )

        guard let cgImage = context?.makeImage() else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
