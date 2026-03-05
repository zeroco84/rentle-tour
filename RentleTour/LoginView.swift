// LoginView.swift
// RentleTour
//
// Terminal-styled login screen — exact match to Rentle-Assist.
// Two-step: subdomain → credentials.

import SwiftUI

// MARK: - Login Screen

struct LoginScreen: View {
    @EnvironmentObject var authManager: AuthManager

    @State private var subdomain = ""
    @State private var email = ""
    @State private var password = ""
    @State private var obscurePassword = true
    @State private var subdomainConfirmed = false

    // Typing animation
    @State private var typedTitle = ""
    @State private var titleDone = false
    @State private var cursorVisible = true

    // Fade animations
    @State private var logoOpacity: Double = 0
    @State private var titleOpacity: Double = 0
    @State private var formOpacity: Double = 0
    @State private var footerOpacity: Double = 0

    private let fullTitle = "r e n t l e . a i"

    var body: some View {
        ZStack {
            // Background
            Color(hex: "0A0A0A").ignoresSafeArea()

            // Subtle blue glow — top right
            RadialGradient(
                colors: [Color(hex: "1a237e").opacity(0.08), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: UIScreen.main.bounds.width * 1.8
            )
            .ignoresSafeArea()

            // Subtle blue glow — bottom left
            RadialGradient(
                colors: [Color(hex: "1a237e").opacity(0.06), .clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: UIScreen.main.bounds.width * 1.8
            )
            .ignoresSafeArea()

            VStack {
                Spacer()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // ── ASCII Art Logo ──
                        asciiLogo
                            .opacity(logoOpacity)

                        Spacer().frame(height: 32)

                        // ── Brand name (typed) ──
                        HStack(spacing: 0) {
                            Text(typedTitle)
                                .font(.custom("Courier", size: 28))
                                .foregroundStyle(Color(hex: "E0E0E0"))
                                .tracking(2)

                            if !titleDone {
                                Text("█")
                                    .font(.custom("Courier", size: 28))
                                    .foregroundStyle(Color(hex: "4CAF50"))
                                    .opacity(cursorVisible ? 1 : 0)
                            }
                        }
                        .opacity(titleOpacity)

                        Spacer().frame(height: 12)

                        // ── Subtitle ──
                        Text("// tour_application.access")
                            .font(.custom("Courier", size: 13))
                            .foregroundStyle(Color(hex: "5C6370"))
                            .tracking(1.5)
                            .opacity(titleOpacity)

                        Spacer().frame(height: 48)

                        // ── Step 1: Subdomain or Step 2: Login ──
                        Group {
                            if subdomainConfirmed {
                                loginForm
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .offset(x: 15)),
                                        removal: .opacity.combined(with: .offset(x: -15))
                                    ))
                            } else {
                                subdomainForm
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .offset(x: -15)),
                                        removal: .opacity.combined(with: .offset(x: -15))
                                    ))
                            }
                        }
                        .opacity(formOpacity)

                        Spacer().frame(height: 24)

                        // ── Sign up CTA ──
                        VStack(spacing: 2) {
                            HStack(spacing: 0) {
                                Text("Not using ")
                                    .foregroundStyle(Color(hex: "5C6370"))
                                Text("Rentle.ai")
                                    .foregroundStyle(Color(hex: "4CAF50"))
                                    .underline(color: Color(hex: "4CAF50"))
                                Text("? Sign up now to the")
                                    .foregroundStyle(Color(hex: "5C6370"))
                            }
                            Text("automated intelligence PMS.")
                                .foregroundStyle(Color(hex: "5C6370"))
                        }
                        .font(.custom("Courier", size: 12))
                        .tracking(0.5)
                        .opacity(footerOpacity)

                        Spacer().frame(height: 24)

                        // ── Status indicator ──
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color(hex: "4CAF50"))
                                .frame(width: 8, height: 8)
                                .shadow(color: Color(hex: "4CAF50").opacity(0.5), radius: 8, x: 0, y: 0)

                            Text("status: active")
                                .font(.custom("Courier", size: 12))
                                .foregroundStyle(Color(hex: "5C6370"))
                                .tracking(1.5)
                        }
                        .opacity(footerOpacity)
                    }
                    .padding(.horizontal, 36)
                }

                Spacer()

                // ── Footer ──
                HStack {
                    Text("v1.0.0  tour_app")
                        .font(.custom("Courier", size: 10))
                        .foregroundStyle(Color(hex: "3A3A3A"))
                        .tracking(1)

                    Spacer()

                    Text(EnvironmentConfig.isStaging ? "env: staging" : "sec_v1.0 encrypted")
                        .font(.custom("Courier", size: 10))
                        .foregroundStyle(
                            EnvironmentConfig.isStaging
                                ? Color(hex: "FF9F0A").opacity(0.6)
                                : Color(hex: "4CAF50").opacity(0.4)
                        )
                        .tracking(1)
                }
                .opacity(footerOpacity)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Pre-fill saved subdomain
            if let saved = authManager.getSavedSubdomain() {
                subdomain = saved
            }
            startAnimations()
        }
        .task {
            // Cursor blink
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 600_000_000)
                cursorVisible.toggle()
            }
        }
    }

    // MARK: - ASCII Logo

    private var asciiLogo: some View {
        VStack(spacing: 0) {
            Text("┌──────────────────┐")
            Text("│  ╔══╗  ╔══╗  ╔══╗│")
            Text("│  ║▓▓║  ║░░║  ║▓▓║│")
            Text("│  ╚══╝  ╚══╝  ╚══╝│")
            Text("│  ═══════════════ ││")
            Text("│  ▓▓▓▓▓ ░░░ ▓▓▓▓ ││")
            Text("└──────────────────┘")
        }
        .font(.custom("Courier", size: 14))
        .lineSpacing(0)
        .foregroundStyle(Color(hex: "4A4A4A").opacity(0.8))
        .padding(20)
        .overlay(Rectangle().stroke(Color(hex: "2A2A2A"), lineWidth: 1))
    }

    // MARK: - Subdomain Form (Step 1)

    private var subdomainForm: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header comment
            Text("// connect to your instance")
                .font(.custom("Courier", size: 12))
                .foregroundStyle(Color(hex: "E0E0E0"))
                .tracking(1.5)
                .padding(.bottom, 20)

            // Label
            Text("> subdomain")
                .font(.custom("Courier", size: 12))
                .foregroundStyle(Color(hex: "E0E0E0"))
                .tracking(1.5)
                .padding(.bottom, 6)

            // Subdomain field + suffix
            HStack(spacing: 0) {
                TextField("vesta", text: $subdomain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.custom("Courier", size: 15))
                    .foregroundStyle(Color(hex: "E0E0E0"))
                    .tint(Color(hex: "4CAF50"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(Color(hex: "141414"))
                    .overlay(Rectangle().stroke(Color(hex: "1E1E1E"), lineWidth: 1))
                    .onSubmit { handleSubdomainContinue() }
                    .onChange(of: subdomain) { _, newVal in
                        subdomain = newVal.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
                    }

                // .rentle.ai suffix
                Text(".rentle.ai")
                    .font(.custom("Courier", size: 15))
                    .foregroundStyle(Color(hex: "E0E0E0"))
                    .tracking(1)
                    .padding(.horizontal, 12)
                    .frame(height: 48)
                    .background(Color(hex: "141414"))
                    .overlay(
                        Rectangle()
                            .stroke(Color(hex: "1E1E1E"), lineWidth: 1)
                    )
            }

            Spacer().frame(height: 28)

            // Continue button — matches E8E6E3 bg, 0A0A0A text
            Button(action: handleSubdomainContinue) {
                Text("connect />")
                    .font(.custom("Courier", size: 14).weight(.bold))
                    .foregroundStyle(Color(hex: "0A0A0A"))
                    .tracking(2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color(hex: "E8E6E3"))
            }
            .disabled(subdomain.trimmingCharacters(in: .whitespaces).count < 2)
            .opacity(subdomain.trimmingCharacters(in: .whitespaces).count < 2 ? 0.4 : 1)
        }
        .padding(24)
        .background(Color(hex: "0F0F0F"))
        .overlay(Rectangle().stroke(Color(hex: "1E1E1E"), lineWidth: 1))
    }

    // MARK: - Login Form (Step 2)

    private var loginForm: some View {
        let isLoading = authManager.state == .loading

        return VStack(alignment: .leading, spacing: 0) {
            // Header: back + instance
            HStack {
                Button(action: handleBackToSubdomain) {
                    Text("< back")
                        .font(.custom("Courier", size: 12))
                        .foregroundStyle(Color(hex: "4CAF50"))
                        .tracking(1)
                }
                .disabled(isLoading)

                Spacer()

                Text("\(EnvironmentConfig.isStaging ? "staging." : "")\(subdomain.trimmingCharacters(in: .whitespaces).lowercased()).rentle.ai")
                    .font(.custom("Courier", size: 11))
                    .foregroundStyle(Color(hex: "4CAF50").opacity(0.6))
                    .tracking(0.5)
            }
            .padding(.bottom, 16)

            // Header comment
            Text("// authentication")
                .font(.custom("Courier", size: 12))
                .foregroundStyle(Color(hex: "5C6370"))
                .tracking(1.5)
                .padding(.bottom, 20)

            // Error message
            if let errorMsg = authManager.errorMessage {
                HStack(spacing: 0) {
                    Text("✗ ")
                        .font(.custom("Courier", size: 14))
                        .foregroundStyle(Color(hex: "CF6679"))
                    Text(errorMsg)
                        .font(.custom("Courier", size: 12))
                        .foregroundStyle(Color(hex: "CF6679"))
                        .tracking(0.5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(hex: "CF6679").opacity(0.05))
                .overlay(Rectangle().stroke(Color(hex: "CF6679").opacity(0.4), lineWidth: 1))
                .padding(.bottom, 16)
            }

            // Email field
            terminalField(label: "> email", text: $email, placeholder: "_", keyboardType: .emailAddress, contentType: .emailAddress)
                .padding(.bottom, 16)

            // Password field
            VStack(alignment: .leading, spacing: 6) {
                Text("> password")
                    .font(.custom("Courier", size: 12))
                    .foregroundStyle(Color(hex: "5C6370"))
                    .tracking(1.5)

                HStack(spacing: 0) {
                    Group {
                        if obscurePassword {
                            SecureField("_", text: $password)
                        } else {
                            TextField("_", text: $password)
                        }
                    }
                    .textContentType(.password)
                    .font(.custom("Courier", size: 15))
                    .foregroundStyle(Color(hex: "E0E0E0"))
                    .tint(Color(hex: "4CAF50"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)

                    Button {
                        obscurePassword.toggle()
                    } label: {
                        Text(obscurePassword ? "[show]" : "[hide]")
                            .font(.custom("Courier", size: 11))
                            .foregroundStyle(Color(hex: "5C6370"))
                            .tracking(0.5)
                            .padding(.trailing, 12)
                    }
                }
                .background(Color(hex: "141414"))
                .overlay(Rectangle().stroke(Color(hex: "1E1E1E"), lineWidth: 1))
            }

            Spacer().frame(height: 28)

            // Login button — loading state matches Rentle-Assist
            Button(action: handleLogin) {
                Group {
                    if isLoading {
                        HStack(spacing: 12) {
                            ProgressView()
                                .tint(Color(hex: "4CAF50"))
                                .scaleEffect(0.8)
                            Text("authenticating...")
                                .font(.custom("Courier", size: 14))
                                .foregroundStyle(Color(hex: "5C6370"))
                                .tracking(2)
                        }
                    } else {
                        Text("proceed />")
                            .font(.custom("Courier", size: 14).weight(.bold))
                            .foregroundStyle(Color(hex: "0A0A0A"))
                            .tracking(2)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(isLoading ? Color(hex: "1A1A1A") : Color(hex: "E8E6E3"))
                .overlay(
                    Rectangle().stroke(
                        isLoading ? Color(hex: "2A2A2A") : Color(hex: "E8E6E3"),
                        lineWidth: 1
                    )
                )
            }
            .disabled(isLoading || email.isEmpty || password.isEmpty)
            .opacity(email.isEmpty || password.isEmpty ? 0.4 : 1)
        }
        .padding(24)
        .background(Color(hex: "0F0F0F"))
        .overlay(Rectangle().stroke(Color(hex: "1E1E1E"), lineWidth: 1))
    }

    // MARK: - Terminal Field Helper

    private func terminalField(
        label: String,
        text: Binding<String>,
        placeholder: String = "_",
        keyboardType: UIKeyboardType = .default,
        contentType: UITextContentType? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.custom("Courier", size: 12))
                .foregroundStyle(Color(hex: "5C6370"))
                .tracking(1.5)

            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboardType)
                .textContentType(contentType)
                .font(.custom("Courier", size: 15))
                .foregroundStyle(Color(hex: "E0E0E0"))
                .tint(Color(hex: "4CAF50"))
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(Color(hex: "141414"))
                .overlay(Rectangle().stroke(Color(hex: "1E1E1E"), lineWidth: 1))
        }
    }

    // MARK: - Actions

    private func handleSubdomainContinue() {
        let trimmed = subdomain.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return }
        authManager.setSubdomain(trimmed)
        withAnimation(.easeOut(duration: 0.35)) {
            subdomainConfirmed = true
        }
    }

    private func handleBackToSubdomain() {
        withAnimation(.easeOut(duration: 0.35)) {
            subdomainConfirmed = false
        }
    }

    private func handleLogin() {
        Task {
            let success = await authManager.login(
                email: email.trimmingCharacters(in: .whitespaces),
                password: password
            )
            if success {
                authManager.saveSubdomain(subdomain.trimmingCharacters(in: .whitespaces).lowercased())
            }
        }
    }

    // MARK: - Animations (matching Rentle-Assist intervals)

    private func startAnimations() {
        // Logo: 0%–30%
        withAnimation(.easeOut(duration: 0.75)) { logoOpacity = 1 }

        // Title: 15%–50%
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.375) {
            withAnimation(.easeOut(duration: 0.875)) { titleOpacity = 1 }
        }

        // Form: 40%–75%
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.875)) { formOpacity = 1 }
        }

        // Footer: 65%–100%
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.625) {
            withAnimation(.easeOut(duration: 0.875)) { footerOpacity = 1 }
        }

        // Start typing animation at 600ms
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            for i in 0...fullTitle.count {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: 45_000_000)
                typedTitle = String(fullTitle.prefix(i))
            }
            titleDone = true
        }
    }
}
