//
//  ScanResultsView.swift
//  3D
//
//  View for displaying scan results and accuracy metrics
//

import SwiftUI

struct ScanResultsView: View {

    @StateObject private var database = ScanDatabaseManager.shared
    @State private var recentScans: [ScanResult] = []
    @State private var statistics: OverallStatistics?
    @State private var groundTruthObjects: [GroundTruthObject] = []

    @State private var showingAddObject = false
    @State private var showingExport = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationView {
            List {
                // Statistics Section
                Section {
                    if let stats = statistics {
                        StatisticsCard(statistics: stats)
                    } else {
                        Text("Loading statistics...")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Label("Overall Performance", systemImage: "chart.bar.fill")
                }

                // Ground Truth Objects
                Section {
                    if groundTruthObjects.isEmpty {
                        Text("No ground truth objects added yet")
                            .foregroundColor(.secondary)

                        Button {
                            showingAddObject = true
                        } label: {
                            Label("Add Ground Truth Object", systemImage: "plus.circle.fill")
                        }
                    } else {
                        ForEach(groundTruthObjects, id: \.id) { object in
                            GroundTruthObjectRow(object: object)
                        }

                        Button {
                            showingAddObject = true
                        } label: {
                            Label("Add More", systemImage: "plus")
                        }
                    }
                } header: {
                    Label("Ground Truth Objects", systemImage: "cube.box.fill")
                }

                // Recent Scans
                Section {
                    if recentScans.isEmpty {
                        Text("No scans recorded yet")
                            .foregroundColor(.secondary)
                        Text("Scan an object to see results here")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(recentScans, id: \.id) { scan in
                            ScanResultRow(scan: scan)
                        }
                    }
                } header: {
                    Label("Recent Scans (\(database.totalScans))", systemImage: "clock.fill")
                }

                // Actions
                Section {
                    Button {
                        Task {
                            exportURL = await database.exportToCSV()
                            showingExport = true
                        }
                    } label: {
                        Label("Export to CSV", systemImage: "square.and.arrow.up")
                    }

                    NavigationLink {
                        DetailedStatisticsView()
                    } label: {
                        Label("Detailed Analytics", systemImage: "chart.line.uptrend.xyaxis")
                    }
                } header: {
                    Text("Actions")
                }
            }
            .navigationTitle("Scan Results Database")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingAddObject) {
                AddGroundTruthObjectView()
            }
            .alert("Export Complete", isPresented: $showingExport) {
                if let url = exportURL {
                    Button("Share") {
                        shareCSV(url)
                    }
                }
                Button("OK", role: .cancel) { }
            } message: {
                if let url = exportURL {
                    Text("Exported to:\n\(url.lastPathComponent)")
                }
            }
            .task {
                await loadData()
            }
            .refreshable {
                await loadData()
            }
        }
    }

    private func loadData() async {
        recentScans = await database.getRecentScans(limit: 20)
        statistics = await database.getOverallStatistics()
        groundTruthObjects = await database.getAllGroundTruthObjects()
    }

    private func shareCSV(_ url: URL) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Statistics Card

struct StatisticsCard: View {
    let statistics: OverallStatistics

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                StatItem(
                    title: "Total Scans",
                    value: "\(statistics.totalScans)",
                    icon: "camera.fill",
                    color: .blue
                )

                Divider()

                StatItem(
                    title: "Avg Accuracy",
                    value: String(format: "%.1f%%", 100 - statistics.avgVolumeError),
                    icon: "target",
                    color: .green
                )
            }
            .frame(height: 60)

            Divider()

            HStack {
                StatItem(
                    title: "Avg Duration",
                    value: String(format: "%.1fs", statistics.avgDuration),
                    icon: "timer",
                    color: .orange
                )

                Divider()

                StatItem(
                    title: "Confidence",
                    value: String(format: "%.0f%%", statistics.avgConfidence * 100),
                    icon: "checkmark.seal.fill",
                    color: .purple
                )
            }
            .frame(height: 60)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct StatItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(value)
                .font(.headline)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Ground Truth Object Row

struct GroundTruthObjectRow: View {
    let object: GroundTruthObject

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(object.name)
                .font(.headline)

            HStack {
                Label("\(object.category)", systemImage: "tag")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Label(object.material, systemImage: "cube")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Volume")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f cm³", object.trueVolume))
                        .font(.caption)
                        .fontWeight(.medium)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text("Weight")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f g", object.trueWeight))
                        .font(.caption)
                        .fontWeight(.medium)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text("Density")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2f g/cm³", object.trueDensity))
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Scan Result Row

