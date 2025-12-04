//
//  ScannedObjectsGalleryView.swift
//  3D
//
//  Gallery view for all scanned objects with measurements
//

import SwiftUI
import QuickLook
import UniformTypeIdentifiers
import os.log

struct ScannedObjectsGalleryView: View {
    @ObservedObject var manager = ScannedObjectsManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedObject: ScannedObject?
    @State private var showingDetail = false
    @State private var showingDocumentPicker = false

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.1, green: 0.1, blue: 0.15),
                        Color(red: 0.15, green: 0.1, blue: 0.2)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if manager.objects.isEmpty {
                    // Empty state
                    emptyStateView
                } else {
                    // Gallery grid
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)
                        ], spacing: 16) {
                            ForEach(manager.objects) { object in
                                ObjectCardView(object: object)
                                    .onTapGesture {
                                        selectedObject = object
                                        showingDetail = true
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Gescannte Objekte")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        Logger.ui.info("+ Button tapped - opening DocumentPicker")
                        debugLog("+ Button tapped - opening DocumentPicker", category: "UI")
                        showingDocumentPicker = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            .sheet(isPresented: $showingDetail) {
                if let object = selectedObject {
                    ObjectDetailView(object: object)
                }
            }
            .sheet(isPresented: $showingDocumentPicker) {
                DocumentPickerView { urls in
                    handleImportedFiles(urls)
                }
            }
        }
    }

    // MARK: - Import Handler

    private func handleImportedFiles(_ urls: [URL]) {
        Logger.fileImport.info("handleImportedFiles called with \(urls.count) files")
        debugLog("📥 handleImportedFiles called with \(urls.count) files", category: "FileImport")

        guard !urls.isEmpty else {
            Logger.fileImport.warning("No files selected")
            debugLog("⚠️ No files selected", category: "FileImport", type: .error)
            return
        }

        for url in urls {
            Logger.fileImport.info("Processing: \(url.lastPathComponent)")
            debugLog("📁 Processing: \(url.lastPathComponent)", category: "FileImport")
            debugLog("   Full URL: \(url.absoluteString)", category: "FileImport")
            debugLog("   Path: \(url.path)", category: "FileImport")
            debugLog("   File exists: \(FileManager.default.fileExists(atPath: url.path))", category: "FileImport")

            // Import the USDZ file
            manager.importUsdzFile(from: url)
        }

        Logger.fileImport.info("All files sent to importUsdzFile")
        debugLog("✅ All files sent to importUsdzFile", category: "FileImport")
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Noch keine Scans")
                .font(.title2.bold())
                .foregroundColor(.white)

            Text("Scanne dein erstes Objekt,\num es hier zu sehen!")
                .font(.body)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            Button(action: { dismiss() }) {
                HStack {
                    Image(systemName: "viewfinder.circle.fill")
                    Text("Scan starten")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }
            .padding(.top)
        }
        .padding()
    }
}

// MARK: - Object Card View

struct ObjectCardView: View {
    let object: ScannedObject

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 3D Icon placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 140)

                Image(systemName: "cube.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.white.opacity(0.8))
            }

            // Object info
            VStack(alignment: .leading, spacing: 4) {
                Text(object.name)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(object.formattedTimestamp)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))

                Divider()
                    .background(Color.white.opacity(0.2))

                if object.volume > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "ruler")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text(object.dimensionsString)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "cube")
                            .font(.caption)
                            .foregroundColor(.purple)
                        Text(object.volumeString)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.doc")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("Importiert")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Object Detail View

struct ObjectDetailView: View {
    let object: ScannedObject
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager = ScannedObjectsManager.shared

    @State private var showingQuickLook = false
    @State private var showingDeleteAlert = false
    @State private var showMaterialInput = false
    @State private var materialDensity: String = ""
    @State private var selectedDensity: Double?

