// TourDataModel.swift
// RentleTour
//
// Core data models for the hybrid capture flow.
// A TourNode links a world-space position to a high-res snapshot.
// A TourManifest describes the full tour package.

import Foundation
import simd
import UIKit

// MARK: - Tour Node

/// A single 360° capture point in world space, linked to a panorama image.
struct TourNode: Identifiable, Codable {
    let id: UUID
    let label: String

    // World-space position (from ARFrame.camera.transform)
    let positionX: Float
    let positionY: Float
    let positionZ: Float

    // Camera orientation at capture time (euler angles)
    let rotationX: Float
    let rotationY: Float
    let rotationZ: Float

    // Image file name (relative to the panoramas/ directory)
    let imageFileName: String

    // Metadata
    let capturedAt: Date
    let roomIndex: Int

    // Convenience
    var position: SIMD3<Float> {
        SIMD3(positionX, positionY, positionZ)
    }

    init(
        id: UUID = UUID(),
        label: String,
        transform: simd_float4x4,
        imageFileName: String,
        roomIndex: Int
    ) {
        self.id = id
        self.label = label
        self.positionX = transform.columns.3.x
        self.positionY = transform.columns.3.y
        self.positionZ = transform.columns.3.z

        // Extract euler angles from rotation matrix
        let sy = sqrt(transform.columns.0.x * transform.columns.0.x +
                      transform.columns.1.x * transform.columns.1.x)
        let singular = sy < 1e-6
        if !singular {
            self.rotationX = atan2(transform.columns.2.y, transform.columns.2.z)
            self.rotationY = atan2(-transform.columns.2.x, sy)
            self.rotationZ = atan2(transform.columns.1.x, transform.columns.0.x)
        } else {
            self.rotationX = atan2(-transform.columns.1.z, transform.columns.1.y)
            self.rotationY = atan2(-transform.columns.2.x, sy)
            self.rotationZ = 0
        }

        self.imageFileName = imageFileName
        self.capturedAt = Date()
        self.roomIndex = roomIndex
    }
}

// MARK: - Texture Frame (Auto-Captured)

/// A single auto-captured texture frame with world-space transform and quality metadata.
struct TextureFrame: Identifiable, Codable {
    let id: UUID
    let imageFileName: String

    // Full 4x4 transform matrix stored as 16-element flat array
    let transform: [Float]

    // Metadata
    let roomIndex: Int
    let capturedAt: Date
    let exposureDuration: Double
    let imageWidth: Int
    let imageHeight: Int

    // Convenience: extract position
    var positionX: Float { transform.count >= 13 ? transform[12] : 0 }
    var positionY: Float { transform.count >= 14 ? transform[13] : 0 }
    var positionZ: Float { transform.count >= 15 ? transform[14] : 0 }

    var position: SIMD3<Float> {
        SIMD3(positionX, positionY, positionZ)
    }

    /// Create from a simd_float4x4 transform
    init(
        id: UUID = UUID(),
        imageFileName: String,
        simdTransform: simd_float4x4,
        roomIndex: Int,
        exposureDuration: Double,
        imageWidth: Int,
        imageHeight: Int
    ) {
        self.id = id
        self.imageFileName = imageFileName
        // Flatten column-major simd_float4x4 to 16-element array
        let cols = simdTransform
        self.transform = [
            cols.columns.0.x, cols.columns.0.y, cols.columns.0.z, cols.columns.0.w,
            cols.columns.1.x, cols.columns.1.y, cols.columns.1.z, cols.columns.1.w,
            cols.columns.2.x, cols.columns.2.y, cols.columns.2.z, cols.columns.2.w,
            cols.columns.3.x, cols.columns.3.y, cols.columns.3.z, cols.columns.3.w
        ]
        self.roomIndex = roomIndex
        self.capturedAt = Date()
        self.exposureDuration = exposureDuration
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }
}

// MARK: - Object Capture Asset

/// A texture-captured object linked to its generated USDZ model.
struct CapturedObject: Identifiable, Codable {
    let id: UUID
    let label: String
    let modelFileName: String      // e.g. "fireplace.usdz"
    let capturedAt: Date
    let imageCount: Int

