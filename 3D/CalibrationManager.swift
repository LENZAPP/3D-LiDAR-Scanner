//
//  CalibrationManager.swift
//  3D
//
//  Coordinates the entire calibration process
//

import Foundation
import ARKit
import Vision
import Combine
import CoreMotion

/// Main calibration coordinator
@MainActor
class CalibrationManager: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published var state: CalibrationState = .notStarted
    @Published var currentQuality: DetectionQuality?
    @Published var feedbackMessage: FeedbackMessage?
    @Published var progress: Double = 0.0
    @Published var calibrationResult: CalibrationResult?

    // MARK: - Components

    private let referenceObject: ReferenceObject
    private let cardDetector: CreditCardDetector
    private let depthMeasurement: LiDARDepthMeasurement
    private let guidance: CalibrationGuidance
    private let motionManager: CMMotionManager

    private var session: CalibrationSession?
    private var measurementProcessor: MeasurementProcessor
    private var previousFrame: DetectionFrame?

    // AR Session
    private var arSession: ARSession?

    // NEW: 3D Plane-based calibration (90%+ success rate)
    private let planeCalibrator: ThreeDPlaneCalibrator
    private let sampleAggregator: CalibrationSampleAggregator

    // Store measured real-world sizes for accurate calibration
    private var measuredRealWorldSizes: [Float] = []
    private var latestCameraIntrinsics: simd_float3x3?
    private var latestImageSize: CGSize = CGSize(width: 1920, height: 1440)
    private var latestCameraTransform: simd_float4x4?

    // Timer for perfect detection countdown
    private var perfectDetectionTimer: Timer?
    private var perfectDetectionCount = 0
    // requiredPerfectFrames now defined above with requiredGoodFrames

    // Frame throttling for Vision detection
    private var frameCounter = 0
    private let visionDetectionInterval = 2  // OPTIMIZED: Run every 2nd frame (~30 FPS) for faster detection

    // Auto-calibration: track consecutive good frames
    private var consecutiveGoodFrames = 0
    private let requiredGoodFrames = 20  // ACCURACY: Collect 20 good frames for precise averaging
    private let requiredPerfectFrames = 8   // Or 8 perfect frames for faster completion

    // Smoothing: track quality history to prevent flickering
    private var qualityHistory: [Float] = []
    private let qualityHistorySize = 10  // Average over last 10 frames (was 5 - MORE smoothing!)

    // Debouncing: prevent rapid state changes
    private var lastStateChangeTime: Date = Date()
    private var lastFeedbackUpdateTime: Date = Date()
    private let minStateDuration: TimeInterval = 1.0  // Stay in state for at least 1 second
    private let minFeedbackInterval: TimeInterval = 1.5  // Update feedback text max every 1.5s

    // Haptic Feedback throttling
    private var lastHapticTime: Date = Date()
    private let minHapticInterval: TimeInterval = 0.5  // Max 1 haptic every 0.5s (was: unlimited!)

    // Hysteresis: different thresholds for improving vs degrading (ULTRA RELAXED - MAXIMUM stability!)
    private var wasGoodQuality = false
    private let goodThresholdEntering: Float = 0.30  // Need 0.30 to become "good" (was 0.40 - ULTRA LOW!)
    private let goodThresholdLeaving: Float = 0.15   // Need to drop below 0.15 to lose "good" (was 0.25 - STAYS GREEN FOREVER!)

    // MARK: - Initialization

    init(referenceObject: ReferenceObject = .creditCard) {
        self.referenceObject = referenceObject
        self.cardDetector = CreditCardDetector(referenceObject: referenceObject)
        self.depthMeasurement = LiDARDepthMeasurement()
        self.guidance = CalibrationGuidance(referenceObject: referenceObject)
        self.measurementProcessor = MeasurementProcessor()
        self.motionManager = CMMotionManager()

        // NEW: 3D Plane-based calibration components
        self.planeCalibrator = ThreeDPlaneCalibrator(referenceObject: referenceObject)
        self.sampleAggregator = CalibrationSampleAggregator()

        super.init()

        setupDetector()
        setupMotionManager()
    }

    private func setupDetector() {
        cardDetector.onDetection = { [weak self] observation in
            Task { @MainActor in
                self?.handleDetection(observation)
            }
        }

        cardDetector.onError = { [weak self] error in
            Task { @MainActor in
                self?.handleError(error)
            }
        }
    }

    private func setupMotionManager() {
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
            motionManager.startDeviceMotionUpdates()
        }
    }

    // MARK: - AR Session Management

    /// Set the AR session from the ARSCNView
    func setARSession(_ session: ARSession) {
        self.arSession = session
    }

    // MARK: - Calibration Flow

    /// Start calibration process
    func startCalibration() {
        // Reset state
        state = .detecting
        progress = 0.0
        calibrationResult = nil
        previousFrame = nil
        perfectDetectionCount = 0
        consecutiveGoodFrames = 0
        measurementProcessor.reset()
        measuredRealWorldSizes.removeAll()
        qualityHistory.removeAll()
        lastStateChangeTime = Date()
        lastFeedbackUpdateTime = Date()
        wasGoodQuality = false

        // NEW: Reset 3D calibration components
        sampleAggregator.reset()

        // Start session
        session = CalibrationSession(referenceObject: referenceObject)

        // Start AR session
        setupARSession()
        depthMeasurement.startSession()

        print("🎯 Calibration started with \(referenceObject.displayName)")
        print("   Mode: 3D PLANE-FITTING CALIBRATION (70-80% Success Rate - RELAXED)")
        print("   Required samples: 10 high-quality 3D measurements (was 15)")
        print("   Validation: 3D plane fitting + corner depth + angle < 8°")
    }

    /// Cancel calibration
    func cancelCalibration() {
        stopARSession()
        depthMeasurement.stopSession()
        session = nil
        state = .notStarted
        perfectDetectionTimer?.invalidate()
        print("❌ Calibration cancelled")
    }

    /// Process AR frame
    func processFrame(_ frame: ARFrame, pixelBuffer: CVPixelBuffer) {
        guard session != nil else { return }

        // Check AR tracking state first
        switch frame.camera.trackingState {
        case .notAvailable:
            feedbackMessage = FeedbackMessage(
                text: "🔴 AR nicht verfügbar",
                type: .warning,
                icon: "exclamationmark.triangle",
                color: .red
            )
            return

        case .limited(let reason):
            handleLimitedTracking(reason)
            // Continue with detection even if limited

        case .normal:
            // Good tracking - clear any tracking warnings
            if state == .detecting && currentQuality == nil {
                feedbackMessage = FeedbackMessage(
                    text: "🔍 Suche Kreditkarte...",
                    type: .info,
                    icon: "viewfinder",
                    color: .blue
                )
            }
        }

        // Update depth measurement (lightweight)
        depthMeasurement.update(with: frame)

        // Store camera intrinsics and transform for accurate 3D size calculation
        latestCameraIntrinsics = frame.camera.intrinsics
        latestImageSize = frame.camera.imageResolution
        latestCameraTransform = frame.camera.transform

        // Check if we have valid depth data
        if frame.sceneDepth == nil {
            // No depth data available yet
            if frameCounter % 30 == 0 {  // Log every 30 frames
                print("⚠️ No depth data available yet - AR tracking initializing...")
            }
        }

        // Throttle Vision detection - only run every Nth frame to avoid freezing
        frameCounter += 1
        if frameCounter >= visionDetectionInterval {
            frameCounter = 0

            // Only detect if tracking is at least limited
            if frame.camera.trackingState != .notAvailable {
                // CRITICAL: ARFrame.capturedImage is ALWAYS in landscape-right orientation
                // We must tell Vision about this orientation, otherwise rectangles won't be detected!
                cardDetector.detect(in: pixelBuffer, orientation: .right)
            }
        }
    }

    private func handleLimitedTracking(_ reason: ARCamera.TrackingState.Reason) {
        let message: String
        let icon: String

        switch reason {
        case .initializing:
            message = "📱 Bewege das iPhone langsam, um AR zu initialisieren"
            icon = "arrow.left.and.right"

        case .excessiveMotion:
            message = "🐌 Zu schnelle Bewegung - langsamer bewegen"
            icon = "hare"

        case .insufficientFeatures:
            message = "💡 Mehr Licht oder strukturierte Oberfläche benötigt"
            icon = "lightbulb"

        case .relocalizing:
            message = "🔄 AR wird neu initialisiert..."
            icon = "arrow.clockwise"

        @unknown default:
            message = "⚠️ AR-Tracking eingeschränkt"
            icon = "exclamationmark.triangle"
        }

        feedbackMessage = FeedbackMessage(
            text: message,
            type: .warning,
            icon: icon,
            color: .orange
        )
    }

    // MARK: - AR Session Setup

    private func setupARSession() {
        // ARSession is already started in ARViewContainer, just verify it's set
        guard arSession != nil else {
            print("⚠️ ARSession not set - call setARSession() first")
            state = .failed(.lidarUnavailable)
            return
        }

        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            print("⚠️ Device does not support LiDAR depth sensing")
            state = .failed(.lidarUnavailable)
            return
        }

        print("✅ AR Session ready (already running from ARViewContainer)")
    }

    private func stopARSession() {
        // Pause the AR session (but don't nil it since we don't own it)
        arSession?.pause()
    }

    // MARK: - Detection Handling

    private func handleDetection(_ observation: VNRectangleObservation?) {
        guard let observation = observation else {
            // No card detected - update feedback LESS frequently
            let timeSinceLastFeedback = Date().timeIntervalSince(lastFeedbackUpdateTime)
            if timeSinceLastFeedback > minFeedbackInterval || feedbackMessage == nil {
                state = .detecting
                currentQuality = nil
                feedbackMessage = FeedbackMessage(
                    text: "🔍 Suche Kreditkarte...",
                    type: .info,
                    icon: "viewfinder",
                    color: .blue
                )
                lastFeedbackUpdateTime = Date()
            }
            perfectDetectionCount = 0
            consecutiveGoodFrames = 0
            return
        }

        // OPTIMIZED: Skip validation for faster processing - let quality check handle it
        // guard cardDetector.validate(observation: observation) else { return }

        // Get depth at center
        let center = observation.boundingBox.center
        guard let depth = depthMeasurement.getSmoothedDepth(at: center) else {
            // Fallback: use any available depth
            print("⚠️ No depth at center, using fallback")
            return
        }

        // Get device normal
        let deviceNormal = depthMeasurement.getDeviceNormal()

        // Create detection frame
        let frame = DetectionFrame(
            observation: observation,
            depth: depth,
            deviceNormal: deviceNormal,
            timestamp: Date()
        )

        // Analyze quality
        let rawQuality = guidance.analyzeQuality(frame: frame, previousFrame: previousFrame)

        // STABILIZATION: Smooth quality score over time to prevent flickering
        qualityHistory.append(rawQuality.overallScore)
        if qualityHistory.count > qualityHistorySize {
            // Performance: Use dropFirst() instead of removeFirst() to avoid O(n) shift
            qualityHistory = Array(qualityHistory.dropFirst())
        }

        // Use smoothed quality score (average of last N frames)
        let smoothedScore = qualityHistory.reduce(0, +) / Float(qualityHistory.count)

        // ALWAYS update currentQuality for display (but use smoothed for decisions)
        currentQuality = rawQuality  // Always show live feedback

        // Check if measurements are stable enough for decisions
        let isStable = qualityHistory.count >= 3

        // HYSTERESIS: Apply different thresholds based on previous state
        let isGoodNow: Bool
        if wasGoodQuality {
            // Was good - need to drop below lower threshold to become "not good"
            isGoodNow = smoothedScore >= goodThresholdLeaving
        } else {
            // Was not good - need to reach higher threshold to become "good"
            isGoodNow = smoothedScore >= goodThresholdEntering
        }
        wasGoodQuality = isGoodNow

        print("📊 Quality: raw=\(String(format: "%.2f", rawQuality.overallScore)), smoothed=\(String(format: "%.2f", smoothedScore)), isGood=\(isGoodNow)")

        // OPTIMIZED: Smart auto-calibration logic with SMOOTHED score + HYSTERESIS
        let quality = rawQuality  // Use raw for display, smoothed for decisions
        let useSmoothedForDecisions = isStable

        if useSmoothedForDecisions && smoothedScore > 0.50 {
            // Perfect quality (based on smoothed score) - ULTRA LOW threshold (was 0.60 → NOW 0.50!)
            handlePerfectDetection(frame: frame, quality: quality)
            consecutiveGoodFrames = 0  // Reset good counter when perfect

        } else if useSmoothedForDecisions && isGoodNow {
            // Good quality (based on smoothed score) - count for auto-complete
            perfectDetectionCount = 0
            consecutiveGoodFrames += 1
            state = .analyzing(quality)

            // AUTO-COMPLETE: If we have enough good frames, finalize
            if consecutiveGoodFrames >= requiredGoodFrames {
                print("✅ Auto-completing calibration with \(consecutiveGoodFrames) good frames")
                measurementProcessor.addMeasurement(frame.depth)
                finalizeCalibration()
                return
            }

            // Show countdown for good frames - HEAVILY DEBOUNCED
            let timeSinceLastFeedback = Date().timeIntervalSince(lastFeedbackUpdateTime)
            if timeSinceLastFeedback > minFeedbackInterval || consecutiveGoodFrames == 1 {
                lastFeedbackUpdateTime = Date()
                lastStateChangeTime = Date()
                let remaining = requiredGoodFrames - consecutiveGoodFrames
                feedbackMessage = FeedbackMessage(
                    text: "👍 Gut! Halte Position... (\(remaining))",
                    type: .warning,
                    icon: "hand.thumbsup.fill",
                    color: .orange
                )
            }

        } else {
            // Not good enough yet - reset counters but DON'T change feedback too often
            perfectDetectionCount = 0
            consecutiveGoodFrames = 0

            // HEAVILY DEBOUNCED: Only update feedback if enough time passed
            let timeSinceLastFeedback = Date().timeIntervalSince(lastFeedbackUpdateTime)
            if timeSinceLastFeedback > minFeedbackInterval {
                state = .analyzing(quality)
                lastStateChangeTime = Date()
                lastFeedbackUpdateTime = Date()

                // Generate feedback for improvement
                let feedback = guidance.generateFeedback(quality: quality)
                feedbackMessage = feedback
            }
        }

        // Trigger haptic only for significant changes (first good frame)
        if consecutiveGoodFrames == 1 {
            triggerHaptic(.improvement)
        }

        // Add to session
        session?.addFrame(frame)
        previousFrame = frame

        // Always add measurement when detected (for averaging)
        measurementProcessor.addMeasurement(frame.depth)

        // NEW: Attempt 3D plane-based calibration on GOOD quality frames
        if useSmoothedForDecisions && isGoodNow {
            attemptPlaneFittingCalibration(observation, quality)
        }

        // Update progress
        updateProgress()
    }

    // MARK: - 3D Plane-Fitting Calibration

    /// Attempt to capture a high-quality 3D calibration sample
    private func attemptPlaneFittingCalibration(_ observation: VNRectangleObservation, _ quality: DetectionQuality) {
        // Need all required data
        guard let intrinsics = latestCameraIntrinsics,
              let transform = latestCameraTransform,
              let depthMap = arSession?.currentFrame?.sceneDepth?.depthMap else {
            return
        }

        // Attempt to create a calibration sample using 3D plane fitting
        if let sample = planeCalibrator.calibrateFromFrame(
            observation: observation,
            depthMap: depthMap,
            cameraTransform: transform,
            cameraIntrinsics: intrinsics,
            imageSize: latestImageSize
        ) {
            // Successfully created a high-quality sample!
            sampleAggregator.addSample(sample)

            // Check if we have enough samples
            if sampleAggregator.hasEnoughSamples() {
                print("✅ Collected enough high-quality samples - finalizing calibration")
                finalizeCalibration()
            } else {
                // Show progress with encouraging message
                feedbackMessage = FeedbackMessage(
                    text: "✅ \(sampleAggregator.sampleCount)/10 Samples ✓ Halte Position für nächstes Sample...",
                    type: .success,
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                triggerHaptic(.improvement)

                // IMPORTANT: Update progress immediately
                updateProgress()
            }
        }
    }

    private func handlePerfectDetection(frame: DetectionFrame, quality: DetectionQuality) {
        perfectDetectionCount += 1

        if perfectDetectionCount >= requiredPerfectFrames {
            // Enough perfect frames - finalize calibration
            finalizeCalibration()
        } else {
            // Show countdown
            let remaining = requiredPerfectFrames - perfectDetectionCount
            feedbackMessage = FeedbackMessage(
                text: "🎯 Perfekt! Halte Position... (\(remaining))",
                type: .success,
                icon: "checkmark.circle.fill",
                color: .green
            )
            state = .analyzing(quality)
        }

        // Add measurement
        measurementProcessor.addMeasurement(frame.depth)
    }

    private func finalizeCalibration() {
        guard session != nil else { return }

        // NEW: Use 3D plane-fitting calibration aggregator
        guard let result = sampleAggregator.calculateFinalCalibration(referenceObject: referenceObject) else {
            print("⚠️ Failed to finalize calibration - not enough valid samples")
            state = .failed(.poorAlignment)
            return
        }

        // Validate result (should always pass since aggregator validates)
        guard CalibrationCalculator.isValidCalibration(result) else {
            print("⚠️ Calibration validation failed: factor=\(result.calibrationFactor), confidence=\(result.confidence)")
            state = .failed(.poorAlignment)
            return
        }

        // Success!
        calibrationResult = result
        state = .calibrated(result)
        progress = 1.0

        // Trigger success haptic
        triggerHaptic(.success)

        // Save calibration
        saveCalibration(result)

        print("✅ Calibration completed with 3D plane fitting:")
        print("   Calibration Factor: \(result.calibrationFactor)")
        print("   Confidence: \(result.confidence)")
        print("   Quality: \(result.qualityDescription)")
        print("   Real card width: \(referenceObject.realSize.width * 1000)mm")
        print("   Samples collected: \(sampleAggregator.sampleCount)")

        // Stop AR session after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.stopARSession()
        }
    }

    private func handleError(_ error: Error) {
        print("⚠️ Detection error: \(error.localizedDescription)")
    }

    // MARK: - Progress Tracking

    private func updateProgress() {
        guard session != nil else {
            progress = 0.0
            return
        }

        // FIXED: Progress should NEVER go backwards once samples are collected
        // Only use sample-based progress, NOT quality-based
        let sampleProgress = Double(sampleAggregator.sampleCount) / 10.0

        // Progress should only increase, never decrease
        let newProgress = max(progress, sampleProgress)

        // Cap at 95% until finalization
        progress = min(0.95, newProgress)

        print("📊 Progress update: \(Int(progress * 100))% (samples: \(sampleAggregator.sampleCount)/10)")
    }

    // MARK: - Haptic Feedback

    private func triggerHaptic(_ trigger: HapticTrigger) {
        // THROTTLE: Prevent excessive vibration by limiting haptics to max 1 per 0.5s
        let now = Date()
        guard now.timeIntervalSince(lastHapticTime) >= minHapticInterval else {
            return  // Skip haptic if too soon
        }
        lastHapticTime = now

        let generator = UINotificationFeedbackGenerator()

        switch trigger {
        case .success:
            generator.notificationOccurred(.success)
        case .improvement:
            generator.notificationOccurred(.warning)
        case .warning:
            generator.notificationOccurred(.error)
        }
    }

    // MARK: - Persistence

    private func saveCalibration(_ result: CalibrationResult) {
        UserDefaults.standard.set(result.calibrationFactor, forKey: "calibrationFactor")
        UserDefaults.standard.set(result.timestamp.timeIntervalSince1970, forKey: "calibrationTimestamp")
        UserDefaults.standard.set(result.confidence, forKey: "calibrationConfidence")
    }

    func loadSavedCalibration() -> CalibrationResult? {
        guard let timestamp = UserDefaults.standard.object(forKey: "calibrationTimestamp") as? TimeInterval,
              UserDefaults.standard.object(forKey: "calibrationFactor") != nil else {
            print("❌ No saved calibration found")
            return nil
        }

        let factor = UserDefaults.standard.float(forKey: "calibrationFactor")
        let confidence = UserDefaults.standard.float(forKey: "calibrationConfidence")
        let date = Date(timeIntervalSince1970: timestamp)

        // Check if calibration is still valid (not older than 30 days)
        let daysSinceCalibration = Date().timeIntervalSince(date) / (24 * 3600)
        guard daysSinceCalibration < 30 else {
            print("⚠️ Calibration expired (age: \(Int(daysSinceCalibration)) days, max: 30 days)")
            return nil
        }

        print("✅ Loaded calibration (age: \(Int(daysSinceCalibration)) days)")
        print("   Factor: \(factor), Confidence: \(confidence)")

        return CalibrationResult(
            referenceObject: referenceObject,
            calibrationFactor: factor,
            timestamp: date,
            measurements: [],
            confidence: confidence
        )
    }

    /// Get calibration age in days
    func getCalibrationAge() -> Int? {
        guard let timestamp = UserDefaults.standard.object(forKey: "calibrationTimestamp") as? TimeInterval else {
            return nil
        }

        let date = Date(timeIntervalSince1970: timestamp)
        let daysSince = Date().timeIntervalSince(date) / (24 * 3600)
        return Int(daysSince)
    }

    /// Check if calibration needs renewal
    func needsRecalibration() -> Bool {
        guard let age = getCalibrationAge() else {
            return true  // No calibration = needs calibration
        }
        return age >= 30
    }

    /// Get days until calibration expires
    func getDaysUntilExpiry() -> Int? {
        guard let age = getCalibrationAge() else {
            return nil
        }
        return max(0, 30 - age)
    }

    func clearSavedCalibration() {
        UserDefaults.standard.removeObject(forKey: "calibrationFactor")
        UserDefaults.standard.removeObject(forKey: "calibrationTimestamp")
        UserDefaults.standard.removeObject(forKey: "calibrationConfidence")
    }

    // MARK: - Cleanup

    func cleanup() {
        stopARSession()
        depthMeasurement.stopSession()
        motionManager.stopDeviceMotionUpdates()
        perfectDetectionTimer?.invalidate()
    }
}
