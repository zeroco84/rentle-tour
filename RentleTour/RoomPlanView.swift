// RoomPlanView.swift
// RentleTour
//
// SwiftUI wrapper around RoomPlan's RoomCaptureView (UIKit).
// Presented full-screen during a scanning session.
// Includes "Capture 360° View" button for spatial node capture.
// Styled to match Rentle-Assist terminal branding.

import SwiftUI
import RoomPlan

// MARK: - UIViewRepresentable Wrapper

struct RoomPlanScanView: UIViewRepresentable {
    @EnvironmentObject var scanManager: ScanManager
    var roomName: String = "Room"

    /// Closure fired when the scan finishes and a CapturedRoom is ready.
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
        // Start the capture session immediately so the camera/LiDAR feed appears
        context.coordinator.startSession()
        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {
        // No dynamic updates needed; session lifecycle handled by coordinator.
    }

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

            // ── Capture flash overlay ──
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
                        Text("× close")
                            .font(.custom("Courier", size: 12))
                            .foregroundStyle(RentleBrand.green)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RentleBrand.background.opacity(0.85))
                            .overlay(
                                Rectangle()
                                    .stroke(RentleBrand.border, lineWidth: 1)
                            )
                    }

                    Spacer()

                    // Room type selector (dropdown)
                    Menu {
                        ForEach(RoomType.allCases) { roomType in
                            Button {
                                selectedRoomType = roomType
                            } label: {
                                Label(roomType.rawValue, systemImage: roomType.icon)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: selectedRoomType.icon)
                                .font(.system(size: 11))
                            Text(selectedRoomType.terminalLabel)
                                .font(.custom("Courier", size: 12))
                                .tracking(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(RentleBrand.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(RentleBrand.background.opacity(0.85))
                        .overlay(
                            Rectangle()
                                .stroke(RentleBrand.border, lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // ── Instructions banner (auto-fades) ──
                if showInstructions && !scanComplete {
                    VStack(spacing: 4) {
                        Text("// slowly walk through the room")
                            .font(.custom("Courier", size: 12))
                            .foregroundStyle(RentleBrand.textPrimary)
                            .tracking(0.5)
                        Text("tap capture_360° at key viewpoints")
                            .font(.custom("Courier", size: 11))
                            .foregroundStyle(RentleBrand.textSecondary)
                            .tracking(0.5)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(RentleBrand.background.opacity(0.85))
                    .overlay(Rectangle().stroke(RentleBrand.border, lineWidth: 1))
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

                // ── 360° Capture Button + Done Button (during active scan) ──
                if !scanComplete {
                    VStack(spacing: 10) {
                        // 360° capture row
                        HStack(spacing: 12) {
                            // Capture 360° View button
                            Button(action: capture360Node) {
                                HStack(spacing: 8) {
                                    Image(systemName: "camera.circle.fill")
                                        .font(.system(size: 18))
                                    Text("capture_360°")
                                        .font(.custom("Courier", size: 12).weight(.bold))
                                        .tracking(1)
                                }
                                .foregroundStyle(RentleBrand.green)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(RentleBrand.background.opacity(0.85))
                                .overlay(
                                    Rectangle()
                                        .stroke(RentleBrand.green.opacity(0.6), lineWidth: 1)
                                )
                            }
                            .disabled(scanManager.spatialCapture.isCapturing)

                            // Node count indicator
                            let nodeCount = scanManager.spatialCapture.capturedNodeCount
                            Text("[\(nodeCount)] node\(nodeCount == 1 ? "" : "s")")
                                .font(.custom("Courier", size: 12))
                                .foregroundStyle(nodeCount > 0 ? RentleBrand.green : RentleBrand.textMuted)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(RentleBrand.background.opacity(0.85))
                                .overlay(
                                    Rectangle()
                                        .stroke(
                                            nodeCount > 0
                                                ? RentleBrand.green.opacity(0.3)
                                                : RentleBrand.border,
                                            lineWidth: 1
                                        )
                                )
                        }
                        .animation(.easeOut(duration: 0.2), value: scanManager.spatialCapture.capturedNodeCount)

                        // Node guidance hint
                        Text(nodeGuidanceText)
                            .font(.custom("Courier", size: 10))
                            .foregroundStyle(RentleBrand.textMuted)
                            .tracking(0.5)

                        // ── Done Scanning button ──
                        Button(action: finishScanning) {
                            Text("done_scanning />")
                                .font(.custom("Courier", size: 14).weight(.bold))
                                .foregroundStyle(RentleBrand.background)
                                .tracking(2)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(hex: "E8E6E3"))
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 8)
                }

                // Status indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(scanComplete ? RentleBrand.green : RentleBrand.blue)
                        .frame(width: 8, height: 8)
                        .shadow(
                            color: (scanComplete ? RentleBrand.green : RentleBrand.blue).opacity(0.5),
                            radius: 6
                        )

                    Text(scanComplete ? "status: captured" : "status: scanning")
                        .font(.custom("Courier", size: 11))
                        .foregroundStyle(RentleBrand.textSecondary)
                        .tracking(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(RentleBrand.background.opacity(0.85))
                .overlay(
                    Rectangle()
                        .stroke(RentleBrand.border, lineWidth: 1)
                )
                .padding(.bottom, 8)

                // ── Bottom action bar (after scan completes) ──
                if scanComplete {
                    VStack(spacing: 12) {
                        Text("// scan captured successfully")
                            .font(.custom("Courier", size: 12))
                            .foregroundStyle(RentleBrand.green)
                            .tracking(1)

                        // Node summary
                        if scanManager.spatialCapture.capturedNodeCount > 0 {
                            Text("✓ \(scanManager.spatialCapture.capturedNodeCount) tour node(s) captured")
                                .font(.custom("Courier", size: 11))
                                .foregroundStyle(RentleBrand.textSecondary)
                                .tracking(0.5)
                        }

                        HStack(spacing: 12) {
                            Button {
                                scanComplete = false
                                dismiss()
                            } label: {
                                Text("scan_another />")
                                    .font(.custom("Courier", size: 12).weight(.bold))
                                    .foregroundStyle(RentleBrand.blue)
                                    .tracking(1)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .overlay(
                                        Rectangle()
                                            .stroke(RentleBrand.blue, lineWidth: 1)
                                    )
                            }

                            Button {
                                dismiss()
                            } label: {
                                Text("done />")
                                    .font(.custom("Courier", size: 12).weight(.bold))
                                    .foregroundStyle(RentleBrand.background)
                                    .tracking(1)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(RentleBrand.textPrimary)
                            }
                        }
                    }
                    .padding(20)
                    .background(RentleBrand.surface.opacity(0.95))
                    .overlay(
                        Rectangle()
                            .stroke(RentleBrand.border, lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: scanComplete)
        .animation(.easeOut(duration: 0.15), value: showCaptureFlash)
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
            return "// capture 3-5 nodes for best results"
        } else if count < 3 {
            return "// \(3 - count) more recommended (3-5 optimal)"
        } else if count <= 5 {
            return "// ✓ good coverage — add more or tap done"
        } else {
            return "// ✓ excellent coverage"
        }
    }

    // MARK: - Finish Scanning

    private func finishScanning() {
        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        impact.impactOccurred()

        // Stop the RoomCaptureSession — this triggers the delegate
        // which will process the scan and call onScanFinished
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

/// Variant that passes the RoomCaptureView reference back to the parent
/// so SpatialCaptureManager can access the ARSession.
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

        // Pass the view reference back
        DispatchQueue.main.async {
            captureViewRef = view
        }

        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}

    static func dismantleUIView(_ uiView: RoomCaptureView, coordinator: RoomCaptureCoordinator) {
        coordinator.stopSession()
    }
}
