//
//  MeasurementCoordinator.swift
//  3D
//
//  Coordinates calibration and measurements for accurate real-world dimensions
//  Main integration point between CalibrationManager and MeshAnalyzer
//

import Foundation
import ModelIO
import Combine

/// Coordinates calibrated measurements for scanned objects
@MainActor
class MeasurementCoordinator: ObservableObject {

    // MARK: - Published Properties

    @Published var calibrationResult: CalibrationResult?
    @Published var currentMeasurements: CalibratedMeasurements?
    @Published var isAnalyzing = false
    @Published var error: MeasurementError?
    @Published var needsCalibration = false

    // MARK: - Components

    private let meshAnalyzer: MeshAnalyzer
    private let calibrationManager: CalibrationManager

    // MARK: - Configuration

    private let calibrationExpirationDays = 30
    private let calibrationWarningDays = 14

    // MARK: - Initialization

    init() {
        self.meshAnalyzer = MeshAnalyzer()
        self.calibrationManager = CalibrationManager()

        // Load saved calibration
        loadSavedCalibration()
    }

    // MARK: - Public API

    /// Analyze mesh with calibration applied
    func analyzeMesh(from url: URL) async throws -> CalibratedMeasurements {
        isAnalyzing = true
        error = nil

        defer {
            isAnalyzing = false
        }

        // PRIORITY 1: Try to load Simple Calibration (2-point method)
        var scaleFactor: Float = 1.0

        if let simpleScale = SimpleCalibrationManager.loadScaleFactor() {
            scaleFactor = simpleScale
            print("✅ Using Simple Calibration Factor: \(scaleFactor)")
        }
        // FALLBACK: Try old calibration method
        else if let calibration = calibrationResult {
            // Check if calibration is expired
            if isCalibrationExpired(calibration) {
                needsCalibration = true
                print("⚠️ Calibration expired - measurements may be inaccurate")
            }
            scaleFactor = calibration.calibrationFactor
            print("⚠️ Using old calibration Factor: \(scaleFactor)")
        }
        // NO CALIBRATION
        else {
            needsCalibration = true
            print("⚠️ NO CALIBRATION - using raw ARKit values (scale = 1.0)")
            // Don't throw error, just warn - measurements will be uncalibrated
        }

        do {
            // Set calibration in analyzer
            // scaleFactor is applied to all measurements
            meshAnalyzer.setCalibration(realWorldSize: 1.0, measuredSize: 1.0 / scaleFactor)

            // Analyze the mesh
            try await meshAnalyzer.analyzeMesh(from: url)

            // Convert to calibrated measurements
            let measurements = try createCalibratedMeasurements(from: meshAnalyzer, calibration: calibration)

            // Save result
            currentMeasurements = measurements

            print("""
            ✅ Calibrated Measurements Complete:
            \(measurements.summary)
            """)

            return measurements

        } catch {
            self.error = .analysisFailed(error)
            throw error
        }
    }

    /// Analyze MDLMesh directly (for in-memory meshes)
    func analyzeMesh(_ mesh: MDLMesh) async throws -> CalibratedMeasurements {
        isAnalyzing = true
        error = nil

        defer {
            isAnalyzing = false
        }

        // Check calibration
        guard let calibration = calibrationResult else {
            needsCalibration = true
            throw MeasurementError.noCalibration
        }

        // Set calibration
        let factor = calibration.calibrationFactor
        meshAnalyzer.setCalibration(realWorldSize: 1.0, measuredSize: 1.0 / factor)

        // Analyze
        await meshAnalyzer.analyzeMDLMesh(mesh)

        // Convert to calibrated measurements
        let measurements = try createCalibratedMeasurements(from: meshAnalyzer, calibration: calibration)
        currentMeasurements = measurements

        return measurements
    }

