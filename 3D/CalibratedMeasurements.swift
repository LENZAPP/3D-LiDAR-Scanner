//
//  CalibratedMeasurements.swift
//  3D
//
//  Enhanced measurement models with calibration integration
//  Provides accurate real-world measurements using credit card calibration
//

import Foundation
import simd

// MARK: - Calibrated Measurements

/// Complete measurement results with calibration applied
struct CalibratedMeasurements {
    let dimensions: Dimensions
    let volume: Volume
    let surfaceArea: Double // cm²
    let boundingBox: BoundingBox
    let meshQuality: MeshQuality
    let calibrationInfo: CalibrationInfo

    /// Overall confidence score (0-1)
    var confidenceScore: Double {
        // Weighted average of mesh quality and calibration confidence
        return (meshQuality.confidence * 0.6) + (Double(calibrationInfo.confidence) * 0.4)
    }

    /// Quality level for UI display
    var qualityLevel: QualityLevel {
        switch confidenceScore {
        case 0.9...1.0: return .excellent
        case 0.75..<0.9: return .good
        case 0.6..<0.75: return .acceptable
        default: return .poor
        }
    }

    /// Formatted summary for display
    var summary: String {
        """
        Dimensionen: \(dimensions.formatted)
        Volumen: \(volume.formatted)
        Oberfläche: \(String(format: "%.2f cm²", surfaceArea))
        Qualität: \(qualityLevel.displayName) (\(String(format: "%.1f%%", confidenceScore * 100)))
        Kalibrierung: \(calibrationInfo.qualityDescription)
        """
    }
}

// MARK: - Dimensions

/// 3D dimensions with calibration applied
struct Dimensions {
    let width: Double   // X-axis (cm)
    let height: Double  // Y-axis (cm)
    let depth: Double   // Z-axis (cm)

    /// Total dimensions as SIMD3
    var vector: SIMD3<Double> {
        SIMD3(width, height, depth)
    }

    /// Largest dimension
    var maxDimension: Double {
        max(width, height, depth)
    }

    /// Smallest dimension
    var minDimension: Double {
        min(width, height, depth)
    }

    /// Formatted for display
    var formatted: String {
        """
        \(String(format: "%.2f", width)) × \(String(format: "%.2f", height)) × \(String(format: "%.2f", depth)) cm
        """
    }

    /// Detailed description
    var description: String {
        """
        Breite: \(String(format: "%.2f", width)) cm
        Höhe: \(String(format: "%.2f", height)) cm
        Tiefe: \(String(format: "%.2f", depth)) cm
        """
    }
}

// MARK: - Volume

/// Volume measurement with multiple units
struct Volume {
    let cubicCentimeters: Double // cm³

    /// Volume in liters
    var liters: Double {
        cubicCentimeters / 1000.0
    }

    /// Volume in milliliters
    var milliliters: Double {
        cubicCentimeters
    }

    /// Volume in cubic meters
    var cubicMeters: Double {
        cubicCentimeters / 1_000_000.0
    }

    /// Best unit for display based on size
    var bestUnit: VolumeUnit {
        if cubicCentimeters < 10 {
            return .cubicCentimeters
        } else if cubicCentimeters < 10000 {
            return .cubicCentimeters
        } else {
            return .liters
        }
    }

    /// Formatted with best unit
    var formatted: String {
        switch bestUnit {
        case .cubicCentimeters:
            return String(format: "%.2f cm³", cubicCentimeters)
        case .liters:
            return String(format: "%.3f L", liters)
        case .milliliters:
            return String(format: "%.1f ml", milliliters)
        }
    }

    /// All units formatted
    var detailedDescription: String {
        """
        \(String(format: "%.2f cm³", cubicCentimeters))
        \(String(format: "%.3f L", liters))
        \(String(format: "%.1f ml", milliliters))
        """
    }
}

enum VolumeUnit {
    case cubicCentimeters
    case liters
    case milliliters
}

// MARK: - Bounding Box

/// 3D bounding box in calibrated coordinates
struct BoundingBox {
    let min: SIMD3<Float>
    let max: SIMD3<Float>
    let center: SIMD3<Float>

    var size: SIMD3<Float> {
        max - min
    }

    /// Diagonal length
    var diagonal: Float {
        length(size)
    }

    /// Volume of bounding box (cubic units)
    var volume: Float {
        size.x * size.y * size.z
    }
}

// MARK: - Mesh Quality

/// Quality metrics for the scanned mesh
struct MeshQuality {
    let vertexCount: Int
    let triangleCount: Int
    let watertight: Bool
    let confidence: Double // 0.0 - 1.0

    var qualityScore: String {
        switch confidence {
        case 0.9...1.0: return "Exzellent"
        case 0.7..<0.9: return "Sehr Gut"
        case 0.5..<0.7: return "Gut"
        case 0.3..<0.5: return "Akzeptabel"
        default: return "Niedrig"
        }
    }

