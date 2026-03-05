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

    init(propertyName: String, roomCount: Int) {
        self.version = "1.0"
        self.createdAt = Date()
        self.propertyName = propertyName
        self.roomCount = roomCount
        self.structureFile = "structure.usdz"
        self.nodes = []
        self.objects = []
    }
}

// MARK: - Tour Bundle (In-memory working state)

/// Manages tour data in memory during a capture session.
/// Stored images are written to a temporary directory.
@MainActor
final class TourBundle: ObservableObject {

    @Published var nodes: [TourNode] = []
    @Published var objects: [CapturedObject] = []
    @Published var propertyName: String = "Untitled Property"

    /// Temporary directory for in-progress captures
    let workingDirectory: URL

    init() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("RentleTour_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        // Create panoramas subdirectory
        let panoDir = tmp.appendingPathComponent("panoramas", isDirectory: true)
        try? FileManager.default.createDirectory(at: panoDir, withIntermediateDirectories: true)
        // Create objects subdirectory
        let objDir = tmp.appendingPathComponent("objects", isDirectory: true)
        try? FileManager.default.createDirectory(at: objDir, withIntermediateDirectories: true)

        self.workingDirectory = tmp
    }

    var panoramasDirectory: URL {
        workingDirectory.appendingPathComponent("panoramas", isDirectory: true)
    }

    var objectsDirectory: URL {
        workingDirectory.appendingPathComponent("objects", isDirectory: true)
    }

    // MARK: - Node Management

    func addNode(_ node: TourNode) {
        nodes.append(node)
    }

    func addObject(_ object: CapturedObject) {
        objects.append(object)
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
        return manifest
    }

    /// Clean up temporary files.
    func cleanup() {
        try? FileManager.default.removeItem(at: workingDirectory)
    }

    deinit {
        // Note: cleanup is called explicitly; deinit is a safety net
        try? FileManager.default.removeItem(at: workingDirectory)
    }
}
