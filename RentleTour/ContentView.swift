// ContentView.swift
// RentleTour
//
// Main app navigation: Property list → Scanning → Review / Export.
// UI follows Apple iOS Human Interface Guidelines.

import SwiftUI

// MARK: - Tour Filter

enum TourFilter: String, CaseIterable, Identifiable {
    case pending = "Pending"
    case completed = "Completed"
    case archived = "Archived"

    var id: String { rawValue }
}

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
    var isArchived: Bool = false

    /// Computed tour filter based on upload status and archive flag
    var tourFilter: TourFilter {
        if isArchived { return .archived }
        if uploadStatus == .uploaded { return .completed }
        return .pending
    }
}

// MARK: - Rentle Brand Colors (Splash / Login only)

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

// MARK: - Content View (Dashboard)

struct ContentView: View {
    @EnvironmentObject var scanManager: ScanManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var networkMonitor: NetworkMonitor

    @State private var properties: [Property] = []
    @State private var showScanner = false
    @State private var showReview = false
    @State private var showUnsupportedAlert = false
    @State private var showApartmentPicker = false
    @State private var showPropertyActions = false
    @State private var activePropertyIndex: Int?
    @State private var showSyncCenter = false
    @State private var showTourViewer = false
    @State private var activeTourData: ApartmentTourData? = nil
    @State private var showBrowseTours = false
    @State private var availableTours: [ApartmentTourData] = []
    @State private var tourAlertMessage: String? = nil
    @State private var selectedFilter: TourFilter = .pending

    /// Properties filtered by the selected pill tab
    private var filteredProperties: [Property] {
        properties.filter { $0.tourFilter == selectedFilter }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Pill segmented control
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(TourFilter.allCases) { filter in
                        Text(filter.rawValue)
                            .tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                // Content
                if filteredProperties.isEmpty {
                    emptyStateForFilter
                } else {
                    propertyListView
                }
            }
            .navigationTitle("Tours")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sign Out", role: .destructive) {
                        authManager.logout()
                    }
                    .font(.subheadline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showSyncCenter = true
                        } label: {
                            Image(systemName: "icloud.and.arrow.up")
                        }

