//
//  ScanOverlayView.swift
//  3D
//
//  Beautiful overlay with progress, tips, and quality indicator
//

import SwiftUI
import RealityKit

struct ScanOverlayView: View {
    let session: ObjectCaptureSession
    @ObservedObject var feedback: FeedbackManager

    @State private var animatePulse = false
    @State private var showTip = true

    var body: some View {
        VStack {
            // Top bar with state and quality
            topBar
                .padding(.top, 60)
                .padding(.horizontal, 20)

            Spacer()

            // Center guidance
            if session.state == .detecting {
                detectingGuidance
            }

            Spacer()

            // Bottom controls
            bottomControls
                .padding(.bottom, 40)
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // State indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(stateColor)
                    .frame(width: 10, height: 10)
                    .scaleEffect(animatePulse ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(), value: animatePulse)

                Text(session.state.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.5))
            .clipShape(Capsule())

            Spacer()

            // Quality indicator (only during capture)
            if session.state == .capturing {
                qualityBadge
            }
        }
        .onAppear { animatePulse = true }
    }

    private var qualityBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 12))

            Text(feedback.scanQuality.label)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundColor(feedback.scanQuality.color)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.5))
        .clipShape(Capsule())
    }

    // MARK: - Detecting Guidance

    private var detectingGuidance: some View {
        VStack(spacing: 20) {
            // Animated scanning frame
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    .frame(width: 250, height: 250)

                // Corner brackets
                ForEach(0..<4, id: \.self) { corner in
                    CornerBracket()
                        .stroke(Color.blue, lineWidth: 3)
                        .frame(width: 40, height: 40)
                        .offset(
                            x: corner % 2 == 0 ? -105 : 105,
                            y: corner < 2 ? -105 : 105
                        )
                        .rotationEffect(.degrees(Double(corner) * 90))
                }

                // Scanning line animation
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0), .blue.opacity(0.5), .blue.opacity(0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 230, height: 3)
                    .offset(y: animatePulse ? -100 : 100)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: animatePulse)
            }

            // Tip
            if showTip {
                Text(feedback.currentTip.isEmpty ? "Richte die Kamera auf ein Objekt" : feedback.currentTip)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 16) {
            // Progress tip during capture
            if session.state == .capturing {
                capturingProgress
            }

            // Main action button
            if session.state == .ready || session.state == .detecting {
                mainActionButton
            }
        }
    }

    private var capturingProgress: some View {
        VStack(spacing: 12) {
            // Circular progress hint
            HStack(spacing: 16) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                    .rotationEffect(.degrees(animatePulse ? 360 : 0))
                    .animation(.linear(duration: 3).repeatForever(autoreverses: false), value: animatePulse)

                Text("Umkreise das Objekt langsam")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.6))
            .clipShape(Capsule())
        }
    }

    private var mainActionButton: some View {
        Button(action: {
            feedback.mediumHaptic()

            if session.state == .ready {
                // Safe call with state check
                let result = session.startDetecting()
                if result {
                    feedback.speak("Richte die Kamera auf ein Objekt")
                    feedback.updateTip(for: "detecting")
                } else {
                    print("⚠️ Failed to start detecting - session may not be ready")
                    feedback.speak("Bitte warte einen Moment")
                }
            } else if session.state == .detecting {
                session.startCapturing()
                feedback.speak("Gehe langsam um das Objekt herum")
                feedback.updateTip(for: "capturing")
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: buttonIcon)
                    .font(.system(size: 18, weight: .semibold))

                Text(buttonLabel)
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Helpers

    private var stateColor: Color {
        switch session.state {
        case .ready: return .gray
        case .detecting: return .blue
        case .capturing: return .green
        case .finishing: return .orange
        case .completed: return .green
        case .failed: return .red
        default: return .gray
        }
    }

    private var buttonIcon: String {
        session.state == .ready ? "viewfinder" : "record.circle"
    }

    private var buttonLabel: String {
        session.state == .ready ? "Scannen starten" : "Aufnahme starten"
    }
}

// MARK: - Corner Bracket Shape

struct CornerBracket: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        return path
    }
}
