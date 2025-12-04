//
//  HybridScanView.swift
//  3D
//
//  UI for hybrid scanning with real-time progress
//

import SwiftUI
import RealityKit

struct HybridScanView: View {

    @StateObject private var scanManager = HybridScanManager()
    @State private var isScanning = false
    @State private var showSettings = false
    @State private var resultURL: URL?

    let onComplete: (URL) -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with settings
                header

                Spacer()

                // Progress Display
                if isScanning {
                    progressView
                        .transition(.opacity)
                } else {
                    instructionsView
                        .transition(.opacity)
                }

                Spacer()

                // Controls
                controls
                    .padding(.horizontal, 24)
                    .padding(.bottom, 50)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(config: $scanManager.config)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hybrid Scan")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                Text("LiDAR + Photo + AI")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Circle().fill(.white.opacity(0.2)))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 60)
    }

    // MARK: - Instructions

    private var instructionsView: some View {
        VStack(spacing: 24) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            VStack(spacing: 12) {
                Text("Bereit zum Scannen")
                    .font(.title.bold())

                Text("Kombiniert LiDAR, Photogrammetrie\nund KI für beste Ergebnisse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 16) {
                FeatureRow(
                    icon: "sensor",
                    title: "LiDAR Geometrie",
                    enabled: scanManager.config.useLiDAR
                )
                FeatureRow(
                    icon: "camera.fill",
                    title: "Photogrammetrie",
                    enabled: scanManager.config.usePhotogrammetry
                )
                FeatureRow(
                    icon: "brain",
                    title: "KI-Vervollständigung",
                    enabled: scanManager.config.useAI
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

    // MARK: - Progress View

    private var progressView: some View {
        VStack(spacing: 32) {
            // Phase Indicator
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.2), lineWidth: 8)
                        .frame(width: 120, height: 120)

                    Circle()
                        .trim(from: 0, to: scanManager.scanProgress)
                        .stroke(.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear, value: scanManager.scanProgress)

                    phaseIcon
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)
                }

                Text(scanManager.currentPhase.rawValue)
                    .font(.title3.bold())

                Text("\(Int(scanManager.scanProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Stats
            VStack(spacing: 12) {
                StatRow(
                    icon: "sensor",
                    label: "LiDAR Punkte",
                    value: "\(scanManager.lidarPointCount)"
                )

                StatRow(
                    icon: "photo",
                    label: "Fotos",
                    value: "\(scanManager.photoCount)"
                )

                StatRow(
                    icon: "chart.bar.fill",
                    label: "Qualität",
                    value: "\(Int(scanManager.estimatedQuality * 100))%"
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

    private var phaseIcon: some View {
        Group {
            switch scanManager.currentPhase {
            case .idle:
                Image(systemName: "pause.circle")
            case .lidarScanning:
                Image(systemName: "sensor")
            case .photoCapture:
                Image(systemName: "camera.fill")
            case .aiProcessing:
                Image(systemName: "brain")
            case .photogrammetry:
                Image(systemName: "cube.fill")
            case .meshOptimization:
                Image(systemName: "slider.horizontal.3")
            case .completed:
                Image(systemName: "checkmark.circle.fill")
            case .failed:
                Image(systemName: "xmark.circle.fill")
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 16) {
            if !isScanning {
                Button(action: startScan) {
                    HStack(spacing: 12) {
                        Image(systemName: "play.fill")
                        Text("Scan starten")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            } else {
                Button(action: cancelScan) {
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

    struct FeatureRow: View {
        let icon: String
        let title: String
        let enabled: Bool

        var body: some View {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(enabled ? .blue : .gray)
                    .frame(width: 24)

                Text(title)
                    .font(.subheadline)

                Spacer()

                Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(enabled ? .green : .gray)
            }
        }
    }

    struct StatRow: View {
        let icon: String
        let label: String
        let value: String

        var body: some View {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                    .frame(width: 24)

                Text(label)
                    .font(.subheadline)

                Spacer()

                Text(value)
                    .font(.subheadline.bold())
            }
        }
    }

    // MARK: - Actions

    private func startScan() {
        isScanning = true

        Task {
            do {
                // Create temporary directory for images
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)

                try FileManager.default.createDirectory(
                    at: tempDir,
                    withIntermediateDirectories: true
                )

                // Start hybrid scan
                let resultURL = try await scanManager.startHybridScan(imagesDirectory: tempDir)

                await MainActor.run {
                    self.resultURL = resultURL
                    isScanning = false
                    onComplete(resultURL)
                }

            } catch {
                print("Scan failed: \(error)")
                await MainActor.run {
                    isScanning = false
                }
            }
        }
    }

    private func cancelScan() {
        isScanning = false
        // Cancel ongoing scan
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Binding var config: HybridScanManager.ScanConfiguration
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Scan-Methoden") {
                    Toggle("LiDAR verwenden", isOn: $config.useLiDAR)
                    Toggle("Photogrammetrie", isOn: $config.usePhotogrammetry)
                    Toggle("KI-Vervollständigung", isOn: $config.useAI)
                }

                Section("Qualität") {
                    Stepper("Min. Fotos: \(config.minPhotos)", value: $config.minPhotos, in: 10...50)

                    VStack(alignment: .leading) {
                        Text("LiDAR Confidence: \(Int(config.confidenceThreshold * 100))%")
                            .font(.subheadline)

                        Slider(value: $config.confidenceThreshold, in: 0...1)
                    }
                }

                Section {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Preview

#Preview {
    HybridScanView { url in
        print("Scan complete: \(url)")
    }
    .preferredColorScheme(.dark)
}
