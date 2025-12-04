//
//  Logger.swift
//  3D
//
//  Unified logging system using OSLog for better console visibility
//

import Foundation
import os.log

/// Unified Logger for 3D App
/// Uses OSLog which is visible in Console.app and Xcode Console
extension Logger {
    /// Logger for USDZ file import operations
    static let fileImport = Logger(subsystem: Bundle.main.bundleIdentifier ?? "3D", category: "FileImport")

    /// Logger for document picker operations
    static let documentPicker = Logger(subsystem: Bundle.main.bundleIdentifier ?? "3D", category: "DocumentPicker")

    /// Logger for scanned objects manager
    static let objectsManager = Logger(subsystem: Bundle.main.bundleIdentifier ?? "3D", category: "ObjectsManager")

    /// Logger for UI events
    static let ui = Logger(subsystem: Bundle.main.bundleIdentifier ?? "3D", category: "UI")
}

/// Helper for debugging - prints to Xcode Console
/// Uses BOTH print() and NSLog() to ensure visibility
func debugLog(_ message: String, category: String = "Debug", type: OSLogType = .debug) {
    let emoji: String

    switch type {
    case .fault:
        emoji = "🔴"
    case .error:
        emoji = "❌"
    case .info:
        emoji = "ℹ️"
    default:
        emoji = "🔵"
    }

    let logMessage = "\(emoji) [\(category)] \(message)"

    // Use BOTH to ensure visibility in all scenarios
    print(logMessage)
    NSLog("%@", logMessage)

    // Also write to stderr for device debugging
    fputs(logMessage + "\n", stderr)
}
