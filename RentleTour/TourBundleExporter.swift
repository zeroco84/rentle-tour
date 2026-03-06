// TourBundleExporter.swift
// RentleTour
//
// Creates the 'Matterport-style' data bundle:
//   structure.usdz      — The 3D model
//   tour_data.json      — Manifest linking nodes to images
//   panoramas/          — High-res images at each node
//   textures/           — Auto-captured texture frames
//   objects/             — Object capture models (if any)
//
// Exported as a .rentletour ZIP package.

import Foundation
import RoomPlan
import UIKit

// MARK: - Tour Bundle Exporter

@MainActor
final class TourBundleExporter {

    enum ExportError: LocalizedError {
        case noStructure
        case exportFailed(String)
        case zipFailed

        var errorDescription: String? {
            switch self {
            case .noStructure: return "No 3D structure to export."
            case .exportFailed(let msg): return "Export failed: \(msg)"
            case .zipFailed: return "Failed to create tour package."
            }
        }
    }

    /// Exports the full tour bundle as a .rentletour ZIP package.
    ///
    /// - Parameters:
    ///   - structure: The merged CapturedStructure (or nil to use first CapturedRoom)
    ///   - rooms: Array of captured rooms (fallback if no structure)
    ///   - tourBundle: The TourBundle containing nodes and images
    ///   - propertyName: Name of the property
    /// - Returns: URL of the created .rentletour package
    static func export(
        structure: CapturedStructure?,
        rooms: [CapturedRoom],
        tourBundle: TourBundle,
        propertyName: String
    ) async throws -> URL {

        let fm = FileManager.default
        let documentsDir = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let bundleName = "\(propertyName.replacingOccurrences(of: " ", with: "_"))_\(timestamp)"
        let bundleDir = documentsDir.appendingPathComponent(bundleName, isDirectory: true)

        // Clean up any existing bundle at this path
        try? fm.removeItem(at: bundleDir)

        // Create directory structure
        try fm.createDirectory(at: bundleDir, withIntermediateDirectories: true)
        let panoramasDir = bundleDir.appendingPathComponent("panoramas", isDirectory: true)
        try fm.createDirectory(at: panoramasDir, withIntermediateDirectories: true)
        let texturesDir = bundleDir.appendingPathComponent("textures", isDirectory: true)
        try fm.createDirectory(at: texturesDir, withIntermediateDirectories: true)
        let objectsDir = bundleDir.appendingPathComponent("objects", isDirectory: true)
        try fm.createDirectory(at: objectsDir, withIntermediateDirectories: true)

        // 1. Export structure.usdz
        let usdzURL = bundleDir.appendingPathComponent("structure.usdz")
        if let structure = structure {
            if #available(iOS 17.0, *) {
                try structure.export(to: usdzURL)
            }
        } else if let firstRoom = rooms.first {
            try firstRoom.export(to: usdzURL)
        } else {
            throw ExportError.noStructure
        }

        // 2. Copy panorama images
        for node in tourBundle.nodes {
            let sourceURL = tourBundle.panoramasDirectory.appendingPathComponent(node.imageFileName)
            let destURL = panoramasDir.appendingPathComponent(node.imageFileName)
            if fm.fileExists(atPath: sourceURL.path) {
                try fm.copyItem(at: sourceURL, to: destURL)
            }
        }

        // 3. Copy auto-captured textures
        for texture in tourBundle.textureFrames {
            let sourceURL = tourBundle.texturesDirectory.appendingPathComponent(texture.imageFileName)
            let destURL = texturesDir.appendingPathComponent(texture.imageFileName)
            if fm.fileExists(atPath: sourceURL.path) {
                try fm.copyItem(at: sourceURL, to: destURL)
            }
        }

        // 4. Copy object capture models
        for obj in tourBundle.objects {
            let sourceURL = tourBundle.objectsDirectory.appendingPathComponent(obj.modelFileName)
            let destURL = objectsDir.appendingPathComponent(obj.modelFileName)
            if fm.fileExists(atPath: sourceURL.path) {
                try fm.copyItem(at: sourceURL, to: destURL)
            }
        }

        // 4. Generate tour_data.json
        let manifest = tourBundle.buildManifest(roomCount: rooms.count)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(manifest)
        let jsonURL = bundleDir.appendingPathComponent("tour_data.json")
        try jsonData.write(to: jsonURL)

        // 5. Create ZIP package
        let zipURL = documentsDir.appendingPathComponent("\(bundleName).rentletour")
        try? fm.removeItem(at: zipURL)
        try createZIP(from: bundleDir, to: zipURL)

        // Clean up the uncompressed directory
        try? fm.removeItem(at: bundleDir)

        print("[TourExporter] ✓ Exported tour package: \(zipURL.lastPathComponent)")
        return zipURL
    }

    // MARK: - ZIP Creation

    /// Creates a ZIP archive from a directory using Cocoa's built-in coordinator.
    private static func createZIP(from sourceDir: URL, to destURL: URL) throws {
        let coordinator = NSFileCoordinator()
        var error: NSError?

        // Use NSFileCoordinator to create a ZIP — Apple's recommended approach
        coordinator.coordinate(
            readingItemAt: sourceDir,
            options: [.forUploading],
            error: &error
        ) { zipURL in
            do {
                try FileManager.default.moveItem(at: zipURL, to: destURL)
            } catch {
                print("[TourExporter] ZIP move failed: \(error)")
            }
        }

        if let error = error {
            throw ExportError.exportFailed(error.localizedDescription)
        }

        // Verify ZIP was created
        guard FileManager.default.fileExists(atPath: destURL.path) else {
            throw ExportError.zipFailed
        }
    }

    // MARK: - Share

    /// Presents a share sheet for the exported tour package.
    static func share(url: URL) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }

        var presenter = rootVC
        while let presented = presenter.presentedViewController {
            presenter = presented
        }

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 0, height: 0
            )
            popover.permittedArrowDirections = []
        }

        presenter.present(activityVC, animated: true)
    }
}
