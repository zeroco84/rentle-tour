// ContentView.swift
// RentleTour
//
// Main app navigation: Property list → Scanning → Review / Export.
// Branded to match the Rentle-Assist terminal aesthetic.

import SwiftUI

// MARK: - Data Model

struct Property: Identifiable {
    let id = UUID()
    var name: String
    var apartmentId: Int
    var buildingName: String?
    var roomCount: Int = 0
    var exportedURL: URL?
    var uploadStatus: UploadStatus = .pending
    var dateCreated: Date = .now
}

// MARK: - Rentle Brand Colors

enum RentleBrand {
    // Core backgrounds
    static let background     = Color(hex: "0A0A0A")
    static let surface        = Color(hex: "0F0F0F")
    static let surfaceAlt     = Color(hex: "1C1C1E")
    static let surfaceTertiary = Color(hex: "2C2C2E")

    // Borders
    static let border         = Color(hex: "1E1E1E")
    static let borderAlt      = Color(hex: "2A2A2A")

    // Text
    static let textPrimary    = Color(hex: "E0E0E0")
    static let textSecondary  = Color(hex: "5C6370")
    static let textMuted      = Color(hex: "3A3A3A")

    // Accents
    static let green          = Color(hex: "4CAF50")
    static let blue           = Color(hex: "0A84FF")
    static let blueLight      = Color(hex: "5AC8FA")
    static let red            = Color(hex: "FF453A")
    static let orange         = Color(hex: "FF9F0A")
}

// MARK: - Content View (Landing Screen)

struct ContentView: View {
    @EnvironmentObject var scanManager: ScanManager
    @EnvironmentObject var authManager: AuthManager

    @State private var properties: [Property] = []
    @State private var showScanner = false
    @State private var showReview = false
    @State private var showUnsupportedAlert = false
    @State private var showApartmentPicker = false
    @State private var activePropertyIndex: Int?

