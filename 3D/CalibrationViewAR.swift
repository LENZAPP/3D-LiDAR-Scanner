//
//  CalibrationViewAR.swift
//  3D
//
//  AR overlay UI for credit card calibration with Vision Framework
//

import SwiftUI
import ARKit

struct CalibrationViewAR: View {

    @StateObject private var manager = CalibrationManager()
    @State private var showOnboarding = false  // OPTIMIZED: Skip onboarding by default
    @State private var isCalibrating = true    // OPTIMIZED: Start immediately
    @State private var hasAutoStarted = false
    @Environment(\.dismiss) private var dismiss

    var onCalibrationComplete: ((CalibrationResult) -> Void)?

    var body: some View {
        ZStack {
            // AR Camera Feed
            ARViewContainerForCalibration(manager: manager, isCalibrating: $isCalibrating)
                .ignoresSafeArea(.all)

            // Light overlay for better visibility
            Color.black.opacity(0.2)
                .ignoresSafeArea(.all)

            // OPTIMIZED: Always show calibration UI, no onboarding screen
            VStack {
                Spacer().frame(height: 50)

                // Compact instruction banner at top
                QuickInstructionBanner()
                    .padding(.horizontal)

                // Top feedback area
                FeedbackCardAR(
                    message: manager.feedbackMessage,
                    quality: manager.currentQuality
                )
                .padding(.horizontal)

                Spacer()

                // Center guide frame
                CreditCardGuideFrameAR(
                    isDetected: manager.currentQuality != nil,
                    quality: manager.currentQuality
                )

                Spacer()

                // Bottom progress area - compact version
                CompactProgressAR(
                    progress: manager.progress,
                    state: manager.state
                )
                .padding()

                Spacer().frame(height: 30)
            }

            // Success overlay - auto-dismiss after 1.5 seconds
            if case .calibrated(let result) = manager.state {
                SuccessOverlayAR(result: result) {
                    onCalibrationComplete?(result)
                    dismiss()
                }
                .onAppear {
                    // Auto-dismiss after 1.5 seconds for faster flow
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        onCalibrationComplete?(result)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // AUTO-START: Begin calibration immediately when view appears
            if !hasAutoStarted {
                hasAutoStarted = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    manager.startCalibration()
                    print("🚀 Auto-started calibration")
                }
            }
        }
        .onDisappear {
            manager.cleanup()
        }
    }
}

// MARK: - Quick Instruction Banner

struct QuickInstructionBanner: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "creditcard.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Schrittweise Kalibrierung")
                        .font(.headline.bold())
                        .foregroundStyle(.white)

                    Text("Folge den Farben: Blau → Orange → Grün")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }

                Spacer()
            }

            // Schritt-Anzeige
            HStack(spacing: 12) {
                StepIndicator(number: 1, text: "Höhe ~30cm", icon: "arrow.up.and.down")
                StepIndicator(number: 2, text: "Parallel", icon: "rotate.3d")
                StepIndicator(number: 3, text: "Im Rahmen", icon: "viewfinder")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.7))
        )
    }
}

struct StepIndicator: View {
    let number: Int
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.blue)

            Text(text)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(.white.opacity(0.15))
        )
    }
}

// MARK: - Compact Progress View

struct CompactProgressAR: View {
    let progress: Double
    let state: CalibrationState

    var body: some View {
        HStack(spacing: 16) {
            // Progress circle
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.3), lineWidth: 4)
                    .frame(width: 50, height: 50)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(-90))

                Text("\(Int(progress * 100))%")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Kalibrierung")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(state.description)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.black.opacity(0.6))
        )
    }
}

// MARK: - AR View Container

struct ARViewContainerForCalibration: UIViewRepresentable {
    let manager: CalibrationManager
    @Binding var isCalibrating: Bool

    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)

        // Configure AR view
        arView.autoenablesDefaultLighting = true
        arView.automaticallyUpdatesLighting = true
        arView.session.delegate = context.coordinator

        // Pass the ARSession to the manager
        manager.setARSession(arView.session)

        // Start AR session with minimal configuration for faster initialization
        let configuration = ARWorldTrackingConfiguration()

        // CRITICAL: Only use sceneDepth for LiDAR, not full mesh reconstruction
        // Mesh reconstruction is slow and not needed for calibration
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics = .sceneDepth
        }

        // Disable plane detection - not needed for calibration
        configuration.planeDetection = []

        // Enable auto focus for better credit card detection
        configuration.isAutoFocusEnabled = true

        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        print("✅ ARSession started in ARViewContainer")

        return arView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // If calibration started, ensure session is running
        if isCalibrating && uiView.session.currentFrame == nil {
            let configuration = ARWorldTrackingConfiguration()

            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                configuration.frameSemantics = .sceneDepth
            }

            configuration.planeDetection = []
            configuration.isAutoFocusEnabled = true

            uiView.session.run(configuration)
            print("🔄 ARSession restarted in updateUIView")
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(manager: manager)
    }

    class Coordinator: NSObject, ARSessionDelegate {
        let manager: CalibrationManager

        init(manager: CalibrationManager) {
            self.manager = manager
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            Task { @MainActor in
                let pixelBuffer = frame.capturedImage
                manager.processFrame(frame, pixelBuffer: pixelBuffer)
            }
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            print("⚠️ ARSession error in Coordinator: \(error.localizedDescription)")
        }

        func sessionWasInterrupted(_ session: ARSession) {
            print("⚠️ ARSession was interrupted")
        }

        func sessionInterruptionEnded(_ session: ARSession) {
            print("✅ ARSession interruption ended")
        }
    }
}