    // Position in world space where the capture was initiated
    let anchorX: Float
    let anchorY: Float
    let anchorZ: Float

    var anchorPosition: SIMD3<Float> {
        SIMD3(anchorX, anchorY, anchorZ)
    }
}

// MARK: - Tour Manifest

/// The JSON manifest that describes the full tour package.
struct TourManifest: Codable {
    let version: String
    let createdAt: Date
    let propertyName: String
    let roomCount: Int
    let structureFile: String      // "structure.usdz"
    var nodes: [TourNode]
    var objects: [CapturedObject]
    var textureFrames: [TextureFrame]
    var roomNames: [String]

    /// Map Swift property names to backend-expected JSON keys
    enum CodingKeys: String, CodingKey {
        case version
        case createdAt = "created_at"
        case propertyName = "property_name"
        case roomCount = "room_count"
        case structureFile = "structure_file"
        case nodes
        case objects
        case textureFrames = "images"       // Backend Python worker reads "images"
        case roomNames = "room_names"
    }

    init(propertyName: String, roomCount: Int) {
        self.version = "2.0"
        self.createdAt = Date()
        self.propertyName = propertyName
        self.roomCount = roomCount
        self.structureFile = "structure.usdz"
        self.nodes = []
        self.objects = []
        self.textureFrames = []
        self.roomNames = []
    }
}

// MARK: - Tour Bundle (In-memory working state)

/// Manages tour data in memory during a capture session.
/// Stored images are written to a temporary directory.
@MainActor
final class TourBundle: ObservableObject {

    @Published var nodes: [TourNode] = []
    @Published var objects: [CapturedObject] = []
    @Published var textureFrames: [TextureFrame] = []
    @Published var propertyName: String = "Untitled Property"

    /// Temporary directory for in-progress captures
    let workingDirectory: URL

    init() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("RentleTour_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        // Create subdirectories
        for subdir in ["panoramas", "objects", "textures"] {
            let dir = tmp.appendingPathComponent(subdir, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        self.workingDirectory = tmp
    }

    var panoramasDirectory: URL {
        workingDirectory.appendingPathComponent("panoramas", isDirectory: true)
    }

    var objectsDirectory: URL {
        workingDirectory.appendingPathComponent("objects", isDirectory: true)
    }

    var texturesDirectory: URL {
        workingDirectory.appendingPathComponent("textures", isDirectory: true)
    }

    // MARK: - Node Management

    func addNode(_ node: TourNode) {
        nodes.append(node)
    }

    func addObject(_ object: CapturedObject) {
        objects.append(object)
    }

    // MARK: - Texture Frame Management

    func addTextureFrame(_ frame: TextureFrame) {
        textureFrames.append(frame)
    }

    /// Save a texture image to the textures directory (called from background thread).
    /// Returns the file URL on success.
    nonisolated func saveTextureImage(_ data: Data, fileName: String) -> URL? {
        let fileURL = workingDirectory
            .appendingPathComponent("textures", isDirectory: true)
            .appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            print("[TourBundle] Failed to save texture: \(error)")
            return nil
        }
    }

    /// Save a captured image to the panoramas directory.
    func saveNodeImage(_ image: UIImage, fileName: String) -> URL? {
        guard let data = image.jpegData(compressionQuality: 0.92) else { return nil }
        let fileURL = panoramasDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("[TourBundle] Failed to save image: \(error)")
            return nil
        }
    }

    /// Load a node's image from disk.
    func loadNodeImage(for node: TourNode) -> UIImage? {
        let fileURL = panoramasDirectory.appendingPathComponent(node.imageFileName)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    /// Build a manifest from the current state.
    func buildManifest(roomCount: Int) -> TourManifest {
        var manifest = TourManifest(propertyName: propertyName, roomCount: roomCount)
        manifest.nodes = nodes
        manifest.objects = objects
        manifest.textureFrames = textureFrames
        return manifest
    }

    /// Clean up temporary files.
    func cleanup() {
        try? FileManager.default.removeItem(at: workingDirectory)
    }

    deinit {
        try? FileManager.default.removeItem(at: workingDirectory)
    }
}
