//
//  ProcessingView.swift
//  3D
//
//  Beautiful processing view with animated stages
//

import SwiftUI

struct ProcessingView: View {
    @State private var currentStage = 0
    @State private var progress: Double = 0
    @State private var animateGlow = false

    let stages = [
        (icon: "photo.stack", title: "Bilder analysieren", duration: 2.0),
        (icon: "cube.transparent", title: "Punktwolke erstellen", duration: 3.0),
        (icon: "square.3.layers.3d", title: "3D-Mesh generieren", duration: 4.0),
        (icon: "paintbrush", title: "Texturen anwenden", duration: 2.0),
        (icon: "checkmark.seal", title: "Modell optimieren", duration: 1.5)
    ]

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Main animation
                ZStack {
                    // Outer glow rings
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(
                                Color.blue.opacity(0.2 - Double(i) * 0.05),
                                lineWidth: 2
                            )
                            .frame(width: CGFloat(160 + i * 40), height: CGFloat(160 + i * 40))
                            .scaleEffect(animateGlow ? 1.1 : 1.0)
                            .animation(
                                .easeInOut(duration: 1.5)
                                .repeatForever()
                                .delay(Double(i) * 0.2),
                                value: animateGlow
                            )
                    }

                    // Center icon
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 140, height: 140)

                        Circle()
                            .fill(Color.blue.opacity(0.3))
                            .frame(width: 100, height: 100)

                        Image(systemName: stages[currentStage].icon)
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                            .symbolEffect(.pulse)
                    }

                    // Progress ring
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 160, height: 160)
                        .rotationEffect(.degrees(-90))
                }

                // Stage info
                VStack(spacing: 12) {
                    Text(stages[currentStage].title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)

                    Text("Bitte warten...")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()

                // Stage indicators
                HStack(spacing: 12) {
                    ForEach(0..<stages.count, id: \.self) { index in
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(index <= currentStage ? Color.blue : Color.white.opacity(0.2))
                                    .frame(width: 36, height: 36)

                                if index < currentStage {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                } else if index == currentStage {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.7)
                                } else {
                                    Text("\(index + 1)")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                            }

                            if index < stages.count - 1 {
                                Rectangle()
                                    .fill(index < currentStage ? Color.blue : Color.white.opacity(0.2))
                                    .frame(width: 20, height: 2)
                            }
                        }
                    }
                }
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            animateGlow = true
            simulateProgress()
        }
    }

    private func simulateProgress() {
        // This is visual only - actual progress comes from PhotogrammetrySession
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            withAnimation(.linear(duration: 0.1)) {
                progress += 0.005

                if progress >= 1.0 {
                    progress = 0
                    if currentStage < stages.count - 1 {
                        currentStage += 1
                    } else {
                        timer.invalidate()
                    }
                }
            }
        }
    }
}
