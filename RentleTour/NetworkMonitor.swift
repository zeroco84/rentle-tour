// NetworkMonitor.swift
// RentleTour
//
// Observes network connectivity via NWPathMonitor.
// Provides Wi-Fi vs cellular status and a user preference
// to restrict large uploads to Wi-Fi only.

import Foundation
import Network
import SwiftUI

// MARK: - Network Monitor

final class NetworkMonitor: ObservableObject {

    @Published var isConnected: Bool = true
    @Published var isWiFi: Bool = false
    @Published var isCellular: Bool = false

    /// User preference: allow large uploads over cellular
    @AppStorage("useCellularData") var useCellularData: Bool = false

    /// Whether uploads should proceed based on connectivity and preferences
    var canUpload: Bool {
        isConnected && (isWiFi || useCellularData)
    }

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.rentle.tour.network-monitor", qos: .utility)

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isConnected = path.status == .satisfied
                self.isWiFi = path.usesInterfaceType(.wifi)
                self.isCellular = path.usesInterfaceType(.cellular)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
