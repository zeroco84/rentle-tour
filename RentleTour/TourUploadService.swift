// TourUploadService.swift
// RentleTour
//
// Upload service for .rentletour ZIP bundles.
// Aligned with backend Fargate processing pipeline:
//   - Sends full TourBundle ZIP (not raw .usdz)
//   - Content-Type: application/zip via multipart/form-data
//   - Expects 202 Accepted (async processing via SQS → Fargate)
//
// Endpoint: POST /api/v1/admin/apartments/:apartment_id/virtual_tour

import Foundation

// MARK: - Upload Response (202 Accepted)

struct TourUploadResponse: Codable {
    let status: String           // "queued"
    let apartmentId: Int?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case status
        case apartmentId = "apartment_id"
        case message
    }
}

// MARK: - Upload Error Response

struct UploadErrorResponse: Codable {
    let error: String
}

// MARK: - Tour Upload Service

final class TourUploadService {

    enum UploadError: LocalizedError {
        case fileNotFound
        case invalidURL
        case serverError(Int, String)
        case decodingError(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound: return "Tour bundle not found."
            case .invalidURL: return "Invalid server URL."
            case .serverError(_, let msg): return msg
            case .decodingError(let msg): return msg
            }
        }
    }

    /// Uploads a .rentletour ZIP bundle to the backend for processing.
    ///
    /// The backend will:
    /// 1. Store the ZIP to S3
    /// 2. Set tour_processing_status = "queued"
    /// 3. Push an SQS message for Fargate processing
    /// 4. Return 202 Accepted
    ///
    /// - Parameters:
    ///   - fileURL: Local URL of the .rentletour ZIP
    ///   - apartmentId: The server-side apartment ID
    ///   - token: Bearer auth token
    ///   - baseURL: The instance base URL
    ///   - onProgress: Optional progress callback (0.0–1.0)
    /// - Returns: TourUploadResponse from the server
    static func uploadTourBundle(
        fileURL: URL,
        apartmentId: Int,
        token: String,
        baseURL: String,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> TourUploadResponse {

        // Verify file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw UploadError.fileNotFound
        }

        // Build URL
        guard let url = URL(string: "\(baseURL)/api/v1/admin/apartments/\(apartmentId)/virtual_tour") else {
            throw UploadError.invalidURL
        }

        // Read file data
        let fileData = try Data(contentsOf: fileURL)

        // Build multipart/form-data body
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        // File part — application/zip
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        body.append("Content-Type: application/zip\r\n\r\n")
        body.append(fileData)
        body.append("\r\n")

        // End boundary
        body.append("--\(boundary)--\r\n")

        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 300 // 5 minutes — large ZIPs with textures

        // Report initial progress
        onProgress?(0.1)

        let (responseData, response) = try await URLSession.shared.data(for: request)

        onProgress?(0.9)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.serverError(0, "Invalid response")
        }

        // Handle success: 200 OK or 202 Accepted
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let errorResp = try? JSONDecoder().decode(UploadErrorResponse.self, from: responseData) {
                throw UploadError.serverError(httpResponse.statusCode, errorResp.error)
            }
            throw UploadError.serverError(httpResponse.statusCode, "Upload failed (\(httpResponse.statusCode))")
        }

        onProgress?(1.0)

        // Decode response
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(TourUploadResponse.self, from: responseData)
        } catch {
            // If we got 202 but response doesn't match exactly, treat as success
            if httpResponse.statusCode == 202 {
                return TourUploadResponse(status: "queued", apartmentId: apartmentId, message: "Accepted for processing")
            }
            throw UploadError.decodingError("Invalid response from server")
        }
    }
}

// MARK: - Data Extension (Multipart Helper)

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
