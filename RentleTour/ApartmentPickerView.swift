// ApartmentPickerView.swift
// RentleTour
//
// Two-step apartment picker:
//   1. Search for a building
//   2. Browse apartments within that building
// UI follows Apple iOS Human Interface Guidelines.

import SwiftUI
import Combine

// MARK: - Apartment Picker Sheet

struct ApartmentPickerSheet: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    var onSelect: (ApartmentDTO) -> Void

    @State private var query = ""
    @State private var results: [ApartmentDTO] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var hasSearched = false
    @State private var searchTask: Task<Void, Never>?

    /// Unique buildings extracted from search results
    private var buildings: [String] {
        let names = results.compactMap { $0.building }
        // Preserve order, deduplicate
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    var body: some View {
        NavigationStack {
            List {
                // Search field
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search by building name…", text: $query)
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
                        Text("Type at least 2 characters to search")
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

                // Buildings list
                if !buildings.isEmpty {
                    Section {
                        ForEach(buildings, id: \.self) { building in
                            NavigationLink {
                                BuildingApartmentsView(
                                    buildingName: building,
                                    apartments: results.filter { $0.building == building },
                                    onSelect: { apartment in
                                        onSelect(apartment)
                                        dismiss()
                                    }
                                )
                            } label: {
                                BuildingRow(
                                    name: building,
                                    apartmentCount: results.filter { $0.building == building }.count
                                )
                            }
                        }
                    } header: {
                        Text("\(buildings.count) building\(buildings.count == 1 ? "" : "s")")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Select Building")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
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
                baseURL: baseURL
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

// MARK: - Building Row

struct BuildingRow: View {
    let name: String
    let apartmentCount: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "building.2.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.body.weight(.medium))

                Text("\(apartmentCount) apartment\(apartmentCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Building Apartments View

struct BuildingApartmentsView: View {
    let buildingName: String
    let apartments: [ApartmentDTO]
    var onSelect: (ApartmentDTO) -> Void

    @State private var searchText = ""

    private var filteredApartments: [ApartmentDTO] {
        if searchText.isEmpty {
            return apartments
        }
        return apartments.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            ForEach(filteredApartments) { apartment in
                Button {
                    onSelect(apartment)
                } label: {
                    ApartmentRow(apartment: apartment)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(buildingName)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Filter apartments…")
    }
}

// MARK: - Apartment Row

struct ApartmentRow: View {
    let apartment: ApartmentDTO

    var body: some View {
        HStack(spacing: 14) {
            // Apartment type icon
            Image(systemName: "door.left.hand.open")
                .font(.title2)
                .foregroundStyle(.green)
                .frame(width: 32)

            // Details — address and type only (no tenant info)
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
