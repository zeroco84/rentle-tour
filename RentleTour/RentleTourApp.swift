// RentleTourApp.swift
// RentleTour — Matterport-style 3D Room Scanner for Landlords
//
// Entry point. Gates the app behind authentication.
// Splash screen matches Rentle-Assist boot sequence exactly.

import SwiftUI
import UserNotifications

// MARK: - App Delegate (Background Upload Session Handling)

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundUploadManager.shared.setCompletionHandler(completionHandler, for: identifier)
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Request notification permissions for upload completion
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                print("[RentleTour] ✓ Notification permission granted")
            }
        }
        return true
    }
}

@main
struct RentleTourApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var scanManager = ScanManager()
    @StateObject private var authManager = AuthManager()
    @StateObject private var networkMonitor = NetworkMonitor()

    @State private var isCheckingAuth = true

    var body: some Scene {
        WindowGroup {
            Group {
                if isCheckingAuth {
                    SplashScreen(authManager: authManager, onComplete: {
                        isCheckingAuth = false
                    })
                } else if authManager.isAuthenticated {
                    ContentView()
                        .environmentObject(scanManager)
                        .environmentObject(authManager)
                        .environmentObject(networkMonitor)
                } else {
                    LoginScreen()
                        .environmentObject(authManager)
                }
            }
            .animation(.easeOut(duration: 0.3), value: authManager.isAuthenticated)
            .animation(.easeOut(duration: 0.3), value: isCheckingAuth)
        }
    }
}

// MARK: - Boot Line Model

enum BootLineColor { case muted, green }

struct BootLine {
    let text: String
    let color: BootLineColor
}

// MARK: - Splash Screen (matches Rentle-Assist exactly)

struct SplashScreen: View {
    let authManager: AuthManager
    var onComplete: () -> Void

    @State private var visibleLines = 0
    @State private var currentTypingText = ""
    @State private var bootDone = false
    @State private var cursorVisible = true
    @State private var logoOpacity: Double = 0
    @State private var linesOpacity: Double = 0
    @State private var footerOpacity: Double = 0

    private let bootLines: [BootLine] = [
        BootLine(text: "> sys.init()", color: .muted),
        BootLine(text: "  loading core modules...", color: .muted),
        BootLine(text: "  ✓ auth_service", color: .green),
        BootLine(text: "  ✓ api_service", color: .green),
        BootLine(text: "  ✓ secure_storage", color: .green),
        BootLine(text: "> checking credentials...", color: .muted),
    ]

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

                VStack(spacing: 0) {
                    // ── ASCII Art Logo ──
                    asciiLogo
                        .opacity(logoOpacity)

                    Spacer().frame(height: 28)

                    // ── Brand name ──
                    Text("r e n t l e . a i")
                        .font(.custom("Courier", size: 28))
                        .foregroundStyle(Color(hex: "E0E0E0"))
                        .tracking(2)
                        .opacity(logoOpacity)

                    Spacer().frame(height: 8)

                    // ── Subtitle ──
                    Text("// tour_application v1.0")
                        .font(.custom("Courier", size: 13))
                        .foregroundStyle(Color(hex: "5C6370"))
                        .tracking(1.5)
                        .opacity(logoOpacity)

                    Spacer().frame(height: 36)

                    // ── Boot sequence terminal ──
                    bootTerminal
                        .opacity(linesOpacity)
                }
                .padding(.horizontal, 36)

                Spacer()

                // ── Footer ──
                HStack {
                    Text("v1.0.0  tour_app")
                        .font(.custom("Courier", size: 10))
                        .foregroundStyle(Color(hex: "3A3A3A"))
                        .tracking(1)

                    Spacer()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: "4CAF50"))
                            .frame(width: 6, height: 6)
                            .shadow(color: Color(hex: "4CAF50").opacity(0.5), radius: 6, x: 0, y: 1)

                        Text("sec_v1.0 encrypted")
                            .font(.custom("Courier", size: 10))
                            .foregroundStyle(Color(hex: "4CAF50").opacity(0.4))
                            .tracking(1)
                    }
                }
                .opacity(footerOpacity)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await runBootSequence()
        }
        .task {
            // Cursor blink
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 530_000_000)
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

    // MARK: - Boot Terminal

    private var bootTerminal: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Completed lines
            ForEach(0..<min(visibleLines, bootLines.count), id: \.self) { i in
                Text(bootLines[i].text)
                    .font(.custom("Courier", size: 13))
                    .foregroundStyle(
                        bootLines[i].color == .green
                            ? Color(hex: "4CAF50")
                            : Color(hex: "5C6370")
                    )
                    .tracking(0.5)
                    .lineSpacing(1.5)
            }

            // Currently typing line
            if visibleLines < bootLines.count && !currentTypingText.isEmpty {
                HStack(spacing: 0) {
                    Text(currentTypingText)
                        .font(.custom("Courier", size: 13))
                        .foregroundStyle(
                            bootLines[visibleLines].color == .green
                                ? Color(hex: "4CAF50")
                                : Color(hex: "5C6370")
                        )
                        .tracking(0.5)
                    Text("█")
                        .font(.custom("Courier", size: 13))
                        .foregroundStyle(Color(hex: "4CAF50"))
                        .opacity(cursorVisible ? 1 : 0)
                }
            }

            // Final cursor after boot
            if bootDone {
                HStack(spacing: 0) {
                    Text("> ")
                        .font(.custom("Courier", size: 13))
                        .foregroundStyle(Color(hex: "4CAF50"))
                        .tracking(0.5)
                    Text("█")
                        .font(.custom("Courier", size: 13))
                        .foregroundStyle(Color(hex: "4CAF50"))
                        .opacity(cursorVisible ? 1 : 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(hex: "0F0F0F"))
        .overlay(Rectangle().stroke(Color(hex: "1E1E1E"), lineWidth: 1))
    }

    // MARK: - Boot Sequence Animation

    private func runBootSequence() async {
        // Start auth check in parallel
        let authTask = Task {
            await authManager.tryAutoLogin()
        }

        // Fade in logo
        try? await Task.sleep(nanoseconds: 100_000_000)
        withAnimation(.easeOut(duration: 0.7)) { logoOpacity = 1 }

        try? await Task.sleep(nanoseconds: 300_000_000)
        withAnimation(.easeOut(duration: 0.6)) { linesOpacity = 1 }

        // Type out each boot line
        for i in 0..<bootLines.count {
            let line = bootLines[i].text
            for c in 0...line.count {
                try? await Task.sleep(nanoseconds: UInt64((8 + Int.random(in: 0..<8)) * 1_000_000))
                visibleLines = i
                currentTypingText = String(line.prefix(c))
            }
            // Finish line
            visibleLines = i + 1
            currentTypingText = ""
            try? await Task.sleep(nanoseconds: UInt64((30 + Int.random(in: 0..<30)) * 1_000_000))
        }

        withAnimation(.easeOut(duration: 0.5)) { footerOpacity = 1 }
        bootDone = true

        // Wait for auth if needed
        await authTask.value

        // Brief pause then navigate
        try? await Task.sleep(nanoseconds: 300_000_000)
        onComplete()
    }
}
