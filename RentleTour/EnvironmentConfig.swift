// EnvironmentConfig.swift
// RentleTour
//
// Environment configuration matching Rentle-Assist patterns.
// Determined at build time via ENVIRONMENT user-defined build setting.
//
// Production:  subdomain.rentle.ai
// Staging:     staging.subdomain.rentle.ai

import Foundation

enum AppEnvironment: String {
    case staging
    case production
}

struct EnvironmentConfig {

    /// Reads the ENVIRONMENT value injected by the Xcode build configuration
    /// via Info.plist → $(ENVIRONMENT). Defaults to staging.
    static var current: AppEnvironment {
        guard let envString = Bundle.main.infoDictionary?["ENVIRONMENT"] as? String else {
            return .staging
        }
        return AppEnvironment(rawValue: envString.lowercased()) ?? .staging
    }

    static var isProduction: Bool { current == .production }
    static var isStaging: Bool { current == .staging }

    /// Human-readable label
    static var label: String {
        isProduction ? "Production" : "Staging"
    }

    /// App display title
    static var appTitle: String {
        isProduction ? "Rentle Tour" : "Rentle Tour (S)"
    }

    /// Build the full base URL for a given subdomain.
    ///
    /// Production: `https://<subdomain>.rentle.ai`
    /// Staging:    `https://staging.<subdomain>.rentle.ai`
    static func baseURL(for subdomain: String) -> String {
        if isProduction {
            return "https://\(subdomain).rentle.ai"
        }
        return "https://staging.\(subdomain).rentle.ai"
    }

    /// Default base URL (before subdomain is entered)
    static var defaultBaseURL: String {
        if isProduction {
            return "https://vesta.rentle.ai"
        }
        return "https://staging.vesta.rentle.ai"
    }
}
