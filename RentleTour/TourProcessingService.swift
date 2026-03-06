// TourProcessingService.swift
// RentleTour
//
// Polls the backend for tour processing status.
// After uploading a TourBundle ZIP, the backend queues it for
// Fargate processing. This service polls the status endpoint
// until the tour is completed or fails.
//
// Endpoint: GET /api/v1/admin/apartments/:apartment_id/virtual_tour/status

import Foundation

// MARK: - Processing Status DTO

struct TourProcessingStatusDTO: Codable {
    let status: String               // "queued" | "processing" | "completed" | "failed"
    let queuedAt: Date?
    let processedAt: Date?
    let error: String?
    let tourModelUrl: String?         // GLB URL on S3/CDN (when completed)
    let tourNavGraph: NavGraphDTO?    // Navigation graph (when completed)
    let tourPanoramaUrls: [String]?   // WebP panorama URLs (when completed)

    enum CodingKeys: String, CodingKey {
        case status
        case queuedAt = "queued_at"
        case processedAt = "processed_at"
        case error
        case tourModelUrl = "tour_model_url"
        case tourNavGraph = "tour_nav_graph"
        case tourPanoramaUrls = "tour_panorama_urls"
    }
}

// MARK: - Navigation Graph

struct NavGraphDTO: Codable {
    let nodes: [NavNodeDTO]
    let edges: [[Int]]
}

struct NavNodeDTO: Codable, Identifiable {
    let id: Int
    let position: [Float]           // [x, y, z] world position
    let panoramaUrl: String
    let label: String?

    enum CodingKeys: String, CodingKey {
        case id, position, label
        case panoramaUrl = "panorama_url"
    }
}

// MARK: - Tour Processing Service

final class TourProcessingService {

    enum ProcessingError: LocalizedError {
        case invalidURL
        case unauthorized
        case serverError(Int, String)
        case decodingError
        case processingFailed(String)
        case timeout

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid server URL."
            case .unauthorized: return "Authentication expired. Please log in again."
            case .serverError(_, let msg): return msg
            case .decodingError: return "Failed to parse processing status."
            case .processingFailed(let msg): return "Tour processing failed: \(msg)"
            case .timeout: return "Processing timed out."
            }
        }
    }

    /// Fetch the current processing status for an apartment's tour.
    ///
    /// - Returns: Current TourProcessingStatusDTO
    static func fetchStatus(
        apartmentId: Int,
        token: String,
        baseURL: String
    ) async throws -> TourProcessingStatusDTO {

        guard let url = URL(string: "\(baseURL)/api/v1/admin/apartments/\(apartmentId)/virtual_tour/status") else {
            throw ProcessingError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProcessingError.serverError(0, "Invalid response")
        }

        if httpResponse.statusCode == 401 {
            throw ProcessingError.unauthorized
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ProcessingError.serverError(httpResponse.statusCode, "Status check failed")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(TourProcessingStatusDTO.self, from: data)
        } catch {
            throw ProcessingError.decodingError
        }
    }

    /// Polls the processing status until completion or failure.
    ///
    /// - Parameters:
    ///   - pollInterval: Seconds between polls (default 10)
    ///   - maxDuration: Maximum seconds to poll before timeout (default 20 min)
    ///   - onStatusUpdate: Callback for each status change
    /// - Returns: Final TourProcessingStatusDTO (completed or failed)
    static func pollUntilComplete(
        apartmentId: Int,
        token: String,
        baseURL: String,
        pollInterval: TimeInterval = 10,
        maxDuration: TimeInterval = 1200,
        onStatusUpdate: ((TourProcessingStatusDTO) -> Void)? = nil
    ) async throws -> TourProcessingStatusDTO {

        let startTime = Date()

        while Date().timeIntervalSince(startTime) < maxDuration {
            let status = try await fetchStatus(
                apartmentId: apartmentId,
                token: token,
                baseURL: baseURL
            )

            onStatusUpdate?(status)

            switch status.status {
            case "completed":
                return status
            case "failed":
                throw ProcessingError.processingFailed(status.error ?? "Unknown error")
            default:
                // "queued" or "processing" — wait and poll again
                try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            }
        }

        throw ProcessingError.timeout
    }
}
