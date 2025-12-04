//
//  FeedbackManager.swift
//  3D
//
//  Intelligent feedback system with haptics and voice guidance
//

import SwiftUI
import AVFoundation
import CoreHaptics

@MainActor
class FeedbackManager: ObservableObject {
    static let shared = FeedbackManager()

    @Published var currentTip: String = ""
    @Published var scanQuality: ScanQuality = .unknown

    private var speechSynthesizer = AVSpeechSynthesizer()
    private var hapticEngine: CHHapticEngine?
    private var lastSpokenTip: String = ""

    enum ScanQuality {
        case unknown, poor, fair, good, excellent

        var color: Color {
            switch self {
            case .unknown: return .gray
            case .poor: return .red
            case .fair: return .orange
            case .good: return .yellow
            case .excellent: return .green
            }
        }

        var label: String {
            switch self {
            case .unknown: return "Analysiere..."
            case .poor: return "Schlechte Qualität"
            case .fair: return "Ausreichend"
            case .good: return "Gut"
            case .excellent: return "Ausgezeichnet"
            }
        }
    }

    // Scan tips based on state
    let tips: [String: [String]] = [
        "detecting": [
            "Richte die Kamera auf ein Objekt",
            "Das Objekt sollte gut beleuchtet sein",
            "Vermeide reflektierende Oberflächen",
            "Halte das iPhone ruhig"
        ],
        "capturing": [
            "Gehe langsam um das Objekt herum",
            "Halte einen gleichmäßigen Abstand",
            "Erfasse alle Seiten des Objekts",
            "Bewege dich in einer Kreisbahn"
        ],
        "finishing": [
            "Fast geschafft!",
            "Daten werden verarbeitet...",
            "Bitte warten..."
        ]
    ]

    init() {
        setupHaptics()
    }

    private func setupHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
        } catch {
            print("Haptic engine error: \(error)")
        }
    }

    // MARK: - Haptic Feedback

    func lightHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    func mediumHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    func successHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    func warningHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    // MARK: - Voice Guidance

    func speak(_ text: String, force: Bool = false) {
        guard force || text != lastSpokenTip else { return }
        lastSpokenTip = text

        // Stop any ongoing speech
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.1
        utterance.volume = 0.8

        speechSynthesizer.speak(utterance)
    }

    func stopSpeaking() {
        speechSynthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - Tips

    func getRandomTip(for state: String) -> String {
        guard let stateTips = tips[state], !stateTips.isEmpty else {
            return "Weiter so!"
        }
        return stateTips.randomElement() ?? "Weiter so!"
    }

    func updateTip(for state: String) {
        currentTip = getRandomTip(for: state)
    }

    // MARK: - Quality Assessment

    func assessQuality(coverage: Float, imageCount: Int) {
        // Simple heuristic for quality assessment
        if imageCount < 10 {
            scanQuality = .poor
        } else if imageCount < 20 {
            scanQuality = coverage > 0.5 ? .fair : .poor
        } else if imageCount < 40 {
            scanQuality = coverage > 0.7 ? .good : .fair
        } else {
            scanQuality = coverage > 0.85 ? .excellent : .good
        }
    }
}