    // Calculated weight based on volume and density
    private var calculatedWeight: Double? {
        guard object.volume > 0,
              let density = selectedDensity else {
            return nil
        }
        return object.volume * density
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    colors: [
                        Color(red: 0.1, green: 0.1, blue: 0.15),
                        Color(red: 0.15, green: 0.1, blue: 0.2)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // 3D Preview
                        preview3DSection

                        // Measurements Section
                        measurementsSection

                        // Metadata Section
                        metadataSection

                        // Actions
                        actionsSection
                    }
                    .padding()
                }
            }
            .navigationTitle(object.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Text("Fertig")
                            .foregroundColor(.blue)
                    }
                }
            }
            .alert("Objekt löschen?", isPresented: $showingDeleteAlert) {
                Button("Abbrechen", role: .cancel) {}
                Button("Löschen", role: .destructive) {
                    manager.deleteObject(object)
                    dismiss()
                }
            } message: {
                Text("Möchtest du \"\(object.name)\" wirklich löschen? Diese Aktion kann nicht rückgängig gemacht werden.")
            }
            .sheet(isPresented: $showingQuickLook) {
                QuickLookView(url: manager.getUsdzURL(for: object))
            }
        }
    }

    // MARK: - 3D Preview Section

    private var preview3DSection: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.2), .purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 250)

                VStack(spacing: 12) {
                    Image(systemName: "cube.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.white.opacity(0.8))

                    Button(action: { showingQuickLook = true }) {
                        HStack {
                            Image(systemName: "arkit")
                            Text("3D Vorschau öffnen")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                }
            }
        }
    }

    // MARK: - Measurements Section

    private var measurementsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "ruler.fill")
                    .foregroundColor(.blue)
                Text("Präzise Messungen")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            if object.volume > 0 {
                VStack(spacing: 12) {
                    MeasurementRow(
                        icon: "arrow.left.and.right",
                        label: "Breite (X-Achse)",
                        value: String(format: "%.1f cm", object.width),
                        color: .red
                    )

                    MeasurementRow(
                        icon: "arrow.up.and.down",
                        label: "Höhe (Y-Achse)",
                        value: String(format: "%.1f cm", object.height),
                        color: .green
                    )

                    MeasurementRow(
                        icon: "arrow.forward.to.line",
                        label: "Tiefe (Z-Achse)",
                        value: String(format: "%.1f cm", object.depth),
                        color: .blue
                    )

                    Divider()
                        .background(Color.white.opacity(0.3))

                    MeasurementRow(
                        icon: "cube.fill",
                        label: "Volumen",
                        value: String(format: "%.1f cm³", object.volume),
                        color: .purple
                    )

                    if object.volume >= 1000 {
                        MeasurementRow(
                            icon: "drop.fill",
                            label: "Volumen (Liter)",
                            value: String(format: "%.2f L", object.volume / 1000.0),
                            color: .cyan
                        )
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )

                // Material Selection Button
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
                                    .foregroundColor(.white.opacity(0.6))
                            } else {
                                Text("Materialdichte eingeben für Gewichtsberechnung")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.orange.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .foregroundColor(.orange)
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

                // Weight Display (if density selected)
                if let weight = calculatedWeight {
                    VStack(spacing: 12) {
                        MeasurementRow(
                            icon: "scalemass.fill",
                            label: "Gewicht",
                            value: formatWeight(weight),
                            color: .orange
                        )

                        if let density = selectedDensity {
                            HStack {
                                Spacer()
                                Text("bei \(String(format: "%.2f", density).replacingOccurrences(of: ".", with: ",")) g/cm³")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.orange.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
            } else {
                // Imported file - no measurements available
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.orange)
                        Text("Keine Messungen verfügbar")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.8))
                    }

                    Text("Diese Datei wurde importiert und enthält keine Messdaten. Scanne das Objekt erneut, um Messungen zu erhalten.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.leading)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.orange.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.orange)
                Text("Details")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            VStack(spacing: 12) {
                MetadataRow(label: "Gescannt am", value: object.formattedTimestamp)

                if let scaleFactor = object.scaleFactor {
                    MetadataRow(
                        label: "Kalibrierungsfaktor",
                        value: String(format: "%.4f", scaleFactor)
                    )
                }

                MetadataRow(
                    label: "Mesh-Qualität",
                    value: String(format: "%.0f%%", object.meshQuality * 100)
                )

                MetadataRow(label: "Dateiformat", value: "USDZ")
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Helper Functions

    private func formatWeight(_ weight: Double) -> String {
        if weight < 1000 {
            return String(format: "%.1f g", weight)
        } else {
            return String(format: "%.2f kg", weight / 1000)
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button(action: { showingDeleteAlert = true }) {
                HStack {
                    Image(systemName: "trash.fill")
                    Text("Objekt löschen")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .cornerRadius(12)
            }
        }
        .padding(.top)
    }
}

// MARK: - Measurement Row

struct MeasurementRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 30)

            Text(label)
                .font(.body)
                .foregroundColor(.white.opacity(0.8))

            Spacer()

            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundColor(.white)
        }
    }
}

// MARK: - Metadata Row

struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundColor(.white.opacity(0.7))

            Spacer()

            Text(value)
                .font(.body)
                .foregroundColor(.white)
        }
    }
}

// MARK: - QuickLook View

struct QuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            return 1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return url as QLPreviewItem
        }
    }
}

// MARK: - Document Picker

struct DocumentPickerView: UIViewControllerRepresentable {
    let onFilesSelected: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.usdz], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFilesSelected: onFilesSelected)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFilesSelected: ([URL]) -> Void

        init(onFilesSelected: @escaping ([URL]) -> Void) {
            self.onFilesSelected = onFilesSelected
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            Logger.documentPicker.info("DocumentPicker didPickDocumentsAt called with \(urls.count) URLs")
            debugLog("📄 DocumentPicker didPickDocumentsAt called", category: "DocumentPicker")
            debugLog("   URLs count: \(urls.count)", category: "DocumentPicker")

            for (index, url) in urls.enumerated() {
                debugLog("   [\(index)] \(url.lastPathComponent)", category: "DocumentPicker")
                debugLog("       Path: \(url.path)", category: "DocumentPicker")
                debugLog("       Exists: \(FileManager.default.fileExists(atPath: url.path))", category: "DocumentPicker")
                debugLog("       Is security scoped: \(url.startAccessingSecurityScopedResource())", category: "DocumentPicker")
                url.stopAccessingSecurityScopedResource()
            }

            onFilesSelected(urls)
            debugLog("✅ DocumentPicker callback completed", category: "DocumentPicker")
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            Logger.documentPicker.info("DocumentPicker was cancelled by user")
            debugLog("❌ DocumentPicker cancelled by user", category: "DocumentPicker")
        }
    }
}

// MARK: - UTType Extension

extension UTType {
    static var usdz: UTType {
        UTType(filenameExtension: "usdz")!
    }
}

// MARK: - Preview

#Preview {
    ScannedObjectsGalleryView()
}
