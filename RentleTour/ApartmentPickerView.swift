// ApartmentPickerView.swift
// RentleTour
//
// Two-step apartment picker:
//   1. Buildings list (from /buildings endpoint, or search-driven fallback)
//   2. Apartment search within selected building
// UI follows Apple iOS Human Interface Guidelines.

import SwiftUI
import Combine

// MARK: - Apartment Picker Sheet

struct ApartmentPickerSheet: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    var onSelect: (ApartmentDTO) -> Void

    // Buildings mode (when /buildings endpoint exists)
    @State private var buildings: [BuildingDTO] = []
    @State private var isLoadingBuildings = true
    @State private var buildingsAvailable = true

    // Search fallback mode (when /buildings endpoint doesn't exist)
    @State private var searchQuery = ""
    @State private var searchResults: [ApartmentDTO] = []
    @State private var isSearching = false
    @State private var hasSearched = false

    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    /// Buildings filtered by local search
    private var filteredBuildings: [BuildingDTO] {
        if searchQuery.isEmpty { return buildings }
        return buildings.filter {
            $0.name.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    /// Buildings derived from search results
    private var searchBuildings: [String] {
        let names = searchResults.compactMap { $0.building }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    var body: some View {
        NavigationStack {
            Group {
                if buildingsAvailable {
                    buildingsListView
                } else {
                    searchFallbackView
                }
            }
            .navigationTitle("Select Building")
            .navigationBarTitleDisplayMode(.large)
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

    // MARK: - Buildings List (API available)

    @ViewBuilder
    private var buildingsListView: some View {
        if isLoadingBuildings {
            VStack(spacing: 16) {
                ProgressView()
                Text("Loading buildings…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(filteredBuildings) { building in
                    NavigationLink {
                        BuildingApartmentsView(
                            buildingName: building.name,
                            onSelect: { apartment in
                                onSelect(apartment)
                                dismiss()
                            }
                        )
                        .environmentObject(authManager)
                    } label: {
                        BuildingRow(name: building.name, count: building.apartmentCount)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchQuery, prompt: "Filter buildings…")
            .overlay {
                if !searchQuery.isEmpty && filteredBuildings.isEmpty {
                    ContentUnavailableView.search(text: searchQuery)
                }
            }
        }
    }

    // MARK: - Search Fallback (no /buildings endpoint)

    private var searchFallbackView: some View {
        List {
            // Search field
            Section {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search by building or apartment…", text: $searchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: searchQuery) { _, newValue in
                            debounceSearch(newValue)
                        }
                    if isSearching {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                            searchResults = []
                            hasSearched = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if searchQuery.isEmpty {
                    Text("Type a building or apartment name to search")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if searchQuery.count > 0 && searchQuery.count < 2 {
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
            if hasSearched && searchResults.isEmpty && !isSearching && errorMessage == nil {
                Section {
                    ContentUnavailableView.search(text: searchQuery)
                }
            }

            // Buildings grouped from search results
            if !searchBuildings.isEmpty {
                Section {
                    ForEach(searchBuildings, id: \.self) { building in
                        NavigationLink {
                            BuildingApartmentsView(
                                buildingName: building,
                                prefetchedApartments: searchResults.filter { $0.building == building },
                                onSelect: { apartment in
                                    onSelect(apartment)
                                    dismiss()
                                }
                            )
                            .environmentObject(authManager)
                        } label: {
                            BuildingRow(
                                name: building,
                                count: searchResults.filter { $0.building == building }.count
                            )
                        }
                    }
                } header: {
                    Text("\(searchBuildings.count) building\(searchBuildings.count == 1 ? "" : "s")")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Load Buildings

    private func loadBuildings() async {
        do {
            let token = authManager.authToken ?? ""
            let baseURL = authManager.activeBaseURL
            let result = try await ApartmentService.fetchBuildings(
                token: token,
                baseURL: baseURL
            )
            buildings = result.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            isLoadingBuildings = false
            buildingsAvailable = true
        } catch {
            // If the endpoint doesn't exist, fall back to search mode
            isLoadingBuildings = false
            buildingsAvailable = false
            print("[ApartmentPicker] Buildings endpoint unavailable, using search fallback")
        }
    }

    // MARK: - Search (fallback mode)

    private func debounceSearch(_ query: String) {
        searchTask?.cancel()

        guard query.count >= 2 else {
            searchResults = []
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
                baseURL: baseURL
            )

            await MainActor.run {
                searchResults = apartments
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

// MARK: - Building Row

struct BuildingRow: View {
    let name: String
    var count: Int? = nil

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "building.2.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.body.weight(.medium))

                if let count = count {
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

    let buildingName: String
    var prefetchedApartments: [ApartmentDTO]? = nil
    var onSelect: (ApartmentDTO) -> Void

    @State private var query = ""
    @State private var results: [ApartmentDTO] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var hasSearched = false
    @State private var searchTask: Task<Void, Never>?

    /// Show prefetched results initially, then search results
    private var displayResults: [ApartmentDTO] {
        if hasSearched || !query.isEmpty {
            return results
        }
        return prefetchedApartments ?? []
    }

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
            if !displayResults.isEmpty {
                Section {
                    ForEach(displayResults) { apartment in
                        Button {
                            onSelect(apartment)
                        } label: {
                            ApartmentRow(apartment: apartment)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("\(displayResults.count) apartment\(displayResults.count == 1 ? "" : "s")")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(buildingName)
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
                buildingName: buildingName
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
