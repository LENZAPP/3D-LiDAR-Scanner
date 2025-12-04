//
//  ScannedObject.swift
//  3D
//
//  Data model for saved 3D scans with measurements
//

import Foundation
import SwiftUI
import ModelIO
import os.log

// MARK: - Scanned Object Model

struct ScannedObject: Identifiable, Codable {
    let id: UUID
    let name: String
    let timestamp: Date
    let usdzFileName: String  // Stored in Documents/Scans/
    let thumbnailFileName: String?  // PNG thumbnail

    // Calibrated Measurements
    let width: Double   // cm
    let height: Double  // cm
    let depth: Double   // cm
    let volume: Double  // cm³

    // Additional metadata
    let scaleFactor: Float?
    let meshQuality: Double  // 0.0 - 1.0

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    var dimensionsString: String {
        return String(format: "%.1f × %.1f × %.1f cm", width, height, depth)
    }

    var volumeString: String {
        return String(format: "%.1f cm³", volume)
    }
}

// MARK: - Scanned Objects Manager

class ScannedObjectsManager: ObservableObject {
    static let shared = ScannedObjectsManager()

    @Published var objects: [ScannedObject] = []

    private let scansDirectory: URL
    private let metadataFileName = "objects.json"

    init() {
        // Setup scans directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.scansDirectory = documentsPath.appendingPathComponent("Scans", isDirectory: true)

        print("📂 Scans directory: \(scansDirectory.path)")

        // Create directory if needed
        try? FileManager.default.createDirectory(at: scansDirectory, withIntermediateDirectories: true)

        // Load existing objects
        loadObjects()

        // DEBUG: Add test object if no objects exist
        #if DEBUG
        if objects.isEmpty {
            print("🧪 DEBUG: Adding test object for UI verification")
            let testObject = ScannedObject(
                id: UUID(),
                name: "TEST Objekt (sollte sichtbar sein)",
                timestamp: Date(),
                usdzFileName: "test.usdz",
                thumbnailFileName: nil,
                width: 12.3,
                height: 4.5,
                depth: 6.7,
                volume: 123.4,
                scaleFactor: 1.0,
                meshQuality: 0.95
            )
            objects.append(testObject)
            print("   Test object added. Total objects: \(objects.count)")
        }
        #endif
    }

    // MARK: - Save New Scan

    func saveScannedObject(
        name: String,
        usdzURL: URL,
        width: Double,
        height: Double,
        depth: Double,
        volume: Double,
        meshQuality: Double,
        scaleFactor: Float?
    ) -> ScannedObject? {

        let id = UUID()
        let timestamp = Date()

        // Generate unique filenames
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateString = formatter.string(from: timestamp)

        let usdzFileName = "\(dateString)_\(id.uuidString.prefix(8)).usdz"
        let thumbnailFileName = "\(dateString)_\(id.uuidString.prefix(8)).png"

        // Copy USDZ to scans directory
        let destinationURL = scansDirectory.appendingPathComponent(usdzFileName)
        do {
            try FileManager.default.copyItem(at: usdzURL, to: destinationURL)
        } catch {
            print("❌ Failed to copy USDZ: \(error)")
            return nil
        }

        // Generate thumbnail (optional)
        generateThumbnail(for: usdzURL, saveTo: scansDirectory.appendingPathComponent(thumbnailFileName))

        // Create object
        let object = ScannedObject(
            id: id,
            name: name,
            timestamp: timestamp,
            usdzFileName: usdzFileName,
            thumbnailFileName: thumbnailFileName,
            width: width,
            height: height,
            depth: depth,
            volume: volume,
            scaleFactor: scaleFactor,
            meshQuality: meshQuality
        )

        // Add to list
        objects.append(object)
        objects.sort { $0.timestamp > $1.timestamp }  // Newest first

        // Save metadata
        saveObjects()

        print("✅ Saved scanned object: \(name)")
        print("   Dimensions: \(object.dimensionsString)")
        print("   Volume: \(object.volumeString)")

        return object
    }

    // MARK: - Import USDZ File

