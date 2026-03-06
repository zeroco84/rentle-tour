// ApartmentPickerView.swift
// RentleTour
//
// Two-step apartment picker:
//   1. Buildings list (loaded on appear, filterable)
//   2. Apartment search within selected building
// UI follows Apple iOS Human Interface Guidelines.

import SwiftUI
import Combine

// MARK: - Apartment Picker Sheet

struct ApartmentPickerSheet: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    var onSelect: (ApartmentDTO) -> Void

    @State private var buildings: [BuildingDTO] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""

    /// Buildings filtered by local search text
    private var filteredBuildings: [BuildingDTO] {
        if searchText.isEmpty {
            return buildings
        }
        return buildings.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading buildings…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else if let error = errorMessage {
                    ContentUnavailableView {
                        Label("Unable to Load", systemImage: "exclamationmark.triangle.fill")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") {
                            Task { await loadBuildings() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if filteredBuildings.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else if buildings.isEmpty {
                    ContentUnavailableView {
                        Label("No Buildings", systemImage: "building.2")
                    } description: {
                        Text("No buildings found for this account.")
                    }
                } else {
                    List {
                        ForEach(filteredBuildings) { building in
                            NavigationLink {
                                BuildingApartmentsView(
                                    building: building,
                                    onSelect: { apartment in
                                        onSelect(apartment)
                                        dismiss()
                                    }
                                )
                                .environmentObject(authManager)
                            } label: {
                                BuildingRow(building: building)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Select Building")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Filter buildings…")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                await loadBuildings()
            }
        }
    }

    // MARK: - Load Buildings

    private func loadBuildings() async {
        isLoading = true
        errorMessage = nil

        do {
            let token = authManager.authToken ?? ""
            let baseURL = authManager.activeBaseURL
            let result = try await ApartmentService.fetchBuildings(
                token: token,
                baseURL: baseURL
            )

            buildings = result.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

// MARK: - Building Row

struct BuildingRow: View {
    let building: BuildingDTO

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "building.2.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(building.name)
                    .font(.body.weight(.medium))

                if let count = building.apartmentCount {
                    Text("\(count) apartment\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Building Apartments View

struct BuildingApartmentsView: View {
    @EnvironmentObject var authManager: AuthManager

    let building: BuildingDTO
    var onSelect: (ApartmentDTO) -> Void

    @State private var query = ""
    @State private var results: [ApartmentDTO] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var hasSearched = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        List {
            // Search field
            Section {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search apartments…", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: query) { _, newValue in
                            debounceSearch(newValue)
                        }
                    if isSearching {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if !query.isEmpty {
                        Button {
                            query = ""
                            results = []
                            hasSearched = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if query.count > 0 && query.count < 2 {
                    Text("Type at least 2 characters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Error
            if let error = errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            // Empty state
            if hasSearched && results.isEmpty && !isSearching && errorMessage == nil {
                Section {
                    ContentUnavailableView.search(text: query)
                }
            }

            // Results
            if !results.isEmpty {
                Section {
                    ForEach(results) { apartment in
                        Button {
                            onSelect(apartment)
                        } label: {
                            ApartmentRow(apartment: apartment)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("\(results.count) apartment\(results.count == 1 ? "" : "s")")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(building.name)
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Debounced Search

    private func debounceSearch(_ query: String) {
        searchTask?.cancel()

        guard query.count >= 2 else {
            results = []
            hasSearched = false
            errorMessage = nil
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(query)
        }
    }

    private func performSearch(_ query: String) async {
        await MainActor.run {
            isSearching = true
            errorMessage = nil
        }

        do {
            let token = authManager.authToken ?? ""
            let baseURL = authManager.activeBaseURL
            let apartments = try await ApartmentService.searchApartments(
                query: query,
                token: token,
                baseURL: baseURL,
                buildingName: building.name
            )

            await MainActor.run {
                results = apartments
                isSearching = false
                hasSearched = true
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isSearching = false
                hasSearched = true
            }
        }
    }
}

// MARK: - Apartment Row

struct ApartmentRow: View {
    let apartment: ApartmentDTO

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "door.left.hand.open")
                .font(.title2)
                .foregroundStyle(.green)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(apartment.name)
                    .font(.body.weight(.medium))

                if let tourStatus = apartment.tourProcessingStatus {
                    tourStatusBadge(tourStatus)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func tourStatusBadge(_ status: String) -> some View {
        switch status {
        case "completed":
            Label("Tour ready", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case "processing", "queued":
            Label("Processing…", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.blue)
        case "failed":
            Label("Tour failed", systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.red)
        default:
            EmptyView()
        }
    }
}
