// AutoTextureCaptureManager.swift
// RentleTour
//
// Observes the ARSession during RoomPlan scanning to automatically
// capture high-resolution texture frames AND 360° tour nodes based
// on spatial triggers.
// Processing happens on a background utility queue to keep the UI at 60fps.

import Foundation
import ARKit
import RoomPlan
import CoreImage
import UIKit

// MARK: - Auto-Texture Capture Manager

final class AutoTextureCaptureManager: NSObject, ObservableObject, ARSessionDelegate {

    // MARK: Published State (updated on MainActor)

    @MainActor @Published var capturedFrameCount: Int = 0
    @MainActor @Published var isAutoCapturing: Bool = false
    @MainActor @Published var lastCaptureTimestamp: Date?
    @MainActor @Published var autoNodeCount: Int = 0

    // MARK: Texture Capture Configuration

    /// Minimum distance (meters) from last capture before triggering texture
    var distanceThreshold: Float = 0.5

    /// Minimum rotation (radians) from last capture direction before triggering texture
    var rotationThreshold: Float = .pi / 4  // 45°

    /// Minimum time (seconds) between texture captures (rate limiter)
    var minCaptureInterval: TimeInterval = 0.5

    /// Maximum exposure duration (seconds) before rejecting frame as blurry
    var maxExposureDuration: TimeInterval = 1.0 / 30.0

    /// JPEG compression quality for saved textures
    var jpegQuality: CGFloat = 0.85

    // MARK: Auto-Node Capture Configuration

    /// Minimum distance (meters) from last node before triggering auto-capture
    var nodeDistanceThreshold: Float = 2.0

    /// Minimum rotation (radians) from last node direction before triggering
    var nodeRotationThreshold: Float = .pi / 2  // 90°

    /// Minimum time (seconds) between auto-node captures
    var nodeMinInterval: TimeInterval = 3.0

    /// Enable/disable automatic 360° node capture
    var autoNodeCaptureEnabled: Bool = true

    // MARK: Internal State — Textures

    private var lastCapturePosition: SIMD3<Float>?
    private var lastCaptureForward: SIMD3<Float>?
    private var lastCaptureTime: Date?
    private var frameCount: Int = 0
    private var currentRoomIndex: Int = 0

    // MARK: Internal State — Auto-Node

    private var lastNodePosition: SIMD3<Float>?
    private var lastNodeForward: SIMD3<Float>?
    private var lastNodeTime: Date?

    /// Reference to the TourBundle for saving images
    private let tourBundle: TourBundle

    /// Weak reference to SpatialCaptureManager for triggering node captures
    private weak var spatialManager: SpatialCaptureManager?

    /// Weak reference to the RoomCaptureView (needed for SpatialCaptureManager.captureNode)
    private weak var captureView: RoomCaptureView?

    /// Background queue for image conversion — never blocks AR thread
    private let processingQueue = DispatchQueue(
        label: "com.rentle.tour.texture-processing",
        qos: .utility,
        attributes: .concurrent
    )

    /// CIContext for efficient pixel buffer → JPEG conversion (GPU-backed)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Weak reference to the observed ARSession
    private weak var observedSession: ARSession?

    // MARK: Init

    init(tourBundle: TourBundle) {
        self.tourBundle = tourBundle
        super.init()
    }

    // MARK: - Start / Stop

    /// Begin observing an ARSession for auto-capture opportunities.
    /// Called when the scanning screen appears.
    func startObserving(arSession: ARSession) {
        observedSession = arSession
        arSession.delegate = self
        Task { @MainActor in
            isAutoCapturing = true
        }
        print("[AutoTexture] ✓ Started observing ARSession")
    }

    /// Stop observing. Called when scanning screen disappears.
    func stopObserving() {
        observedSession = nil
        Task { @MainActor in
            isAutoCapturing = false
        }
        print("[AutoTexture] Stopped observing. Total frames: \(frameCount), auto-nodes: \(lastNodeTime != nil ? "active" : "none")")
    }

