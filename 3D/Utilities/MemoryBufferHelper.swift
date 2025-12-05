//
//  MemoryBufferHelper.swift
//  3D
//
//  Shared utility for safe memory buffer operations
//  Reduces code duplication across mesh processing files
//

import Foundation
import ModelIO
import simd

/// Shared utility for safe memory buffer access operations
/// Used across mesh processing, analysis, and repair code
enum MemoryBufferHelper {

    // MARK: - Errors

    enum BufferError: Error {
        case bufferOverflow(required: Int, available: Int)
        case invalidBuffer
        case invalidStride
        case invalidOffset

        var localizedDescription: String {
            switch self {
            case .bufferOverflow(let required, let available):
                return "Buffer overflow: required \(required) bytes, but only \(available) available"
            case .invalidBuffer:
                return "Invalid buffer: unable to access buffer data"
            case .invalidStride:
                return "Invalid stride: stride must be greater than 0"
            case .invalidOffset:
                return "Invalid offset: offset exceeds buffer bounds"
            }
        }
    }

    // MARK: - Safe Memory Loading

    /// Safely load a value from a raw pointer with bounds checking
    /// - Parameters:
    ///   - pointer: Unsafe raw pointer to read from
    ///   - offset: Byte offset from pointer start
    ///   - type: Type of value to load
    ///   - bufferSize: Total buffer size in bytes
    /// - Returns: Loaded value of type T
    /// - Throws: BufferError.bufferOverflow if access would exceed buffer bounds
    static func safeLoad<T>(
        from pointer: UnsafeRawPointer,
        offset: Int,
        as type: T.Type,
        bufferSize: Int
    ) throws -> T {
        let requiredSize = offset + MemoryLayout<T>.size
        guard requiredSize <= bufferSize else {
            throw BufferError.bufferOverflow(
                required: requiredSize,
                available: bufferSize
            )
        }
        return pointer.advanced(by: offset).assumingMemoryBound(to: T.self).pointee
    }

    /// Safely load a vertex (SIMD3<Float>) from a vertex buffer with stride
    /// - Parameters:
    ///   - pointer: Unsafe raw pointer to vertex buffer
    ///   - index: Vertex index (0-based)
    ///   - stride: Stride in bytes between vertices
    ///   - bufferSize: Total buffer size in bytes
    /// - Returns: Vertex position as SIMD3<Float>
    /// - Throws: BufferError.bufferOverflow if access would exceed buffer bounds
    static func safeLoadVertex(
        from pointer: UnsafeRawPointer,
        index: Int,
        stride: Int,
        bufferSize: Int
    ) throws -> SIMD3<Float> {
        guard stride > 0 else {
            throw BufferError.invalidStride
        }
        let offset = index * stride
        return try safeLoad(
            from: pointer,
            offset: offset,
            as: SIMD3<Float>.self,
            bufferSize: bufferSize
        )
    }

    /// Safely load an index (UInt32) from an index buffer
    /// - Parameters:
    ///   - pointer: Unsafe raw pointer to index buffer
    ///   - index: Index position (0-based)
    ///   - bufferSize: Total buffer size in bytes
    /// - Returns: Index value as UInt32
    /// - Throws: BufferError.bufferOverflow if access would exceed buffer bounds
    static func safeLoadIndex(
        from pointer: UnsafeRawPointer,
        index: Int,
        bufferSize: Int
    ) throws -> UInt32 {
        let offset = index * MemoryLayout<UInt32>.size
        return try safeLoad(
            from: pointer,
            offset: offset,
            as: UInt32.self,
            bufferSize: bufferSize
        )
    }

