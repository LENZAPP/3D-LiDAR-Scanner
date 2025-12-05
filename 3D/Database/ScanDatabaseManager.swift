//
//  ScanDatabaseManager.swift
//  3D
//
//  SQLite Database Manager for Scan Results
//  Stores measurements, ground truth, and accuracy metrics
//

import Foundation
import SQLite3

/// Manages SQLite database for scan results and ground truth data
@MainActor
class ScanDatabaseManager: ObservableObject {

    // MARK: - Singleton

    static let shared = ScanDatabaseManager()

    // MARK: - Published Properties

    @Published var isInitialized = false
    @Published var totalScans: Int = 0
    @Published var averageAccuracy: Double = 0.0

    // MARK: - Database Connection

    private var db: OpaquePointer?
    private let dbPath: String

    // MARK: - Initialization

    private init() {
        // Database location: Documents/3ddata.db
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dbPath = documentsPath.appendingPathComponent("3ddata.db").path

        print("📊 Scan Database Manager initialized")
        print("   Path: \(dbPath)")

        Task {
            await initializeDatabase()
        }
    }

    deinit {
        if sqlite3_close(db) == SQLITE_OK {
            print("📊 Database closed")
        }
    }

    // MARK: - Database Initialization

    /// Initialize database and create tables
    func initializeDatabase() async {
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            print("❌ Failed to open database")
            return
        }

        print("📦 Opening database...")

        // Load schema from file
        if let schemaPath = Bundle.main.path(forResource: "database_schema", ofType: "sql"),
           let schema = try? String(contentsOfFile: schemaPath) {
            // Execute schema
            await executeSQL(schema)
        } else {
            // Create schema directly
            await createTables()
        }

        isInitialized = true
        await updateStatistics()

