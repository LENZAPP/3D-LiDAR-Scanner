//
//  SimpleCalibration.swift
//  3D
//
//  Simple 2-point calibration approach from GitHub
//  User taps two ends of a credit card → scale factor calculated
//

import Foundation
import ARKit
import SwiftUI
import RealityKit

// MARK: - Simple Calibration Result

struct SimpleCalibrationResult {
    let scaleFactor: Float
    let timestamp: Date
    let measuredDistance: Float  // in meters
    let knownDistance: Float     // in meters
    let referenceObject: String

    var errorPercent: Float {
        let error = abs(scaleFactor - 1.0)
        return error * 100.0
    }

    var qualityDescription: String {
        if errorPercent < 2.0 {
            return "Ausgezeichnet"
        } else if errorPercent < 5.0 {
            return "Gut"
        } else if errorPercent < 10.0 {
            return "Akzeptabel"
        } else {
            return "Ungenau - bitte wiederholen"
        }
    }
}

// MARK: - Simple Calibration Manager

class SimpleCalibrationManager: ObservableObject {

    @Published var state: CalibrationPhase = .instruction
    @Published var message: String = ""
    @Published var result: SimpleCalibrationResult?

    private var firstPoint: SIMD3<Float>?
    private var firstScreenPoint: CGPoint?

    let knownLength: Float = 0.0856  // Credit card width in meters (now public)

    enum CalibrationPhase {
        case instruction
        case waitingForFirstPoint
        case waitingForSecondPoint
        case calculating
        case success
        case failed
    }

    func startCalibration() {
        firstPoint = nil
        firstScreenPoint = nil
        state = .waitingForFirstPoint
        message = "Tippe auf das ERSTE Ende der Kreditkarte"
    }

    func handleTap(at screenPoint: CGPoint, frame: ARFrame, viewportSize: CGSize) {
        switch state {
        case .waitingForFirstPoint:
            // Store first point - try depth first, then raycast fallback
            if let worldPos = worldPosition(from: screenPoint, frame: frame, viewportSize: viewportSize) {
                firstPoint = worldPos
                firstScreenPoint = screenPoint
                state = .waitingForSecondPoint
                message = "✅ Erstes Ende erfasst! Tippe auf das ZWEITE Ende"
            } else if let worldPos = raycastWorldPosition(from: screenPoint, frame: frame, viewportSize: viewportSize) {
                firstPoint = worldPos
                firstScreenPoint = screenPoint
                state = .waitingForSecondPoint
                message = "✅ Erstes Ende (Raycast) erfasst! Tippe auf das ZWEITE Ende"
            } else {
                message = "❌ Kein Depth-Wert. Bitte näher zur Karte oder Oberfläche tippen"
            }

        case .waitingForSecondPoint:
            // Calculate with second point - try depth first, then raycast fallback
            var secondWorldPos: SIMD3<Float>?
            var usedRaycast = false

            if let depthPos = worldPosition(from: screenPoint, frame: frame, viewportSize: viewportSize) {
                secondWorldPos = depthPos
            } else if let raycastPos = raycastWorldPosition(from: screenPoint, frame: frame, viewportSize: viewportSize) {
                secondWorldPos = raycastPos
                usedRaycast = true
            }

            if let secondPos = secondWorldPos, let firstWorldPos = firstPoint {
                state = .calculating
                message = "⚙️ Berechne Kalibrierung..."

                let measuredDistance = simd_distance(firstWorldPos, secondPos)

                // Validate measured distance (credit card width ~85mm)
                if measuredDistance > 0.001 && measuredDistance < 0.5 {  // Between 1mm and 50cm
                    let scale = knownLength / measuredDistance

                    // Validation check: scale should be reasonable
                    if scale > 0.5 && scale < 2.0 {
                        let result = SimpleCalibrationResult(
                            scaleFactor: scale,
                            timestamp: Date(),
                            measuredDistance: measuredDistance,
                            knownDistance: knownLength,
                            referenceObject: "Kreditkarte (85.6mm)"
                        )

                        self.result = result
                        SimpleCalibrationManager.saveScaleFactor(scale)

                        state = .success
                        let method = usedRaycast ? " (Raycast)" : ""
                        message = "✅ Kalibrierung erfolgreich\(method)!\nFaktor: \(String(format: "%.4f", scale))\nGemessen: \(String(format: "%.1f", measuredDistance * 1000))mm"
                    } else {
                        state = .failed
                        message = "❌ Ungültiger Faktor (\(String(format: "%.2f", scale))).\nZu weit von Erwartung (1.0) entfernt.\nBitte nochmal versuchen."
                    }
                } else if measuredDistance <= 0.001 {
                    state = .failed
                    message = "❌ Punkte zu nah beieinander.\nGemessen: \(String(format: "%.1f", measuredDistance * 1000))mm\nErwartet: ~86mm"
                } else {
                    state = .failed
                    message = "❌ Distanz zu groß (\(String(format: "%.0f", measuredDistance * 100))cm).\nErwartet: ~8.6cm für Kreditkarte"
                }
            } else {
                state = .failed
                message = "❌ Zweiter Punkt konnte nicht erfasst werden.\nBitte näher zur Karte oder auf ebene Fläche tippen."
            }

        default:
            break
        }
    }

