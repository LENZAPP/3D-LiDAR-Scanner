//
//  DepthMeasurementProtocol.swift
//  3D
//
//  Protocol abstractions for depth measurement sources
//  Allows for different depth capture methods (LiDAR, structured light, stereo, etc.)
//

import Foundation
import ARKit
import simd

// MARK: - Depth Measurement Result

/// Result of a depth measurement operation
struct DepthMeasurementResult {
    /// Depth map data
    let depthMap: CVPixelBuffer?

    /// Confidence map (if available)
    let confidenceMap: CVPixelBuffer?

    /// Point cloud extracted from depth
    let pointCloud: [SIMD3<Float>]

    /// Quality score (0.0 - 1.0)
    let qualityScore: Float

    /// Measurement method used
    let method: String

    /// Timestamp
    let timestamp: Date

    /// Any warnings or issues
    let warnings: [String]
}

// MARK: - Depth Measurement Protocol

/// Protocol for depth measurement strategies
/// Implementations: LiDARDepthMeasurement, StructuredLightDepth, StereoDepth
protocol DepthMeasurementStrategy {

    /// Name of the measurement strategy (e.g., "LiDAR", "Structured Light")
    var strategyName: String { get }

    /// Check if this strategy is supported on current device
    var isSupported: Bool { get }

    /// Maximum effective range in meters
    var maxRange: Float { get }

    /// Minimum effective range in meters
    var minRange: Float { get }

    /// Accuracy in centimeters (typical)
    var typicalAccuracy: Float { get }

    /// Start depth measurement session
    /// - Throws: Error if session cannot be started
    func startSession() throws

    /// Stop depth measurement session
    func stopSession()

    /// Capture current depth measurement
    /// - Returns: Depth measurement result
    /// - Throws: Error if capture fails
    func captureDepth() async throws -> DepthMeasurementResult

    /// Check if a specific depth range is supported
    /// - Parameter distance: Distance in meters
    /// - Returns: True if distance is within supported range
    func supportsDistance(_ distance: Float) -> Bool
}

// MARK: - Default Implementations

extension DepthMeasurementStrategy {
    func supportsDistance(_ distance: Float) -> Bool {
        return distance >= minRange && distance <= maxRange
    }
}

// MARK: - Depth Measurement Coordinator

/// Coordinates depth measurement by selecting the best strategy
class DepthMeasurementCoordinator {

    private var strategies: [DepthMeasurementStrategy] = []
    private var currentStrategy: DepthMeasurementStrategy?

    /// Register a depth measurement strategy
    func register(strategy: DepthMeasurementStrategy) {
        strategies.append(strategy)
    }

    /// Select the best strategy for current device
    /// - Returns: Best supported strategy or nil
    func selectBestStrategy() -> DepthMeasurementStrategy? {
        // Prefer LiDAR if available (most accurate)
        let supportedStrategies = strategies.filter { $0.isSupported }

        // Sort by accuracy (better accuracy = lower value)
        return supportedStrategies.min { a, b in
            a.typicalAccuracy < b.typicalAccuracy
        }
    }

    /// Start depth measurement with best available strategy
    /// - Throws: Error if no strategy available or session fails
    func startMeasurement() throws {
        guard let strategy = selectBestStrategy() else {
            throw DepthMeasurementError.noSupportedStrategy
        }

        print("📏 Using \(strategy.strategyName) for depth measurement")
        print("   Range: \(strategy.minRange)m - \(strategy.maxRange)m")
        print("   Accuracy: ±\(strategy.typicalAccuracy)cm")

        try strategy.startSession()
        currentStrategy = strategy
    }

    /// Stop current depth measurement
    func stopMeasurement() {
        currentStrategy?.stopSession()
        currentStrategy = nil
    }

    /// Capture depth using current strategy
    /// - Returns: Depth measurement result
    /// - Throws: Error if no active strategy or capture fails
    func captureDepth() async throws -> DepthMeasurementResult {
        guard let strategy = currentStrategy else {
            throw DepthMeasurementError.noActiveSession
        }

        return try await strategy.captureDepth()
    }

    /// Check if a specific distance is supported by current strategy
    /// - Parameter distance: Distance in meters
    /// - Returns: True if supported
    func supportsDistance(_ distance: Float) -> Bool {
        return currentStrategy?.supportsDistance(distance) ?? false
    }
}

// MARK: - Depth Measurement Errors

enum DepthMeasurementError: Error, LocalizedError {
    case noSupportedStrategy
    case noActiveSession
    case captureFailed(String)
    case invalidDepthData
    case deviceNotSupported

    var errorDescription: String? {
        switch self {
        case .noSupportedStrategy:
            return "No depth measurement strategy is supported on this device"
        case .noActiveSession:
            return "No active depth measurement session"
        case .captureFailed(let reason):
            return "Depth capture failed: \(reason)"
        case .invalidDepthData:
            return "Invalid depth data received"
        case .deviceNotSupported:
            return "This device does not support depth measurement"
        }
    }
}

// MARK: - Depth Quality

/// Quality assessment for depth measurements
enum DepthQuality {
    case excellent  // > 0.9
    case good       // 0.7 - 0.9
    case fair       // 0.5 - 0.7
    case poor       // < 0.5

    init(score: Float) {
        switch score {
        case 0.9...1.0:
            self = .excellent
        case 0.7..<0.9:
            self = .good
        case 0.5..<0.7:
            self = .fair
        default:
            self = .poor
        }
    }

    var description: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        }
    }

    var emoji: String {
        switch self {
        case .excellent: return "🟢"
        case .good: return "🟡"
        case .fair: return "🟠"
        case .poor: return "🔴"
        }
    }
}
