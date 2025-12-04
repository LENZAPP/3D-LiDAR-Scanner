//
//  CompletePipelineView.swift
//  3D
//
//  UI for complete scan pipeline:
//  1. Calibration (Credit card) → ZUERST
//  2. Object scan
//  3. AI processing
//  4. Volume result
//

import SwiftUI

struct CompletePipelineView: View {

    @StateObject private var pipeline = CompleteScanPipeline()
    @State private var isScanning = false
    @State private var showResult = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                header
                    .padding(.top, 60)

                Spacer()

                // Content based on step
                if !isScanning {
                    welcomeView
                } else if showResult, let result = pipeline.finalResult {
                    resultView(result)
                } else {
                    progressView
                }

                Spacer()

                // Controls
                controls
                    .padding(.horizontal, 24)
                    .padding(.bottom, 50)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Text("3D Vermessung")
                .font(.largeTitle.bold())
                .foregroundColor(.white)

            Text("Präzise Volumenberechnung")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
        }
    }

    // MARK: - Welcome View

    private var welcomeView: some View {
        VStack(spacing: 32) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            VStack(spacing: 16) {
                Text("So funktioniert's")
                    .font(.title2.bold())

                VStack(spacing: 20) {
                    StepCard(
                        number: 1,
                        icon: "creditcard.fill",
                        title: "Kreditkarte scannen",
                        description: "Für präzise Kalibrierung (Maestro/Visa)",
                        color: .blue
                    )

                    StepCard(
                        number: 2,
                        icon: "cube.fill",
                        title: "Objekt scannen",
                        description: "360° um das Objekt herumgehen",
                        color: .green
                    )

                    StepCard(
                        number: 3,
                        icon: "brain",
                        title: "KI-Verarbeitung",
                        description: "Automatische Berechnung",
                        color: .purple
                    )

                    StepCard(
                        number: 4,
                        icon: "chart.bar.fill",
                        title: "Volumen ablesen",
                        description: "Präzise Messung in cm³",
                        color: .orange
                    )
                }
            }
        }
        .padding()
    }

    // MARK: - Progress View

    private var progressView: some View {
        VStack(spacing: 40) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.2), lineWidth: 12)
                    .frame(width: 160, height: 160)

                Circle()
                    .trim(from: 0, to: pipeline.progress)
                    .stroke(currentStepColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear, value: pipeline.progress)

                VStack(spacing: 8) {
                    currentStepIcon
                        .font(.system(size: 50))
                        .foregroundStyle(currentStepColor)

                    Text("\(Int(pipeline.progress * 100))%")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                }
            }

            // Current step info
            VStack(spacing: 12) {
                Text(pipeline.currentStep.rawValue)
                    .font(.title2.bold())
                    .foregroundColor(.white)

                Text(currentStepInstructions)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Status indicators
            HStack(spacing: 32) {
                StatusIndicator(
                    icon: "creditcard.fill",
                    label: "Karte",
                    isComplete: pipeline.calibrationScanComplete
                )

                StatusIndicator(
                    icon: "cube.fill",
                    label: "Objekt",
                    isComplete: pipeline.objectScanComplete
                )

                StatusIndicator(
                    icon: "checkmark.circle.fill",
                    label: "Fertig",
                    isComplete: pipeline.currentStep == .completed
                )
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
        }
        .padding()
    }

    // MARK: - Result View

    private func resultView(_ result: CompleteScanPipeline.ScanResult) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Success indicator
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(.green.opacity(0.2))
                            .frame(width: 100, height: 100)

                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)
                    }

                    Text("Messung abgeschlossen!")
                        .font(.title.bold())

                    Text("Qualität: \(Int(result.qualityScore * 100))%")
                        .font(.subheadline)
                        .foregroundStyle(qualityColor(result.qualityScore))
                }

                // Main result: Volume
                VStack(spacing: 12) {
                    Label("Volumen", systemImage: "cube.fill")
                        .font(.headline)

                    Text(formatVolume(result.measurements.volume))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)

                    Text(formatVolumeInLiters(result.measurements.volume))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.blue.opacity(0.15))
                )

                // Dimensions
                VStack(spacing: 16) {
                    Text("Abmessungen")
                        .font(.headline)

                    HStack(spacing: 16) {
                        DimensionPill(
                            label: "L",
                            value: result.measurements.dimensions.x,
                            color: .red
                        )
                        DimensionPill(
                            label: "B",
                            value: result.measurements.dimensions.y,
                            color: .green
                        )
                        DimensionPill(
                            label: "H",
                            value: result.measurements.dimensions.z,
                            color: .blue
                        )
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )

                // Scale info
                VStack(spacing: 12) {
                    Text("Kalibrierung")
                        .font(.headline)

                    HStack {
                        Label("Methode", systemImage: "creditcard.fill")
                            .font(.subheadline)
                        Spacer()
                        Text(result.scaleInfo.method.capitalized)
                            .font(.subheadline.bold())
                    }

                    HStack {
                        Label("Genauigkeit", systemImage: "target")
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(result.scaleInfo.confidence * 100))%")
                            .font(.subheadline.bold())
                            .foregroundStyle(confidenceColor(result.scaleInfo.confidence))
                    }

                    HStack {
                        Label("Skalierung", systemImage: "ruler")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.4f", result.scaleInfo.scaleFactor))
                            .font(.subheadline.bold().monospacedDigit())
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )

                // Surface area
                HStack {
                    Label("Oberfläche", systemImage: "square.grid.3x3.fill")
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "%.2f cm²", result.measurements.surfaceArea))
                        .font(.subheadline.bold())
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
            }
            .padding()
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 16) {
            if !isScanning {
                Button(action: startPipeline) {
                    HStack(spacing: 12) {
                        Image(systemName: "play.fill")
                        Text("Messung starten")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            } else if showResult {
                Button(action: reset) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Neue Messung")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            } else {
                Button(action: cancel) {
                    HStack(spacing: 12) {
                        Image(systemName: "xmark")
                        Text("Abbrechen")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.red.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    // MARK: - Helper Views

    struct StepCard: View {
        let number: Int
        let icon: String
        let title: String
        let description: String
        let color: Color

        var body: some View {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 50, height: 50)

                    Text("\(number)")
                        .font(.title3.bold())
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: icon)
                            .foregroundStyle(color)
                        Text(title)
                            .font(.subheadline.bold())
                    }

                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
        }
    }

    struct StatusIndicator: View {
        let icon: String
        let label: String
        let isComplete: Bool

        var body: some View {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isComplete ? .green : .gray)

                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    struct DimensionPill: View {
        let label: String
        let value: Float
        let color: Color

        var body: some View {
            VStack(spacing: 4) {
                Text(label)
                    .font(.caption.bold())
                    .foregroundStyle(color)

                Text(String(format: "%.1f", value))
                    .font(.title3.bold())

                Text("mm")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.1))
            )
        }
    }

    // MARK: - Computed Properties

    private var currentStepIcon: some View {
        Group {
            switch pipeline.currentStep {
            case .initial:
                Image(systemName: "play.circle")
            case .scanningObject:
                Image(systemName: "cube.fill")
            case .scanningCalibration:
                Image(systemName: "creditcard.fill")
            case .aiProcessing:
                Image(systemName: "brain")
            case .cardDetection:
                Image(systemName: "viewfinder")
            case .scaleCalculation:
                Image(systemName: "ruler")
            case .volumeCalculation:
                Image(systemName: "chart.bar.fill")
            case .completed:
                Image(systemName: "checkmark.circle.fill")
            case .failed:
                Image(systemName: "xmark.circle.fill")
            }
        }
    }

    private var currentStepColor: Color {
        switch pipeline.currentStep {
        case .scanningCalibration, .cardDetection:
            return .blue
        case .scanningObject:
            return .green
        case .aiProcessing:
            return .purple
        case .scaleCalculation, .volumeCalculation:
            return .orange
        case .completed:
            return .green
        case .failed:
            return .red
        default:
            return .white
        }
    }

    private var currentStepInstructions: String {
        switch pipeline.currentStep {
        case .initial:
            return "Bereit zum Starten"
        case .scanningCalibration:
            return "Legen Sie Ihre Kreditkarte flach hin und scannen Sie sie"
        case .scanningObject:
            return "Gehen Sie langsam um das Objekt herum (360°)"
        case .aiProcessing:
            return "KI extrahiert Objektmaske..."
        case .cardDetection:
            return "Kreditkarte wird erkannt..."
        case .scaleCalculation:
            return "Skalierung wird berechnet..."
        case .volumeCalculation:
            return "Volumen wird berechnet..."
        case .completed:
            return "Messung abgeschlossen!"
        case .failed:
            return "Fehler aufgetreten"
        }
    }

    // MARK: - Helpers

    private func formatVolume(_ volume: Float) -> String {
        if volume < 1000 {
            return String(format: "%.1f cm³", volume)
        } else {
            return String(format: "%.2f L", volume / 1000)
        }
    }

    private func formatVolumeInLiters(_ volume: Float) -> String {
        let liters = volume / 1000
        return String(format: "≈ %.3f Liter", liters)
    }

    private func qualityColor(_ quality: Double) -> Color {
        switch quality {
        case 0.9...1.0: return .green
        case 0.7..<0.9: return .blue
        case 0.5..<0.7: return .orange
        default: return .red
        }
    }

    private func confidenceColor(_ confidence: Float) -> Color {
        qualityColor(Double(confidence))
    }

    // MARK: - Actions

    private func startPipeline() {
        isScanning = true

        Task {
            do {
                let result = try await pipeline.startCompletePipeline()
                await MainActor.run {
                    showResult = true
                }
            } catch {
                print("Pipeline failed: \(error)")
                await MainActor.run {
                    isScanning = false
                }
            }
        }
    }

    private func cancel() {
        isScanning = false
        // Cancel ongoing pipeline
    }

    private func reset() {
        isScanning = false
        showResult = false
    }
}

// MARK: - Preview

#Preview {
    CompletePipelineView()
        .preferredColorScheme(.dark)
}