    var detailDescription: String {
        """
        Qualität: \(qualityScore)
        Vertices: \(vertexCount.formatted())
        Dreiecke: \(triangleCount.formatted())
        Status: \(watertight ? "Geschlossen" : "Offen")
        """
    }
}

// MARK: - Calibration Info

/// Information about calibration used for measurements
struct CalibrationInfo {
    let calibrationFactor: Float
    let calibrationDate: Date
    let confidence: Float
    let referenceObject: String // e.g., "Kreditkarte"

    /// Age of calibration in days
    var ageInDays: Int {
        let days = Calendar.current.dateComponents([.day], from: calibrationDate, to: Date()).day ?? 0
        return days
    }

    /// Check if calibration is expired (>30 days)
    var isExpired: Bool {
        return ageInDays > 30
    }

    /// Check if recalibration is recommended (>14 days or low confidence)
    var needsRecalibration: Bool {
        return isExpired || confidence < 0.7 || ageInDays > 14
    }

    /// Quality description for display
    var qualityDescription: String {
        if isExpired {
            return "Abgelaufen (vor \(ageInDays) Tagen)"
        } else if needsRecalibration {
            return "Neukalibrierung empfohlen"
        } else {
            switch confidence {
            case 0.95...1.0:
                return "Exzellent (±0.5mm)"
            case 0.85..<0.95:
                return "Sehr Gut (±1mm)"
            case 0.75..<0.85:
                return "Gut (±2mm)"
            default:
                return "Akzeptabel (±5mm)"
            }
        }
    }

    /// Calibration correction percentage
    var correctionPercentage: Double {
        return abs(1.0 - Double(calibrationFactor)) * 100
    }

    /// Formatted age
    var ageDescription: String {
        if ageInDays == 0 {
            return "Heute"
        } else if ageInDays == 1 {
            return "Gestern"
        } else {
            return "vor \(ageInDays) Tagen"
        }
    }

    /// Full description
    var description: String {
        """
        Referenz: \(referenceObject)
        Kalibriert: \(ageDescription)
        Faktor: \(String(format: "%.4f", calibrationFactor))
        Korrektur: \(String(format: "%.1f%%", correctionPercentage))
        Qualität: \(qualityDescription)
        """
    }
}

// MARK: - Quality Level

/// Overall quality level for measurements
enum QualityLevel {
    case excellent
    case good
    case acceptable
    case poor

    var displayName: String {
        switch self {
        case .excellent: return "Exzellent"
        case .good: return "Gut"
        case .acceptable: return "Akzeptabel"
        case .poor: return "Niedrig"
        }
    }

    var icon: String {
        switch self {
        case .excellent: return "star.fill"
        case .good: return "checkmark.circle.fill"
        case .acceptable: return "exclamationmark.circle.fill"
        case .poor: return "xmark.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "blue"
        case .acceptable: return "orange"
        case .poor: return "red"
        }
    }
}

// MARK: - Measurement Export

/// Export measurements to various formats
extension CalibratedMeasurements {

    /// Export as dictionary for JSON serialization
    func toDictionary() -> [String: Any] {
        return [
            "dimensions": [
                "width_cm": dimensions.width,
                "height_cm": dimensions.height,
                "depth_cm": dimensions.depth
            ],
            "volume": [
                "cubic_centimeters": volume.cubicCentimeters,
                "liters": volume.liters
            ],
            "surface_area_cm2": surfaceArea,
            "quality": [
                "overall_confidence": confidenceScore,
                "level": qualityLevel.displayName,
                "mesh_quality": meshQuality.qualityScore,
                "vertex_count": meshQuality.vertexCount,
                "triangle_count": meshQuality.triangleCount,
                "watertight": meshQuality.watertight
            ],
            "calibration": [
                "factor": calibrationInfo.calibrationFactor,
                "date": calibrationInfo.calibrationDate.ISO8601Format(),
                "age_days": calibrationInfo.ageInDays,
                "confidence": calibrationInfo.confidence,
                "reference": calibrationInfo.referenceObject,
                "needs_recalibration": calibrationInfo.needsRecalibration
            ]
        ]
    }

    /// Export as CSV row
    func toCSVRow() -> String {
        return [
            String(format: "%.2f", dimensions.width),
            String(format: "%.2f", dimensions.height),
            String(format: "%.2f", dimensions.depth),
            String(format: "%.2f", volume.cubicCentimeters),
            String(format: "%.2f", surfaceArea),
            String(format: "%.3f", confidenceScore),
            meshQuality.qualityScore,
            String(calibrationInfo.calibrationFactor),
            calibrationInfo.calibrationDate.ISO8601Format()
        ].joined(separator: ",")
    }

    /// CSV header
    static var csvHeader: String {
        return "Width(cm),Height(cm),Depth(cm),Volume(cm3),Surface(cm2),Confidence,Quality,CalibrationFactor,CalibrationDate"
    }
}
