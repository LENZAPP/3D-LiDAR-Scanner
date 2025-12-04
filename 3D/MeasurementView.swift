//
//  MeasurementView.swift
//  3D
//
//  Displays precise measurements and volume calculations
//

import SwiftUI
import ModelIO

struct MeasurementView: View {

    @ObservedObject var analyzer: MeshAnalyzer
    @State private var showSimplification = false
    @State private var showMaterialInput = false
    @State private var materialDensity: String = ""
    @State private var selectedDensity: Double?
    var currentMesh: MDLMesh?

    // Calculated weight based on volume and density
    private var calculatedWeight: Double? {
        guard let volume = analyzer.volume,
              let density = selectedDensity else {
            return nil
        }
        return volume * density
    }

    var body: some View {
        VStack(spacing: 20) {
            // Title
            Text("Vermessung")
                .font(.title2)
                .fontWeight(.bold)

            // Dimensions Card
            if let dimensions = analyzer.dimensions {
                VStack(spacing: 12) {
                    MeasurementRow(
                        icon: "arrow.left.and.right",
                        label: "Breite",
                        value: dimensions.width,
                        unit: "cm",
                        color: .red
                    )

                    MeasurementRow(
                        icon: "arrow.up.and.down",
                        label: "Höhe",
                        value: dimensions.height,
                        unit: "cm",
                        color: .green
                    )

                    MeasurementRow(
                        icon: "arrow.forward.to.line",
                        label: "Tiefe",
                        value: dimensions.depth,
                        unit: "cm",
                        color: .blue
                    )
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )
            }

            // Volume Card
            if let volume = analyzer.volume {
                VStack(spacing: 8) {
                    Label("Volumen", systemImage: "cube.fill")
                        .font(.headline)

                    Text(formatVolume(volume))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)

                    Text(formatVolumeInLiters(volume))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.blue.opacity(0.1))
                )
            }

            // Material Selection Button
            if analyzer.volume != nil {
                Button {
                    showMaterialInput = true
                } label: {
                    HStack {
                        Image(systemName: selectedDensity == nil ? "plus.circle.fill" : "pencil.circle.fill")
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedDensity == nil ? "Material auswählen" : "Material ändern")
                                .font(.subheadline.bold())
                            if let density = selectedDensity {
                                Text("Dichte: \(String(format: "%.2f", density).replacingOccurrences(of: ".", with: ",")) g/cm³")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Materialdichte eingeben für Gewichtsberechnung")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.orange.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(.orange.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showMaterialInput) {
                    MaterialDensityInputView(
                        materialDensity: $materialDensity,
                        selectedDensity: $selectedDensity,
                        isPresented: $showMaterialInput
                    )
                    .presentationDetents([.medium])
                }
            }

            // Weight Card (if density is selected)
            if let weight = calculatedWeight {
                VStack(spacing: 8) {
                    Label("Gewicht", systemImage: "scalemass.fill")
                        .font(.headline)

                    Text(formatWeight(weight))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)

                    if let density = selectedDensity {
                        Text("bei \(String(format: "%.2f", density).replacingOccurrences(of: ".", with: ",")) g/cm³")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.orange.opacity(0.1))
                )
            }

