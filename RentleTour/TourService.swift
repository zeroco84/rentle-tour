// TourService.swift
// RentleTour
//
// Fetches processed tour data for an apartment.
// After the Fargate pipeline completes processing,
// apartments have GLB models, WebP panoramas, and
// navigation graphs available via the API.
//
// Endpoint: GET /api/v1/admin/apartments/:apartment_id

import Foundation

// MARK: - Apartment Tour Data

struct ApartmentTourData: Codable {
    let id: Int
    let name: String
    let building: String?
    let tourProcessingStatus: String?   // nil | "queued" | "processing" | "completed" | "failed"
    let tourModelUrl: String?           // GLB URL on S3/CDN
    let tourNavGraph: NavGraphDTO?      // Navigation graph
    let tourPanoramaUrls: [String]?     // WebP panorama URLs

    enum CodingKeys: String, CodingKey {
        case id, name, building
        case tourProcessingStatus = "tour_processing_status"
        case tourModelUrl = "tour_model_url"
        case tourNavGraph = "tour_nav_graph"
        case tourPanoramaUrls = "tour_panorama_urls"
    }

    /// Whether this apartment has a completed, viewable tour
    var hasTour: Bool {
        tourProcessingStatus == "completed" && tourModelUrl != nil
    }

    /// Whether this apartment has a tour currently being processed
    var isProcessing: Bool {
        tourProcessingStatus == "queued" || tourProcessingStatus == "processing"
    }
}

// MARK: - Tour Service

final class TourService {

    enum TourError: LocalizedError {
        case invalidURL
        case unauthorized
        case notFound
        case serverError(Int, String)
        case decodingError

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid server URL."
            case .unauthorized: return "Authentication expired. Please log in again."
            case .notFound: return "Apartment not found."
            case .serverError(_, let msg): return msg
            case .decodingError: return "Failed to parse tour data."
            }
        }
    }

    /// Fetch tour data for a specific apartment.
    static func fetchTourData(
        apartmentId: Int,
        token: String,
        baseURL: String
    ) async throws -> ApartmentTourData {

        guard let url = URL(string: "\(baseURL)/api/v1/admin/apartments/\(apartmentId)") else {
            throw TourError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TourError.serverError(0, "Invalid response")
        }

        switch httpResponse.statusCode {
        case 200..<300:
            break
        case 401:
            throw TourError.unauthorized
        case 404:
            throw TourError.notFound
        default:
            throw TourError.serverError(httpResponse.statusCode, "Server error")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(ApartmentTourData.self, from: data)
        } catch {
            throw TourError.decodingError
        }
    }

    /// Fetch all apartments that have completed tours.
    static func fetchApartmentsWithTours(
        token: String,
        baseURL: String
    ) async throws -> [ApartmentTourData] {

        guard let url = URL(string: "\(baseURL)/api/v1/admin/apartments?with_tours=true") else {
            throw TourError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TourError.serverError(0, "Invalid response")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 { throw TourError.unauthorized }
            throw TourError.serverError(httpResponse.statusCode, "Server error")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([ApartmentTourData].self, from: data)
        } catch {
            throw TourError.decodingError
        }
    }
}
