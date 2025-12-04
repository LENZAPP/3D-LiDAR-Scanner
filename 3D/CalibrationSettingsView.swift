//
//  CalibrationSettingsView.swift
//  3D
//
//  Settings panel for calibration management
//

import SwiftUI

struct CalibrationSettingsView: View {

    @StateObject private var calibrationManager = CalibrationManager()
    @State private var showRecalibration = false
    @State private var calibrationInfo: CalibrationResult?
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            List {
                // Current Calibration Status
                Section {
                    if let info = calibrationInfo {
                        SimpleCalibrationStatusCard(result: info)
                    } else {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Nicht kalibriert")
                                    .font(.subheadline.bold())

                                Text("Kalibrierung erforderlich für präzise Messungen")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Status")
                }

                // Actions
                Section {
                    Button {
                        showRecalibration = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(.blue)

                            Text("Neu kalibrieren")

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if calibrationInfo != nil {
                        Button(role: .destructive) {
                            clearCalibration()
                        } label: {
                            HStack {
                                Image(systemName: "trash")

                                Text("Kalibrierung löschen")
                            }
                        }
                    }
                } header: {
                    Text("Aktionen")
                }

                // Information
                Section {
                    InfoRow(
                        icon: "info.circle",
                        title: "Warum kalibrieren?",
                        description: "Die Kalibrierung ermöglicht präzise Messungen mit ±0.5-1mm Genauigkeit."
                    )

                    InfoRow(
                        icon: "clock",
                        title: "Wie oft kalibrieren?",
                        description: "Einmal nach der Installation. Neu kalibrieren nach 30 Tagen oder bei Ungenauigkeiten."
                    )

                    InfoRow(
                        icon: "creditcard",
                        title: "Was wird benötigt?",
                        description: "Eine Standard-Kreditkarte (85.6 × 53.98 mm) flach auf einem Tisch."
                    )
                } header: {
                    Text("Information")
                }
            }
            .navigationTitle("Kalibrierung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") {
                        isPresented = false
                    }
                }
            }
        }
        .onAppear {
            loadCalibrationStatus()
        }
        .sheet(isPresented: $showRecalibration) {
            CalibrationViewAR { result in
                calibrationInfo = result
                showRecalibration = false
            }
        }
    }

    // MARK: - Actions

    private func loadCalibrationStatus() {
        calibrationInfo = calibrationManager.loadSavedCalibration()
    }

    private func clearCalibration() {
        calibrationManager.clearSavedCalibration()
        calibrationInfo = nil
    }
}

// MARK: - Simple Calibration Status Card (OLD VERSION - Renamed to avoid conflict)

struct SimpleCalibrationStatusCard: View {
    let result: CalibrationResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Kalibriert")
                        .font(.subheadline.bold())

                    Text(result.qualityDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            // Details
            VStack(spacing: 8) {
                DetailRow(label: "Referenzobjekt", value: result.referenceObject.displayName)
                DetailRow(label: "Kalibrierungsfaktor", value: String(format: "%.4f", result.calibrationFactor))
                DetailRow(label: "Genauigkeit", value: String(format: "±%.1fmm", result.standardDeviation * 1000))
                DetailRow(label: "Datum", value: formatDate(result.timestamp))
                DetailRow(label: "Gültigkeit", value: daysRemaining(from: result.timestamp))
            }
        }
        .padding(.vertical, 8)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func daysRemaining(from date: Date) -> String {
        let daysSince = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        let daysRemaining = 30 - daysSince

        if daysRemaining > 0 {
            return "\(daysRemaining) Tage verbleibend"
        } else {
            return "⚠️ Neu kalibrieren empfohlen"
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.caption.bold())
        }
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    CalibrationSettingsView(isPresented: .constant(true))
}
