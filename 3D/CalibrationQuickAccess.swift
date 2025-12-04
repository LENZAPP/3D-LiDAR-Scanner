//
//  CalibrationQuickAccess.swift
//  3D
//
//  Quick access button for calibration in scan overlay
//

import SwiftUI

/// Floating button for calibration access during scanning
struct CalibrationQuickAccessButton: View {

    @Binding var showSettings: Bool
    @State private var calibrationStatus: CalibrationStatus = .unknown
    @State private var showDebug = false

    enum CalibrationStatus {
        case unknown
        case valid
        case expiring
        case invalid

        var icon: String {
            switch self {
            case .unknown: return "questionmark.circle"
            case .valid: return "checkmark.circle.fill"
            case .expiring: return "exclamationmark.circle.fill"
            case .invalid: return "xmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .unknown: return .gray
            case .valid: return .green
            case .expiring: return .orange
            case .invalid: return .red
            }
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status Indicator
            Menu {
                Button {
                    showSettings = true
                } label: {
                    Label("Einstellungen", systemImage: "gear")
                }

                Button {
                    showDebug = true
                } label: {
                    Label("Debug-Info", systemImage: "info.circle")
                }

                Button {
                    checkCalibrationStatus()
                } label: {
                    Label("Status aktualisieren", systemImage: "arrow.clockwise")
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: calibrationStatus.icon)
                        .foregroundStyle(calibrationStatus.color)

                    Text(statusText)
                        .font(.caption.bold())
                        .foregroundStyle(.white)

                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .shadow(radius: 5)
                )
            }
        }
        .onAppear {
            checkCalibrationStatus()
        }
        .sheet(isPresented: $showDebug) {
            CalibrationDebugView()
        }
    }

    private var statusText: String {
        switch calibrationStatus {
        case .unknown: return "Kalibrierung"
        case .valid: return "Kalibriert"
        case .expiring: return "Bald erneuern"
        case .invalid: return "Nicht kalibriert"
        }
    }

    private func checkCalibrationStatus() {
        let manager = CalibrationManager()

        if let calibration = manager.loadSavedCalibration() {
            let daysSince = Calendar.current.dateComponents([.day], from: calibration.timestamp, to: Date()).day ?? 0

            if daysSince < 25 {
                calibrationStatus = .valid
            } else if daysSince < 30 {
                calibrationStatus = .expiring
            } else {
                calibrationStatus = .invalid
            }
        } else {
            calibrationStatus = .invalid
        }
    }
}

/// Badge to show in preview/results screens
struct CalibrationBadge: View {

    let calibrationResult: CalibrationResult?

    var body: some View {
        if let result = calibrationResult {
            HStack(spacing: 6) {
                Image(systemName: "ruler.fill")
                    .font(.caption)
                    .foregroundStyle(.green)

                Text(result.qualityDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(.green.opacity(0.1))
            )
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            CalibrationQuickAccessButton(showSettings: .constant(false))

            Spacer()

            CalibrationBadge(calibrationResult: CalibrationResult(
                referenceObject: .creditCard,
                calibrationFactor: 1.002,
                timestamp: Date(),
                measurements: [0.0856, 0.0857, 0.0855],
                confidence: 0.95
            ))
        }
        .padding()
    }
}
