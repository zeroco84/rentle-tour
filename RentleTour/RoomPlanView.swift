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

    /// Closure fired when the scan finishes and a CapturedRoom is ready.
    var onScanFinished: () -> Void

    func makeCoordinator() -> RoomCaptureCoordinator {
        let coordinator = RoomCaptureCoordinator()

        coordinator.onCaptureComplete = { room in
            Task { @MainActor in
                scanManager.addRoom(room)
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

    var body: some View {
        ZStack {
            // Full-screen camera / LiDAR view
            RoomPlanScanViewWithRef(
                scanManager: scanManager,
                captureViewRef: $captureView,
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

                    // Room counter badge
                    Text("room_\(scanManager.capturedRooms.count + 1)")
                        .font(.custom("Courier", size: 12))
                        .foregroundStyle(RentleBrand.textPrimary)
                        .tracking(1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(RentleBrand.background.opacity(0.85))
                        .overlay(
                            Rectangle()
                                .stroke(RentleBrand.border, lineWidth: 1)
                        )
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                // ── 360° Capture Button (during active scan) ──
                if !scanComplete {
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
                        if scanManager.spatialCapture.capturedNodeCount > 0 {
                            Text("[\(scanManager.spatialCapture.capturedNodeCount)]")
                                .font(.custom("Courier", size: 12))
                                .foregroundStyle(RentleBrand.green)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(RentleBrand.background.opacity(0.85))
                                .overlay(
                                    Rectangle()
                                        .stroke(RentleBrand.green.opacity(0.3), lineWidth: 1)
                                )
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.bottom, 8)
                    .animation(.easeOut(duration: 0.2), value: scanManager.spatialCapture.capturedNodeCount)
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

                // ── Bottom action bar (after scan) ──
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
    var onScanFinished: () -> Void

    func makeCoordinator() -> RoomCaptureCoordinator {
        let coordinator = RoomCaptureCoordinator()

        coordinator.onCaptureComplete = { room in
            Task { @MainActor in
                scanManager.addRoom(room)
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
