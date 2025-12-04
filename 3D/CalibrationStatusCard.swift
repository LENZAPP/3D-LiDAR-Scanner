//
//  CalibrationStatusCard.swift
//  3D
//
//  Shows calibration status and prompts for recalibration when needed
//

import SwiftUI

struct CalibrationStatusCard: View {

    @StateObject private var manager = CalibrationManager()
    @State private var calibrationResult: CalibrationResult?
    @State private var showCalibrationView = false

    var body: some View {
        VStack(spacing: 0) {
            if let result = calibrationResult {
                // Calibration exists
                CalibrationActiveCard(
                    result: result,
                    manager: manager,
                    onRecalibrate: { showCalibrationView = true }
                )
            } else {
                // No calibration
                CalibrationNeededCard(
                    onCalibrate: { showCalibrationView = true }
                )
            }
        }
        .onAppear {
            checkCalibration()
        }
        .sheet(isPresented: $showCalibrationView) {
            CalibrationViewAR { result in
                calibrationResult = result
            }
        }
    }

    private func checkCalibration() {
        calibrationResult = manager.loadSavedCalibration()
    }
}

// MARK: - Calibration Active Card

struct CalibrationActiveCard: View {
    let result: CalibrationResult
    let manager: CalibrationManager
    let onRecalibrate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(statusColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Kalibrierung")
                        .font(.headline)

                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if manager.needsRecalibration() {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            // Details
            HStack(spacing: 16) {
                DetailBadge(
                    icon: "star.fill",
                    label: "Qualität",
                    value: result.qualityDescription,
                    color: .green
                )

                DetailBadge(
                    icon: "clock.fill",
                    label: "Alter",
                    value: ageText,
                    color: ageColor
                )

                DetailBadge(
                    icon: "chart.bar.fill",
                    label: "Genauigkeit",
                    value: accuracyText,
                    color: .blue
                )
            }

            // Recalibration button if needed
            if manager.needsRecalibration() {
                Button(action: onRecalibrate) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Jetzt neu kalibrieren")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } else if let daysLeft = manager.getDaysUntilExpiry(), daysLeft <= 7 {
                // Warning if expiring soon
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.orange)

                    Text("Kalibrierung läuft in \(daysLeft) Tagen ab")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button(action: onRecalibrate) {
                        Text("Erneuern")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.blue)
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    private var statusText: String {
        if manager.needsRecalibration() {
            return "Abgelaufen - Neukalibrierung erforderlich"
        } else if let age = manager.getCalibrationAge() {
            return "Aktiv seit \(age) Tagen"
        } else {
            return "Aktiv"
        }
    }

    private var statusColor: Color {
        if manager.needsRecalibration() {
            return .orange
        } else {
            return .green
        }
    }

    private var ageText: String {
        guard let age = manager.getCalibrationAge() else {
            return "Unbekannt"
        }
        return "\(age) Tage"
    }

    private var ageColor: Color {
        guard let age = manager.getCalibrationAge() else {
            return .gray
        }

        if age >= 30 {
            return .red
        } else if age >= 25 {
            return .orange
        } else {
            return .green
        }
    }

    private var accuracyText: String {
        let stdDev = result.standardDeviation
        if stdDev == 0 {
            return "±0.5mm"
        } else {
            return String(format: "±%.1fmm", stdDev * 1000)
        }
    }
}

// MARK: - Calibration Needed Card

struct CalibrationNeededCard: View {
    let onCalibrate: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Kalibrierung erforderlich")
                        .font(.headline)

                    Text("Für präzise Messungen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text("Die App benötigt eine einmalige Kalibrierung mit einer Kreditkarte, um präzise Messungen durchzuführen (±1-2% Genauigkeit).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onCalibrate) {
                HStack {
                    Image(systemName: "camera.fill")
                    Text("Jetzt kalibrieren")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Detail Badge

struct DetailBadge: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)

            Text(value)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.primary)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 20) {
            // Preview with mock calibration result
            let mockResult = CalibrationResult(
                referenceObject: .creditCard,
                calibrationFactor: 0.95,
                timestamp: Date().addingTimeInterval(-86400 * 5), // 5 days ago
                measurements: [],
                confidence: 0.92
            )
            CalibrationActiveCard(
                result: mockResult,
                manager: CalibrationManager(),
                onRecalibrate: {}
            )

            // Preview without calibration
            CalibrationNeededCard(onCalibrate: {})
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
