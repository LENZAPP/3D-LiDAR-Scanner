//
//  CaptureState+.swift
//  3D
//

import SwiftUI
import RealityKit

extension ObjectCaptureSession.CaptureState {

    var label: String {
        switch self {
        case .initializing:
            "Initializing..."
        case .ready:
            "Ready"
        case .detecting:
            "Detecting Object..."
        case .capturing:
            "Capturing..."
        case .finishing:
            "Finishing..."
        case .completed:
            "Completed"
        case .failed(let error):
            "Failed: \(String(describing: error))"
        @unknown default:
            fatalError("unknown default: \(self)")
        }
    }
}