// MARK: - Onboarding Overlay

struct OnboardingOverlayAR: View {
    let onStart: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea(.all)

            VStack(spacing: 30) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)

                Text("Kalibrierung")
                    .font(.largeTitle.bold())

                VStack(alignment: .leading, spacing: 16) {
                    InstructionRowAR(
                        number: 1,
                        text: "Lege deine Kreditkarte **flach** auf den Tisch"
                    )

                    InstructionRowAR(
                        number: 2,
                        text: "Halte dein iPhone **30cm über** die Karte"
                    )

                    InstructionRowAR(
                        number: 3,
                        text: "Richte das iPhone **parallel** zum Tisch aus"
                    )

                    InstructionRowAR(
                        number: 4,
                        text: "Folge den **Anweisungen** am Bildschirm"
                    )
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )

                Button(action: onStart) {
                    Text("Kalibrierung starten")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.blue)
                        )
                }
                .padding(.horizontal)
            }
            .padding()
        }
    }
}

struct InstructionRowAR: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(.blue)
                    .frame(width: 32, height: 32)

                Text("\(number)")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
            }

            Text(.init(text))  // Markdown support
                .font(.subheadline)

            Spacer()
        }
    }
}

// MARK: - Feedback Card

struct FeedbackCardAR: View {
    let message: FeedbackMessage?
    let quality: DetectionQuality?

    var body: some View {
        VStack(spacing: 12) {
            if let message = message {
                HStack(spacing: 12) {
                    Image(systemName: message.icon)
                        .font(.title2)
                        .foregroundStyle(message.color)

                    Text(message.text)
                        .font(.headline)
                        .multilineTextAlignment(.leading)

                    Spacer()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .shadow(radius: 10)
                )
            }

            // Quality indicators
            if let quality = quality {
                QualityIndicatorsAR(quality: quality)
            }
        }
    }
}

struct QualityIndicatorsAR: View {
    let quality: DetectionQuality

    var body: some View {
        VStack(spacing: 8) {
            // Distance indicator with live cm display
            HStack(spacing: 16) {
                Image(systemName: "ruler")
                    .font(.title2)
                    .foregroundStyle(distanceColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Abstand: \(quality.distance.currentDistanceCm)cm")
                        .font(.headline.bold())
                        .foregroundStyle(.white)

                    Text(quality.distance.score > 0.8 ? "Perfekt!" : "Ziel: 30cm")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                // Visual distance indicator
                DistanceBarAR(
                    current: quality.distance.currentDistanceCm,
                    ideal: 30,
                    minRange: 20,
                    maxRange: 45
                )
            }

            // Other quality badges
            HStack(spacing: 8) {
                QualityBadgeAR(label: "Ausrichtung", score: quality.alignment.score)
                QualityBadgeAR(label: "Zentrierung", score: quality.centering.score)
                QualityBadgeAR(label: "Stabilität", score: quality.stability.score)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.5))
        )
    }

    var distanceColor: Color {
        if quality.distance.score > 0.8 {
            return .green
        } else if quality.distance.score > 0.5 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - Distance Bar Indicator

struct DistanceBarAR: View {
    let current: Int  // Current distance in cm
    let ideal: Int    // Ideal distance (30cm)
    let minRange: Int // Minimum range to show (20cm)
    let maxRange: Int // Maximum range to show (45cm)

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background bar
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.2))

                // Ideal zone (green area around 30cm)
                let idealStart = CGFloat(ideal - 5 - minRange) / CGFloat(maxRange - minRange)
                let idealWidth = CGFloat(10) / CGFloat(maxRange - minRange)
                RoundedRectangle(cornerRadius: 4)
                    .fill(.green.opacity(0.3))
                    .frame(width: geometry.size.width * idealWidth)
                    .offset(x: geometry.size.width * idealStart)

                // Current position indicator
                let position = CGFloat(min(max(current, minRange), maxRange) - minRange) / CGFloat(maxRange - minRange)
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 12, height: 12)
                    .offset(x: geometry.size.width * position - 6)
            }
        }
        .frame(width: 80, height: 12)
    }

    var indicatorColor: Color {
        let diff = abs(current - ideal)
        if diff <= 5 {
            return .green
        } else if diff <= 10 {
            return .orange
        } else {
            return .red
        }
    }
}

