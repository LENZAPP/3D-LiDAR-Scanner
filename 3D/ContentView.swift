//
//  ContentView.swift
//  3D
//
//  Smart 3D scanning app with AI guidance and beautiful UI
//

import SwiftUI
import RealityKit

struct ContentView: View {

    // MARK: - State

    @State private var session: ObjectCaptureSession?
    @State private var imageFolderPath: URL?
    @State private var photogrammetrySession: PhotogrammetrySession?
    @State private var modelFolderPath: URL?

    @State private var appState: AppState = .startMenu
    @State private var showOnboarding = true
    @State private var showCalibration = false
    @State private var showSimpleCalibration = false  // NEW
    @State private var showGallery = false  // NEW: Gallery view
    @State private var calibrationResult: CalibrationResult?
    @State private var selectedMenuOption: StartMenuView.StartOption?

    @StateObject private var feedback = FeedbackManager.shared
    @StateObject private var meshAnalyzer = MeshAnalyzer()

    // Auto-capture settings
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("autoStartCapture") private var autoStartCapture = true
    @AppStorage("voiceGuidance") private var voiceGuidance = true
    @AppStorage("isCalibrated") private var isCalibrated = false

    enum AppState {
        case startMenu
        case calibration
        case simpleCalibration  // NEW
        case onboarding
        case scanning
        case processing
        case preview
    }

