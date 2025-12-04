//
//  MeshRepairError.swift
//  3D
//
//  Error types for mesh repair operations
//

import Foundation

public enum MeshRepairError: Error {
    case invalidInput(String)
    case poissonFailed(Error)
    case meshFixFailed(Error)
    case insufficientPoints(Int)
    case invalidMeshTopology(String)
    case processingTimeout
    case memoryExhausted
    case normalEstimationFailed
    case bridgeError(String)

    public var localizedDescription: String {
        switch self {
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .poissonFailed(let error):
            return "Poisson reconstruction failed: \(error.localizedDescription)"
        case .meshFixFailed(let error):
            return "MeshFix failed: \(error.localizedDescription)"
        case .insufficientPoints(let count):
            return "Too few points for reconstruction: \(count) (minimum 100)"
        case .invalidMeshTopology(let message):
            return "Invalid mesh topology: \(message)"
        case .processingTimeout:
            return "Processing timeout exceeded"
        case .memoryExhausted:
            return "Memory exhausted during processing"
        case .normalEstimationFailed:
            return "Failed to estimate surface normals"
        case .bridgeError(let message):
            return "C++ bridge error: \(message)"
        }
    }
}
