// ApartmentService.swift
// RentleTour
//
// API client for searching apartments.
// Uses the same auth token and base URL as AuthService.
// Endpoint: GET /api/v1/admin/inspections/search_apartments?q=<query>

import Foundation
import Security

// MARK: - Apartment DTO

struct ApartmentDTO: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let building: String?
    let tenantName: String?
    let tenantEmail: String?
    let label: String

    enum CodingKeys: String, CodingKey {
        case id, name, building, label
        case tenantName = "tenant_name"
        case tenantEmail = "tenant_email"
    }
}

// MARK: - Apartment Service

final class ApartmentService {

    enum ApartmentError: LocalizedError {
        case noToken
        case invalidURL
        case serverError(Int, String)
        case decodingError

        var errorDescription: String? {
            switch self {
            case .noToken: return "Not authenticated. Please log in."
            case .invalidURL: return "Invalid server URL."
            case .serverError(_, let msg): return msg
            case .decodingError: return "Failed to parse apartment data."
            }
        }
    }

    /// Searches apartments using the admin inspections endpoint.
    ///
    /// - Parameters:
    ///   - query: Search string (minimum 2 characters)
    ///   - token: Bearer auth token
    ///   - baseURL: The instance base URL (e.g. https://vesta.rentle.ai)
    /// - Returns: Array of matching apartments
    static func searchApartments(
        query: String,
        token: String,
        baseURL: String
    ) async throws -> [ApartmentDTO] {

        guard query.count >= 2 else { return [] }

        guard var urlComponents = URLComponents(string: "\(baseURL)/api/v1/admin/inspections/search_apartments") else {
            throw ApartmentError.invalidURL
        }
        urlComponents.queryItems = [URLQueryItem(name: "q", value: query)]

        guard let url = urlComponents.url else {
            throw ApartmentError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ApartmentError.serverError(0, "Invalid response")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let message = body["error"] as? String ?? "Server error (\(httpResponse.statusCode))"
            throw ApartmentError.serverError(httpResponse.statusCode, message)
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode([ApartmentDTO].self, from: data)
        } catch {
            throw ApartmentError.decodingError
        }
    }
}