    func importUsdzFile(from sourceURL: URL) {
        Logger.objectsManager.info("========================================")
        Logger.objectsManager.info("importUsdzFile CALLED!")
        debugLog("========================================", category: "ObjectsManager")
        debugLog("📥 importUsdzFile CALLED!", category: "ObjectsManager")
        debugLog("   File: \(sourceURL.lastPathComponent)", category: "ObjectsManager")
        debugLog("   Full path: \(sourceURL.path)", category: "ObjectsManager")
        debugLog("   Current objects count: \(objects.count)", category: "ObjectsManager")
        debugLog("   File exists at path: \(FileManager.default.fileExists(atPath: sourceURL.path))", category: "ObjectsManager")
        debugLog("========================================", category: "ObjectsManager")

        // Check if file exists first
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            Logger.objectsManager.error("File does not exist at path: \(sourceURL.path)")
            debugLog("❌ CRITICAL ERROR: File does not exist!", category: "ObjectsManager", type: .error)
            debugLog("   Path: \(sourceURL.path)", category: "ObjectsManager", type: .error)
            return
        }

        // Start accessing the security-scoped resource
        // NOTE: When using DocumentPicker with asCopy:true, the file is already copied
        // to a temporary location, but we still need to access it
        let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
        debugLog("Security-scoped access: \(didStartAccess ? "SUCCESS" : "FAILED (might be temporary copy)")", category: "ObjectsManager")

        defer {
            if didStartAccess {
                debugLog("🔓 Releasing security-scoped resource", category: "ObjectsManager")
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        // Generate object name from filename or use timestamp
        let fileName = sourceURL.deletingPathExtension().lastPathComponent
        let timestamp = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        let objectName = fileName.isEmpty ? "Import \(formatter.string(from: timestamp))" : fileName

        let id = UUID()

        // Generate unique filename
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateString = dateFormatter.string(from: timestamp)
        let usdzFileName = "\(dateString)_\(id.uuidString.prefix(8)).usdz"

        // Copy USDZ to scans directory
        let destinationURL = scansDirectory.appendingPathComponent(usdzFileName)
        debugLog("📋 Attempting to copy file...", category: "ObjectsManager")
        debugLog("   From: \(sourceURL.path)", category: "ObjectsManager")
        debugLog("   To: \(destinationURL.path)", category: "ObjectsManager")

        do {
            // Check if destination already exists and remove it
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                debugLog("⚠️ Destination file already exists, removing...", category: "ObjectsManager")
                try FileManager.default.removeItem(at: destinationURL)
            }

            // Copy the file
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            Logger.objectsManager.info("Copied USDZ file: \(usdzFileName)")
            debugLog("✅ Copied USDZ file: \(usdzFileName)", category: "ObjectsManager")
            debugLog("   Destination exists: \(FileManager.default.fileExists(atPath: destinationURL.path))", category: "ObjectsManager")
        } catch {
            Logger.objectsManager.error("Failed to copy USDZ: \(error.localizedDescription)")
            debugLog("❌ Failed to copy USDZ: \(error)", category: "ObjectsManager", type: .error)
            debugLog("   Error details: \(error.localizedDescription)", category: "ObjectsManager", type: .error)
            return
        }

        // FIRST: Create placeholder object immediately and add to gallery
        let placeholderObject = ScannedObject(
            id: id,
            name: objectName,
            timestamp: timestamp,
            usdzFileName: usdzFileName,
            thumbnailFileName: nil,
            width: 0.0,
            height: 0.0,
            depth: 0.0,
            volume: 0.0,
            scaleFactor: nil,
            meshQuality: 0.0
        )

        // Add immediately to gallery (this triggers UI update)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                debugLog("❌ Self is nil!", category: "ObjectsManager", type: .error)
                return
            }

            Logger.objectsManager.info("Adding to objects array (current count: \(self.objects.count))")
            debugLog("📝 Adding to objects array (current count: \(self.objects.count))", category: "ObjectsManager")
            self.objects.append(placeholderObject)
            self.objects.sort { $0.timestamp > $1.timestamp }

            // Force UI update
            self.objectWillChange.send()