struct ScanResultRow: View {
    let scan: ScanResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(scan.scanDate, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if scan.usedAI {
                    Image(systemName: "brain")
                        .font(.caption)
                        .foregroundColor(.purple)
                }

                if scan.usedPCN {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundColor(.blue)
                }

                if scan.usedMeshRepair {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            HStack(spacing: 16) {
                MeasurementBadge(
                    title: "Volume",
                    value: String(format: "%.1f cm³", scan.volume),
                    icon: "cube"
                )

                MeasurementBadge(
                    title: "Weight",
                    value: String(format: "%.1f g", scan.weight),
                    icon: "scalemass"
                )

                MeasurementBadge(
                    title: "Confidence",
                    value: String(format: "%.0f%%", scan.confidenceScore * 100),
                    icon: "checkmark.circle"
                )
            }

            if let notes = scan.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct MeasurementBadge: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: icon)
                .font(.caption2)
                .foregroundColor(.secondary)

            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Add Ground Truth Object View

struct AddGroundTruthObjectView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var database = ScanDatabaseManager.shared

    @State private var name = ""
    @State private var category = "Other"
    @State private var material = "Plastic"

    @State private var volume = ""
    @State private var weight = ""
    @State private var density = ""

    @State private var length = ""
    @State private var width = ""
    @State private var height = ""

    @State private var description = ""
    @State private var notes = ""

    let categories = ["Food", "Beverage", "Electronics", "Toy", "Container", "Household", "Tool", "Sports", "Other"]
    let materials = ["Aluminum", "Plastic", "Wood", "Glass", "Ceramic", "Rubber", "Paper", "Metal", "Stone", "Organic"]

    var body: some View {
        NavigationView {
            Form {
                Section("Basic Info") {
                    TextField("Name", text: $name)
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                    Picker("Material", selection: $material) {
                        ForEach(materials, id: \.self) { mat in
                            Text(mat).tag(mat)
                        }
                    }
                }

                Section("Ground Truth Measurements") {
                    TextField("Volume (cm³)", text: $volume)
                        .keyboardType(.decimalPad)

                    TextField("Weight (g)", text: $weight)
                        .keyboardType(.decimalPad)

                    TextField("Density (g/cm³)", text: $density)
                        .keyboardType(.decimalPad)
                }

                Section("Dimensions (Optional)") {
                    TextField("Length (cm)", text: $length)
                        .keyboardType(.decimalPad)

                    TextField("Width (cm)", text: $width)
                        .keyboardType(.decimalPad)

                    TextField("Height (cm)", text: $height)
                        .keyboardType(.decimalPad)
                }

                Section("Additional Info") {
                    TextField("Description", text: $description)
                    TextField("Notes", text: $notes)
                }
            }
            .navigationTitle("Add Ground Truth Object")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveObject()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        !name.isEmpty &&
        !volume.isEmpty &&
        !weight.isEmpty &&
        !density.isEmpty &&
        Double(volume) != nil &&
        Double(weight) != nil &&
        Double(density) != nil
    }

    private func saveObject() {
        let object = GroundTruthObject(
            id: nil,
            name: name,
            category: category,
            material: material,
            trueVolume: Double(volume) ?? 0,
            trueWeight: Double(weight) ?? 0,
            trueDensity: Double(density) ?? 0,
            length: Double(length),
            width: Double(width),
            height: Double(height),
            description: description.isEmpty ? nil : description,
            notes: notes.isEmpty ? nil : notes
        )

        Task {
            if let _ = await database.addGroundTruthObject(object) {
                dismiss()
            }
        }
    }
}

// MARK: - Detailed Statistics View

struct DetailedStatisticsView: View {
    @StateObject private var database = ScanDatabaseManager.shared
    @State private var statistics: OverallStatistics?

    var body: some View {
        List {
            if let stats = statistics {
                Section("Overall Performance") {
                    LabeledContent("Total Scans", value: "\(stats.totalScans)")
                    LabeledContent("Unique Objects", value: "\(stats.uniqueObjects)")
                }

                Section("Accuracy") {
                    LabeledContent("Volume Error", value: String(format: "%.2f%%", stats.avgVolumeError))
                    LabeledContent("Weight Error", value: String(format: "%.2f%%", stats.avgWeightError))
                    LabeledContent("Overall Accuracy", value: String(format: "%.1f%%", 100 - stats.avgVolumeError))
                }

                Section("Quality Metrics") {
                    LabeledContent("Confidence Score", value: String(format: "%.0f%%", stats.avgConfidence * 100))
                    LabeledContent("Avg Scan Duration", value: String(format: "%.1f seconds", stats.avgDuration))
                }
            }
        }
        .navigationTitle("Detailed Analytics")
        .task {
            statistics = await database.getOverallStatistics()
        }
    }
}

#Preview {
    ScanResultsView()
}
