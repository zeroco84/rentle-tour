// ApartmentPickerView.swift
// RentleTour
//
// Apartment search & picker sheet.
// Presented when the admin taps + new.
// Debounced search against the inspections endpoint.
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

    // Debounce
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                // Search field section
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

                    // Minimum characters hint
                    if query.count > 0 && query.count < 2 {
                        Text("Type at least 2 characters to search")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Error state
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
                                dismiss()
                            } label: {
                                ApartmentRow(apartment: apartment)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("\(results.count) results")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Select Apartment")
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

// MARK: - Apartment Row

struct ApartmentRow: View {
    let apartment: ApartmentDTO

    var body: some View {
        HStack(spacing: 14) {
            // Status icon
            Image(systemName: apartment.tenantName != nil ? "person.circle.fill" : "circle.dashed")
                .font(.title2)
                .foregroundStyle(apartment.tenantName != nil ? .green : .orange)
                .frame(width: 32)

            // Details
            VStack(alignment: .leading, spacing: 3) {
                if let building = apartment.building {
                    Text(building)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(apartment.name)
                    .font(.body.weight(.medium))

                if let tenant = apartment.tenantName {
                    Label(tenant, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Vacant")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
