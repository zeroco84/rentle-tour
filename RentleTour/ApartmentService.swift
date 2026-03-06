// ApartmentService.swift
// RentleTour
//
// API client for buildings and apartments.
// Uses the same auth token and base URL as AuthService.

import Foundation
import Security

// MARK: - Building DTO

struct BuildingDTO: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let apartmentCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name
        case apartmentCount = "apartment_count"
    }
}

// MARK: - Apartment DTO

struct ApartmentDTO: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let building: String?
    let buildingId: Int?
    let tenantName: String?
    let tenantEmail: String?
    let label: String
    let tourProcessingStatus: String?
    let tourModelUrl: String?

    /// Whether this apartment has a completed 3D tour
    var hasTour: Bool {
        tourProcessingStatus == "completed" && tourModelUrl != nil
    }

    /// Whether this apartment's tour is currently being processed
    var isTourProcessing: Bool {
        tourProcessingStatus == "queued" || tourProcessingStatus == "processing"
    }

    enum CodingKeys: String, CodingKey {
        case id, name, building, label
        case buildingId = "building_id"
        case tenantName = "tenant_name"
        case tenantEmail = "tenant_email"
        case tourProcessingStatus = "tour_processing_status"
        case tourModelUrl = "tour_model_url"
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
            case .decodingError: return "Failed to parse data."
            }
        }
    }

    /// Fetches all buildings.
    static func fetchBuildings(
        token: String,
        baseURL: String
    ) async throws -> [BuildingDTO] {

        guard let url = URL(string: "\(baseURL)/api/v1/admin/buildings") else {
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
            return try decoder.decode([BuildingDTO].self, from: data)
        } catch {
            throw ApartmentError.decodingError
        }
    }

    /// Searches apartments, optionally filtered by building name.
    static func searchApartments(
        query: String,
        token: String,
        baseURL: String,
        buildingName: String? = nil
    ) async throws -> [ApartmentDTO] {

        guard query.count >= 2 else { return [] }

        guard var urlComponents = URLComponents(string: "\(baseURL)/api/v1/admin/inspections/search_apartments") else {
            throw ApartmentError.invalidURL
        }

        var queryItems = [URLQueryItem(name: "q", value: query)]
        if let building = buildingName {
            queryItems.append(URLQueryItem(name: "building", value: building))
        }
        urlComponents.queryItems = queryItems

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
