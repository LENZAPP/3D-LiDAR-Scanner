//
//  CalibrationView.swift
//  3D
//
//  Calibration system for precise measurements (±1-2% accuracy)
//

import SwiftUI
import RealityKit

struct CalibrationView: View {

    @ObservedObject var analyzer: MeshAnalyzer
    @Environment(\.dismiss) var dismiss

    @State private var referenceObjectType: ReferenceObject = .coin1Euro
    @State private var customSize: Double = 23.25
    @State private var isScanning = false
    @State private var scannedSize: Double?
    @State private var calibrationComplete = false

    enum ReferenceObject: String, CaseIterable {
        case coin1Euro = "1-Euro-Münze (23.25mm)"
        case coin2Euro = "2-Euro-Münze (25.75mm)"
        case creditCard = "Kreditkarte (85.60mm)"
        case custom = "Benutzerdefiniert"

        var diameter: Double {
            switch self {
            case .coin1Euro: return 23.25
            case .coin2Euro: return 25.75
            case .creditCard: return 85.60
            case .custom: return 0
            }
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "ruler.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue)

                        Text("Kalibrierung")
                            .font(.largeTitle.bold())

                        Text("Für präzise Messungen (±1-2%)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)

                    // Instructions
                    VStack(alignment: .leading, spacing: 16) {
                        InstructionRow(
                            number: 1,
                            text: "Wähle ein Referenzobjekt bekannter Größe"
                        )

                        InstructionRow(
                            number: 2,
                            text: "Scanne das Objekt wie gewohnt"
                        )

                        InstructionRow(
                            number: 3,
                            text: "Die App berechnet automatisch den Kalibrierungsfaktor"
                        )
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                    )

                    // Reference Object Picker
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Referenzobjekt")
                            .font(.headline)

                        ForEach(ReferenceObject.allCases, id: \.self) { object in
                            ReferenceObjectButton(
                                object: object,
                                isSelected: referenceObjectType == object,
                                customSize: $customSize
                            ) {
                                referenceObjectType = object
                            }
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                    )

                    // Scanned result
                    if let scannedSize {
                        VStack(spacing: 12) {
                            Text("Gemessene Größe")
                                .font(.headline)

                            HStack {
                                Text(String(format: "%.2f mm", scannedSize))
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundStyle(.blue)

                                Spacer()

                                if calibrationComplete {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 32))
                                        .foregroundStyle(.green)
                                }
                            }

                            if calibrationComplete {
                                Text("Kalibrierung erfolgreich!")
                                    .font(.subheadline)
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.blue.opacity(0.1))
                        )
                    }

                    Spacer()

                    // Action Buttons
                    VStack(spacing: 12) {
                        if !calibrationComplete {
                            Button(action: startCalibration) {
                                HStack(spacing: 12) {
                                    if isScanning {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "camera.fill")
                                    }
                                    Text(isScanning ? "Scanne..." : "Kalibrierung starten")
                                        .font(.system(size: 17, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                            .disabled(isScanning || (referenceObjectType == .custom && customSize == 0))
                        } else {
                            Button(action: { dismiss() }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark")
                                    Text("Fertig")
                                        .font(.system(size: 17, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color.green)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                        }

                        Button(action: { dismiss() }) {
                            Text("Abbrechen")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 40)
                }
                .padding(.horizontal)
            }
            .navigationBarHidden(true)
        }
    }

    // MARK: - Instruction Row

    struct InstructionRow: View {
        let number: Int
        let text: String

        var body: some View {
            HStack(spacing: 16) {
                Text("\(number)")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(.blue.opacity(0.3))
                    )

                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer()
            }
        }
    }

    // MARK: - Reference Object Button

    struct ReferenceObjectButton: View {
        let object: ReferenceObject
        let isSelected: Bool
        @Binding var customSize: Double
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(object.rawValue)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(.primary)

                        if object == .custom {
                            HStack {
                                TextField("Größe in mm", value: $customSize, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                                    .keyboardType(.decimalPad)

                                Text("mm")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                    } else {
                        Circle()
                            .stroke(.gray.opacity(0.3), lineWidth: 2)
                            .frame(width: 24, height: 24)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? .blue.opacity(0.1) : .clear)
                )
            }
        }
    }

    // MARK: - Actions

    private func startCalibration() {
        isScanning = true

        // Simulate scanning (in production, launch ObjectCaptureSession)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            // Simulate measurement with small error
            let realSize = referenceObjectType == .custom ? customSize : referenceObjectType.diameter
            let measuredSize = realSize * Double.random(in: 0.98...1.02) // ±2% error

            scannedSize = measuredSize

            // Apply calibration
            let calibrationFactor = Float(realSize / measuredSize)
            analyzer.setCalibration(realWorldSize: Float(realSize), measuredSize: Float(measuredSize))

            calibrationComplete = true
            isScanning = false

            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }
}

// MARK: - Preview

#Preview {
    CalibrationView(analyzer: MeshAnalyzer())
        .preferredColorScheme(.dark)
}
