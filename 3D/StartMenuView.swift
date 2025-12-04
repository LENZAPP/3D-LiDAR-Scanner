//
//  StartMenuView.swift
//  3D
//
//  Beautiful start menu with app logo and navigation options
//

import SwiftUI

struct StartMenuView: View {

    @Binding var selectedOption: StartOption?
    let hasExistingCalibration: Bool
    let calibrationResult: CalibrationResult?

    @State private var showLogo = false
    @State private var showButtons = false

    enum StartOption {
        case calibration
        case simpleCalibration  // NEW: 2-point calibration
        case scan
        case gallery  // NEW: Scanned objects gallery
    }

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.15),
                    Color(red: 0.15, green: 0.1, blue: 0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // App Logo with animation
                VStack(spacing: 20) {
                    if showLogo {
                        // App Logo Image
                        Image(systemName: "scale.3d")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 120, height: 120)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: .blue.opacity(0.5), radius: 20, x: 0, y: 10)
                            .scaleEffect(showLogo ? 1.0 : 0.5)
                            .opacity(showLogo ? 1.0 : 0.0)
                            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: showLogo)

                        Text("3D Scanner")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .opacity(showLogo ? 1.0 : 0.0)
                            .offset(y: showLogo ? 0 : 20)
                            .animation(.easeOut(duration: 0.6).delay(0.2), value: showLogo)

                        Text("Präzise AR LiDAR Vermessung")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                            .opacity(showLogo ? 1.0 : 0.0)
                            .offset(y: showLogo ? 0 : 20)
                            .animation(.easeOut(duration: 0.6).delay(0.3), value: showLogo)
                    }
                }

                Spacer()

                // Menu Options
                if showButtons {
                    VStack(spacing: 20) {
                        // Calibration Info Card (if exists)
                        if hasExistingCalibration, let result = calibrationResult {
                            CalibrationInfoCard(result: result)
                                .transition(.scale.combined(with: .opacity))
                        }

                        // NEW: Simple 2-Point Calibration Button (RECOMMENDED!)
                        MenuButton(
                            icon: "hand.point.up.left.fill",
                            title: "Einfache Kalibrierung",
                            subtitle: "✨ NEU: 2-Punkt Methode - einfacher!",
                            color: .green,
                            isPrimary: !hasExistingCalibration
                        ) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                selectedOption = .simpleCalibration
                            }
                        }
                        .transition(.scale.combined(with: .opacity))

                        // Old Calibration Button (fallback)
                        MenuButton(
                            icon: "creditcard.fill",
                            title: "Alte Kalibrierung",
                            subtitle: "(nur falls neue Methode nicht funktioniert)",
                            color: .blue.opacity(0.6),
                            isPrimary: false
                        ) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                selectedOption = .calibration
                            }
                        }
                        .transition(.scale.combined(with: .opacity))

                        // Start Scan Button (only if calibrated)
                        if hasExistingCalibration {
                            MenuButton(
                                icon: "viewfinder.circle.fill",
                                title: "3D Scan starten",
                                subtitle: "Mit gespeicherter Kalibrierung",
                                color: .green,
                                isPrimary: true
                            ) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    selectedOption = .scan
                                }
                            }
                            .transition(.scale.combined(with: .opacity))
                        }

                        // NEW: Gallery Button
                        MenuButton(
                            icon: "square.grid.2x2.fill",
                            title: "Gescannte Objekte",
                            subtitle: "Deine gespeicherten 3D-Scans",
                            color: .purple,
                            isPrimary: false
                        ) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                selectedOption = .gallery
                            }
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                    .padding(.horizontal, 30)
                    .opacity(showButtons ? 1.0 : 0.0)
                    .offset(y: showButtons ? 0 : 30)
                    .animation(.easeOut(duration: 0.5).delay(0.4), value: showButtons)
                }

                Spacer()

                // Bottom buttons (Settings & Tutorial)
                if showButtons {
                    HStack(spacing: 20) {
                        // Tutorial Button
                        SmallMenuButton(icon: "book.fill", title: "Anleitung", color: .orange) {
                            // TODO: Show tutorial
                        }

                        // Settings Button
                        SmallMenuButton(icon: "gearshape.fill", title: "Einstellungen", color: .gray) {
                            // TODO: Show settings
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 20)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .onAppear {
            withAnimation {
                showLogo = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    showButtons = true
                }
            }
        }
    }
}

// MARK: - Calibration Info Card

struct CalibrationInfoCard: View {
    let result: CalibrationResult

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 4) {
                Text("Kalibriert")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Genauigkeit: \(result.qualityDescription)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))

                Text("Faktor: \(String(format: "%.4f", result.calibrationFactor))")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.green.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.green.opacity(0.5), lineWidth: 1)
                )
        )
        .padding(.horizontal, 30)
    }
}

// MARK: - Menu Button

struct MenuButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let isPrimary: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
                action()
            }
        }) {
            HStack(spacing: 20) {
                // Icon
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 60, height: 60)

                    Image(systemName: icon)
                        .font(.system(size: 28))
                        .foregroundStyle(color)
                }

                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                // Arrow
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundStyle(color)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        isPrimary
                        ? color.opacity(0.25)
                        : Color.white.opacity(0.1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                isPrimary
                                ? color.opacity(0.6)
                                : Color.white.opacity(0.2),
                                lineWidth: isPrimary ? 2 : 1
                            )
                    )
                    .shadow(
                        color: isPrimary ? color.opacity(0.3) : .clear,
                        radius: 10,
                        x: 0,
                        y: 5
                    )
            )
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
    }
}

// MARK: - Small Menu Button

struct SmallMenuButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
                action()
            }
        }) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 50, height: 50)

                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundStyle(color)
                }

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
    }
}

// MARK: - Preview

#Preview {
    StartMenuView(
        selectedOption: .constant(nil),
        hasExistingCalibration: true,
        calibrationResult: CalibrationResult(
            referenceObject: .creditCard,
            calibrationFactor: 1.0023,
            timestamp: Date(),
            measurements: [0.30, 0.31, 0.29],
            confidence: 0.92
        )
    )
}