                        Button {
                            startNewProperty()
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
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
            .sheet(isPresented: $showSyncCenter) {
                SyncCenterView(networkMonitor: networkMonitor)
            }
            .sheet(isPresented: $showTourViewer) {
                if let tourData = activeTourData {
                    ProcessedTourViewer(tourData: tourData)
                }
            }
            .sheet(isPresented: $showBrowseTours) {
                TourBrowserSheet(
                    tours: availableTours,
                    onSelect: { tourData in
                        activeTourData = tourData
                        showBrowseTours = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showTourViewer = true
                        }
                    }
                )
            }
            .alert("LiDAR Not Available", isPresented: $showUnsupportedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This app requires a LiDAR-equipped device (iPhone 12 Pro or later, or iPad Pro).")
            }
            .alert("Tour", isPresented: Binding(
                get: { tourAlertMessage != nil },
                set: { if !$0 { tourAlertMessage = nil } }
            )) {
                Button("OK", role: .cancel) { tourAlertMessage = nil }
            } message: {
                Text(tourAlertMessage ?? "")
            }
            .confirmationDialog(
                "Property Options",
                isPresented: $showPropertyActions,
                titleVisibility: .visible
            ) {
                Button("View Results") {
                    showReview = true
                }
                Button("View Existing Tour") {
                    if let idx = activePropertyIndex {
                        fetchAndViewTour(apartmentId: properties[idx].apartmentId)
                    }
                }
                Button("Add More Rooms") {
                    guard DeviceCapability.supportsLiDAR else {
                        showUnsupportedAlert = true
                        return
                    }
                    showScanner = true
                }
                Button("Re-scan", role: .destructive) {
                    scanManager.clearAll()
                    if let idx = activePropertyIndex {
                        properties[idx].roomCount = 0
                        properties[idx].uploadStatus = .pending
                        properties[idx].isArchived = false
                    }
                    guard DeviceCapability.supportsLiDAR else {
                        showUnsupportedAlert = true
                        return
                    }
                    showScanner = true
                }
                if let idx = activePropertyIndex {
                    if properties[idx].isArchived {
                        Button("Restore from Archive") {
                            withAnimation { properties[idx].isArchived = false }
                        }
                    } else if properties[idx].uploadStatus == .uploaded {
                        Button("Archive Tour", role: .destructive) {
                            withAnimation { properties[idx].isArchived = true }
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Empty States

    private var emptyStateForFilter: some View {
        Group {
            switch selectedFilter {
            case .pending:
                ContentUnavailableView {
                    Label("No Pending Tours", systemImage: "camera.viewfinder")
                } description: {
                    Text("Tap the + button to select an apartment and start scanning.")
                } actions: {
                    Button {
                        startNewProperty()
                    } label: {
                        Text("New Tour")
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .completed:
                ContentUnavailableView {
                    Label("No Completed Tours", systemImage: "checkmark.circle")
                } description: {
                    Text("Tours will appear here once uploaded and processed.")
                }
            case .archived:
                ContentUnavailableView {
                    Label("No Archived Tours", systemImage: "archivebox")
                } description: {
                    Text("Archived tours from previous scans will appear here.")
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Property List

    private var propertyListView: some View {
        List {
            ForEach(filteredProperties) { property in
                PropertyRow(property: property)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let index = properties.firstIndex(where: { $0.id == property.id }) {
                            activePropertyIndex = index
                            scanManager.selectedApartmentId = property.apartmentId
                            scanManager.selectedApartmentLabel = property.name

                            if property.roomCount > 0 || property.uploadStatus == .uploaded || property.isArchived {
                                showPropertyActions = true
                            } else {
                                scanManager.clearAll()
                                guard DeviceCapability.supportsLiDAR else {
                                    showUnsupportedAlert = true
                                    return
                                }
                                showScanner = true
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if property.isArchived {
                            Button {
                                if let index = properties.firstIndex(where: { $0.id == property.id }) {
                                    withAnimation { properties[index].isArchived = false }
                                }
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.blue)
                        } else {
                            Button {
                                if let index = properties.firstIndex(where: { $0.id == property.id }) {
                                    withAnimation { properties[index].isArchived = true }
                                }
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .tint(.orange)
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Actions

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

    /// Fetches tour data for an apartment and opens the viewer if available.
    private func fetchAndViewTour(apartmentId: Int) {
        Task {
            let token = authManager.authToken ?? ""
            let baseURL = authManager.activeBaseURL

            do {
                let tourData = try await TourService.fetchTourData(
                    apartmentId: apartmentId,
                    token: token,
                    baseURL: baseURL
                )

                if tourData.hasTour {
                    activeTourData = tourData
                    showTourViewer = true
                } else if tourData.isProcessing {
                    tourAlertMessage = "Tour is still being processed. Please check back shortly."
                } else {
                    tourAlertMessage = "No completed tour available for this apartment yet."
                }
            } catch {
                tourAlertMessage = "Failed to load tour: \(error.localizedDescription)"
            }
        }
    }

    /// Fetches all apartments with completed tours for the Browse Tours feature.
    private func fetchAvailableTours() {
        Task {
            let token = authManager.authToken ?? ""
            let baseURL = authManager.activeBaseURL

            do {
                availableTours = try await TourService.fetchApartmentsWithTours(
                    token: token,
                    baseURL: baseURL
                )
                showBrowseTours = true
            } catch {
                tourAlertMessage = "Failed to load tours: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Tour Browser Sheet

struct TourBrowserSheet: View {
    let tours: [ApartmentTourData]
    var onSelect: (ApartmentTourData) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if tours.isEmpty {
                    ContentUnavailableView {
                        Label("No Tours", systemImage: "view.3d")
                    } description: {
                        Text("No completed tours are available yet. Upload a scan to get started.")
                    }
                } else {
                    List(tours, id: \.id) { tour in
                        Button {
                            onSelect(tour)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "view.3d")
                                    .font(.title2)
                                    .foregroundStyle(.tint)
                                    .frame(width: 40, height: 40)
                                    .background(.tint.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tour.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    if let building = tour.building {
                                        Text(building)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Browse Tours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Property Row

struct PropertyRow: View {
    let property: Property

    var body: some View {
        HStack(spacing: 14) {
            // Status icon
            Image(systemName: statusIcon)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 32)

            // Details
            VStack(alignment: .leading, spacing: 3) {
                if let building = property.buildingName {
                    Text(building)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(property.name)
                    .font(.body)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    Label("\(property.roomCount)", systemImage: "cube.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    statusBadge
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch property.uploadStatus {
        case .uploaded: return "checkmark.circle.fill"
        case .uploading: return "arrow.up.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .pending:
            return property.exportedURL != nil ? "checkmark.circle" : "circle.dashed"
        }
    }

    private var statusColor: Color {
        switch property.uploadStatus {
        case .uploaded: return .green
        case .uploading: return .blue
        case .failed: return .red
        case .pending:
            return property.exportedURL != nil ? .green : .orange
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch property.uploadStatus {
        case .uploaded:
            Label("Uploaded", systemImage: "checkmark.icloud.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .uploading:
            Label("Uploading", systemImage: "arrow.up.circle")
                .font(.caption2)
                .foregroundStyle(.blue)
        case .failed:
            Label("Failed", systemImage: "xmark.circle")
                .font(.caption2)
                .foregroundStyle(.red)
        case .pending:
            if property.exportedURL != nil {
                Label("Exported", systemImage: "checkmark")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                Label("Pending", systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.orange)
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
    @State private var showAllNodes = false

    var body: some View {
        NavigationStack {
            List {
                // Summary section
                Section {
                    if let label = scanManager.selectedApartmentLabel {
                        LabeledContent("Apartment", value: label)
                    }

                    let roomCount = scanManager.capturedRooms.count
                    let nodeCount = scanManager.tourBundle.nodes.count
                    let textureCount = scanManager.tourBundle.textureFrames.count
                    LabeledContent("Rooms", value: "\(roomCount)")
                    LabeledContent("360° Nodes", value: "\(nodeCount)")
                    LabeledContent("Textures", value: "\(textureCount)")
                } header: {
                    Text("Scan Summary")
                }

                // Actions section
                Section {
                    // Merge & Export
                    Button {
                        Task {
                            await scanManager.mergeRooms()
                            await scanManager.exportUSDZ()
                            if let url = scanManager.exportedFileURL {
                                onExportComplete?(url)
                            }
                        }
                    } label: {
                        HStack {
                            Label(
                                scanManager.isMerging ? "Merging…" :
                                scanManager.isExporting ? "Exporting…" : "Merge & Export",
                                systemImage: "square.and.arrow.down.on.square"
                            )
                            Spacer()
                            if scanManager.isMerging || scanManager.isExporting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(scanManager.isMerging || scanManager.isExporting)

                    // View Dollhouse
                    if scanManager.exportedFileURL != nil {
                        Button {
                            showDollhouse = true
                        } label: {
                            Label("View 3D Model", systemImage: "view.3d")
                        }
                    }

                    // Upload
                    if scanManager.exportedFileURL != nil && scanManager.selectedApartmentId != nil {
                        if scanManager.uploadStatus == .uploaded {
                            HStack {
                                Label("Uploaded", systemImage: "checkmark.icloud.fill")
                                    .foregroundStyle(.green)
                                Spacer()
                                if let label = scanManager.selectedApartmentLabel {
                                    Text(label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
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
                                HStack {
                                    Label(
                                        scanManager.isUploading ? "Uploading…" : "Upload Tour",
                                        systemImage: "icloud.and.arrow.up"
                                    )
                                    Spacer()
                                    if scanManager.isUploading {
                                        ProgressView()
                                    }
                                }
                            }
                            .disabled(scanManager.isUploading)
                        }

                        // Upload error
                        if let uploadErr = scanManager.uploadError {
                            Label(uploadErr, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    // Share
                    if scanManager.exportedFileURL != nil {
                        Button {
                            scanManager.presentShareSheet()
                        } label: {
                            Label("Share File", systemImage: "square.and.arrow.up")
                        }

                        if scanManager.exportedTourURL != nil {
                            Button {
                                if let url = scanManager.exportedTourURL {
                                    TourBundleExporter.share(url: url)
                                }
                            } label: {
                                Label("Share Tour Bundle", systemImage: "square.and.arrow.up.on.square")
                            }
                        }
                    }
                } header: {
                    Text("Actions")
                }

                // Rooms section
                if !scanManager.capturedRooms.isEmpty {
                    Section {
                        ForEach(Array(scanManager.capturedRooms.enumerated()), id: \.offset) { index, _ in
                            let name = scanManager.roomNames[index] ?? "Room \(index + 1)"
                            Label(name, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.primary)
                        }
                    } header: {
                        Text("Captured Rooms")
                    }
                }

                // Tour Nodes section
                if !scanManager.tourBundle.nodes.isEmpty {
                    Section {
                        let nodesToShow = showAllNodes
                            ? scanManager.tourBundle.nodes
                            : Array(scanManager.tourBundle.nodes.prefix(3))

                        ForEach(nodesToShow) { node in
                            HStack {
                                Label(node.label, systemImage: "mappin.circle.fill")
                                Spacer()
                                Text("(\(String(format: "%.1f", node.positionX)), \(String(format: "%.1f", node.positionY)), \(String(format: "%.1f", node.positionZ)))")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if scanManager.tourBundle.nodes.count > 3 {
                            Button {
                                withAnimation {
                                    showAllNodes.toggle()
                                }
                            } label: {
                                Text(showAllNodes
                                     ? "Show Less"
                                     : "\(scanManager.tourBundle.nodes.count - 3) more nodes…")
                                    .font(.subheadline)
                            }
                        }
                    } header: {
                        Text("360° Nodes (\(scanManager.tourBundle.nodes.count))")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
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
