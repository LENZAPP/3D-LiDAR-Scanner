//
//  ModelPreviewView.swift
//  3D
//
//  Beautiful model preview with AR QuickLook and sharing
//

import SwiftUI
import QuickLook

struct ModelPreviewView: View {
    let modelURL: URL
    let onNewScan: () -> Void

    @State private var showARQuickLook = false
    @State private var showShareSheet = false
    @State private var showSuccessAnimation = true
    @State private var showMeasurements = false
    @StateObject private var analyzer = MeshAnalyzer()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                header
                    .padding(.top, 60)

                // 3D Preview
                modelPreview
                    .padding(20)

                // Measurements section
                if showMeasurements {
                    ScrollView {
                        MeasurementView(analyzer: analyzer)
                    }
                    .frame(maxHeight: 300)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer()

                // Actions
                actionButtons
                    .padding(.horizontal, 24)
                    .padding(.bottom, 50)
            }

            // Success overlay
            if showSuccessAnimation {
                successOverlay
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [modelURL])
        }
        .fullScreenCover(isPresented: $showARQuickLook) {
            ARQuickLookView(modelFile: modelURL) {
                showARQuickLook = false
            }
        }
        .onAppear {
            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // Hide success after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(.easeOut(duration: 0.5)) {
                    showSuccessAnimation = false
                }
            }

            // Analyze the model
            Task {
                do {
                    try await analyzer.analyzeMesh(from: modelURL)
                    withAnimation(.spring()) {
                        showMeasurements = true
                    }
                } catch {
                    print("❌ Failed to analyze mesh: \(error)")
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Text("Dein 3D-Modell")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)

            HStack(spacing: 16) {
                Label("USDZ", systemImage: "doc.fill")
                if let size = fileSize {
                    Label(size, systemImage: "arrow.down.circle")
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - Model Preview

    private var modelPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )

            // 3D model icon
            VStack(spacing: 12) {
                Image(systemName: "cube.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white.opacity(0.3))
                Text("3D-Modell")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 14) {
            // Measurements toggle
            if analyzer.dimensions != nil {
                Button(action: {
                    withAnimation(.spring()) {
                        showMeasurements.toggle()
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "ruler")
                            .font(.system(size: 18))
                        Text(showMeasurements ? "Maße verbergen" : "Maße anzeigen")
                            .font(.system(size: 17, weight: .semibold))
                        Spacer()
                        if let volume = analyzer.volume {
                            Text(String(format: "%.1f cm³", volume))
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .padding(.horizontal, 20)
                    .background(Color.blue.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }

            // Primary: View in AR
            Button(action: { showARQuickLook = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "arkit")
                        .font(.system(size: 18))
                    Text("In AR ansehen")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            // Secondary row
            HStack(spacing: 12) {
                // Share
                Button(action: { showShareSheet = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Teilen")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.white.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                // New Scan
                Button(action: onNewScan) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                        Text("Neuer Scan")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.white.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    // MARK: - Success Overlay

    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.2))
                        .frame(width: 140, height: 140)

                    Circle()
                        .fill(Color.green)
                        .frame(width: 100, height: 100)

                    Image(systemName: "checkmark")
                        .font(.system(size: 50, weight: .bold))
                        .foregroundColor(.white)
                }

                Text("Modell erstellt!")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: - Helpers

    private var fileSize: String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: modelURL.path),
              let size = attrs[.size] as? UInt64 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}


// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
