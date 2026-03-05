// AuthService.swift
// RentleTour
//
// Authentication service: API login, Keychain token persistence,
// and auto-login — matching Rentle-Assist patterns.

import Foundation
import Security
import SwiftUI

// MARK: - API Error

struct APIError: LocalizedError {
    let statusCode: Int
    let message: String

    var errorDescription: String? { message }
}

// MARK: - Auth State

enum AuthState {
    case initial
    case loading
    case authenticated
    case unauthenticated
    case error
}

// MARK: - Authenticated User

struct AppUser: Codable {
    let id: Int
    let firstName: String
    let lastName: String
    let email: String
    let role: String

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case email
        case role
    }

    var displayName: String { "\(firstName) \(lastName)" }
}

// MARK: - Keychain Helper

private enum KeychainHelper {
    static func save(_ data: Data, forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.rentle.tour",
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func load(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.rentle.tour",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.rentle.tour",
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func deleteAll() {
        for key in ["auth_token", "user_profile", "instance_subdomain"] {
            delete(forKey: key)
        }
    }
}

// MARK: - Auth Manager

@MainActor
final class AuthManager: ObservableObject {

    @Published var state: AuthState = .initial
    @Published var user: AppUser?
    @Published var errorMessage: String?

    private var token: String?
    private var baseURL: String = EnvironmentConfig.defaultBaseURL

    var isAuthenticated: Bool { state == .authenticated }

    /// Public read-only access for API services
    var authToken: String? { token }
    var activeBaseURL: String { baseURL }

    // MARK: Subdomain

    func setSubdomain(_ subdomain: String) {
        baseURL = EnvironmentConfig.baseURL(for: subdomain)
    }

    func saveSubdomain(_ subdomain: String) {
        let data = subdomain.data(using: .utf8) ?? Data()
        KeychainHelper.save(data, forKey: "instance_subdomain")
    }

    func getSavedSubdomain() -> String? {
        guard let data = KeychainHelper.load(forKey: "instance_subdomain") else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: Auto Login

    func tryAutoLogin() async {
        state = .loading

        guard let tokenData = KeychainHelper.load(forKey: "auth_token"),
              let savedToken = String(data: tokenData, encoding: .utf8),
              let userData = KeychainHelper.load(forKey: "user_profile"),
              let savedUser = try? JSONDecoder().decode(AppUser.self, from: userData) else {
            state = .unauthenticated
            return
        }

        // Restore subdomain
        if let subdomain = getSavedSubdomain() {
            setSubdomain(subdomain)
        }

        token = savedToken
        user = savedUser
        state = .authenticated
    }

    // MARK: Login

    func login(email: String, password: String) async -> Bool {
        state = .loading
        errorMessage = nil

        do {
            // Try admin login first, fall back to technician (matching Rentle-Assist)
            let data = try await attemptLogin(email: email, password: password)

            guard let tokenStr = data["token"] as? String else {
                throw APIError(statusCode: 500, message: "Invalid login response")
            }

            // Parse user from whichever key is present
            var userData: [String: Any]?
            if let admin = data["admin"] as? [String: Any] {
                userData = admin
            } else if var tech = data["technician"] as? [String: Any] {
                tech["role"] = tech["role"] ?? "technician"
                userData = tech
            }

            guard let userDict = userData,
                  let userJSON = try? JSONSerialization.data(withJSONObject: userDict),
                  let parsedUser = try? JSONDecoder().decode(AppUser.self, from: userJSON) else {
                throw APIError(statusCode: 500, message: "Invalid login response")
            }

            // Persist
            token = tokenStr
            user = parsedUser
            KeychainHelper.save(Data(tokenStr.utf8), forKey: "auth_token")
            KeychainHelper.save(userJSON, forKey: "user_profile")

            state = .authenticated
            return true

        } catch let error as APIError {
            errorMessage = error.message
            state = .error
            return false
        } catch {
            errorMessage = "Connection error. Please check your network."
            state = .error
            return false
        }
    }

    // MARK: Logout

    func logout() {
        // Try server-side logout (fire-and-forget)
        if let t = token {
            Task {
                var request = URLRequest(url: URL(string: "\(baseURL)/api/v1/admin/logout")!)
                request.httpMethod = "DELETE"
                request.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
                _ = try? await URLSession.shared.data(for: request)
            }
        }

        KeychainHelper.deleteAll()
        token = nil
        user = nil
        state = .unauthenticated
    }

    // MARK: Private — API calls

    private func attemptLogin(email: String, password: String) async throws -> [String: Any] {
        // Try admin first
        do {
            let result = try await loginRequest(prefix: "/api/v1/admin", email: email, password: password)
            return result
        } catch let error as APIError where error.statusCode == 401 || error.statusCode == 403 {
            // Fall through to technician
        }

        // Try technician
        return try await loginRequest(prefix: "/api/v1/technician", email: email, password: password)
    }

    private func loginRequest(prefix: String, email: String, password: String) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)\(prefix)/login") else {
            throw APIError(statusCode: 0, message: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError(statusCode: 0, message: "Invalid response")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let message = body["error"] as? String ?? "Invalid email or password"
            throw APIError(statusCode: httpResponse.statusCode, message: message)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError(statusCode: 500, message: "Invalid response format")
        }

        return json
    }
}