    /// Provide the RoomCaptureView reference for auto-node capture.
    func setCaptureView(_ view: RoomCaptureView) {
        captureView = view
    }

    /// Provide the SpatialCaptureManager reference for auto-node capture.
    func setSpatialManager(_ manager: SpatialCaptureManager) {
        spatialManager = manager
    }

    /// Set the current room index (updated when rooms change)
    func setRoomIndex(_ index: Int) {
        currentRoomIndex = index
    }

    /// Reset all state for a new scan
    func reset() {
        lastCapturePosition = nil
        lastCaptureForward = nil
        lastCaptureTime = nil
        lastNodePosition = nil
        lastNodeForward = nil
        lastNodeTime = nil
        frameCount = 0
        currentRoomIndex = 0
        Task { @MainActor in
            capturedFrameCount = 0
            autoNodeCount = 0
            lastCaptureTimestamp = nil
            isAutoCapturing = false
        }
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Quick pre-checks on the AR callback queue (already background)
        guard shouldEvaluateFrame(frame) else { return }

        // Extract frame data we need before the frame is recycled
        let transform = frame.camera.transform
        let exposureDuration = frame.camera.exposureDuration
        let pixelBuffer = frame.capturedImage
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // Check spatial triggers
        guard passesSpatialTriggers(transform: transform) else { return }

        // Check sharpness filter
        guard passesSharpnessFilter(exposureDuration: exposureDuration, trackingState: frame.camera.trackingState) else {
            return
        }

        // Record this position as captured (textures)
        let position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let forward = -SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        lastCapturePosition = position
        lastCaptureForward = forward
        lastCaptureTime = Date()

        let captureIndex = frameCount + 1
        frameCount = captureIndex
        let roomIdx = currentRoomIndex

        // Dispatch heavy image work to background utility queue
        processingQueue.async { [weak self] in
            self?.processAndSaveFrame(
                pixelBuffer: pixelBuffer,
                transform: transform,
                exposureDuration: exposureDuration,
                width: width,
                height: height,
                captureIndex: captureIndex,
                roomIndex: roomIdx
            )
        }

        // ── Auto-Node Capture ──
        // Check if we should also trigger a 360° node capture
        if autoNodeCaptureEnabled {
            evaluateAutoNodeCapture(transform: transform, trackingState: frame.camera.trackingState)
        }
    }

    // MARK: - Auto-Node Trigger Evaluation

    /// Evaluates whether to automatically capture a 360° node.
    /// Uses wider spatial triggers than texture capture (2m / 90°).
    private func evaluateAutoNodeCapture(transform: simd_float4x4, trackingState: ARCamera.TrackingState) {
        // Only capture nodes when tracking is solid
        guard case .normal = trackingState else { return }

        // Rate limit node captures
        if let last = lastNodeTime, Date().timeIntervalSince(last) < nodeMinInterval {
            return
        }

        let position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let forward = -SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)

        // Check node spatial triggers (wider thresholds than textures)
        let shouldCapture: Bool
        if let lastPos = lastNodePosition, let lastFwd = lastNodeForward {
            let distance = simd_distance(position, lastPos)
            let dotProduct = simd_dot(simd_normalize(forward), simd_normalize(lastFwd))
            let angle = acos(min(max(dotProduct, -1.0), 1.0))

            shouldCapture = distance >= nodeDistanceThreshold || angle >= nodeRotationThreshold
        } else {
            // First node always captures after a brief delay
            shouldCapture = lastCaptureTime != nil  // wait for at least one texture frame
        }

        guard shouldCapture else { return }

        // Record node position
        lastNodePosition = position
        lastNodeForward = forward
        lastNodeTime = Date()

        let roomIdx = currentRoomIndex

