// RoomPlanView.swift
// RentleTour
//
// SwiftUI wrapper around RoomPlan's RoomCaptureView (UIKit).
// Presented full-screen during a scanning session.
// Includes "Capture 360° View" button for spatial node capture.
// UI follows Apple iOS Human Interface Guidelines.

import SwiftUI
import RoomPlan

// MARK: - UIViewRepresentable Wrapper

struct RoomPlanScanView: UIViewRepresentable {
    @EnvironmentObject var scanManager: ScanManager
    var roomName: String = "Room"

    var onScanFinished: () -> Void

    func makeCoordinator() -> RoomCaptureCoordinator {
        let coordinator = RoomCaptureCoordinator()

        coordinator.onCaptureComplete = { room in
            Task { @MainActor in
                scanManager.addRoom(room, name: roomName)
                onScanFinished()
            }
        }

        coordinator.onSessionInterrupted = { message in
            Task { @MainActor in
                scanManager.alertMessage = message
                scanManager.showAlert = true
            }
        }

        return coordinator
    }

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = context.coordinator.setupCaptureView()
        context.coordinator.startSession()
        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}

    static func dismantleUIView(_ uiView: RoomCaptureView, coordinator: RoomCaptureCoordinator) {
        coordinator.stopSession()
    }
}

// MARK: - Scanning Screen

struct ScanningScreen: View {
    @EnvironmentObject var scanManager: ScanManager
    @Environment(\.dismiss) private var dismiss

    @State private var scanComplete = false
    @State private var showCaptureFlash = false
    @State private var showObjectCapture = false
    @State private var captureView: RoomCaptureView?
    @State private var showInstructions = true
    @State private var selectedRoomType: RoomType = .livingRoom