    func reset() {
        startCalibration()
    }

    // MARK: - World Position Calculation (Depth + Raycast Fallback)

    /// Primary method: Depth-based unprojection (most accurate)
    func worldPosition(from screenPoint: CGPoint, frame: ARFrame, viewportSize: CGSize) -> SIMD3<Float>? {
        guard let sceneDepth = frame.sceneDepth else { return nil }
        let depthBuffer = sceneDepth.depthMap

        // Map screen point to image coordinates
        let displayTransform = frame.displayTransform(for: .portrait, viewportSize: viewportSize)
        guard let invTransform = displayTransform.inverted() as CGAffineTransform? else { return nil }

        let normalizedPoint = CGPoint(
            x: screenPoint.x / viewportSize.width,
            y: screenPoint.y / viewportSize.height
        )
        let mapped = normalizedPoint.applying(invTransform)

        let imageResolution = frame.camera.imageResolution
        let px = Int(round(mapped.x * imageResolution.width))
        let py = Int(round(mapped.y * imageResolution.height))

        // Get depth at pixel
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        let depthWidth = CVPixelBufferGetWidth(depthBuffer)
        let depthHeight = CVPixelBufferGetHeight(depthBuffer)

        let depthX = Int(round(Float(px) * Float(depthWidth) / Float(imageResolution.width)))
        let depthY = Int(round(Float(py) * Float(depthHeight) / Float(imageResolution.height)))

        guard depthX >= 0, depthX < depthWidth, depthY >= 0, depthY < depthHeight else {
            return nil
        }

        guard let base = CVPixelBufferGetBaseAddress(depthBuffer) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(depthBuffer)
        let floatSize = MemoryLayout<Float32>.size
        let ptr = base.advanced(by: depthY * rowBytes + depthX * floatSize)
            .assumingMemoryBound(to: Float32.self)
        let depth = Float(ptr.pointee)

        guard depth.isFinite, depth > 0 else { return nil }

        // Unproject to world coordinates
        let intrinsics = frame.camera.intrinsics
        let fx = intrinsics[0, 0]
        let fy = intrinsics[1, 1]
        let cx = intrinsics[0, 2]
        let cy = intrinsics[1, 2]

        let u = Float(px)
        let v = Float(py)

        let x_cam = (u - cx) * depth / fx
        let y_cam = (v - cy) * depth / fy
        let z_cam = depth

        let camPoint = SIMD4<Float>(x_cam, y_cam, z_cam, 1.0)
        let worldPoint = frame.camera.transform * camPoint

        return SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z)
    }

    // MARK: - Persistence

    static func saveScaleFactor(_ factor: Float) {
        UserDefaults.standard.set(factor, forKey: "SimpleCalibrationScaleFactor")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "SimpleCalibrationTimestamp")
        print("✅ Scale Factor saved: \(factor)")
    }

    static func loadScaleFactor() -> Float? {
        let factor = UserDefaults.standard.float(forKey: "SimpleCalibrationScaleFactor")
        return factor > 0 ? factor : nil
    }

    static func getCalibrationAge() -> Int? {
        let timestamp = UserDefaults.standard.double(forKey: "SimpleCalibrationTimestamp")
        guard timestamp > 0 else { return nil }

        let calibrationDate = Date(timeIntervalSince1970: timestamp)
        let days = Calendar.current.dateComponents([.day], from: calibrationDate, to: Date()).day
        return days
    }

    static func needsRecalibration() -> Bool {
        guard let age = getCalibrationAge() else { return true }
        return age >= 30  // Recalibrate every 30 days
    }

    // MARK: - Raycast Fallback (when depth unavailable)

    /// Fallback method: Camera ray projection (when depth unavailable)
    /// Projects ray from camera through screen point to estimated distance
    func raycastWorldPosition(from screenPoint: CGPoint, frame: ARFrame, viewportSize: CGSize) -> SIMD3<Float>? {
        // Map screen point to normalized image coordinates
        let displayTransform = frame.displayTransform(for: .portrait, viewportSize: viewportSize)
        guard let invTransform = displayTransform.inverted() as CGAffineTransform? else { return nil }

        let normalizedViewPoint = CGPoint(
            x: screenPoint.x / viewportSize.width,
            y: screenPoint.y / viewportSize.height
        )
        let mapped = normalizedViewPoint.applying(invTransform)

        let imageResolution = frame.camera.imageResolution
        let px = Float(mapped.x * imageResolution.width)
        let py = Float(mapped.y * imageResolution.height)

        // Generate camera ray using intrinsics
        let K = frame.camera.intrinsics
        let fx = K[0, 0]
        let fy = K[1, 1]
        let cx = K[0, 2]
        let cy = K[1, 2]

        let x_cam = (px - cx) / fx
        let y_cam = (py - cy) / fy
        let rayDirCamera = simd_normalize(SIMD3<Float>(x_cam, y_cam, 1.0))

        // Transform ray to world space
        let camToWorld = frame.camera.transform
        let rotation = simd_float3x3(
            camToWorld.columns.0.xyz,
            camToWorld.columns.1.xyz,
            camToWorld.columns.2.xyz
        )
        let worldDir = rotation * rayDirCamera
        let worldOrigin = SIMD3<Float>(
            camToWorld.columns.3.x,
            camToWorld.columns.3.y,
            camToWorld.columns.3.z
        )

        // Project ray to estimated distance for calibration
        // Credit card is typically held ~20-40cm from camera
        // Using 30cm as reasonable estimate
        let estimatedDistance: Float = 0.3  // 30cm
        return worldOrigin + worldDir * estimatedDistance
    }
}