        // Dispatch to main actor since SpatialCaptureManager is @MainActor
        Task { @MainActor [weak self] in
            guard let self,
                  let view = self.captureView,
                  let manager = self.spatialManager else { return }

            let _ = manager.captureNode(from: view, roomIndex: roomIdx)
            self.autoNodeCount = manager.capturedNodeCount
            print("[AutoTexture] ✓ Auto-captured 360° node #\(manager.capturedNodeCount)")
        }
    }

    // MARK: - Spatial Trigger Evaluation

    private func shouldEvaluateFrame(_ frame: ARFrame) -> Bool {
        // Skip if not actively capturing
        guard observedSession != nil else { return false }

        // Rate limiting — don't evaluate faster than minCaptureInterval
        if let last = lastCaptureTime, Date().timeIntervalSince(last) < minCaptureInterval {
            return false
        }

        return true
    }

    private func passesSpatialTriggers(transform: simd_float4x4) -> Bool {
        let position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let forward = -SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)

        // First capture always passes
        guard let lastPos = lastCapturePosition, let lastFwd = lastCaptureForward else {
            return true
        }

        // Check distance trigger
        let distance = simd_distance(position, lastPos)
        if distance >= distanceThreshold {
            return true
        }

        // Check rotation trigger (angle between forward vectors)
        let normalizedCurrent = simd_normalize(forward)
        let normalizedLast = simd_normalize(lastFwd)
        let dotProduct = simd_dot(normalizedCurrent, normalizedLast)
        let clampedDot = min(max(dotProduct, -1.0), 1.0)
        let angle = acos(clampedDot)
        if angle >= rotationThreshold {
            return true
        }

        return false
    }

    // MARK: - Sharpness Filter

    private func passesSharpnessFilter(exposureDuration: TimeInterval, trackingState: ARCamera.TrackingState) -> Bool {
        // Reject if tracking is degraded
        switch trackingState {
        case .normal:
            break
        case .limited(let reason):
            // Allow through for some limited reasons (e.g. initializing is OK after a moment)
            switch reason {
            case .excessiveMotion:
                return false  // Moving too fast
            case .insufficientFeatures:
                return false  // Not enough visual features
            default:
                break
            }
        case .notAvailable:
            return false
        }

        // Reject if exposure duration too long (motion blur risk)
        if exposureDuration > maxExposureDuration {
            return false
        }

        return true
    }

    // MARK: - Image Processing (Background Thread)

    private func processAndSaveFrame(
        pixelBuffer: CVPixelBuffer,
        transform: simd_float4x4,
        exposureDuration: TimeInterval,
        width: Int,
        height: Int,
        captureIndex: Int,
        roomIndex: Int
    ) {
        // Convert CVPixelBuffer → JPEG data
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let oriented = ciImage.oriented(.right)

        guard let cgImage = ciContext.createCGImage(oriented, from: oriented.extent) else {
            print("[AutoTexture] Failed to create CGImage for frame \(captureIndex)")
            return
        }

        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: jpegQuality) else {
            print("[AutoTexture] Failed to create JPEG data for frame \(captureIndex)")
            return
        }

        // Generate unique filename
        let fileName = "tex_\(String(format: "%04d", captureIndex))_\(UUID().uuidString.prefix(8)).jpg"

        // Save to disk (on this background thread)
        guard tourBundle.saveTextureImage(jpegData, fileName: fileName) != nil else {
            print("[AutoTexture] Failed to save texture \(captureIndex) to disk")
            return
        }

        // Create the TextureFrame model
        let textureFrame = TextureFrame(
            imageFileName: fileName,
            simdTransform: transform,
            roomIndex: roomIndex,
            exposureDuration: exposureDuration,
            imageWidth: width,
            imageHeight: height
        )

        // Update published state + TourBundle on main actor
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.tourBundle.addTextureFrame(textureFrame)
            self.capturedFrameCount = captureIndex
            self.lastCaptureTimestamp = Date()
        }

        print("[AutoTexture] ✓ Frame \(captureIndex) saved (\(fileName)) — \(jpegData.count / 1024)KB")
    }
}
