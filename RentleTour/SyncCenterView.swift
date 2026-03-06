// SyncCenterView.swift
// RentleTour
//
// Shows upload progress for all tour bundles.
// Per-property rows with progress bars, status icons,
// cellular toggle, and retry controls.
// UI follows Apple iOS Human Interface Guidelines.

import SwiftUI

// MARK: - Sync Center View

struct SyncCenterView: View {
    @ObservedObject var uploadManager = BackgroundUploadManager.shared
    @ObservedObject var networkMonitor: NetworkMonitor

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Network status
                Section {
                    networkStatusRow
                    cellularToggle
                }

                // Active uploads
                if !uploadManager.activeJobs.isEmpty {
                    Section {
                        ForEach(uploadManager.activeJobs) { job in
                            UploadJobRow(
                                job: job,
                                progress: uploadManager.uploadProgress[job.id] ?? 0,
                                onRetry: { uploadManager.retryJob(id: job.id) },
                                onRemove: { uploadManager.removeJob(id: job.id) }
                            )
                        }
                    } header: {
                        Text("Uploads")
                    }
                } else {
                    Section {
                        ContentUnavailableView {
                            Label("No Uploads", systemImage: "arrow.up.circle")
                        } description: {
                            Text("Upload a tour from the review screen to see it here.")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Sync Center")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Network Status Row

    private var networkStatusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: networkMonitor.isConnected ? "wifi" : "wifi.slash")
                .font(.title3)
                .foregroundStyle(networkMonitor.isConnected ? .green : .red)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(networkMonitor.isConnected ? "Connected" : "Offline")
                    .font(.body.weight(.medium))

                Text(connectionDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !networkMonitor.canUpload {
                Label("Paused", systemImage: "pause.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var connectionDetail: String {
        if !networkMonitor.isConnected { return "No network connection" }
        if networkMonitor.isWiFi { return "Wi-Fi" }
        if networkMonitor.isCellular {
            return networkMonitor.useCellularData ? "Cellular (enabled)" : "Cellular (uploads paused)"
        }
        return "Connected"
    }

    // MARK: - Cellular Toggle

    private var cellularToggle: some View {
        Toggle(isOn: $networkMonitor.useCellularData) {
            Label("Use Cellular Data", systemImage: "antenna.radiowaves.left.and.right")
        }
    }
}

// MARK: - Upload Job Row

struct UploadJobRow: View {
    let job: UploadJobManifest
    let progress: Double
    var onRetry: () -> Void
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                statusIcon
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(job.propertyName)
                        .font(.body.weight(.medium))
                    Text(job.apartmentLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusBadge
            }

            // Progress bar (during upload)
            if job.status == .uploading || job.status == .zipping {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: job.status == .zipping ? nil : progress) {
                        Text(job.status == .zipping ? "Compressing…" : "\(Int(progress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Error message
            if let error = job.errorMessage, job.status == .failed {
                HStack {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)

                    Spacer()

                    Button("Retry", action: onRetry)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
            }

            // File info
            HStack {
                Text("\(job.totalFiles) files")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("·")
                    .foregroundStyle(.quaternary)

                Text(formattedSize)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let completed = job.completedAt {
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(completed, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            if job.status == .completed || job.status == .failed {
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Status Icon

    @ViewBuilder
    private var statusIcon: some View {
        switch job.status {
        case .pending:
            Image(systemName: "clock.fill")
                .foregroundStyle(.secondary)
        case .zipping:
            Image(systemName: "archivebox.fill")
                .foregroundStyle(.blue)
        case .uploading:
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.blue)
                .symbolEffect(.pulse)
        case .completed:
            Image(systemName: "checkmark.icloud.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        switch job.status {
        case .pending:
            Text("Queued")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.secondary.opacity(0.1), in: Capsule())
        case .zipping:
            Text("Compressing")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.blue.opacity(0.1), in: Capsule())
        case .uploading:
            Text("Uploading")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.blue.opacity(0.1), in: Capsule())
        case .completed:
            Text("Synced")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.green.opacity(0.1), in: Capsule())
        case .failed:
            Text("Failed")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.red.opacity(0.1), in: Capsule())
        }
    }

    // MARK: - Formatted Size

    private var formattedSize: String {
        let bytes = job.totalBytes
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}
