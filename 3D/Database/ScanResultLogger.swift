//
//  ScanResultLogger.swift
//  3D
//
//  Automatic logging of scan results to database
//

import Foundation
import ModelIO
import UIKit

/// Automatically logs scan results to database
@MainActor
class ScanResultLogger {

    static let shared = ScanResultLogger()

    private let database = ScanDatabaseManager.shared

    private init() {
        print("📝 Scan Result Logger initialized")
    }

    // MARK: - Automatic Logging

    /// Log scan result after completing a scan
    func logScanResult(
        mesh: MDLMesh,
        volume: Double,
        weight: Double,
        density: Double,
        scanDuration: Double,
        objectName: String? = nil,
        calibrationMethod: String = "1-Euro Coin",
        scaleFactor: Float = 1.0,
        usedPCN: Bool = false,
        usedMeshRepair: Bool = false,
        usedAI: Bool = false
    ) async {
        print("📝 Logging scan result...")

        // Extract mesh statistics
        let vertexCount = mesh.vertexCount
        let faceCount = mesh.vertexDescriptor.layouts.count

        // Try to find matching ground truth object
        let objectId = await findObjectId(name: objectName)

        // Calculate quality metrics
        let meshQuality = calculateMeshQuality(mesh: mesh)
        let confidence = calculateConfidenceScore(
            meshQuality: meshQuality,
            scanDuration: scanDuration,
            vertexCount: vertexCount
        )

        // Get device info
        let deviceModel = await getDeviceModel()
        let iosVersion = await getIOSVersion()

        // Create scan result
        let result = ScanResult(
            id: nil,
            objectId: objectId,
            scanDate: Date(),
            scanDuration: scanDuration,
            deviceModel: deviceModel,
            volume: volume,
            weight: weight,
            density: density,
            pointCount: vertexCount,
            meshVertexCount: vertexCount,
            confidenceScore: confidence,
            meshQualityScore: meshQuality,
            usedPCN: usedPCN,
            usedMeshRepair: usedMeshRepair,
            usedAI: usedAI,
            calibrationMethod: calibrationMethod,
            scaleFactor: scaleFactor,
            notes: nil
        )

        // Save to database
        if let scanId = await database.saveScanResult(result) {
            print("✅ Scan logged (ID: \(scanId))")

            // If we have ground truth, print accuracy
            if objectId != nil, let accuracy = await database.getScanAccuracy(scanId: scanId) {
                printAccuracy(accuracy)
            }
        }
    }

    /// Quick log for simple scans
    func quickLog(
        volume: Double,
        weight: Double,
        density: Double,
        pointCount: Int,
        scanDuration: Double
    ) async {
        let result = ScanResult(
            id: nil,
            objectId: nil,
            scanDate: Date(),
            scanDuration: scanDuration,
            deviceModel: await getDeviceModel(),
            volume: volume,
            weight: weight,
            density: density,
            pointCount: pointCount,
            meshVertexCount: pointCount,
            confidenceScore: 0.7,
            meshQualityScore: 0.75,
            usedPCN: false,
            usedMeshRepair: false,
            usedAI: false,
            calibrationMethod: "Manual",
            scaleFactor: 1.0,
            notes: nil
        )

        _ = await database.saveScanResult(result)
    }

    // MARK: - Helper Methods

    private func findObjectId(name: String?) async -> Int? {
        // Try to match with ground truth objects
        let objects = await database.getAllGroundTruthObjects()

        // Try exact name match
        if let name = name,
           let match = objects.first(where: { $0.name.lowercased() == name.lowercased() }) {
            return match.id
        }

        // Try partial match
        if let name = name,
           let match = objects.first(where: { $0.name.lowercased().contains(name.lowercased()) }) {
            return match.id
        }

        return nil
    }

    private func calculateMeshQuality(mesh: MDLMesh) -> Float {
        // Simple mesh quality heuristic
        let vertexCount = mesh.vertexCount

        // More vertices = better quality (up to a point)
        let vertexScore = min(Float(vertexCount) / 10000.0, 1.0)

        // Check if mesh has normals
        let hasNormals = mesh.vertexDescriptor.attributes.contains { (attribute: MDLVertexAttribute) in
            attribute.name == MDLVertexAttributeNormal
        }
        let normalScore: Float = hasNormals ? 1.0 : 0.5

        return (vertexScore + normalScore) / 2.0
    }

    private func calculateConfidenceScore(
        meshQuality: Float,
        scanDuration: Double,
        vertexCount: Int
    ) -> Float {
        // Confidence based on multiple factors

        // Mesh quality contributes 50%
        var confidence = meshQuality * 0.5

        // Scan duration (longer = more confident, up to 10 seconds)
        let durationScore = min(Float(scanDuration) / 10.0, 1.0)
        confidence += durationScore * 0.3

        // Vertex count (more points = higher confidence)
        let pointScore = min(Float(vertexCount) / 5000.0, 1.0)
        confidence += pointScore * 0.2

        return min(confidence, 1.0)
    }

    private func getDeviceModel() async -> String {
        #if targetEnvironment(simulator)
        return "Simulator"
        #else
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }
        return modelCode ?? "Unknown"
        #endif
    }

    private func getIOSVersion() async -> String {
        return UIDevice.current.systemVersion
    }

    private func printAccuracy(_ accuracy: ScanAccuracy) {
        print("""

        📊 SCAN ACCURACY REPORT
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        Object:      \(accuracy.objectName)
        Category:    \(accuracy.category)
        Material:    \(accuracy.material)

        VOLUME
        True:        \(String(format: "%.2f", accuracy.trueVolume)) cm³
        Measured:    \(String(format: "%.2f", accuracy.measuredVolume)) cm³
        Error:       \(String(format: "%.2f%%", accuracy.volumeErrorPercent))

        WEIGHT
        True:        \(String(format: "%.2f", accuracy.trueWeight)) g
        Measured:    \(String(format: "%.2f", accuracy.measuredWeight)) g
        Error:       \(String(format: "%.2f%%", accuracy.weightErrorPercent))

        QUALITY
        Confidence:  \(String(format: "%.0f%%", accuracy.confidenceScore * 100))
        Points:      \(accuracy.pointCount)
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        """)
    }
}

// MARK: - Integration Extensions

extension ScanResultLogger {

    /// Helper to log from ScannedObject
    func logFromScannedObject(_ scannedObject: ScannedObject, scanDuration: Double, density: Double = 1.0) async {
        // Calculate weight from volume and density
        let weight = scannedObject.volume * density

        await quickLog(
            volume: scannedObject.volume,
            weight: weight,
            density: density,
            pointCount: 1000, // Placeholder
            scanDuration: scanDuration
        )
    }

}
