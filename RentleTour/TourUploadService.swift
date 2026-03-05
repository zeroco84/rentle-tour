// TourUploadService.swift
// RentleTour
//
// Multipart upload service for .usdz tour files.
// Endpoint: POST /api/v1/admin/apartments/:apartment_id/virtual_tour
// Content-Type: multipart/form-data

import Foundation

// MARK: - Upload Response

struct UploadResponse: Codable {
    let success: Bool
    let apartmentId: Int?
    let apartmentName: String?
    let buildingName: String?
    let filename: String?
    let url: String?
    let virtualTourType: String?

    enum CodingKeys: String, CodingKey {
        case success
        case apartmentId = "apartment_id"
        case apartmentName = "apartment_name"
        case buildingName = "building_name"
        case filename, url
        case virtualTourType = "virtual_tour_type"
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
            case .fileNotFound: return "Tour file not found."
            case .invalidURL: return "Invalid server URL."
            case .serverError(_, let msg): return msg
            case .decodingError(let msg): return msg
            }
        }
    }

    /// Uploads a .usdz tour file to the backend.
    ///
    /// - Parameters:
    ///   - fileURL: Local URL of the .usdz file
    ///   - apartmentId: The server-side apartment ID
    ///   - token: Bearer auth token
    ///   - baseURL: The instance base URL
    ///   - onProgress: Optional progress callback (0.0–1.0)
    /// - Returns: UploadResponse from the server
    static func uploadTour(
        fileURL: URL,
        apartmentId: Int,
        token: String,
        baseURL: String,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> UploadResponse {

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

        // File part
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        body.append("Content-Type: model/vnd.usdz+zip\r\n\r\n")
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
        request.timeoutInterval = 120 // 2 minutes for large files

        // Report initial progress
        onProgress?(0.1)

        let (responseData, response) = try await URLSession.shared.data(for: request)

        onProgress?(0.9)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.serverError(0, "Invalid response")
        }

        // Handle errors
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let errorResp = try? JSONDecoder().decode(UploadErrorResponse.self, from: responseData) {
                throw UploadError.serverError(httpResponse.statusCode, errorResp.error)
            }
            throw UploadError.serverError(httpResponse.statusCode, "Upload failed (\(httpResponse.statusCode))")
        }

        onProgress?(1.0)

        // Decode success response
        do {
            return try JSONDecoder().decode(UploadResponse.self, from: responseData)
        } catch {
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