    /// Safely load a vertex with explicit offset (for custom vertex formats)
    /// - Parameters:
    ///   - pointer: Unsafe raw pointer to vertex buffer
    ///   - index: Vertex index (0-based)
    ///   - stride: Stride in bytes between vertices
    ///   - offset: Additional offset within vertex (e.g., for position attribute)
    ///   - bufferSize: Total buffer size in bytes
    /// - Returns: Vertex position as SIMD3<Float>
    /// - Throws: BufferError if access would exceed buffer bounds
    static func safeLoadVertexWithOffset(
        from pointer: UnsafeRawPointer,
        index: Int,
        stride: Int,
        offset: Int,
        bufferSize: Int
    ) throws -> SIMD3<Float> {
        guard stride > 0 else {
            throw BufferError.invalidStride
        }
        let totalOffset = index * stride + offset
        return try safeLoad(
            from: pointer,
            offset: totalOffset,
            as: SIMD3<Float>.self,
            bufferSize: bufferSize
        )
    }

    // MARK: - Buffer Validation

    /// Validate that a buffer is large enough for the expected access
    /// - Parameters:
    ///   - bufferSize: Actual buffer size in bytes
    ///   - elementCount: Number of elements to access
    ///   - elementSize: Size of each element in bytes
    /// - Returns: True if buffer is large enough
    static func validateBufferSize(
        bufferSize: Int,
        elementCount: Int,
        elementSize: Int
    ) -> Bool {
        return bufferSize >= elementCount * elementSize
    }

    /// Get vertex buffer data with validation
    /// - Parameter mesh: MDLMesh to extract vertex buffer from
    /// - Returns: Tuple of (pointer, size, stride) or nil if invalid
    static func getVertexBufferData(
        from mesh: MDLMesh
    ) -> (pointer: UnsafeRawPointer, size: Int, stride: Int)? {
        guard let vertexBuffer = mesh.vertexBuffers.first else {
            return nil
        }

        guard let layout = mesh.vertexDescriptor.layouts.object(at: 0) as? MDLVertexBufferLayout else {
            return nil
        }

        let pointer = vertexBuffer.map().bytes
        let size = vertexBuffer.length
        let stride = layout.stride

        guard stride > 0, size > 0 else {
            return nil
        }

        return (pointer, size, stride)
    }

    /// Get index buffer data with validation
    /// - Parameter submesh: MDLSubmesh to extract index buffer from
    /// - Returns: Tuple of (pointer, size, count) or nil if invalid
    static func getIndexBufferData(
        from submesh: MDLSubmesh
    ) -> (pointer: UnsafeRawPointer, size: Int, count: Int)? {
        let indexBuffer = submesh.indexBuffer
        let pointer = indexBuffer.map().bytes
        let size = indexBuffer.length
        let count = submesh.indexCount

        guard size > 0, count > 0 else {
            return nil
        }

        return (pointer, size, count)
    }

    // MARK: - Convenience Methods

    /// Extract all vertices from a mesh safely
    /// - Parameter mesh: MDLMesh to extract vertices from
    /// - Returns: Array of vertex positions
    static func extractVertices(from mesh: MDLMesh) -> [SIMD3<Float>] {
        guard let (pointer, size, stride) = getVertexBufferData(from: mesh) else {
            return []
        }

        let vertexCount = mesh.vertexCount
        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(vertexCount)

        for i in 0..<vertexCount {
            do {
                let vertex = try safeLoadVertex(
                    from: pointer,
                    index: i,
                    stride: stride,
                    bufferSize: size
                )
                vertices.append(vertex)
            } catch {
                print("⚠️ Warning: Skipping vertex \(i): \(error.localizedDescription)")
                continue
            }
        }

        return vertices
    }

    /// Extract all indices from a submesh safely
    /// - Parameter submesh: MDLSubmesh to extract indices from
    /// - Returns: Array of indices
    static func extractIndices(from submesh: MDLSubmesh) -> [UInt32] {
        guard let (pointer, size, count) = getIndexBufferData(from: submesh) else {
            return []
        }

        var indices: [UInt32] = []
        indices.reserveCapacity(count)

        for i in 0..<count {
            do {
                let index = try safeLoadIndex(
                    from: pointer,
                    index: i,
                    bufferSize: size
                )
                indices.append(index)
            } catch {
                print("⚠️ Warning: Skipping index \(i): \(error.localizedDescription)")
                continue
            }
        }

        return indices
    }
}