    var body: some View {
        NavigationStack {
            ZStack {
                // Pure black background with subtle radial glows
                RentleBrand.background.ignoresSafeArea()

                // Subtle blue glow top-right
                RadialGradient(
                    colors: [Color(hex: "1a237e").opacity(0.08), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: UIScreen.main.bounds.width * 1.5
                )
                .ignoresSafeArea()

                // Subtle blue glow bottom-left
                RadialGradient(
                    colors: [Color(hex: "1a237e").opacity(0.06), .clear],
                    center: .bottomLeading,
                    startRadius: 0,
                    endRadius: UIScreen.main.bounds.width * 1.5
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    if properties.isEmpty {
                        emptyStateView
                    } else {
                        propertyList
                    }
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        authManager.logout()
                    } label: {
                        Text("logout")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(RentleBrand.red.opacity(0.8))
                    }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(EnvironmentConfig.appTitle.lowercased().replacingOccurrences(of: " ", with: "_"))
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(RentleBrand.textPrimary)
                            .tracking(1)
                        if let user = authManager.user {
                            Text(user.displayName.lowercased())
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(RentleBrand.textSecondary)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        startNewProperty()
                    } label: {
                        Text("+ new")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(RentleBrand.green)
                    }
                }
            }
            .toolbarBackground(RentleBrand.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showApartmentPicker) {
                ApartmentPickerSheet { apartment in
                    handleApartmentSelected(apartment)
                }
                .environmentObject(authManager)
            }
            .fullScreenCover(isPresented: $showScanner) {
                ScanningScreen()
                    .environmentObject(scanManager)
                    .onDisappear {
                        if let idx = activePropertyIndex {
                            properties[idx].roomCount = scanManager.capturedRooms.count
                        }
                        // Show review if rooms were captured OR nodes were captured
                        if !scanManager.capturedRooms.isEmpty || !scanManager.tourBundle.nodes.isEmpty {
                            showReview = true
                        }
                    }
            }
            .sheet(isPresented: $showReview) {
                ReviewScreen(
                    onExportComplete: { url in
                        if let idx = activePropertyIndex {
                            properties[idx].exportedURL = url
                        }
                    },
                    onUploadComplete: {
                        if let idx = activePropertyIndex {
                            properties[idx].uploadStatus = .uploaded
                        }
                    }
                )
                .environmentObject(scanManager)
                .environmentObject(authManager)
            }
            .alert("LiDAR Not Available", isPresented: $showUnsupportedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This app requires a LiDAR-equipped device (iPhone 12 Pro or later, or iPad Pro). Your device does not support room scanning.")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Sub-views

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            // ASCII art building
            VStack(spacing: 0) {
                Text("┌──────────────────┐")
                Text("│  ╔══╗  ╔══╗  ╔══╗│")
                Text("│  ║▓▓║  ║░░║  ║▓▓║│")
                Text("│  ╚══╝  ╚══╝  ╚══╝│")
                Text("│  ═══════════════ ││")
                Text("│  ▓▓▓▓▓ ░░░ ▓▓▓▓ ││")
                Text("└──────────────────┘")
            }
            .font(.system(size: 14, design: .monospaced))
            .foregroundStyle(RentleBrand.textMuted.opacity(0.8))
            .padding(20)
            .overlay(
                Rectangle()
                    .stroke(RentleBrand.borderAlt, lineWidth: 1)
            )

            VStack(spacing: 8) {
                Text("// no properties scanned")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(RentleBrand.textSecondary)
                    .tracking(1.5)

                Text("tap '+ new' to select an apartment")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(RentleBrand.textMuted)
            }

            Button {
                startNewProperty()
            } label: {
                Text("select_apartment />")
                    .font(.custom("Courier", size: 14).weight(.bold))
                    .foregroundStyle(RentleBrand.background)
                    .tracking(2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(hex: "E8E6E3"))
            }
            .padding(.horizontal, 36)
            .padding(.top, 8)

            Spacer()

            // Footer
            HStack {
                Text("v1.0.0  tour_app")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(RentleBrand.textMuted)
                    .tracking(1)

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(RentleBrand.green)
                        .frame(width: 6, height: 6)
                        .shadow(color: RentleBrand.green.opacity(0.5), radius: 6)

                    Text("lidar_ready")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(RentleBrand.green.opacity(0.4))
                        .tracking(1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    private var propertyList: some View {
        VStack(spacing: 0) {
            // Terminal-style header
            HStack {
                Text("// properties[\(properties.count)]")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(RentleBrand.textSecondary)
                    .tracking(1.5)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(properties.enumerated()), id: \.element.id) { index, property in
                        PropertyCard(property: property) {
                            activePropertyIndex = index
                            scanManager.clearAll()
                            scanManager.selectedApartmentId = property.apartmentId
                            scanManager.selectedApartmentLabel = property.name
                            guard DeviceCapability.supportsLiDAR else {
                                showUnsupportedAlert = true
                                return
                            }
                            showScanner = true
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            // Footer
            HStack {
                Text("v1.0.0  tour_app")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(RentleBrand.textMuted)
                    .tracking(1)

                Spacer()

                Text("sec_v1.0 encrypted")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(RentleBrand.green.opacity(0.4))
                    .tracking(1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: Actions

    private func startNewProperty() {
        showApartmentPicker = true
    }

    private func handleApartmentSelected(_ apartment: ApartmentDTO) {
        guard DeviceCapability.supportsLiDAR else {
            showUnsupportedAlert = true
            return
        }

        let newProperty = Property(
            name: apartment.label,
            apartmentId: apartment.id,
            buildingName: apartment.building
        )
        properties.append(newProperty)
        activePropertyIndex = properties.count - 1

        scanManager.clearAll()
        scanManager.selectedApartmentId = apartment.id
        scanManager.selectedApartmentLabel = apartment.label
        showScanner = true
    }
}

// MARK: - Property Card

struct PropertyCard: View {
    let property: Property
    var onScan: () -> Void

    var body: some View {
        Button(action: onScan) {
            HStack(spacing: 14) {
                // Status indicator
                VStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: statusColor.opacity(0.5), radius: 6)
                }

                // Details
                VStack(alignment: .leading, spacing: 4) {
                    // Building name
                    if let building = property.buildingName {
                        Text(building.lowercased().replacingOccurrences(of: " ", with: "_"))
                            .font(.custom("Courier", size: 11))
                            .foregroundStyle(RentleBrand.textSecondary)
                            .tracking(0.5)
                    }

                    Text(property.name.lowercased().replacingOccurrences(of: " ", with: "_"))
                        .font(.custom("Courier", size: 14))
                        .foregroundStyle(RentleBrand.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 16) {
                        Text("rooms: \(property.roomCount)")
                            .foregroundStyle(RentleBrand.textSecondary)

                        uploadStatusBadge
                    }
                    .font(.custom("Courier", size: 11))
                }

                Spacer()

                // Scan action
                Text(">")
                    .font(.custom("Courier", size: 16).weight(.bold))
                    .foregroundStyle(RentleBrand.green)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(RentleBrand.surface)
            .overlay(
                Rectangle()
                    .stroke(RentleBrand.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        switch property.uploadStatus {
        case .uploaded: return RentleBrand.green
        case .uploading: return RentleBrand.blue
        case .failed: return RentleBrand.red
        case .pending:
            return property.exportedURL != nil ? RentleBrand.green : RentleBrand.orange
        }
    }

    @ViewBuilder
    private var uploadStatusBadge: some View {
        switch property.uploadStatus {
        case .uploaded:
            Text("✓ uploaded")
                .foregroundStyle(RentleBrand.green)
        case .uploading:
            Text("uploading...")
                .foregroundStyle(RentleBrand.blue)
        case .failed:
            Text("✗ failed")
                .foregroundStyle(RentleBrand.red)
        case .pending:
            if property.exportedURL != nil {
                Text("✓ exported")
                    .foregroundStyle(RentleBrand.green)
            } else {
                Text("pending")
                    .foregroundStyle(RentleBrand.orange)
            }
        }
    }
}

// MARK: - Review Screen

struct ReviewScreen: View {
    @EnvironmentObject var scanManager: ScanManager
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    var onExportComplete: ((URL) -> Void)?
    var onUploadComplete: (() -> Void)?

    @State private var showDollhouse = false

    var body: some View {
        NavigationStack {
            ZStack {
                RentleBrand.background.ignoresSafeArea()

                // Subtle glow
                RadialGradient(
                    colors: [Color(hex: "1a237e").opacity(0.08), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: UIScreen.main.bounds.width * 1.5
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Terminal header
                    VStack(spacing: 8) {
                        // Show apartment target
                        if let label = scanManager.selectedApartmentLabel {
                            Text("// \(label.lowercased())")
                                .font(.custom("Courier", size: 12))
                                .foregroundStyle(RentleBrand.green)
                                .tracking(0.5)
                                .lineLimit(1)
                        }

                        Text("// review_scan.process")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(RentleBrand.textSecondary)
                            .tracking(1.5)

                        let roomCount = scanManager.capturedRooms.count
                        let nodeCount = scanManager.tourBundle.nodes.count

                        Text("\(roomCount) room\(roomCount == 1 ? "" : "s"), \(nodeCount) node\(nodeCount == 1 ? "" : "s")")
                            .font(.system(size: 20, weight: .regular, design: .monospaced))
                            .foregroundStyle(RentleBrand.textPrimary)

                        Text("tap merge_and_export to\nbuild the 3D model")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(RentleBrand.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                    }
                    .padding(.top, 32)
                    .padding(.bottom, 24)

                    // ── Action buttons FIRST (above the fold) ──
                    actionButtons
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    // ── Room list in terminal container ──
                    VStack(spacing: 0) {
                        HStack {
                            Text("> scan_results[\(scanManager.capturedRooms.count)]")
                                .font(.custom("Courier", size: 11))
                                .foregroundStyle(RentleBrand.textSecondary)
                                .tracking(1)
                            Spacer()
                            if scanManager.capturedRooms.isEmpty {
                                Text("pending")
                                    .font(.custom("Courier", size: 11))
                                    .foregroundStyle(RentleBrand.orange)
                                    .tracking(1)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        if scanManager.capturedRooms.isEmpty {
                            // Guidance when no rooms are captured
                            Text("// room data processed on merge")
                                .font(.custom("Courier", size: 11))
                                .foregroundStyle(RentleBrand.textMuted)
                                .tracking(0.5)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 10)
                        } else {
                            ForEach(Array(scanManager.capturedRooms.enumerated()), id: \.offset) { index, _ in
                                HStack(spacing: 12) {
                                    Text("✓")
                                        .foregroundStyle(RentleBrand.green)
                                    Text("room_\(index + 1)")
                                        .foregroundStyle(RentleBrand.textPrimary)
                                    Spacer()
                                    Text("captured")
                                        .foregroundStyle(RentleBrand.green.opacity(0.6))
                                }
                                .font(.custom("Courier", size: 13))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(RentleBrand.surface)
                            }
                        }
                    }
                    .background(RentleBrand.surface)
                    .overlay(
                        Rectangle()
                            .stroke(RentleBrand.border, lineWidth: 1)
                    )
                    .padding(.horizontal, 16)

                    // Tour nodes summary (collapsed list with toggle)
                    if !scanManager.tourBundle.nodes.isEmpty {
                        tourNodesSummary
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    }

                    // ── Action buttons (repeated at bottom for long scrolls) ──
                    actionButtons
                        .padding(.horizontal, 16)
                        .padding(.bottom, 30)
                        .animation(.easeOut(duration: 0.3), value: scanManager.exportedFileURL != nil)
                        .animation(.easeOut(duration: 0.3), value: scanManager.exportedTourURL != nil)
                        .animation(.easeOut(duration: 0.3), value: scanManager.uploadStatus)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(RentleBrand.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Text("< close")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(RentleBrand.green)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("// review")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(RentleBrand.textSecondary)
                }
            }
            .alert("Notice", isPresented: $scanManager.showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(scanManager.alertMessage ?? "")
            }
            .fullScreenCover(isPresented: $showDollhouse) {
                DollhouseViewerScreen(
                    tourBundle: scanManager.tourBundle,
                    usdzURL: scanManager.exportedFileURL
                )
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Merge & Export USDZ
            Button {
                Task {
                    await scanManager.mergeRooms()
                    await scanManager.exportUSDZ()
                    if let url = scanManager.exportedFileURL {
                        onExportComplete?(url)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if scanManager.isMerging || scanManager.isExporting {
                        ProgressView()
                            .tint(RentleBrand.background)
                            .scaleEffect(0.8)
                    }
                    Text(scanManager.isMerging ? "merging..." :
                            scanManager.isExporting ? "exporting..." : "merge_and_export />")
                        .tracking(2)
                }
                .font(.custom("Courier", size: 14).weight(.bold))
                .foregroundStyle(RentleBrand.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(hex: "E8E6E3"))
            }
            .disabled(scanManager.isMerging || scanManager.isExporting)

            // View in Dollhouse (after export)
            if scanManager.exportedFileURL != nil {
                Button {
                    showDollhouse = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "view.3d")
                            .font(.system(size: 14))
                        Text("view_dollhouse />")
                            .tracking(2)
                    }
                    .font(.custom("Courier", size: 14).weight(.bold))
                    .foregroundStyle(RentleBrand.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(
                        Rectangle()
                            .stroke(RentleBrand.blue, lineWidth: 1)
                    )
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // ── Upload to Backend (primary action after export) ──
            if scanManager.exportedFileURL != nil && scanManager.selectedApartmentId != nil {
                VStack(spacing: 8) {
                    if scanManager.uploadStatus == .uploaded {
                        HStack(spacing: 8) {
                            Text("✓")
                                .foregroundStyle(RentleBrand.green)
                            Text("uploaded to server")
                                .foregroundStyle(RentleBrand.green)
                                .tracking(1)
                        }
                        .font(.custom("Courier", size: 14).weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RentleBrand.green.opacity(0.1))
                        .overlay(
                            Rectangle()
                                .stroke(RentleBrand.green.opacity(0.5), lineWidth: 1)
                        )
                    } else {
                        Button {
                            Task {
                                let token = authManager.authToken ?? ""
                                let baseURL = authManager.activeBaseURL
                                await scanManager.uploadTour(token: token, baseURL: baseURL)
                                if scanManager.uploadStatus == .uploaded {
                                    onUploadComplete?()
                                }
                            }
                        } label: {
                            Group {
                                if scanManager.isUploading {
                                    HStack(spacing: 12) {
                                        ProgressView()
                                            .tint(RentleBrand.green)
                                            .scaleEffect(0.8)
                                        Text("uploading...")
                                            .font(.custom("Courier", size: 14))
                                            .foregroundStyle(RentleBrand.textSecondary)
                                            .tracking(2)
                                    }
                                } else {
                                    Text("upload_tour />")
                                        .font(.custom("Courier", size: 14).weight(.bold))
                                        .foregroundStyle(RentleBrand.background)
                                        .tracking(2)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(scanManager.isUploading ? Color(hex: "1A1A1A") : Color(hex: "E8E6E3"))
                            .overlay(
                                Rectangle().stroke(
                                    scanManager.isUploading ? RentleBrand.border : Color(hex: "E8E6E3"),
                                    lineWidth: 1
                                )
                            )
                        }
                        .disabled(scanManager.isUploading)
                    }

                    // Upload error message
                    if let uploadErr = scanManager.uploadError {
                        HStack(spacing: 0) {
                            Text("✗ ")
                                .font(.custom("Courier", size: 14))
                                .foregroundStyle(Color(hex: "CF6679"))
                            Text(uploadErr)
                                .font(.custom("Courier", size: 12))
                                .foregroundStyle(Color(hex: "CF6679"))
                                .tracking(0.5)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(hex: "CF6679").opacity(0.05))
                        .overlay(Rectangle().stroke(Color(hex: "CF6679").opacity(0.4), lineWidth: 1))
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Share buttons row
            if scanManager.exportedFileURL != nil {
                HStack(spacing: 12) {
                    Button {
                        scanManager.presentShareSheet()
                    } label: {
                        HStack(spacing: 6) {
                            Text("↑")
                            Text("share_file")
                                .tracking(1)
                        }
                        .font(.custom("Courier", size: 12).weight(.bold))
                        .foregroundStyle(RentleBrand.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay(
                            Rectangle()
                                .stroke(RentleBrand.border, lineWidth: 1)
                        )
                    }

                    if scanManager.exportedTourURL != nil {
                        Button {
                            if let url = scanManager.exportedTourURL {
                                TourBundleExporter.share(url: url)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("↑")
                                Text("share_tour")
                                    .tracking(1)
                            }
                            .font(.custom("Courier", size: 12).weight(.bold))
                            .foregroundStyle(RentleBrand.green)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .overlay(
                                Rectangle()
                                    .stroke(RentleBrand.green.opacity(0.5), lineWidth: 1)
                            )
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Tour Nodes Summary (Collapsible)

    @State private var showAllNodes = false

    private var tourNodesSummary: some View {
        VStack(spacing: 0) {
            // Header row with toggle
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    showAllNodes.toggle()
                }
            } label: {
                HStack {
                    Text("> tour_nodes[\(scanManager.tourBundle.nodes.count)]")
                        .font(.custom("Courier", size: 11))
                        .foregroundStyle(RentleBrand.textSecondary)
                        .tracking(1)
                    Spacer()
                    Text(showAllNodes ? "[collapse]" : "[expand]")
                        .font(.custom("Courier", size: 10))
                        .foregroundStyle(RentleBrand.textMuted)
                        .tracking(0.5)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            // Show first 3 nodes always, rest on expand
            let nodesToShow = showAllNodes
                ? scanManager.tourBundle.nodes
                : Array(scanManager.tourBundle.nodes.prefix(3))

            ForEach(nodesToShow) { node in
                HStack(spacing: 12) {
                    Text("◉")
                        .foregroundStyle(RentleBrand.green)
                    Text(node.label.lowercased().replacingOccurrences(of: " ", with: "_"))
                        .foregroundStyle(RentleBrand.textPrimary)
                    Spacer()
                    Text("(\(String(format: "%.1f", node.positionX)), \(String(format: "%.1f", node.positionY)), \(String(format: "%.1f", node.positionZ)))")
                        .foregroundStyle(RentleBrand.textMuted)
                }
                .font(.custom("Courier", size: 12))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(RentleBrand.surface)
            }

            // "and N more" indicator
            if !showAllNodes && scanManager.tourBundle.nodes.count > 3 {
                Text("// + \(scanManager.tourBundle.nodes.count - 3) more nodes")
                    .font(.custom("Courier", size: 10))
                    .foregroundStyle(RentleBrand.textMuted)
                    .tracking(0.5)
                    .padding(.vertical, 6)
            }
        }
        .background(RentleBrand.surface)
        .overlay(
            Rectangle()
                .stroke(RentleBrand.border, lineWidth: 1)
        )
    }
}

// MARK: - Hex Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
