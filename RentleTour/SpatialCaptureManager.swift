// SpatialCaptureManager.swift
// RentleTour
//
// Manages spatial 360° capture during a RoomCaptureSession.
// Uses ARFrame.camera.transform to record exact world-space positions
// and captures high-res images from the AR camera feed.

import Foundation
import ARKit
import RoomPlan
import UIKit
import CoreImage

// MARK: - Spatial Capture Manager

@MainActor
final class SpatialCaptureManager: ObservableObject {

    @Published var capturedNodeCount: Int = 0
    @Published var lastCaptureTimestamp: Date?
    @Published var isCapturing: Bool = false

    /// The active tour bundle being built
    var tourBundle: TourBundle

    /// CIContext for efficient pixel buffer → UIImage conversion
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    init(tourBundle: TourBundle) {
        self.tourBundle = tourBundle
    }

    // MARK: - Capture 360° Snapshot

    /// Captures the current AR frame's position and image, creating a TourNode.
    ///
    /// - Parameters:
    ///   - captureView: The active RoomCaptureView (to access the AR session)
    ///   - roomIndex: Which room this node belongs to
    /// - Returns: The created TourNode, or nil on failure
    func captureNode(from captureView: RoomCaptureView, roomIndex: Int) -> TourNode? {
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        // 1. Get the current AR frame
        guard let frame = captureView.captureSession.arSession.currentFrame else {
            print("[SpatialCapture] No AR frame available")
            return nil
        }

        // 2. Extract camera transform (world-space position + orientation)
        let transform = frame.camera.transform

        // 3. Capture the camera image
        guard let image = imageFromARFrame(frame) else {
            print("[SpatialCapture] Failed to convert AR frame to image")
            return nil
        }

        // 4. Generate unique file name
        let nodeIndex = capturedNodeCount + 1
        let fileName = "node_\(String(format: "%03d", nodeIndex))_\(UUID().uuidString.prefix(8)).jpg"

        // 5. Save image to disk
        guard tourBundle.saveNodeImage(image, fileName: fileName) != nil else {
            print("[SpatialCapture] Failed to save node image")
            return nil
        }

        // 6. Create the TourNode
        let node = TourNode(
            label: "Node \(nodeIndex)",
            transform: transform,
            imageFileName: fileName,
            roomIndex: roomIndex
        )

        // 7. Add to tour bundle
        tourBundle.addNode(node)
        capturedNodeCount += 1
        lastCaptureTimestamp = Date()

        print("[SpatialCapture] ✓ Captured node \(nodeIndex) at (\(node.positionX), \(node.positionY), \(node.positionZ))")
        return node
    }

    // MARK: - AR Frame → UIImage

    /// Converts an ARFrame's pixel buffer to a high-resolution UIImage.
    private func imageFromARFrame(_ frame: ARFrame) -> UIImage? {
        let pixelBuffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Rotate to match device orientation
        let oriented = ciImage.oriented(.right)

        guard let cgImage = ciContext.createCGImage(oriented, from: oriented.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    // MARK: - Reset

    func reset() {
        capturedNodeCount = 0
        lastCaptureTimestamp = nil
    }
}
