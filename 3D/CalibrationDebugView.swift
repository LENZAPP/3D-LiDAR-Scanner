//
//  CalibrationDebugView.swift
//  3D
//
//  Debug panel for calibration testing and validation
//

import SwiftUI

struct CalibrationDebugView: View {

    @StateObject private var calibrationManager = CalibrationManager()
    @State private var testObject = TestObject.creditCard
    @State private var measuredSize: Float = 0.0856 // 85.6mm in meters
    @State private var calculatedFactor: Float = 1.0
    @State private var estimatedError: Float = 0.0

    enum TestObject: String, CaseIterable {
        case creditCard = "Kreditkarte (85.6mm)"
        case coin1Euro = "1-Euro-Münze (23.25mm)"
        case coin2Euro = "2-Euro-Münze (25.75mm)"

        var realSize: Float {
            switch self {
            case .creditCard: return 0.0856  // 85.6mm
            case .coin1Euro: return 0.02325  // 23.25mm
            case .coin2Euro: return 0.02575  // 25.75mm
            }
        }
    }

    var body: some View {
        NavigationView {
            List {
                // Current Calibration
                Section("Aktuelle Kalibrierung") {
                    if let saved = calibrationManager.loadSavedCalibration() {
                        VStack(alignment: .leading, spacing: 8) {
                            DataRow(label: "Faktor", value: String(format: "%.6f", saved.calibrationFactor))
                            DataRow(label: "Konfidenz", value: String(format: "%.1f%%", saved.confidence * 100))
                            DataRow(label: "Std. Abweichung", value: String(format: "%.4f m", saved.standardDeviation))
                            DataRow(label: "Messungen", value: "\(saved.measurements.count)")

                            if !saved.measurements.isEmpty {
                                DataRow(
                                    label: "Min/Max",
                                    value: String(format: "%.4f / %.4f m",
                                                saved.measurements.min() ?? 0,
                                                saved.measurements.max() ?? 0)
                                )
                            }
                        }
                    } else {
                        Text("Keine Kalibrierung vorhanden")
                            .foregroundStyle(.secondary)
                    }
                }

                // Test Calculator
                Section("Test-Rechner") {
                    Picker("Testobjekt", selection: $testObject) {
                        ForEach(TestObject.allCases, id: \.self) { object in
                            Text(object.rawValue).tag(object)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reale Größe")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(String(format: "%.4f m (%.2f mm)", testObject.realSize, testObject.realSize * 1000))
                            .font(.subheadline.bold())
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Gemessene Größe (simuliert)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            TextField("Messung", value: $measuredSize, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.decimalPad)

                            Text("m")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Berechnen") {
                        calculateCalibration()
                    }
                    .buttonStyle(.borderedProminent)

                    if calculatedFactor != 1.0 {
                        VStack(alignment: .leading, spacing: 12) {
                            Divider()

                            DataRow(
                                label: "Kalibrierungsfaktor",
                                value: String(format: "%.6f", calculatedFactor),
                                highlight: true
                            )

                            DataRow(
                                label: "Geschätzter Fehler",
                                value: String(format: "%.2f%%", abs(estimatedError) * 100),
                                highlight: abs(estimatedError) > 0.05
                            )

                            DataRow(
                                label: "Genauigkeit",
                                value: getAccuracyRating(error: abs(estimatedError))
                            )
                        }
                    }
                }

                // Validation Tests
                Section("Validierungs-Tests") {
                    Button {
                        runValidationTest(size: 0.10) // 10cm
                    } label: {
                        TestButton(size: "10 cm", icon: "ruler")
                    }

                    Button {
                        runValidationTest(size: 0.05) // 5cm
                    } label: {
                        TestButton(size: "5 cm", icon: "ruler.fill")
                    }

                    Button {
                        runValidationTest(size: 0.02325) // 1-Euro coin
                    } label: {
                        TestButton(size: "1€ Münze", icon: "eurosign.circle")
                    }
                }

                // Advanced Debug Info
                Section("Erweiterte Debug-Info") {
                    if let saved = calibrationManager.loadSavedCalibration() {
                        DisclosureGroup("Rohdaten") {
                            ForEach(Array(saved.measurements.enumerated()), id: \.offset) { index, measurement in
                                HStack {
                                    Text("Messung \(index + 1)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    Text(String(format: "%.6f m", measurement))
                                        .font(.caption.monospacedDigit())
                                }
                            }
                        }

                        Button("Als JSON exportieren") {
                            exportCalibrationData(saved)
                        }
                    }
                }
            }
            .navigationTitle("Kalibrierungs-Debug")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Actions

    private func calculateCalibration() {
        calculatedFactor = testObject.realSize / measuredSize
        estimatedError = (measuredSize - testObject.realSize) / testObject.realSize
    }

    private func getAccuracyRating(error: Float) -> String {
        switch abs(error) {
        case 0..<0.005:
            return "🟢 Exzellent (<0.5%)"
        case 0.005..<0.01:
            return "🟢 Sehr gut (<1%)"
        case 0.01..<0.02:
            return "🟡 Gut (<2%)"
        case 0.02..<0.05:
            return "🟠 Akzeptabel (<5%)"
        default:
            return "🔴 Ungenau (>5%)"
        }
    }

    private func runValidationTest(size: Float) {
        guard let saved = calibrationManager.loadSavedCalibration() else {
            print("No calibration available for testing")
            return
        }

        // Simulate measurement with calibration applied
        let simulatedMeasurement = size / saved.calibrationFactor
        let calibratedSize = simulatedMeasurement * saved.calibrationFactor

        let error = abs(calibratedSize - size)
        let errorPercent = (error / size) * 100

        print("""
        📊 Validation Test:
        - Target Size: \(size * 1000) mm
        - Simulated Raw: \(simulatedMeasurement * 1000) mm
        - Calibrated: \(calibratedSize * 1000) mm
        - Error: \(error * 1000) mm (\(String(format: "%.2f", errorPercent))%)
        """)
    }

    private func exportCalibrationData(_ result: CalibrationResult) {
        let jsonData: [String: Any] = [
            "timestamp": result.timestamp.timeIntervalSince1970,
            "referenceObject": result.referenceObject.displayName,
            "calibrationFactor": result.calibrationFactor,
            "confidence": result.confidence,
            "measurements": result.measurements,
            "averageMeasurement": result.averageMeasurement,
            "standardDeviation": result.standardDeviation,
            "qualityDescription": result.qualityDescription
        ]

        if let jsonString = try? JSONSerialization.data(withJSONObject: jsonData, options: .prettyPrinted),
           let str = String(data: jsonString, encoding: .utf8) {
            print("📋 Calibration Data (JSON):")
            print(str)

            // Copy to pasteboard
            UIPasteboard.general.string = str
            print("✅ Copied to clipboard!")
        }
    }
}

// MARK: - Helper Views

struct DataRow: View {
    let label: String
    let value: String
    var highlight: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(highlight ? .orange : .primary)
        }
    }
}

struct TestButton: View {
    let size: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.blue)

            Text("Test mit \(size)")

            Spacer()

            Image(systemName: "play.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    CalibrationDebugView()
}