    /// Get quick measurements without full analysis (uses bounding box only)
    func quickMeasure(mesh: MDLMesh) -> CalibratedMeasurements? {
        guard let calibration = calibrationResult else { return nil }

        let factor = calibration.calibrationFactor
        meshAnalyzer.setCalibration(realWorldSize: 1.0, measuredSize: 1.0 / factor)

        // Quick calculation using bounding box only
        let bbox = calculateBoundingBox(mesh)
        let dimensions = createDimensions(from: bbox, calibration: factor)

        // Estimate volume from bounding box (less accurate)
        let estimatedVolume = Double(bbox.size.x * bbox.size.y * bbox.size.z) * pow(Double(factor), 3) * 1_000_000

        let meshQuality = MeshQuality(
            vertexCount: mesh.vertexCount,
            triangleCount: (mesh.submeshes?.first as? MDLSubmesh)?.indexCount ?? 0 / 3,
            watertight: false, // Unknown for quick measure
            confidence: 0.6 // Lower confidence for quick measure
        )

        let calibrationInfo = createCalibrationInfo(from: calibration)

        return CalibratedMeasurements(
            dimensions: dimensions,
            volume: Volume(cubicCentimeters: estimatedVolume),
            surfaceArea: 0, // Not calculated in quick mode
            boundingBox: bbox,
            meshQuality: meshQuality,
            calibrationInfo: calibrationInfo
        )
    }

    // MARK: - Calibration Management

    /// Load saved calibration from storage
    func loadSavedCalibration() {
        if let saved = calibrationManager.loadSavedCalibration() {
            calibrationResult = saved
            needsCalibration = isCalibrationExpired(saved) || needsRecalibration(saved)

            print("""
            ✅ Loaded saved calibration:
            - Factor: \(saved.calibrationFactor)
            - Age: \(daysOld(saved)) days
            - Confidence: \(saved.confidence)
            - Status: \(needsCalibration ? "Needs recalibration" : "Valid")
            """)
        } else {
            needsCalibration = true
            print("⚠️ No saved calibration found - calibration required")
        }
    }

    /// Update calibration with new result
    func updateCalibration(_ result: CalibrationResult) {
        calibrationResult = result
        needsCalibration = false

        print("✅ Calibration updated: factor=\(result.calibrationFactor), confidence=\(result.confidence)")
    }

    /// Clear current calibration
    func clearCalibration() {
        calibrationManager.clearSavedCalibration()
        calibrationResult = nil
        needsCalibration = true
        print("🗑️ Calibration cleared")
    }

    /// Check if calibration is valid
    func isCalibrationValid() -> Bool {
        guard let calibration = calibrationResult else { return false }
        return !isCalibrationExpired(calibration) && calibration.confidence > 0.6
    }

    // MARK: - Private Helpers

    private func createCalibratedMeasurements(
        from analyzer: MeshAnalyzer,
        calibration: CalibrationResult
    ) throws -> CalibratedMeasurements {

        guard let dimensions = analyzer.dimensions else {
            throw MeasurementError.noDimensions
        }

        guard let volume = analyzer.volume else {
            throw MeasurementError.noVolume
        }

        guard let boundingBox = analyzer.boundingBox else {
            throw MeasurementError.noBoundingBox
        }

        guard let quality = analyzer.meshQuality else {
            throw MeasurementError.noQualityData
        }

        // Create structured measurements
        let calibratedDimensions = Dimensions(
            width: dimensions.width,
            height: dimensions.height,
            depth: dimensions.depth
        )

        let calibratedVolume = Volume(cubicCentimeters: volume)

        let meshQuality = MeshQuality(
            vertexCount: quality.vertexCount,
            triangleCount: quality.triangleCount,
            watertight: quality.watertight,
            confidence: quality.confidence
        )

        let calibrationInfo = createCalibrationInfo(from: calibration)

        return CalibratedMeasurements(
            dimensions: calibratedDimensions,
            volume: calibratedVolume,
            surfaceArea: quality.surfaceArea,
            boundingBox: boundingBox,
            meshQuality: meshQuality,
            calibrationInfo: calibrationInfo
        )
    }

    private func createCalibrationInfo(from result: CalibrationResult) -> CalibrationInfo {
        return CalibrationInfo(
            calibrationFactor: result.calibrationFactor,
            calibrationDate: result.timestamp,
            confidence: result.confidence,
            referenceObject: result.referenceObject.displayName
        )
    }

    private func createDimensions(from bbox: BoundingBox, calibration: Float) -> Dimensions {
        let size = bbox.size
        return Dimensions(
            width: Double(size.x * calibration * 100),
            height: Double(size.y * calibration * 100),
            depth: Double(size.z * calibration * 100)
        )
    }

