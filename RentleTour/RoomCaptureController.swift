// RoomCaptureController.swift
// RentleTour
//
// Manages RoomPlan scanning sessions, stores captured rooms,
// merges them via StructureBuilder, and exports USDZ files.

import Foundation
import RoomPlan
import Combine
import UIKit

// MARK: - LiDAR Availability Check

enum DeviceCapability {
    /// Returns true only on devices with a LiDAR scanner (iPhone 12 Pro+, iPad Pro 2020+).
    static var supportsLiDAR: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        if #available(iOS 17.0, *) {
            return RoomCaptureSession.isSupported
        } else {
            return false
        }
        #endif
    }
}

// MARK: - Room Type

/// Room type options for naming scanned rooms
enum RoomType: String, CaseIterable, Identifiable {
    case livingRoom = "Living Room"
    case kitchen = "Kitchen"
    case bathroom = "Bathroom"
    case bedroom = "Bedroom"
    case hallway = "Hallway"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .livingRoom: return "sofa"
        case .kitchen: return "fork.knife"
        case .bathroom: return "shower"
        case .bedroom: return "bed.double"
        case .hallway: return "door.left.hand.open"
        case .other: return "square.dashed"
        }
    }

    var terminalLabel: String {
        rawValue.lowercased().replacingOccurrences(of: " ", with: "_")
    }
}

// MARK: - Upload Status

enum UploadStatus: Equatable {
    case pending
    case uploading
    case uploaded
    case failed(String)
}

// MARK: - Scan Manager (Observable State)

/// Central state manager shared across the app via @EnvironmentObject.
/// Stores captured rooms and handles merging + export.
@MainActor
final class ScanManager: ObservableObject {

    // MARK: Published state

    /// All rooms captured so far in the current property scan.
    @Published var capturedRooms: [CapturedRoom] = []

    /// Room names keyed by index (parallel to capturedRooms)
    var roomNames: [Int: String] = [:]

    /// Set after a successful merge.
    @Published var mergedStructure: CapturedStructure?

    /// URL of the last exported USDZ file.
    @Published var exportedFileURL: URL?

    /// URL of the last exported tour bundle (.rentletour)
    @Published var exportedTourURL: URL?

    /// User-facing error / info messages.
    @Published var alertMessage: String?
    @Published var showAlert: Bool = false

    /// Flags
    @Published var isMerging: Bool = false
    @Published var isExporting: Bool = false

    // MARK: Apartment & Upload

    /// The selected apartment ID from the picker
    @Published var selectedApartmentId: Int?
    @Published var selectedApartmentLabel: String?
    @Published var uploadStatus: UploadStatus = .pending
    @Published var isUploading: Bool = false
    @Published var uploadError: String?

    // MARK: Tour Bundle (Hybrid Capture)

    /// The active tour data bundle for spatial captures.
    let tourBundle = TourBundle()

    /// Spatial capture manager for 360 node captures.
    lazy var spatialCapture = SpatialCaptureManager(tourBundle: tourBundle)

    // MARK: Room management

    func addRoom(_ room: CapturedRoom, name: String = "Room") {
        let index = capturedRooms.count
        capturedRooms.append(room)
        roomNames[index] = name
    }

    func clearAll() {
        capturedRooms.removeAll()
        roomNames.removeAll()
        mergedStructure = nil
        exportedFileURL = nil
        exportedTourURL = nil
        selectedApartmentId = nil
        selectedApartmentLabel = nil
        uploadStatus = .pending
        uploadError = nil
        spatialCapture.reset()
    }

    // MARK: Merge via StructureBuilder