            self.saveObjects()
            Logger.objectsManager.info("Added placeholder to gallery: \(objectName)")
            debugLog("✅ Added placeholder to gallery: \(objectName)", category: "ObjectsManager")
            debugLog("   Total objects now: \(self.objects.count)", category: "ObjectsManager")
        }

        // THEN: Analyze in background and update
        Task { @MainActor in
            let analyzer = MeshAnalyzer()

            // Load calibration factor
            let scaleFactorValue = SimpleCalibrationManager.loadScaleFactor()
            if let scaleFactor = scaleFactorValue {
                analyzer.setCalibration(realWorldSize: 1.0, measuredSize: 1.0 / scaleFactor)
            }

            do {
                Logger.objectsManager.info("Analyzing mesh...")
                debugLog("📊 Analyzing mesh from: \(destinationURL.path)", category: "ObjectsManager")
                try await analyzer.analyzeMesh(from: destinationURL)

                let width = analyzer.dimensions?.width ?? 0.0
                let height = analyzer.dimensions?.height ?? 0.0
                let depth = analyzer.dimensions?.depth ?? 0.0
                let volume = analyzer.volume ?? 0.0
                let quality = analyzer.meshQuality?.confidence ?? 0.0

                // Update object with measurements
                let updatedObject = ScannedObject(
                    id: id,
                    name: objectName,
                    timestamp: timestamp,
                    usdzFileName: usdzFileName,
                    thumbnailFileName: nil,
                    width: width,
                    height: height,
                    depth: depth,
                    volume: volume,
                    scaleFactor: scaleFactorValue,
                    meshQuality: quality
                )

                // Replace placeholder with measured object
                if let index = self.objects.firstIndex(where: { $0.id == id }) {
                    self.objects[index] = updatedObject

                    // Force UI update
                    self.objectWillChange.send()

                    self.saveObjects()
                    Logger.objectsManager.info("Updated with measurements: \(objectName)")
                    debugLog("✅ Updated with measurements: \(objectName)", category: "ObjectsManager")
                    debugLog("   Dimensions: \(String(format: "%.1f × %.1f × %.1f cm", width, height, depth))", category: "ObjectsManager")
                    debugLog("   Volume: \(String(format: "%.1f cm³", volume))", category: "ObjectsManager")
                } else {
                    Logger.objectsManager.warning("Could not find object with id \(id.uuidString) to update")
                    debugLog("⚠️ Could not find object with id \(id) to update", category: "ObjectsManager", type: .error)
                }
            } catch {
                Logger.objectsManager.error("Failed to analyze imported mesh: \(error.localizedDescription)")
                debugLog("⚠️ Failed to analyze imported mesh: \(error)", category: "ObjectsManager", type: .error)
                debugLog("   Object remains in gallery without measurements", category: "ObjectsManager")
            }
        }
    }

    // MARK: - Delete Object

    func deleteObject(_ object: ScannedObject) {
        // Remove files
        let usdzURL = scansDirectory.appendingPathComponent(object.usdzFileName)
        try? FileManager.default.removeItem(at: usdzURL)

        if let thumbnail = object.thumbnailFileName {
            let thumbnailURL = scansDirectory.appendingPathComponent(thumbnail)
            try? FileManager.default.removeItem(at: thumbnailURL)
        }

        // Remove from list
        objects.removeAll { $0.id == object.id }

        // Save metadata
        saveObjects()

        print("🗑️ Deleted object: \(object.name)")
    }

    // MARK: - Get File URLs

    func getUsdzURL(for object: ScannedObject) -> URL {
        return scansDirectory.appendingPathComponent(object.usdzFileName)
    }

    func getThumbnailURL(for object: ScannedObject) -> URL? {
        guard let thumbnail = object.thumbnailFileName else { return nil }
        return scansDirectory.appendingPathComponent(thumbnail)
    }

    // MARK: - Persistence

    private func saveObjects() {
        let metadataURL = scansDirectory.appendingPathComponent(metadataFileName)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(objects)
            try data.write(to: metadataURL)
        } catch {
            print("❌ Failed to save objects metadata: \(error)")
        }
    }

    private func loadObjects() {
        let metadataURL = scansDirectory.appendingPathComponent(metadataFileName)

        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            print("ℹ️ No saved objects found")
            return
        }

        do {
            let data = try Data(contentsOf: metadataURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            objects = try decoder.decode([ScannedObject].self, from: data)
            objects.sort { $0.timestamp > $1.timestamp }
            print("✅ Loaded \(objects.count) saved objects")
        } catch {
            print("❌ Failed to load objects metadata: \(error)")
        }
    }

    // MARK: - Thumbnail Generation

    private func generateThumbnail(for usdzURL: URL, saveTo thumbnailURL: URL) {
        // TODO: Generate actual 3D preview thumbnail
        // For now, skip - will use 3D icon placeholder
        print("ℹ️ Thumbnail generation not yet implemented")
    }
}

// Note: Using existing Dimensions, Volume, and CalibratedMeasurements from CalibratedMeasurements.swift