    private func calculateBoundingBox(_ mesh: MDLMesh) -> BoundingBox {
        var minPoint = SIMD3<Float>(Float.infinity, Float.infinity, Float.infinity)
        var maxPoint = SIMD3<Float>(-Float.infinity, -Float.infinity, -Float.infinity)

        guard let vertexBuffer = mesh.vertexBuffers.first else {
            return BoundingBox(min: .zero, max: .zero, center: .zero)
        }

        let vertexData = vertexBuffer.map().bytes
        guard let layout = mesh.vertexDescriptor.layouts.object(at: 0) as? MDLVertexBufferLayout else {
            return BoundingBox(min: .zero, max: .zero, center: .zero)
        }
        let stride = layout.stride

        for i in 0..<mesh.vertexCount {
            let offset = i * stride
            let vertex = vertexData.advanced(by: offset).assumingMemoryBound(to: SIMD3<Float>.self).pointee

            minPoint = SIMD3<Float>(
                Swift.min(minPoint.x, vertex.x),
                Swift.min(minPoint.y, vertex.y),
                Swift.min(minPoint.z, vertex.z)
            )
            maxPoint = SIMD3<Float>(
                Swift.max(maxPoint.x, vertex.x),
                Swift.max(maxPoint.y, vertex.y),
                Swift.max(maxPoint.z, vertex.z)
            )
        }

        let center = (minPoint + maxPoint) / 2

        return BoundingBox(min: minPoint, max: maxPoint, center: center)
    }

    // MARK: - Calibration Validation

    private func isCalibrationExpired(_ calibration: CalibrationResult) -> Bool {
        let days = daysOld(calibration)
        return days > calibrationExpirationDays
    }

    private func needsRecalibration(_ calibration: CalibrationResult) -> Bool {
        let days = daysOld(calibration)
        return days > calibrationWarningDays || calibration.confidence < 0.7
    }

    private func daysOld(_ calibration: CalibrationResult) -> Int {
        let components = Calendar.current.dateComponents([.day], from: calibration.timestamp, to: Date())
        return components.day ?? 0
    }

    // MARK: - Utilities

    /// Get calibration status for UI display
    func getCalibrationStatus() -> CalibrationStatus {
        guard let calibration = calibrationResult else {
            return .notCalibrated
        }

        if isCalibrationExpired(calibration) {
            return .expired
        } else if needsRecalibration(calibration) {
            return .needsUpdate
        } else {
            return .valid
        }
    }

    /// Get calibration age string
    func getCalibrationAgeString() -> String? {
        guard let calibration = calibrationResult else { return nil }

        let days = daysOld(calibration)
        if days == 0 {
            return "Heute kalibriert"
        } else if days == 1 {
            return "Gestern kalibriert"
        } else {
            return "Kalibriert vor \(days) Tagen"
        }
    }
}

// MARK: - Calibration Status

enum CalibrationStatus {
    case notCalibrated
    case valid
    case needsUpdate
    case expired

    var displayText: String {
        switch self {
        case .notCalibrated: return "Nicht kalibriert"
        case .valid: return "Kalibriert"
        case .needsUpdate: return "Neukalibrierung empfohlen"
        case .expired: return "Kalibrierung abgelaufen"
        }
    }

    var icon: String {
        switch self {
        case .notCalibrated: return "exclamationmark.triangle.fill"
        case .valid: return "checkmark.circle.fill"
        case .needsUpdate: return "exclamationmark.circle.fill"
        case .expired: return "xmark.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .notCalibrated: return "red"
        case .valid: return "green"
        case .needsUpdate: return "orange"
        case .expired: return "red"
        }
    }
}

// MARK: - Measurement Error

enum MeasurementError: LocalizedError {
    case noCalibration
    case analysisFailed(Error)
    case noDimensions
    case noVolume
    case noBoundingBox
    case noQualityData
    case invalidMesh

    var errorDescription: String? {
        switch self {
        case .noCalibration:
            return "Keine Kalibrierung verfügbar. Bitte führen Sie zuerst eine Kalibrierung durch."
        case .analysisFailed(let error):
            return "Mesh-Analyse fehlgeschlagen: \(error.localizedDescription)"
        case .noDimensions:
            return "Dimensionen konnten nicht berechnet werden"
        case .noVolume:
            return "Volumen konnte nicht berechnet werden"
        case .noBoundingBox:
            return "Bounding Box konnte nicht berechnet werden"
        case .noQualityData:
            return "Qualitätsdaten nicht verfügbar"
        case .invalidMesh:
            return "Ungültiges 3D-Mesh"
        }
    }
}