        print("✅ Database initialized")
    }

    /// Create database tables
    private func createTables() async {
        let schema = """
        PRAGMA foreign_keys = ON;

        CREATE TABLE IF NOT EXISTS objects (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            category TEXT NOT NULL,
            material TEXT NOT NULL,
            true_volume_cm3 REAL NOT NULL,
            true_weight_g REAL NOT NULL,
            true_density_g_cm3 REAL NOT NULL,
            true_length_cm REAL,
            true_width_cm REAL,
            true_height_cm REAL,
            description TEXT,
            notes TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            CHECK (true_volume_cm3 > 0),
            CHECK (true_weight_g > 0)
        );

        CREATE TABLE IF NOT EXISTS scans (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            object_id INTEGER,
            scan_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            scan_duration_seconds REAL,
            device_model TEXT DEFAULT 'iPhone 15 Pro',
            measured_volume_cm3 REAL NOT NULL,
            measured_weight_g REAL NOT NULL,
            measured_density_g_cm3 REAL NOT NULL,
            point_count INTEGER,
            mesh_vertex_count INTEGER,
            confidence_score REAL DEFAULT 0.0,
            mesh_quality_score REAL DEFAULT 0.0,
            used_pcn_completion BOOLEAN DEFAULT 0,
            used_mesh_repair BOOLEAN DEFAULT 0,
            used_ai_detection BOOLEAN DEFAULT 0,
            calibration_method TEXT,
            scale_factor REAL DEFAULT 1.0,
            notes TEXT,
            FOREIGN KEY (object_id) REFERENCES objects(id),
            CHECK (measured_volume_cm3 > 0),
            CHECK (measured_weight_g > 0)
        );

        CREATE INDEX IF NOT EXISTS idx_scans_object_id ON scans(object_id);
        CREATE INDEX IF NOT EXISTS idx_scans_date ON scans(scan_date);
        """

        await executeSQL(schema)
    }

    // MARK: - Execute SQL

    @discardableResult
    private func executeSQL(_ sql: String) async -> Bool {
        var error: UnsafeMutablePointer<CChar>?

        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            if let error = error {
                let errorMessage = String(cString: error)
                print("❌ SQL Error: \(errorMessage)")
                sqlite3_free(error)
            }
            return false
        }

        return true
    }

    // MARK: - Insert Scan Result

    /// Save scan result to database
    func saveScanResult(_ result: ScanResult) async -> Int64? {
        let sql = """
        INSERT INTO scans (
            object_id, scan_duration_seconds, device_model,
            measured_volume_cm3, measured_weight_g, measured_density_g_cm3,
            point_count, mesh_vertex_count,
            confidence_score, mesh_quality_score,
            used_pcn_completion, used_mesh_repair, used_ai_detection,
            calibration_method, scale_factor, notes
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            print("❌ Failed to prepare statement")
            return nil
        }

        defer { sqlite3_finalize(statement) }

        // Bind parameters
        sqlite3_bind_int(statement, 1, Int32(result.objectId ?? 0))
        sqlite3_bind_double(statement, 2, result.scanDuration)
        sqlite3_bind_text(statement, 3, (result.deviceModel as NSString).utf8String, -1, nil)
        sqlite3_bind_double(statement, 4, result.volume)
        sqlite3_bind_double(statement, 5, result.weight)
        sqlite3_bind_double(statement, 6, result.density)
        sqlite3_bind_int(statement, 7, Int32(result.pointCount))
        sqlite3_bind_int(statement, 8, Int32(result.meshVertexCount))
        sqlite3_bind_double(statement, 9, Double(result.confidenceScore))
        sqlite3_bind_double(statement, 10, Double(result.meshQualityScore))
        sqlite3_bind_int(statement, 11, result.usedPCN ? 1 : 0)
        sqlite3_bind_int(statement, 12, result.usedMeshRepair ? 1 : 0)
        sqlite3_bind_int(statement, 13, result.usedAI ? 1 : 0)
        sqlite3_bind_text(statement, 14, (result.calibrationMethod as NSString).utf8String, -1, nil)
        sqlite3_bind_double(statement, 15, Double(result.scaleFactor))
        let notesText = (result.notes ?? "") as NSString
        sqlite3_bind_text(statement, 16, notesText.utf8String, -1, nil)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            print("❌ Failed to insert scan result")
            return nil
        }

        let scanId = sqlite3_last_insert_rowid(db)
        print("✅ Scan saved to database (ID: \(scanId))")

        await updateStatistics()

        return scanId
    }

    // MARK: - Query Results

    /// Get all scans for an object
    func getScans(forObjectId objectId: Int) async -> [ScanResult] {
        let sql = """
        SELECT id, object_id, scan_date, scan_duration_seconds,
               measured_volume_cm3, measured_weight_g, measured_density_g_cm3,
               point_count, mesh_vertex_count, confidence_score, mesh_quality_score,
               used_pcn_completion, used_mesh_repair, used_ai_detection,
               calibration_method, scale_factor, notes
        FROM scans
        WHERE object_id = ?
        ORDER BY scan_date DESC
        """

        return await executeQuery(sql, parameters: [objectId])
    }

    /// Get recent scans
    func getRecentScans(limit: Int = 10) async -> [ScanResult] {
        let sql = """
        SELECT id, object_id, scan_date, scan_duration_seconds,
               measured_volume_cm3, measured_weight_g, measured_density_g_cm3,
               point_count, mesh_vertex_count, confidence_score, mesh_quality_score,
               used_pcn_completion, used_mesh_repair, used_ai_detection,
               calibration_method, scale_factor, notes
        FROM scans
        ORDER BY scan_date DESC
        LIMIT ?
        """

        return await executeQuery(sql, parameters: [limit])
    }

    /// Get scan accuracy (with ground truth comparison)
    func getScanAccuracy(scanId: Int64) async -> ScanAccuracy? {
        let sql = """
        SELECT
            s.id, s.scan_date,
            o.name, o.category, o.material,
            o.true_volume_cm3, o.true_weight_g, o.true_density_g_cm3,
            s.measured_volume_cm3, s.measured_weight_g, s.measured_density_g_cm3,
            s.confidence_score, s.point_count
        FROM scans s
        LEFT JOIN objects o ON s.object_id = o.id
        WHERE s.id = ?
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }

        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, scanId)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        return parseScanAccuracy(from: statement)
    }

    // MARK: - Ground Truth Objects

    /// Add ground truth object
    func addGroundTruthObject(_ object: GroundTruthObject) async -> Int64? {
        let sql = """
        INSERT INTO objects (
            name, category, material,
            true_volume_cm3, true_weight_g, true_density_g_cm3,
            true_length_cm, true_width_cm, true_height_cm,
            description, notes
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            print("❌ Failed to prepare statement")
            return nil
        }

        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (object.name as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (object.category as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (object.material as NSString).utf8String, -1, nil)
        sqlite3_bind_double(statement, 4, object.trueVolume)
        sqlite3_bind_double(statement, 5, object.trueWeight)
        sqlite3_bind_double(statement, 6, object.trueDensity)

        if let length = object.length {
            sqlite3_bind_double(statement, 7, length)
        } else {
            sqlite3_bind_null(statement, 7)
        }

        if let width = object.width {
            sqlite3_bind_double(statement, 8, width)
        } else {
            sqlite3_bind_null(statement, 8)
        }

        if let height = object.height {
            sqlite3_bind_double(statement, 9, height)
        } else {
            sqlite3_bind_null(statement, 9)
        }

        let descText = (object.description ?? "") as NSString
        let notesText = (object.notes ?? "") as NSString
        sqlite3_bind_text(statement, 10, descText.utf8String, -1, nil)
        sqlite3_bind_text(statement, 11, notesText.utf8String, -1, nil)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            print("❌ Failed to insert ground truth object")
            return nil
        }

        let objectId = sqlite3_last_insert_rowid(db)
        print("✅ Ground truth object saved (ID: \(objectId))")

        return objectId
    }

    /// Get all ground truth objects
    func getAllGroundTruthObjects() async -> [GroundTruthObject] {
        let sql = """
        SELECT id, name, category, material,
               true_volume_cm3, true_weight_g, true_density_g_cm3,
               true_length_cm, true_width_cm, true_height_cm,
               description, notes
        FROM objects
        ORDER BY name
        """

        var objects: [GroundTruthObject] = []
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return objects
        }

        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            if let obj = parseGroundTruthObject(from: statement) {
                objects.append(obj)
            }
        }

        return objects
    }

    // MARK: - Statistics

    /// Update cached statistics
    private func updateStatistics() async {
        // Get total scans
        let countSQL = "SELECT COUNT(*) FROM scans"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, countSQL, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                totalScans = Int(sqlite3_column_int(statement, 0))
            }
            sqlite3_finalize(statement)
        }

        // Get average accuracy
        let accuracySQL = """
        SELECT AVG(ABS(s.measured_volume_cm3 - o.true_volume_cm3) / o.true_volume_cm3 * 100)
        FROM scans s
        JOIN objects o ON s.object_id = o.id
        """

        if sqlite3_prepare_v2(db, accuracySQL, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                averageAccuracy = sqlite3_column_double(statement, 0)
            }
            sqlite3_finalize(statement)
        }
    }

    /// Get overall statistics
    func getOverallStatistics() async -> OverallStatistics? {
        let sql = """
        SELECT
            COUNT(*) as total_scans,
            COUNT(DISTINCT object_id) as unique_objects,
            AVG(ABS(s.measured_volume_cm3 - o.true_volume_cm3) / o.true_volume_cm3 * 100) as avg_vol_error,
            AVG(ABS(s.measured_weight_g - o.true_weight_g) / o.true_weight_g * 100) as avg_weight_error,
            AVG(s.confidence_score) as avg_confidence,
            AVG(s.scan_duration_seconds) as avg_duration
        FROM scans s
        LEFT JOIN objects o ON s.object_id = o.id
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }

        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        return OverallStatistics(
            totalScans: Int(sqlite3_column_int(statement, 0)),
            uniqueObjects: Int(sqlite3_column_int(statement, 1)),
            avgVolumeError: sqlite3_column_double(statement, 2),
            avgWeightError: sqlite3_column_double(statement, 3),
            avgConfidence: sqlite3_column_double(statement, 4),
            avgDuration: sqlite3_column_double(statement, 5)
        )
    }

    // MARK: - Helper Methods

    private func executeQuery(_ sql: String, parameters: [Any]) async -> [ScanResult] {
        var results: [ScanResult] = []
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return results
        }

        defer { sqlite3_finalize(statement) }

        // Bind parameters
        for (index, param) in parameters.enumerated() {
            if let intValue = param as? Int {
                sqlite3_bind_int(statement, Int32(index + 1), Int32(intValue))
            } else if let doubleValue = param as? Double {
                sqlite3_bind_double(statement, Int32(index + 1), doubleValue)
            }
        }

        while sqlite3_step(statement) == SQLITE_ROW {
            if let result = parseScanResult(from: statement) {
                results.append(result)
            }
        }

        return results
    }

    private func parseScanResult(from statement: OpaquePointer?) -> ScanResult? {
        guard let statement = statement else { return nil }

        return ScanResult(
            id: Int64(sqlite3_column_int64(statement, 0)),
            objectId: Int(sqlite3_column_int(statement, 1)),
            scanDate: Date(),
            scanDuration: sqlite3_column_double(statement, 3),
            deviceModel: sqlite3_column_text(statement, 4) != nil ? String(cString: sqlite3_column_text(statement, 4)!) : "Unknown",
            volume: sqlite3_column_double(statement, 4),
            weight: sqlite3_column_double(statement, 5),
            density: sqlite3_column_double(statement, 6),
            pointCount: Int(sqlite3_column_int(statement, 7)),
            meshVertexCount: Int(sqlite3_column_int(statement, 8)),
            confidenceScore: Float(sqlite3_column_double(statement, 9)),
            meshQualityScore: Float(sqlite3_column_double(statement, 10)),
            usedPCN: sqlite3_column_int(statement, 11) == 1,
            usedMeshRepair: sqlite3_column_int(statement, 12) == 1,
            usedAI: sqlite3_column_int(statement, 13) == 1,
            calibrationMethod: sqlite3_column_text(statement, 14) != nil ? String(cString: sqlite3_column_text(statement, 14)!) : "Unknown",
            scaleFactor: Float(sqlite3_column_double(statement, 15)),
            notes: nil
        )
    }

    private func parseScanAccuracy(from statement: OpaquePointer?) -> ScanAccuracy? {
        guard let statement = statement else { return nil }

        let trueVolume = sqlite3_column_double(statement, 5)
        let trueWeight = sqlite3_column_double(statement, 6)
        let measuredVolume = sqlite3_column_double(statement, 8)
        let measuredWeight = sqlite3_column_double(statement, 9)

        return ScanAccuracy(
            scanId: sqlite3_column_int64(statement, 0),
            objectName: sqlite3_column_text(statement, 2) != nil ? String(cString: sqlite3_column_text(statement, 2)!) : "Unknown",
            category: sqlite3_column_text(statement, 3) != nil ? String(cString: sqlite3_column_text(statement, 3)!) : "Unknown",
            material: sqlite3_column_text(statement, 4) != nil ? String(cString: sqlite3_column_text(statement, 4)!) : "Unknown",
            trueVolume: trueVolume,
            trueWeight: trueWeight,
            measuredVolume: measuredVolume,
            measuredWeight: measuredWeight,
            volumeErrorPercent: abs(measuredVolume - trueVolume) / trueVolume * 100,
            weightErrorPercent: abs(measuredWeight - trueWeight) / trueWeight * 100,
            confidenceScore: Float(sqlite3_column_double(statement, 11)),
            pointCount: Int(sqlite3_column_int(statement, 12))
        )
    }

    private func parseGroundTruthObject(from statement: OpaquePointer?) -> GroundTruthObject? {
        guard let statement = statement else { return nil }

        return GroundTruthObject(
            id: Int(sqlite3_column_int(statement, 0)),
            name: String(cString: sqlite3_column_text(statement, 1)),
            category: String(cString: sqlite3_column_text(statement, 2)),
            material: String(cString: sqlite3_column_text(statement, 3)),
            trueVolume: sqlite3_column_double(statement, 4),
            trueWeight: sqlite3_column_double(statement, 5),
            trueDensity: sqlite3_column_double(statement, 6),
            length: sqlite3_column_type(statement, 7) != SQLITE_NULL ? sqlite3_column_double(statement, 7) : nil,
            width: sqlite3_column_type(statement, 8) != SQLITE_NULL ? sqlite3_column_double(statement, 8) : nil,
            height: sqlite3_column_type(statement, 9) != SQLITE_NULL ? sqlite3_column_double(statement, 9) : nil,
            description: sqlite3_column_type(statement, 10) != SQLITE_NULL ? String(cString: sqlite3_column_text(statement, 10)!) : nil,
            notes: sqlite3_column_type(statement, 11) != SQLITE_NULL ? String(cString: sqlite3_column_text(statement, 11)!) : nil
        )
    }

    // MARK: - Export

    /// Export database to CSV
    func exportToCSV() async -> URL? {
        let sql = """
        SELECT
            s.scan_date,
            o.name,
            o.category,
            o.material,
            o.true_volume_cm3,
            s.measured_volume_cm3,
            ABS(s.measured_volume_cm3 - o.true_volume_cm3) / o.true_volume_cm3 * 100 as volume_error_percent,
            o.true_weight_g,
            s.measured_weight_g,
            ABS(s.measured_weight_g - o.true_weight_g) / o.true_weight_g * 100 as weight_error_percent,
            s.confidence_score,
            s.point_count
        FROM scans s
        LEFT JOIN objects o ON s.object_id = o.id
        ORDER BY s.scan_date DESC
        """

        var csvString = "Scan Date,Object,Category,Material,True Volume (cm³),Measured Volume (cm³),Volume Error %,True Weight (g),Measured Weight (g),Weight Error %,Confidence,Points\n"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }

        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            let row = (0..<12).map { i -> String in
                if let text = sqlite3_column_text(statement, Int32(i)) {
                    return String(cString: text)
                } else if sqlite3_column_type(statement, Int32(i)) == SQLITE_FLOAT {
                    return String(format: "%.2f", sqlite3_column_double(statement, Int32(i)))
                } else {
                    return String(sqlite3_column_int(statement, Int32(i)))
                }
            }
            csvString += row.joined(separator: ",") + "\n"
        }

        // Save to file
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let csvURL = documentsPath.appendingPathComponent("scan_results_\(Date().timeIntervalSince1970).csv")

        do {
            try csvString.write(to: csvURL, atomically: true, encoding: .utf8)
            print("✅ Exported to: \(csvURL.path)")
            return csvURL
        } catch {
            print("❌ Export failed: \(error)")
            return nil
        }
    }

    // MARK: - Cleanup

    private func closeDatabase() {
        if sqlite3_close(db) == SQLITE_OK {
            print("📊 Database closed")
        }
    }
}

