//
//  CreditCardDetector.swift
//  3D
//
//  Vision Framework based credit card detection
//

import Foundation
import Vision
import CoreImage
import UIKit
import ImageIO  // For CGImagePropertyOrientation

/// Detects credit cards using Vision Framework
class CreditCardDetector {

    // MARK: - Configuration

    struct Config {
        var minimumConfidence: Float = 0.5  // Lowered from 0.7 for better initial detection
        var minimumAspectRatio: Float = 1.3  // Widened range for rotated cards
        var maximumAspectRatio: Float = 1.9
        var maximumObservations: Int = 8  // More candidates to choose from
    }

    private let config: Config
    private let referenceObject: ReferenceObject

    // Vision requests
    private lazy var rectangleDetectionRequest: VNDetectRectanglesRequest = {
        let request = VNDetectRectanglesRequest { [weak self] request, error in
            self?.handleRectangleDetection(request: request, error: error)
        }

        request.minimumAspectRatio = VNAspectRatio(config.minimumAspectRatio)
        request.maximumAspectRatio = VNAspectRatio(config.maximumAspectRatio)
        request.minimumConfidence = VNConfidence(config.minimumConfidence)
        request.maximumObservations = config.maximumObservations
        request.minimumSize = 0.08  // Reduced from 0.2 - card at 30-40cm may be smaller in frame

        return request
    }()

    // Detection callback
    var onDetection: ((VNRectangleObservation?) -> Void)?
    var onError: ((Error) -> Void)?

    private var latestDetection: VNRectangleObservation?

    init(referenceObject: ReferenceObject, config: Config = Config()) {
        self.referenceObject = referenceObject
        self.config = config
    }

    // MARK: - Detection

    /// Detect credit card in image buffer
    /// - Parameters:
    ///   - pixelBuffer: The CVPixelBuffer from ARFrame.capturedImage
    ///   - orientation: Image orientation (default .right for portrait mode apps using AR)
    ///                  ARFrame.capturedImage is ALWAYS in landscape-right orientation
    func detect(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .right) {
        // Perform detection on background queue to avoid blocking main thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // CRITICAL FIX: Specify orientation for ARFrame's capturedImage
            // ARKit camera output is in landscape-right orientation
            // Without this, Vision looks for rectangles in a 90-degree rotated image!
            let requestHandler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: orientation,
                options: [:]
            )

