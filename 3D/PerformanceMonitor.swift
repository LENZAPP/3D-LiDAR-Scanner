//
//  PerformanceMonitor.swift
//  3D
//
//  Performance monitoring and adaptive quality control
//

import Foundation
import UIKit
import os.log

// MARK: - Performance Metrics

struct PerformanceMetrics {
    var fps: Double = 60.0
    var memoryUsage: UInt64 = 0  // bytes
    var cpuUsage: Double = 0.0   // percentage
    var batteryLevel: Float = 1.0
    var thermalState: ProcessInfo.ThermalState = .nominal
    var frameDrops: Int = 0
    var timestamp: Date = Date()

    var isLowPerformance: Bool {
        return fps < 30 || frameDrops > 10 || thermalState == .critical
    }

    var shouldReduceQuality: Bool {
        return fps < 45 || frameDrops > 5 || thermalState == .serious
    }

    var description: String {
        return """
        📊 Performance:
        - FPS: \(String(format: "%.1f", fps))
        - Memory: \(memoryUsage / 1_000_000)MB
        - CPU: \(String(format: "%.1f", cpuUsage))%
        - Battery: \(String(format: "%.0f", batteryLevel * 100))%
        - Thermal: \(thermalStateDescription)
        - Frame Drops: \(frameDrops)
        """
    }

    private var thermalStateDescription: String {
        switch thermalState {
        case .nominal: return "✅ Normal"
        case .fair: return "⚠️ Warm"
        case .serious: return "🔥 Hot"
        case .critical: return "🚨 Critical"
        @unknown default: return "Unknown"
        }
    }
}

// MARK: - Scene Configuration

enum SceneConfiguration {
    case highQuality
    case balanced
    case lowPower

    var depthMapResolution: CGSize {
        switch self {
        case .highQuality: return CGSize(width: 256, height: 192)
        case .balanced: return CGSize(width: 192, height: 144)
        case .lowPower: return CGSize(width: 160, height: 120)
        }
    }

    var maxPointCloudPoints: Int {
        switch self {
        case .highQuality: return 100_000
        case .balanced: return 50_000
        case .lowPower: return 25_000
        }
    }

    var targetFPS: Int {
        switch self {
        case .highQuality: return 60
        case .balanced: return 30
        case .lowPower: return 24
        }
    }

    static var current: SceneConfiguration = .balanced
}

// MARK: - Performance Monitor

class PerformanceMonitor: ObservableObject {

    static let shared = PerformanceMonitor()

    @Published var metrics = PerformanceMetrics()
    @Published var currentConfiguration: SceneConfiguration = .balanced

    private var frameDrops = 0
    private let maxFrameDrops = 10

    private var lastFrameTime: CFTimeInterval = 0
    private var frameCount = 0
    private var metricsTimer: Timer?

    private let logger = OSLog(subsystem: "com.lenz.3D", category: "Performance")

    // MARK: - Monitoring

    func startMonitoring() {
        // Monitor thermal state
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )

        // Start metrics collection timer
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMetrics()
        }

        os_log("🚀 Performance monitoring started", log: logger, type: .info)
    }

    func stopMonitoring() {
        metricsTimer?.invalidate()
        metricsTimer = nil
        NotificationCenter.default.removeObserver(self)
        os_log("🛑 Performance monitoring stopped", log: logger, type: .info)
    }

    // MARK: - Frame Tracking

    func frameRendered(timestamp: CFTimeInterval) {
        if lastFrameTime > 0 {
            let frameDuration = timestamp - lastFrameTime
            let fps = 1.0 / frameDuration

            metrics.fps = fps

            // Detect frame drop (> 33ms = < 30 FPS)
            if frameDuration > 0.033 {
                frameDrops += 1
                metrics.frameDrops = frameDrops

                if shouldReduceQuality() {
                    adaptQuality()
                }
            }
        }

        lastFrameTime = timestamp
        frameCount += 1
    }

    func frameDropDetected() {
        frameDrops += 1
        metrics.frameDrops = frameDrops

        if shouldReduceQuality() {
            adaptQuality()
        }
    }

    // MARK: - Quality Adaptation

    func shouldReduceQuality() -> Bool {
        return frameDrops > maxFrameDrops || metrics.shouldReduceQuality
    }

    private func adaptQuality() {
        switch currentConfiguration {
        case .highQuality:
            currentConfiguration = .balanced
            os_log("⚠️ Reducing quality: High → Balanced", log: logger, type: .info)

        case .balanced:
            currentConfiguration = .lowPower
            os_log("⚠️ Reducing quality: Balanced → Low Power", log: logger, type: .info)

        case .lowPower:
            os_log("⚠️ Already at lowest quality", log: logger, type: .warning)
        }

        SceneConfiguration.current = currentConfiguration

        // Reset frame drop counter after adapting
        frameDrops = 0
        metrics.frameDrops = 0
    }

    func resetQuality() {
        currentConfiguration = .balanced
        SceneConfiguration.current = .balanced
        frameDrops = 0
        metrics.frameDrops = 0
    }

    // MARK: - Metrics Collection

    private func updateMetrics() {
        // Memory usage
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if kerr == KERN_SUCCESS {
            metrics.memoryUsage = info.resident_size
        }

        // Battery level
        UIDevice.current.isBatteryMonitoringEnabled = true
        metrics.batteryLevel = UIDevice.current.batteryLevel

        // Thermal state
        metrics.thermalState = ProcessInfo.processInfo.thermalState

        // CPU usage (simplified)
        var totalUsageOfCPU: Double = 0.0
        var threadsList: thread_act_array_t?
        var threadsCount = mach_msg_type_number_t(0)
        let threadsResult = withUnsafeMutablePointer(to: &threadsList) {
            $0.withMemoryRebound(to: thread_act_array_t?.self, capacity: 1) {
                task_threads(mach_task_self_, $0, &threadsCount)
            }
        }

        if threadsResult == KERN_SUCCESS, let threadsList = threadsList {
            for index in 0..<threadsCount {
                var threadInfo = thread_basic_info()
                var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
                let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                        thread_info(threadsList[Int(index)], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                    }
                }

                guard infoResult == KERN_SUCCESS else {
                    break
                }

                let threadBasicInfo = threadInfo as thread_basic_info
                if threadBasicInfo.flags & TH_FLAGS_IDLE == 0 {
                    totalUsageOfCPU += (Double(threadBasicInfo.cpu_usage) / Double(TH_USAGE_SCALE)) * 100.0
                }
            }
        }

        metrics.cpuUsage = totalUsageOfCPU
        metrics.timestamp = Date()
    }

    @objc private func thermalStateChanged() {
        let state = ProcessInfo.processInfo.thermalState
        os_log("🌡️ Thermal state changed: %{public}@", log: logger, type: .info, "\(state)")

        if state == .critical || state == .serious {
            adaptQuality()
        }
    }

    // MARK: - Logging

    func logMetrics() {
        os_log("%{public}@", log: logger, type: .info, metrics.description)
    }
}