            // Mesh Quality Card
            if let quality = analyzer.meshQuality {
                VStack(spacing: 8) {
                    Label("Mesh-Qualität", systemImage: "chart.bar.fill")
                        .font(.headline)

                    HStack(spacing: 20) {
                        VStack(spacing: 4) {
                            Text("\(quality.vertexCount)")
                                .font(.title3.bold())
                            Text("Vertices")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Divider()
                            .frame(height: 30)

                        VStack(spacing: 4) {
                            Text("\(quality.triangleCount)")
                                .font(.title3.bold())
                            Text("Dreiecke")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Divider()
                            .frame(height: 30)

                        VStack(spacing: 4) {
                            Text(quality.qualityScore)
                                .font(.title3.bold())
                                .foregroundStyle(qualityColor(quality.confidence))
                            Text("Bewertung")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Confidence Bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(.gray.opacity(0.2))
                                .frame(height: 8)
                                .cornerRadius(4)

                            Rectangle()
                                .fill(qualityGradient(quality.confidence))
                                .frame(width: geometry.size.width * quality.confidence, height: 8)
                                .cornerRadius(4)
                        }
                    }
                    .frame(height: 8)

                    HStack {
                        Image(systemName: quality.watertight ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(quality.watertight ? .green : .orange)
                        Text(quality.watertight ? "Geschlossenes Mesh" : "Offenes Mesh")
                            .font(.caption)
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )
            }

            // Surface Area
            if let quality = analyzer.meshQuality {
                HStack {
                    Image(systemName: "square.grid.3x3.fill")
                    Text("Oberfläche:")
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "%.2f cm²", quality.surfaceArea))
                        .font(.subheadline.bold())
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
            }

            // Mesh Optimization Button
            if currentMesh != nil {
                Button {
                    showSimplification = true
                } label: {
                    HStack {
                        Image(systemName: "wand.and.stars")
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mesh Optimieren")
                                .font(.subheadline.bold())
                            Text("Vertices reduzieren & Performance verbessern")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
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
                    .foregroundStyle(.purple)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showSimplification) {
                    if let mesh = currentMesh {
                        MeshSimplificationView(
                            analyzer: analyzer,
                            sourceMesh: mesh,
                            onSimplified: { simplified in
                                // Handle simplified mesh
                                showSimplification = false
                            }
                        )
                        .presentationDetents([.large])
                    }
                }
            }
        }
        .padding()
    }

    // MARK: - Helper Views

    struct MeasurementRow: View {
        let icon: String
        let label: String
        let value: Double
        let unit: String
        let color: Color

        var body: some View {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 24)

                Text(label)
                    .font(.subheadline)

                Spacer()

                Text(String(format: "%.2f", value))
                    .font(.title3.bold())
                    .foregroundStyle(color)

                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func formatVolume(_ volume: Double) -> String {
        if volume < 1000 {
            return String(format: "%.1f cm³", volume)
        } else {
            return String(format: "%.2f L", volume / 1000)
        }
    }

    private func formatVolumeInLiters(_ volume: Double) -> String {
        let liters = volume / 1000
        return String(format: "≈ %.3f Liter", liters)
    }

    private func formatWeight(_ weight: Double) -> String {
        if weight < 1000 {
            return String(format: "%.1f g", weight)
        } else {
            return String(format: "%.2f kg", weight / 1000)
        }
    }

    private func qualityColor(_ confidence: Double) -> Color {
        switch confidence {
        case 0.9...1.0: return .green
        case 0.7..<0.9: return .blue
        case 0.5..<0.7: return .orange
        default: return .red
        }
    }

    private func qualityGradient(_ confidence: Double) -> LinearGradient {
        let color = qualityColor(confidence)
        return LinearGradient(
            colors: [color.opacity(0.6), color],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Material Density Input View

struct MaterialDensityInputView: View {
    @Binding var materialDensity: String
    @Binding var selectedDensity: Double?
    @Binding var isPresented: Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "scalemass.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)

                    Text("Materialdichte eingeben")
                        .font(.title2.bold())

                    Text("Geben Sie die Dichte des Materials in g/cm³ ein")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Dichte (g/cm³)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)

                    TextField("z.B. 0,46 oder 1,23", text: $materialDensity)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                        .focused($isFocused)
                        .padding(.horizontal)
                }
                .padding(.horizontal)

                // Common materials reference
                VStack(alignment: .leading, spacing: 8) {
                    Text("Beispiele:")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)

                    VStack(spacing: 4) {
                        MaterialExampleRow(name: "Wasser", density: "1,00")
                        MaterialExampleRow(name: "Holz (Kiefer)", density: "0,46")
                        MaterialExampleRow(name: "Aluminium", density: "2,70")
                        MaterialExampleRow(name: "Stahl", density: "7,85")
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
                .padding(.horizontal)

                Spacer()

                Button {
                    saveDensity()
                } label: {
                    Text("Bestätigen")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isValidInput ? .orange : .gray)
                        )
                }
                .disabled(!isValidInput)
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        isPresented = false
                    }
                }
            }
            .onAppear {
                // Pre-fill with current density if available
                if let density = selectedDensity {
                    materialDensity = String(format: "%.2f", density).replacingOccurrences(of: ".", with: ",")
                }
                isFocused = true
            }
        }
    }

    private var isValidInput: Bool {
        parseDensity(materialDensity) != nil
    }

    private func saveDensity() {
        if let density = parseDensity(materialDensity) {
            selectedDensity = density
            isPresented = false
        }
    }

    private func parseDensity(_ input: String) -> Double? {
        // Replace comma with period for Double parsing
        let normalized = input.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else {
            return nil
        }
        return value
    }
}

struct MaterialExampleRow: View {
    let name: String
    let density: String

    var body: some View {
        HStack {
            Text(name)
                .font(.caption)
            Spacer()
            Text("\(density) g/cm³")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    PreviewWrapper()
}

struct PreviewWrapper: View {
    @StateObject private var analyzer: MeshAnalyzer = {
        let analyzer = MeshAnalyzer()
        analyzer.dimensions = MeshAnalyzer.Dimensions(width: 15.3, height: 8.7, depth: 4.2)
        analyzer.volume = 560.2
        analyzer.meshQuality = MeshAnalyzer.MeshQuality(
            vertexCount: 12458,
            triangleCount: 24916,
            surfaceArea: 342.5,
            watertight: true,
            confidence: 0.87
        )
        return analyzer
    }()

    var body: some View {
        MeasurementView(analyzer: analyzer)
            .preferredColorScheme(.dark)
    }
}