    var body: some View {
        ZStack {
            // Full-screen camera / LiDAR view
            RoomPlanScanViewWithRef(
                scanManager: scanManager,
                captureViewRef: $captureView,
                roomName: selectedRoomType.rawValue,
                onScanFinished: {
                    scanComplete = true
                }
            )
            .ignoresSafeArea()

            // Capture flash overlay
            if showCaptureFlash {
                Color.white.opacity(0.3)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            // Overlay controls
            VStack {
                // ── Top bar ──
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Spacer()

                    // Auto-texture count badge
                    HStack(spacing: 6) {
                        Image(systemName: "camera.aperture")
                            .font(.caption)
                        Text("\(scanManager.autoTextureCapture.capturedFrameCount)")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.green.opacity(0.6), in: Capsule())
                    .opacity(scanManager.autoTextureCapture.capturedFrameCount > 0 ? 1 : 0.5)
                    .animation(.easeOut(duration: 0.2), value: scanManager.autoTextureCapture.capturedFrameCount)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Room type selector row
                HStack {
                    Spacer()
                    Menu {
                        ForEach(RoomType.allCases) { roomType in
                            Button {
                                selectedRoomType = roomType
                                scanManager.autoTextureCapture.setRoomIndex(scanManager.capturedRooms.count)
                            } label: {
                                Label(roomType.rawValue, systemImage: roomType.icon)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: selectedRoomType.icon)
                                .font(.subheadline)
                            Text(selectedRoomType.rawValue)
                                .font(.subheadline.weight(.medium))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding(.horizontal, 16)

                // ── Instructions banner (auto-fades) ──
                if showInstructions && !scanComplete {
                    VStack(spacing: 4) {
                        Text("Slowly walk through the room")
                            .font(.subheadline.weight(.medium))
                        Text("Tap Capture 360° at key viewpoints")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                            withAnimation(.easeOut(duration: 0.5)) {
                                showInstructions = false
                            }
                        }
                    }
                }

                Spacer()

                // ── Active scan controls (compact floating bar) ──
                if !scanComplete {
                    VStack(spacing: 8) {
                        // Single row: 360° capture + node count + Done
                        HStack(spacing: 10) {
                            Button(action: capture360Node) {
                                HStack(spacing: 6) {
                                    Image(systemName: "camera.circle.fill")
                                        .font(.body)
                                    Text("360°")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1))
                            }
                            .disabled(scanManager.spatialCapture.isCapturing)

                            // Node count badge
                            let nodeCount = scanManager.spatialCapture.capturedNodeCount
                            Text("\(nodeCount)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(
                                    nodeCount > 0 ? AnyShapeStyle(.green.opacity(0.6)) : AnyShapeStyle(.ultraThinMaterial),
                                    in: Circle()
                                )

                            Spacer()

                            // Done button (inline)
                            Button(action: finishScanning) {
                                Text("Done")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 10)
                                    .background(.blue, in: Capsule())
                            }
                        }
                        .animation(.easeOut(duration: 0.2), value: scanManager.spatialCapture.capturedNodeCount)

                        // Compact guidance
                        Text(nodeGuidanceText)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 12)
                }

                Spacer()
                    .frame(height: 4)

                // Status indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(scanComplete ? .green : .blue)
                        .frame(width: 8, height: 8)

                    Text(scanComplete ? "Captured" : "Scanning…")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())

                // ── Post-scan bar ──
                if scanComplete {
                    VStack(spacing: 16) {
                        Label("Scan captured successfully", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.green)

                        if scanManager.spatialCapture.capturedNodeCount > 0 {
                            Text("\(scanManager.spatialCapture.capturedNodeCount) tour node(s) captured")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 12) {
                            Button {
                                scanComplete = false
                                dismiss()
                            } label: {
                                Text("Scan Another")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.blue)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.blue.opacity(0.5), lineWidth: 1))
                            }

                            Button {
                                dismiss()
                            } label: {
                                Text("Done")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(.blue, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .padding(20)
                    .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: scanComplete)
        .animation(.easeOut(duration: 0.15), value: showCaptureFlash)
        .onAppear {
            // Prevent screen from dimming during scanning
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .alert("Scan Issue", isPresented: $scanManager.showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(scanManager.alertMessage ?? "An unknown error occurred.")
        }
    }

    // MARK: - Node Guidance Text

    private var nodeGuidanceText: String {
        let count = scanManager.spatialCapture.capturedNodeCount
        if count == 0 {
            return "Capture 3–5 nodes for best results"
        } else if count < 3 {
            return "\(3 - count) more recommended (3–5 optimal)"
        } else if count <= 5 {
            return "Good coverage — add more or tap done"
        } else {
            return "Excellent coverage"
        }
    }

    // MARK: - Finish Scanning

    private func finishScanning() {
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        impact.impactOccurred()
        captureView?.captureSession.stop()
    }

    // MARK: - Capture 360° Node

    private func capture360Node() {
        guard let captureView = captureView else {
            print("[ScanningScreen] No capture view reference")
            return
        }

        // Visual feedback — flash
        withAnimation(.easeOut(duration: 0.1)) { showCaptureFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.2)) { showCaptureFlash = false }
        }

        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        // Capture the node
        let roomIndex = scanManager.capturedRooms.count
        let _ = scanManager.spatialCapture.captureNode(from: captureView, roomIndex: roomIndex)
    }
}

// MARK: - RoomPlanScanView with Ref (exposes captureView)

struct RoomPlanScanViewWithRef: UIViewRepresentable {
    var scanManager: ScanManager
    @Binding var captureViewRef: RoomCaptureView?
    var roomName: String = "Room"
    var onScanFinished: () -> Void

    func makeCoordinator() -> RoomCaptureCoordinator {
        let coordinator = RoomCaptureCoordinator()

        coordinator.onCaptureComplete = { room in
            Task { @MainActor in
                scanManager.addRoom(room, name: roomName)
                onScanFinished()
            }
        }

        coordinator.onSessionInterrupted = { message in
            Task { @MainActor in
                scanManager.alertMessage = message
                scanManager.showAlert = true
            }
        }

        return coordinator
    }

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = context.coordinator.setupCaptureView()
        context.coordinator.startSession()

        // Pass reference back and start auto-texture capture
        DispatchQueue.main.async {
            captureViewRef = view
            // Start auto-texture observer on the ARSession
            scanManager.autoTextureCapture.startObserving(
                arSession: view.captureSession.arSession
            )
            scanManager.autoTextureCapture.setRoomIndex(scanManager.capturedRooms.count)
            // Wire up auto-node capture
            scanManager.autoTextureCapture.setCaptureView(view)
            scanManager.autoTextureCapture.setSpatialManager(scanManager.spatialCapture)
        }

        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}

    static func dismantleUIView(_ uiView: RoomCaptureView, coordinator: RoomCaptureCoordinator) {
        // Stop auto-texture capture before stopping the session
        coordinator.stopSession()
    }
}