    var modelPath: URL? {
        return modelFolderPath?.appending(path: "model.usdz")
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            switch appState {
            case .startMenu:
                StartMenuView(
                    selectedOption: $selectedMenuOption,
                    hasExistingCalibration: isCalibrated && calibrationResult != nil,
                    calibrationResult: calibrationResult
                )
                .transition(.opacity)

            case .simpleCalibration:
                if showSimpleCalibration {
                    SimpleCalibrationView { scaleFactor in
                        // Simple calibration successful
                        isCalibrated = true
                        showSimpleCalibration = false

                        // Apply scale factor to MeshAnalyzer
                        meshAnalyzer.setCalibration(realWorldSize: 1.0, measuredSize: 1.0 / scaleFactor)

                        // Haptic & Voice feedback
                        feedback.successHaptic()
                        if voiceGuidance {
                            feedback.speak("Einfache Kalibrierung abgeschlossen! Scale Faktor: \(String(format: "%.3f", scaleFactor))")
                        }

                        // Return to start menu
                        withAnimation {
                            appState = .startMenu
                        }
                    }
                    .transition(.opacity)
                }

            case .calibration:
                if showCalibration {
                    CalibrationViewAR { result in
                        // Calibration successful
                        calibrationResult = result
                        isCalibrated = true
                        showCalibration = false

                        // Apply calibration to MeshAnalyzer
                        let realSize = Float(result.referenceObject.realSize.width)
                        let measuredSize = realSize / result.calibrationFactor
                        meshAnalyzer.setCalibration(realWorldSize: realSize, measuredSize: measuredSize)

                        // Haptic & Voice feedback
                        feedback.successHaptic()
                        if voiceGuidance {
                            feedback.speak("Kalibrierung abgeschlossen. Genauigkeit: \(result.qualityDescription)")
                        }

                        // Return to start menu or go to scanning
                        withAnimation {
                            if hasSeenOnboarding {
                                appState = .scanning
                                startNewSession()
                            } else {
                                appState = .onboarding
                            }
                        }
                    }
                    .transition(.opacity)
                } else {
                    // Return to start menu after calibration
                    Color.clear
                        .onAppear {
                            withAnimation {
                                appState = .startMenu
                            }
                        }
                }

            case .onboarding:
                OnboardingView(showOnboarding: $showOnboarding)
                    .transition(.opacity)

            case .scanning:
                scanningView
                    .transition(.opacity)

            case .processing:
                ProcessingView()
                    .transition(.opacity)

            case .preview:
                if let modelPath {
                    ModelPreviewView(modelURL: modelPath, onNewScan: restartScan)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState)
        .sheet(isPresented: $showGallery) {
            ScannedObjectsGalleryView()
        }
        .onChange(of: selectedMenuOption) { (oldValue: StartMenuView.StartOption?, newValue: StartMenuView.StartOption?) in
            guard let option = newValue else { return }

            switch option {
            case .simpleCalibration:
                // NEW: Start simple 2-point calibration
                showSimpleCalibration = true
                withAnimation {
                    appState = .simpleCalibration
                }

            case .calibration:
                // Old calibration method (fallback)
                showCalibration = true
                withAnimation {
                    appState = .calibration
                }

            case .scan:
                // Skip to scanning with existing calibration
                withAnimation {
                    if hasSeenOnboarding {
                        appState = .scanning
                        startNewSession()
                    } else {
                        appState = .onboarding
                    }
                }

            case .gallery:
                // NEW: Show scanned objects gallery
                showGallery = true
            }

            // Reset selection
            selectedMenuOption = nil
        }
        .onChange(of: showOnboarding) { _, newValue in
            if !newValue {
                hasSeenOnboarding = true
                withAnimation {
                    appState = .scanning
                }
                startNewSession()
            }
        }
        .onAppear {
            // Check if calibration exists
            let calibrationManager = CalibrationManager()
            if let savedCalibration = calibrationManager.loadSavedCalibration() {
                // Use saved calibration
                calibrationResult = savedCalibration
                isCalibrated = true
                showCalibration = false

                // Apply to MeshAnalyzer
                let realSize = Float(savedCalibration.referenceObject.realSize.width)
                let measuredSize = realSize / savedCalibration.calibrationFactor
                meshAnalyzer.setCalibration(realWorldSize: realSize, measuredSize: measuredSize)

                print("✅ Loaded saved calibration (Factor: \(savedCalibration.calibrationFactor))")

                // Stay on start menu, user can choose
                appState = .startMenu
            } else {
                // No calibration - stay on start menu, user must calibrate first
                appState = .startMenu
            }
        }
    }

    // MARK: - Scanning View

    private var scanningView: some View {
        ZStack {
            if let session {
                // Camera view
                ObjectCaptureView(session: session)
                    .ignoresSafeArea()

                // Smart overlay
                ScanOverlayView(session: session, feedback: feedback)
            } else {
                // Loading state
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView()
                        .tint(.white)
                }
            }
        }
        .onChange(of: session?.state) { _, newValue in
            handleStateChange(newValue)
        }
        .onChange(of: session?.userCompletedScanPass) { _, newValue in
            if newValue == true {
                // User completed a scan pass
                feedback.successHaptic()
                if voiceGuidance {
                    feedback.speak("Scan abgeschlossen. Modell wird erstellt.")
                }
                session?.finish()
            }
        }
        // Auto-start detecting when session is ready
        .onChange(of: session?.state) { oldValue, newValue in
            if oldValue == .initializing && newValue == .ready && autoStartCapture {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    _ = session?.startDetecting()
                    if voiceGuidance {
                        feedback.speak("Richte die Kamera auf ein Objekt")
                    }
                    feedback.updateTip(for: "detecting")
                }
            }
        }
    }

    // MARK: - State Handling

    private func handleStateChange(_ newState: ObjectCaptureSession.CaptureState?) {
        guard let newState else { return }

        switch newState {
        case .ready:
            feedback.updateTip(for: "detecting")

        case .detecting:
            feedback.lightHaptic()
            feedback.updateTip(for: "detecting")

        case .capturing:
            feedback.mediumHaptic()
            if voiceGuidance {
                feedback.speak("Gehe langsam um das Objekt herum")
            }
            feedback.updateTip(for: "capturing")

        case .finishing:
            feedback.updateTip(for: "finishing")

        case .completed:
            session = nil
            withAnimation {
                appState = .processing
            }
            Task {
                await startReconstruction()
            }

        case .failed(let error):
            feedback.warningHaptic()
            if voiceGuidance {
                feedback.speak("Fehler beim Scannen. Bitte erneut versuchen.")
            }
            print("Capture failed: \(error)")
            // Auto restart after failure
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                restartScan()
            }

        default:
            break
        }
    }

    // MARK: - Session Management

    private func startNewSession() {
        // Clean up previous session to prevent memory issues
        if let existingSession = session {
            existingSession.cancel()
            session = nil
        }

        guard let directory = createNewScanDirectory() else {
            print("❌ Failed to create scan directory")
            feedback.speak("Fehler beim Erstellen des Verzeichnisses")
            return
        }

        // Create new session
        let newSession = ObjectCaptureSession()
        modelFolderPath = directory.appending(path: "Models/")
        imageFolderPath = directory.appending(path: "Images/")

        guard let imageFolderPath else {
            print("❌ Failed to create images path")
            feedback.speak("Fehler beim Erstellen des Bildpfads")
            return
        }

        newSession.start(imagesDirectory: imageFolderPath)
        session = newSession

        print("✅ New ObjectCapture session started")
    }

    private func restartScan() {
        feedback.stopSpeaking()
        withAnimation {
            appState = .scanning
        }
        startNewSession()
    }

    // MARK: - Reconstruction

    private func startReconstruction() async {
        guard let imageFolderPath, let modelPath else {
            restartScan()
            return
        }

        do {
            photogrammetrySession = try PhotogrammetrySession(input: imageFolderPath)
            guard let photogrammetrySession else { return }

            try photogrammetrySession.process(requests: [.modelFile(url: modelPath)])

            for try await output in photogrammetrySession.outputs {
                switch output {
                case .requestError(_, let error):
                    print("Reconstruction error: \(error)")
                    await MainActor.run {
                        self.photogrammetrySession = nil
                        if voiceGuidance {
                            feedback.speak("Modell konnte nicht erstellt werden")
                        }
                        restartScan()
                    }

                case .processingCancelled:
                    await MainActor.run {
                        self.photogrammetrySession = nil
                        restartScan()
                    }

                case .processingComplete:
                    await MainActor.run {
                        self.photogrammetrySession = nil
                        feedback.successHaptic()
                        if voiceGuidance {
                            feedback.speak("Dein 3D-Modell ist fertig!")
                        }

                        // Auto-save scanned object with measurements
                        saveScannedObject()

                        withAnimation {
                            appState = .preview
                        }
                    }

                default:
                    break
                }
            }
        } catch {
            print("Reconstruction error: \(error)")
            await MainActor.run {
                if voiceGuidance {
                    feedback.speak("Fehler bei der Verarbeitung")
                }
                restartScan()
            }
        }
    }

    // MARK: - File Management

    func createNewScanDirectory() -> URL? {
        guard let capturesFolder = getRootScansFolder() else { return nil }

        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
        let newCaptureDirectory = capturesFolder.appendingPathComponent(timestamp, isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: newCaptureDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            print("Failed to create capture path: \(error)")
            return nil
        }

        return newCaptureDirectory
    }

    private func getRootScansFolder() -> URL? {
        guard let documentFolder = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return nil }

        return documentFolder.appendingPathComponent("Scans/", isDirectory: true)
    }

    // MARK: - Auto-Save Scanned Object

    private func saveScannedObject() {
        guard let modelPath,
              FileManager.default.fileExists(atPath: modelPath.path) else {
            print("⚠️ Model file not found, cannot save")
            return
        }

        // Analyze mesh to get measurements
        Task {
            do {
                // Use existing meshAnalyzer
                try await meshAnalyzer.analyzeMesh(from: modelPath)

                guard let dimensions = meshAnalyzer.dimensions,
                      let volume = meshAnalyzer.volume,
                      let quality = meshAnalyzer.meshQuality else {
                    print("⚠️ Measurements not available")
                    return
                }

                // Get current scale factor
                let scaleFactor = SimpleCalibrationManager.loadScaleFactor()

                // Generate object name
                let formatter = DateFormatter()
                formatter.dateFormat = "dd.MM.yyyy HH:mm"
                let objectName = "Scan \(formatter.string(from: Date()))"

                // Save to gallery
                let savedObject = ScannedObjectsManager.shared.saveScannedObject(
                    name: objectName,
                    usdzURL: modelPath,
                    width: dimensions.width,
                    height: dimensions.height,
                    depth: dimensions.depth,
                    volume: volume,
                    meshQuality: quality.confidence,
                    scaleFactor: scaleFactor
                )

                if savedObject != nil {
                    print("✅ Object auto-saved to gallery")
                    await MainActor.run {
                        if voiceGuidance {
                            feedback.speak("Objekt wurde gespeichert")
                        }
                    }
                }
            } catch {
                print("❌ Failed to save object: \(error)")
            }
        }
    }
}
