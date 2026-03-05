// ApartmentPickerView.swift
// RentleTour
//
// Terminal-styled apartment search & picker sheet.
// Presented when the admin taps [+ new].
// Debounced search against the inspections endpoint.

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

    // Fade animations
    @State private var headerOpacity: Double = 0
    @State private var searchOpacity: Double = 0
    @State private var resultsOpacity: Double = 0

    // Debounce
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
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
                // ── Top bar ──
                topBar
                    .opacity(headerOpacity)

                // ── Section header ──
                HStack {
                    Text("// select_target")
                        .font(.custom("Courier", size: 12))
                        .foregroundStyle(RentleBrand.textSecondary)
                        .tracking(1.5)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)
                .opacity(headerOpacity)

                // ── Search field ──
                searchField
                    .padding(.horizontal, 20)
                    .opacity(searchOpacity)

                Spacer().frame(height: 16)

                // ── Results ──
                resultsList
                    .opacity(resultsOpacity)

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            startAnimations()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Text("× close")
                    .font(.custom("Courier", size: 12))
                    .foregroundStyle(RentleBrand.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RentleBrand.background.opacity(0.85))
                    .overlay(Rectangle().stroke(RentleBrand.border, lineWidth: 1))
            }

            Spacer()

            Text("// search_apartments")
                .font(.custom("Courier", size: 12))
                .foregroundStyle(RentleBrand.textSecondary)
                .tracking(1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - Search Field

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("> search")
                .font(.custom("Courier", size: 12))
                .foregroundStyle(RentleBrand.textSecondary)
                .tracking(1.5)

            HStack(spacing: 0) {
                TextField("type to search...", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.custom("Courier", size: 15))
                    .foregroundStyle(RentleBrand.textPrimary)
                    .tint(RentleBrand.green)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .onChange(of: query) { _, newValue in
                        debounceSearch(newValue)
                    }

                if isSearching {
                    ProgressView()
                        .tint(RentleBrand.green)
                        .scaleEffect(0.7)
                        .padding(.trailing, 12)
                } else if !query.isEmpty {
                    Button {
                        query = ""
                        results = []
                        hasSearched = false
                    } label: {
                        Text("[clear]")
                            .font(.custom("Courier", size: 11))
                            .foregroundStyle(RentleBrand.textSecondary)
                            .tracking(0.5)
                            .padding(.trailing, 12)
                    }
                }
            }
            .background(Color(hex: "141414"))
            .overlay(Rectangle().stroke(RentleBrand.border, lineWidth: 1))

            // Minimum characters hint
            if query.count > 0 && query.count < 2 {
                Text("> min 2 characters")
                    .font(.custom("Courier", size: 10))
                    .foregroundStyle(RentleBrand.textMuted)
                    .tracking(0.5)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        VStack(spacing: 0) {
            if let error = errorMessage {
                // Error state
                HStack(spacing: 0) {
                    Text("✗ ")
                        .font(.custom("Courier", size: 14))
                        .foregroundStyle(Color(hex: "CF6679"))
                    Text(error)
                        .font(.custom("Courier", size: 12))
                        .foregroundStyle(Color(hex: "CF6679"))
                        .tracking(0.5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(hex: "CF6679").opacity(0.05))
                .overlay(Rectangle().stroke(Color(hex: "CF6679").opacity(0.4), lineWidth: 1))
                .padding(.horizontal, 20)
            } else if hasSearched && results.isEmpty && !isSearching {
                // Empty state
                VStack(spacing: 8) {
                    Text("// no results found")
                        .font(.custom("Courier", size: 12))
                        .foregroundStyle(RentleBrand.textSecondary)
                        .tracking(1)

                    Text("try a different search term")
                        .font(.custom("Courier", size: 11))
                        .foregroundStyle(RentleBrand.textMuted)
                }
                .padding(.top, 32)
            } else {
                // Results
                ScrollView {
                    LazyVStack(spacing: 1) {
                        // Results count header
                        if !results.isEmpty {
                            HStack {
                                Text("> results[\(results.count)]")
                                    .font(.custom("Courier", size: 11))
                                    .foregroundStyle(RentleBrand.textSecondary)
                                    .tracking(1)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                        }

                        ForEach(results) { apartment in
                            ApartmentResultCard(apartment: apartment) {
                                onSelect(apartment)
                                dismiss()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
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
            // 300ms debounce
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

    // MARK: - Animations

    private func startAnimations() {
        withAnimation(.easeOut(duration: 0.4)) { headerOpacity = 1 }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.4)) { searchOpacity = 1 }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeOut(duration: 0.4)) { resultsOpacity = 1 }
        }
    }
}

// MARK: - Apartment Result Card

struct ApartmentResultCard: View {
    let apartment: ApartmentDTO
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Status dot
                Circle()
                    .fill(apartment.tenantName != nil ? RentleBrand.green : RentleBrand.orange)
                    .frame(width: 8, height: 8)
                    .shadow(
                        color: (apartment.tenantName != nil ? RentleBrand.green : RentleBrand.orange).opacity(0.5),
                        radius: 6
                    )

                // Details
                VStack(alignment: .leading, spacing: 4) {
                    // Building + apartment
                    if let building = apartment.building {
                        Text(building.lowercased().replacingOccurrences(of: " ", with: "_"))
                            .font(.custom("Courier", size: 11))
                            .foregroundStyle(RentleBrand.textSecondary)
                            .tracking(0.5)
                    }

                    Text(apartment.name)
                        .font(.custom("Courier", size: 15))
                        .foregroundStyle(RentleBrand.textPrimary)

                    // Tenant
                    HStack(spacing: 8) {
                        if let tenant = apartment.tenantName {
                            Text("tenant: \(tenant.lowercased())")
                                .foregroundStyle(RentleBrand.green.opacity(0.7))
                        } else {
                            Text("vacant")
                                .foregroundStyle(RentleBrand.orange)
                        }
                    }
                    .font(.custom("Courier", size: 11))
                }

                Spacer()

                // Select arrow
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
}
