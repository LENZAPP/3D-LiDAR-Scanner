//
//  MeshSimplificationView.swift
//  3D
//
//  UI for mesh simplification controls with real-time preview
//

import SwiftUI
import ModelIO

struct MeshSimplificationView: View {

    @ObservedObject var analyzer: MeshAnalyzer
    @State private var targetPercentage: Double = 0.5
    @State private var selectedMethod: MeshSimplifier.SimplificationMethod = .balanced
    @State private var isSimplifying = false
    @State private var showResult = false
    @State private var lastResult: String = ""

    let sourceMesh: MDLMesh
    let onSimplified: (MDLMesh) -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.title2)
                    .foregroundStyle(.purple)

                Text("Mesh Optimierung")
                    .font(.title2.bold())

                Spacer()
            }

            // Method Selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Methode")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    MethodButton(
                        icon: "hare.fill",
                        title: "Schnell",
                        subtitle: "Echtzeit",
                        isSelected: selectedMethod == .fast
                    ) {
                        selectedMethod = .fast
                    }

                    MethodButton(
                        icon: "scale.3d",
                        title: "Ausgewogen",
                        subtitle: "QEM",
                        isSelected: selectedMethod == .balanced
                    ) {
                        selectedMethod = .balanced
                    }

                    MethodButton(
                        icon: "sparkles",
                        title: "Qualität",
                        subtitle: "Beste",
                        isSelected: selectedMethod == .highQuality
                    ) {
                        selectedMethod = .highQuality
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )

            // Target Percentage Slider
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Ziel-Vertices")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(Int(targetPercentage * 100))%")
                        .font(.title3.bold())
                        .foregroundStyle(.purple)
                }

                Slider(value: $targetPercentage, in: 0.1...0.9)
                    .tint(.purple)

                HStack {
                    Text("Mehr Reduktion")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("Mehr Qualität")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )

            // Current Mesh Info
            if let quality = analyzer.meshQuality {
                HStack(spacing: 20) {
                    InfoBadge(
                        icon: "circle.grid.3x3",
                        label: "Vertices",
                        value: "\(quality.vertexCount)"
                    )

                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)

                    InfoBadge(
                        icon: "circle.grid.2x2",
                        label: "Ziel",
                        value: "\(Int(Double(quality.vertexCount) * targetPercentage))",
                        color: .purple
                    )
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )
            }

            // Progress Bar
            if isSimplifying {
                VStack(spacing: 8) {
                    HStack {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)

                        Text("Verarbeitung läuft...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(Int(analyzer.simplificationProgress * 100))%")
                            .font(.subheadline.bold())
                            .foregroundStyle(.purple)
                    }

                    ProgressView(value: analyzer.simplificationProgress)
                        .tint(.purple)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.purple.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(.purple.opacity(0.3), lineWidth: 1)
                        )
                )
            }

            // Result Display
            if showResult && !lastResult.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Erfolgreich optimiert")
                            .font(.subheadline.bold())
                    }

                    Text(lastResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.green.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(.green.opacity(0.3), lineWidth: 1)
                        )
                )
            }

            Spacer()

            // Action Buttons
            HStack(spacing: 12) {
                Button {
                    Task {
                        await simplifyAuto()
                    }
                } label: {
                    HStack {
                        Image(systemName: "wand.and.stars.inverse")
                        Text("Auto")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.purple.opacity(0.2))
                    )
                    .foregroundStyle(.purple)
                }
                .disabled(isSimplifying)

                Button {
                    Task {
                        await simplifyManual()
                    }
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Optimieren")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.purple)
                    )
                    .foregroundStyle(.white)
                }
                .disabled(isSimplifying)
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func simplifyAuto() async {
        isSimplifying = true
        showResult = false

        if let result = await analyzer.simplifyMeshAuto(sourceMesh) {
            lastResult = "Auto-Optimierung abgeschlossen"
            showResult = true
            onSimplified(result)
        }

        isSimplifying = false
    }

    private func simplifyManual() async {
        isSimplifying = true
        showResult = false

        if let result = await analyzer.simplifyMesh(
            sourceMesh,
            targetPercentage: targetPercentage,
            method: selectedMethod
        ) {
            lastResult = generateResultSummary()
            showResult = true
            onSimplified(result)
        }

        isSimplifying = false
    }

    private func generateResultSummary() -> String {
        guard let quality = analyzer.meshQuality else {
            return "Optimierung abgeschlossen"
        }

        let originalCount = quality.vertexCount
        let targetCount = Int(Double(originalCount) * targetPercentage)
        let reduction = Int((1.0 - targetPercentage) * 100)

        return "\(originalCount) → ~\(targetCount) Vertices (\(reduction)% Reduktion)"
    }
}

// MARK: - Helper Views

struct MethodButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .purple : .secondary)

                VStack(spacing: 2) {
                    Text(title)
                        .font(.caption.bold())
                        .foregroundStyle(isSelected ? .primary : .secondary)

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? .purple.opacity(0.2) : .clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? .purple : .gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct InfoBadge: View {
    let icon: String
    let label: String
    let value: String
    var color: Color = .blue

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.title3.bold())
                .foregroundStyle(color)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    struct PreviewContainer: View {
        @StateObject private var analyzer: MeshAnalyzer = {
            let analyzer = MeshAnalyzer()
            analyzer.meshQuality = MeshAnalyzer.MeshQuality(
                vertexCount: 15420,
                triangleCount: 30840,
                surfaceArea: 450.2,
                watertight: true,
                confidence: 0.85
            )
            return analyzer
        }()

        var body: some View {
            MeshSimplificationView(
                analyzer: analyzer,
                sourceMesh: MDLMesh(), // Placeholder for preview
                onSimplified: { _ in }
            )
            .preferredColorScheme(.dark)
        }
    }

    return PreviewContainer()
}