// MARK: - Data Models

struct ScanResult {
    let id: Int64?
    let objectId: Int?
    let scanDate: Date
    let scanDuration: Double
    let deviceModel: String

    let volume: Double
    let weight: Double
    let density: Double

    let pointCount: Int
    let meshVertexCount: Int

    let confidenceScore: Float
    let meshQualityScore: Float

    let usedPCN: Bool
    let usedMeshRepair: Bool
    let usedAI: Bool

    let calibrationMethod: String
    let scaleFactor: Float

    let notes: String?
}

struct GroundTruthObject {
    let id: Int?
    let name: String
    let category: String
    let material: String

    let trueVolume: Double
    let trueWeight: Double
    let trueDensity: Double

    let length: Double?
    let width: Double?
    let height: Double?

    let description: String?
    let notes: String?
}

struct ScanAccuracy {
    let scanId: Int64
    let objectName: String
    let category: String
    let material: String

    let trueVolume: Double
    let trueWeight: Double
    let measuredVolume: Double
    let measuredWeight: Double

    let volumeErrorPercent: Double
    let weightErrorPercent: Double

    let confidenceScore: Float
    let pointCount: Int
}

struct OverallStatistics {
    let totalScans: Int
    let uniqueObjects: Int
    let avgVolumeError: Double
    let avgWeightError: Double
    let avgConfidence: Double
    let avgDuration: Double
}