struct QualityBadgeAR: View {
    let label: String
    let score: Float

    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(scoreColor)
                .frame(width: 12, height: 12)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.white)
        }
    }

    var scoreColor: Color {
        if score > 0.9 {
            return .green
        } else if score > 0.7 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - Credit Card Guide Frame

struct CreditCardGuideFrameAR: View {
    let isDetected: Bool
    let quality: DetectionQuality?

    private let cardAspectRatio: CGFloat = 85.6 / 53.98  // 1.586

    var body: some View {
        GeometryReader { geometry in
            let outerFrameWidth: CGFloat = geometry.size.width * 0.7
            let outerFrameHeight: CGFloat = outerFrameWidth / cardAspectRatio

            // NEUE BERECHNUNG: Innerer Referenz-Rahmen basierend auf erwarteter Größe bei 30cm
            // Bei 30cm Abstand erscheint die Karte ungefähr 50% der Bildschirmgröße
            let innerFrameWidth: CGFloat = outerFrameWidth * 0.55  // 55% des äußeren Rahmens
            let innerFrameHeight: CGFloat = innerFrameWidth / cardAspectRatio

            ZStack {
                // ÄUSSERER Rahmen (Toleranzbereich) - blau gestrichelt
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        Color.blue.opacity(0.5),
                        style: StrokeStyle(lineWidth: 2, dash: [10, 5])
                    )
                    .frame(width: outerFrameWidth, height: outerFrameHeight)

                // INNERER Referenz-Rahmen (Zielgröße) - farbcodiert
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        frameColor,
                        style: StrokeStyle(lineWidth: 4, dash: [8, 4])
                    )
                    .frame(width: innerFrameWidth, height: innerFrameHeight)
                    .animation(.easeInOut(duration: 0.3), value: isDetected)

                // Corner markers am INNEREN Rahmen
                CornerMarkersAR(
                    width: innerFrameWidth,
                    height: innerFrameHeight,
                    color: frameColor
                )

                // Center crosshair
                CrosshairAR()
                    .stroke(frameColor.opacity(0.5), lineWidth: 1)
                    .frame(width: 30, height: 30)

                // Hilfstext für äußeren Rahmen
                VStack {
                    Spacer()
                    Text("Passe Kartengröße an inneren Rahmen an")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(.black.opacity(0.7))
                        )
                        .opacity(isDetected && !(quality?.isPerfect ?? false) ? 1.0 : 0.0)
                        .animation(.easeInOut, value: isDetected)
                }
                .frame(width: outerFrameWidth, height: outerFrameHeight)
                .offset(y: outerFrameHeight / 2 + 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 250)
    }

    var frameColor: Color {
        if let quality = quality {
            if quality.isPerfect {
                return .green
            } else if quality.isGood {
                return .orange
            }
        }
        return .blue
    }
}

struct CornerMarkersAR: View {
    let width: CGFloat
    let height: CGFloat
    let color: Color

    var body: some View {
        ZStack {
            CornerMarkerAR(color: color)
                .offset(x: -width/2, y: -height/2)

            CornerMarkerAR(color: color)
                .rotationEffect(.degrees(90))
                .offset(x: width/2, y: -height/2)

            CornerMarkerAR(color: color)
                .rotationEffect(.degrees(180))
                .offset(x: width/2, y: height/2)

            CornerMarkerAR(color: color)
                .rotationEffect(.degrees(270))
                .offset(x: -width/2, y: height/2)
        }
    }
}

struct CornerMarkerAR: View {
    let color: Color

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 20))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 20, y: 0))
        }
        .stroke(color, lineWidth: 4)
    }
}

struct CrosshairAR: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.move(to: CGPoint(x: rect.midX, y: 0))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

// MARK: - Progress Card

struct ProgressCardAR: View {
    let progress: Double
    let state: CalibrationState

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.blue)

                Text("Kalibrierung")
                    .font(.subheadline.bold())

                Spacer()

                Text("\(Int(progress * 100))%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress)
                .tint(.blue)

            Text(state.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(radius: 10)
        )
    }
}

// MARK: - Success Overlay

struct SuccessOverlayAR: View {
    let result: CalibrationResult
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea(.all)

            VStack(spacing: 30) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 100))
                    .foregroundStyle(.green)

                Text("Kalibrierung erfolgreich!")
                    .font(.largeTitle.bold())

                VStack(spacing: 12) {
                    ResultRowAR(
                        label: "Qualität",
                        value: result.qualityDescription,
                        icon: "star.fill"
                    )

                    ResultRowAR(
                        label: "Genauigkeit",
                        value: String(format: "±%.1fmm", result.standardDeviation * 1000),
                        icon: "ruler.fill"
                    )

                    ResultRowAR(
                        label: "Messungen",
                        value: "\(result.measurements.count)",
                        icon: "chart.bar.fill"
                    )
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )

                Button(action: onDismiss) {
                    Text("Fertig")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.green)
                        )
                }
                .padding(.horizontal)
            }
            .padding()
        }
    }
}

struct ResultRowAR: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .frame(width: 24)

            Text(label)
                .font(.subheadline)

            Spacer()

            Text(value)
                .font(.subheadline.bold())
        }
    }
}

// MARK: - Preview

#Preview {
    CalibrationViewAR()
}