// MARK: - SIMD Extensions

private extension simd_float4 {
    var xyz: SIMD3<Float> {
        return SIMD3<Float>(x, y, z)
    }
}

// MARK: - Pin Marker Model

struct PinMarker: Identifiable {
    let id = UUID()
    var position: CGPoint
    let index: Int
    var isDragging: Bool = false
}

// MARK: - SwiftUI View

struct SimpleCalibrationView: View {
    @StateObject private var manager = SimpleCalibrationManager()
    @StateObject private var arManager = ARSessionManager()
    @Environment(\.dismiss) private var dismiss

    @State private var pins: [PinMarker] = []
    @State private var viewportSize: CGSize = .zero
    @State private var showConfirmButton = false

    var onComplete: ((Float) -> Void)?

    var body: some View {
        ZStack {
            // AR Camera Feed with proper RealityKit rendering
            RealityKitARViewContainer(arManager: arManager, onTap: { point, size in
                handleTapOrDrag(at: point, size: size)
            })
            .edgesIgnoringSafeArea(.all)

            // Pin Markers Overlay
            GeometryReader { geometry in
                ForEach(pins) { pin in
                    PinMarkerView(
                        pin: pin,
                        onDrag: { newPosition in
                            updatePinPosition(pin.id, to: newPosition)
                        }
                    )
                }
                .onChange(of: geometry.size) { _, newSize in
                    viewportSize = newSize
                }
                .onAppear {
                    viewportSize = geometry.size
                }
            }
            .edgesIgnoringSafeArea(.all)

            VStack {
                // Top instruction
                VStack(spacing: 12) {
                    Text(instructionTitle)
                        .font(.headline)
                        .foregroundColor(.white)

                    Text(manager.message)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(12)
                .padding()

                Spacer()

                // Confirm button (when 2 pins placed)
                if showConfirmButton && pins.count == 2 {
                    Button(action: {
                        calculateCalibration()
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Kalibrierung berechnen")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(12)
                        .shadow(color: .green.opacity(0.5), radius: 10)
                    }
                    .padding(.horizontal)
                    .transition(.scale.combined(with: .opacity))
                }

                // Bottom controls
                VStack(spacing: 16) {
                    if manager.state == .success, let result = manager.result {
                        VStack(spacing: 8) {
                            Text("Scale Factor: \(String(format: "%.4f", result.scaleFactor))")
                                .font(.title2.bold())
                                .foregroundColor(.green)

                            Text("Qualität: \(result.qualityDescription)")
                                .font(.subheadline)
                                .foregroundColor(.white)

                            Text("Gemessen: \(String(format: "%.1f", result.measuredDistance * 1000))mm")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding()
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(12)

                        Button(action: {
                            if let factor = manager.result?.scaleFactor {
                                onComplete?(factor)
                            }
                            dismiss()
                        }) {
                            Text("Fertig")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .cornerRadius(12)
                        }
                    } else if manager.state == .failed {
                        Button(action: {
                            manager.reset()
                        }) {
                            Text("Nochmal versuchen")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange)
                                .cornerRadius(12)
                        }
                    } else if manager.state == .instruction {
                        Button(action: {
                            manager.startCalibration()
                        }) {
                            Text("Kalibrierung starten")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                    }

                    Button(action: { dismiss() }) {
                        Text("Abbrechen")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding()
            }
        }
        .onAppear {
            arManager.startSession()
        }
        .onDisappear {
            arManager.stopSession()
        }
    }

    private var instructionTitle: String {
        switch manager.state {
        case .instruction:
            return "📏 Einfache Kalibrierung"
        case .waitingForFirstPoint:
            return pins.isEmpty ? "1️⃣ Erstes Ende" : "📍 Pin 1 platziert - Feintuning möglich"
        case .waitingForSecondPoint:
            return pins.count < 2 ? "2️⃣ Zweites Ende" : "📍 Beide Pins platziert - Feintuning möglich"
        case .calculating:
            return "⚙️ Berechne..."
        case .success:
            return "✅ Erfolgreich!"
        case .failed:
            return "❌ Fehlgeschlagen"
        }
    }

    // MARK: - Pin Management

    private func handleTapOrDrag(at point: CGPoint, size: CGSize) {
        guard pins.count < 2 else { return }

        // Add new pin
        let pin = PinMarker(position: point, index: pins.count)
        pins.append(pin)

        if pins.count == 1 {
            manager.state = .waitingForSecondPoint
            manager.message = "Gut! Tippe auf das ZWEITE Ende (oder verschiebe Pin 1)"
        } else if pins.count == 2 {
            showConfirmButton = true
            manager.message = "Pins platziert! Verschiebe sie für Feintuning oder berechne Kalibrierung"
        }
    }

    private func updatePinPosition(_ pinId: UUID, to newPosition: CGPoint) {
        if let index = pins.firstIndex(where: { $0.id == pinId }) {
            pins[index].position = newPosition
        }
    }

    private func calculateCalibration() {
        guard pins.count == 2,
              let frame = arManager.currentFrame else { return }

        showConfirmButton = false
        manager.state = .calculating

        // Use final pin positions for calculation
        if let firstWorld = manager.worldPosition(from: pins[0].position, frame: frame, viewportSize: viewportSize),
           let secondWorld = manager.worldPosition(from: pins[1].position, frame: frame, viewportSize: viewportSize) {

            let measuredDistance = simd_distance(firstWorld, secondWorld)

            if measuredDistance > 0.001 && measuredDistance < 0.5 {
                let scale = manager.knownLength / measuredDistance

                if scale > 0.5 && scale < 2.0 {
                    let result = SimpleCalibrationResult(
                        scaleFactor: scale,
                        timestamp: Date(),
                        measuredDistance: measuredDistance,
                        knownDistance: manager.knownLength,
                        referenceObject: "Kreditkarte (85.6mm)"
                    )

                    manager.result = result
                    SimpleCalibrationManager.saveScaleFactor(scale)

                    manager.state = .success
                    manager.message = "✅ Kalibrierung erfolgreich!\nFaktor: \(String(format: "%.4f", scale))\nGemessen: \(String(format: "%.1f", measuredDistance * 1000))mm"
                } else {
                    manager.state = .failed
                    manager.message = "❌ Ungültiger Faktor (\(String(format: "%.2f", scale))). Bitte Pins neu platzieren."
                    pins.removeAll()
                    showConfirmButton = false
                }
            } else {
                manager.state = .failed
                manager.message = measuredDistance <= 0.001
                    ? "❌ Pins zu nah (\(String(format: "%.1f", measuredDistance * 1000))mm). Erwartet: ~86mm"
                    : "❌ Distanz zu groß (\(String(format: "%.0f", measuredDistance * 100))cm). Erwartet: ~8.6cm"
                pins.removeAll()
                showConfirmButton = false
            }
        } else {
            manager.state = .failed
            manager.message = "❌ Depth-Werte nicht verfügbar. Bitte näher zur Oberfläche."
            pins.removeAll()
            showConfirmButton = false
        }
    }

    // Make knownLength accessible
    private var knownLength: Float { manager.knownLength }
}

// MARK: - AR Session Manager (minimal)

class ARSessionManager: NSObject, ObservableObject {
    let session = ARSession()
    @Published var currentFrame: ARFrame?

    func startSession() {
        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics = .sceneDepth
        }
        session.delegate = self
        session.run(config)
    }

    func stopSession() {
        session.pause()
    }
}

extension ARSessionManager: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        DispatchQueue.main.async {
            self.currentFrame = frame
        }
    }
}

// MARK: - Pin Marker View (Draggable)

struct PinMarkerView: View {
    let pin: PinMarker
    let onDrag: (CGPoint) -> Void

    @State private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack {
            // Pin shadow
            Circle()
                .fill(Color.black.opacity(0.3))
                .frame(width: 50, height: 50)
                .offset(x: 2, y: 2)

            // Pin body (stecknadel)
            ZStack {
                // Pin head (round top)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                pin.index == 0 ? Color.blue : Color.red,
                                pin.index == 0 ? Color.blue.opacity(0.7) : Color.red.opacity(0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 3)
                    )
                    .shadow(color: pin.index == 0 ? .blue.opacity(0.5) : .red.opacity(0.5), radius: 8)

                // Pin number
                Text("\(pin.index + 1)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)

                // Pin tip (pointing down)
                Triangle()
                    .fill(pin.index == 0 ? Color.blue : Color.red)
                    .frame(width: 8, height: 12)
                    .offset(y: 26)
            }
        }
        .position(x: pin.position.x + dragOffset.width, y: pin.position.y + dragOffset.height)
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    let newPosition = CGPoint(
                        x: pin.position.x + value.translation.width,
                        y: pin.position.y + value.translation.height
                    )
                    onDrag(newPosition)
                    dragOffset = .zero
                }
        )
    }
}

// Triangle shape for pin tip
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - RealityKit AR View Container

struct RealityKitARViewContainer: UIViewRepresentable {
    let arManager: ARSessionManager
    let onTap: (CGPoint, CGSize) -> Void

    func makeUIView(context: Context) -> RealityKit.ARView {
        let arView = RealityKit.ARView(frame: .zero)
        arView.session = arManager.session

        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        context.coordinator.arView = arView

        return arView
    }

    func updateUIView(_ uiView: RealityKit.ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    class Coordinator: NSObject {
        let onTap: (CGPoint, CGSize) -> Void
        weak var arView: RealityKit.ARView?

        init(onTap: @escaping (CGPoint, CGSize) -> Void) {
            self.onTap = onTap
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = arView else { return }
            let location = gesture.location(in: view)
            let size = view.bounds.size
            onTap(location, size)
        }
    }
}

// End of SimpleCalibration.swift
// Uses RealityKit.ARView for proper camera display with draggable pin markers