    /// Merges all captured rooms into a single CapturedStructure.
    func mergeRooms() async {
        guard capturedRooms.count >= 1 else {
            presentAlert("Capture at least one room before merging.")
            return
        }

        isMerging = true
        defer { isMerging = false }

        do {
            if #available(iOS 17.0, *) {
                let builder = StructureBuilder(options: [.beautifyObjects])
                let structure = try await builder.capturedStructure(from: capturedRooms)
                mergedStructure = structure
            } else {
                presentAlert("StructureBuilder requires iOS 17+.")
            }
        } catch {
            presentAlert("Merge failed: \(error.localizedDescription)")
        }
    }

    // MARK: USDZ Export

    /// Exports the merged structure (or the first room) to a .usdz file in Documents.
    func exportUSDZ() async {
        isExporting = true
        defer { isExporting = false }

        let fileManager = FileManager.default
        guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            presentAlert("Cannot locate Documents directory.")
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let fileName = "RentleTour_\(timestamp).usdz"
        let destinationURL = documentsDir.appendingPathComponent(fileName)

        do {
            if let structure = mergedStructure {
                if #available(iOS 17.0, *) {
                    try structure.export(to: destinationURL)
                }
            } else if let firstRoom = capturedRooms.first {
                try firstRoom.export(to: destinationURL.deletingPathExtension().appendingPathExtension("usdz"))
            } else {
                presentAlert("Nothing to export. Capture a room first.")
                return
            }

            exportedFileURL = destinationURL
        } catch {
            presentAlert("Export failed: \(error.localizedDescription)")
        }
    }

    // MARK: Tour Bundle Export

    /// Exports the full tour bundle as a .rentletour package.
    func exportTourBundle(propertyName: String) async {
        isExporting = true
        defer { isExporting = false }

        do {
            let url = try await TourBundleExporter.export(
                structure: mergedStructure,
                rooms: capturedRooms,
                tourBundle: tourBundle,
                propertyName: propertyName
            )
            exportedTourURL = url
        } catch {
            presentAlert("Tour export failed: \(error.localizedDescription)")
        }
    }

    // MARK: Upload Tour to Backend

    /// Uploads the exported .usdz file to the backend.
    func uploadTour(token: String, baseURL: String) async {
        guard let fileURL = exportedFileURL else {
            presentAlert("No exported file to upload. Export first.")
            return
        }
        guard let apartmentId = selectedApartmentId else {
            presentAlert("No apartment selected.")
            return
        }

        isUploading = true
        uploadStatus = .uploading
        uploadError = nil

        do {
            let response = try await TourUploadService.uploadTour(
                fileURL: fileURL,
                apartmentId: apartmentId,
                token: token,
                baseURL: baseURL
            )
            if response.success {
                uploadStatus = .uploaded
            } else {
                uploadStatus = .failed("Upload returned unsuccessful.")
                uploadError = "Upload returned unsuccessful."
            }
        } catch {
            uploadStatus = .failed(error.localizedDescription)
            uploadError = error.localizedDescription
        }

        isUploading = false
    }

    // MARK: Share Sheet

    /// Presents a UIActivityViewController for the exported file.
    func presentShareSheet() {
        guard let url = exportedFileURL else {
            presentAlert("No file to share. Export first.")
            return
        }

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        // Find the top-most view controller to present the share sheet.
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            presentAlert("Unable to present share sheet.")
            return
        }

        var presenter = rootVC
        while let presented = presenter.presentedViewController {
            presenter = presented
        }

        // iPad popover anchor
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                        y: presenter.view.bounds.midY,
                                        width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        presenter.present(activityVC, animated: true)
    }

    // MARK: Helpers

    private func presentAlert(_ message: String) {
        alertMessage = message
        showAlert = true
    }
}

// MARK: - Room Capture Session Coordinator

/// UIKit coordinator that owns and drives a `RoomCaptureView`.
/// Communicates results back via a completion handler.
final class RoomCaptureCoordinator: NSObject, RoomCaptureViewDelegate {

    var onCaptureComplete: ((CapturedRoom) -> Void)?
    var onSessionInterrupted: ((String) -> Void)?

    /// Exposed so SpatialCaptureManager can access the ARSession
    private(set) var captureView: RoomCaptureView?
    private var sessionConfig: RoomCaptureSession.Configuration

    override init() {
        self.sessionConfig = RoomCaptureSession.Configuration()
        super.init()
    }

    // MARK: NSCoding conformance (required by RoomCaptureViewDelegate)

    required init?(coder: NSCoder) {
        self.sessionConfig = RoomCaptureSession.Configuration()
        super.init()
    }

    func encode(with coder: NSCoder) {
        // No state to persist — required by protocol only.
    }

    // MARK: Setup

    func setupCaptureView() -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.delegate = self
        self.captureView = view
        return view
    }

    func startSession() {
        captureView?.captureSession.run(configuration: sessionConfig)
    }

    func stopSession() {
        captureView?.captureSession.stop()
    }

    // MARK: RoomCaptureViewDelegate

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: (Error)?) -> Bool {
        // Returning true tells RoomPlan to process the scan data.
        if let error = error {
            print("[RentleTour] Capture error: \(error.localizedDescription)")
        }
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: (Error)?) {
        if let error = error {
            onSessionInterrupted?("Processing error: \(error.localizedDescription)")
            return
        }
        onCaptureComplete?(processedResult)
    }
}