            do {
                try requestHandler.perform([self.rectangleDetectionRequest])
            } catch {
                print("❌ Vision detection error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.onError?(error)
                }
            }
        }
    }

    /// Detect credit card in UIImage
    func detect(in image: UIImage) {
        guard let ciImage = CIImage(image: image) else {
            onError?(DetectionError.invalidImage)
            return
        }

        let requestHandler = VNImageRequestHandler(ciImage: ciImage, options: [:])

        do {
            try requestHandler.perform([rectangleDetectionRequest])
        } catch {
            onError?(error)
        }
    }

    // MARK: - Handle Detection Results

    private func handleRectangleDetection(request: VNRequest, error: Error?) {
        if let error = error {
            print("⚠️ Vision error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.onError?(error)
                self.latestDetection = nil
                self.onDetection?(nil)
            }
            return
        }

        guard let observations = request.results as? [VNRectangleObservation],
              !observations.isEmpty else {
            print("📸 Vision: No rectangles detected")
            DispatchQueue.main.async {
                self.latestDetection = nil
                self.onDetection?(nil)
            }
            return
        }

        print("📸 Vision: Found \(observations.count) rectangles")

        // Filter observations by aspect ratio
        let filteredObservations = observations.filter { observation in
            let aspectRatio = observation.boundingBox.width / observation.boundingBox.height
            let expectedRatio = CGFloat(referenceObject.aspectRatio)
            let invertedRatio = 1.0 / expectedRatio  // For portrait-oriented cards

            print("   - Rectangle: confidence=\(observation.confidence), aspectRatio=\(String(format: "%.2f", aspectRatio)) (expected: \(String(format: "%.2f", expectedRatio)) or inverted: \(String(format: "%.2f", invertedRatio)))")

            // Check if aspect ratio matches (within tolerance) - check both orientations
            let matchesNormal = abs(aspectRatio - expectedRatio) < 0.35
            let matchesInverted = abs(aspectRatio - invertedRatio) < 0.35
            let matches = matchesNormal || matchesInverted

            if matches {
                print("     ✅ Aspect ratio match! (normal: \(matchesNormal), inverted: \(matchesInverted))")
            }
            return matches
        }

        print("📸 Vision: \(filteredObservations.count) rectangles match aspect ratio filter")

        // Take best match (highest confidence, best aspect ratio match)
        let bestMatch = filteredObservations.max { obs1, obs2 in
            let ratio1 = obs1.boundingBox.width / obs1.boundingBox.height
            let ratio2 = obs2.boundingBox.width / obs2.boundingBox.height
            let expectedRatio = CGFloat(referenceObject.aspectRatio)

            let score1 = obs1.confidence * Float(1.0 - abs(ratio1 - expectedRatio))
            let score2 = obs2.confidence * Float(1.0 - abs(ratio2 - expectedRatio))

            return score1 < score2
        }

        if let match = bestMatch {
            print("✅ Best match: confidence=\(match.confidence), bbox=\(match.boundingBox)")
        }

        DispatchQueue.main.async {
            self.latestDetection = bestMatch
            self.onDetection?(bestMatch)
        }
    }

    // MARK: - Validation

    /// Validate if detected rectangle is likely a credit card
    func validate(observation: VNRectangleObservation) -> Bool {
        // 1. Check aspect ratio
        let aspectRatio = observation.boundingBox.width / observation.boundingBox.height
        let expectedRatio = referenceObject.aspectRatio
        guard abs(aspectRatio - expectedRatio) < 0.2 else {
            return false
        }

        // 2. Check confidence
        guard observation.confidence > config.minimumConfidence else {
            return false
        }

        // 3. Check if corners form reasonable rectangle
        guard isValidRectangle(observation) else {
            return false
        }

        return true
    }

    /// Check if corners form a valid rectangle (not too skewed)
    private func isValidRectangle(_ observation: VNRectangleObservation) -> Bool {
        let corners = [
            observation.topLeft,
            observation.topRight,
            observation.bottomRight,
            observation.bottomLeft
        ]

        // Calculate angles at corners (should be close to 90°)
        for i in 0..<4 {
            let prev = corners[(i + 3) % 4]
            let curr = corners[i]
            let next = corners[(i + 1) % 4]

            let angle = angleBetween(prev, curr, next)

            // Angle should be between 70° and 110° for a reasonable rectangle
            if angle < 70 || angle > 110 {
                return false
            }
        }

        return true
    }

    /// Calculate angle between three points (in degrees)
    private func angleBetween(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> CGFloat {
        let v1 = CGPoint(x: p1.x - p2.x, y: p1.y - p2.y)
        let v2 = CGPoint(x: p3.x - p2.x, y: p3.y - p2.y)

        let dot = v1.x * v2.x + v1.y * v2.y
        let mag1 = sqrt(v1.x * v1.x + v1.y * v1.y)
        let mag2 = sqrt(v2.x * v2.x + v2.y * v2.y)

        guard mag1 > 0 && mag2 > 0 else { return 0 }

        let cosAngle = dot / (mag1 * mag2)
        let angleRad = acos(max(-1, min(1, cosAngle)))
        return angleRad * 180 / .pi
    }

    // MARK: - Errors

    enum DetectionError: LocalizedError {
        case invalidImage
        case noRectangleDetected
        case invalidAspectRatio

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return "Ungültiges Bild"
            case .noRectangleDetected:
                return "Kein Rechteck erkannt"
            case .invalidAspectRatio:
                return "Seitenverhältnis stimmt nicht"
            }
        }
    }
}

// MARK: - Image Preprocessing

extension CreditCardDetector {

    /// Preprocess image for better detection
    func preprocessImage(_ ciImage: CIImage) -> CIImage {
        var processed = ciImage

        // 1. Auto-enhance (brightness, contrast)
        if let autoEnhance = CIFilter(name: "CIColorControls") {
            autoEnhance.setValue(processed, forKey: kCIInputImageKey)
            autoEnhance.setValue(0.1, forKey: kCIInputBrightnessKey)
            autoEnhance.setValue(1.2, forKey: kCIInputContrastKey)

            if let output = autoEnhance.outputImage {
                processed = output
            }
        }

        // 2. Sharpen edges
        if let sharpen = CIFilter(name: "CISharpenLuminance") {
            sharpen.setValue(processed, forKey: kCIInputImageKey)
            sharpen.setValue(0.7, forKey: kCIInputSharpnessKey)

            if let output = sharpen.outputImage {
                processed = output
            }
        }

        return processed
    }
}

// MARK: - CGRect Extension

extension CGRect {
    var center: CGPoint {
        return CGPoint(x: midX, y: midY)
    }
}
