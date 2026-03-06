// PanoramaViewer.swift
// RentleTour
//
// Full-screen image viewer for captured 360° node photos.
// Supports pinch-to-zoom and drag-to-pan.
// UI follows Apple iOS Human Interface Guidelines.

import SwiftUI

// MARK: - Panorama Viewer Screen

struct PanoramaViewerScreen: View {
    let node: TourNode
    let tourBundle: TourBundle

    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var isLoading = true

    // Zoom/pan state
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView("Loading…")
                    .tint(.white)
                    .foregroundStyle(.white)
            } else if let image = image {
                // Zoomable/pannable image viewer
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = lastScale * value
                            }
                            .onEnded { value in
                                lastScale = scale
                                if scale < 1.0 {
                                    withAnimation(.spring(response: 0.3)) {
                                        scale = 1.0
                                        lastScale = 1.0
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                if scale > 1.0 {
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                    .simultaneousGesture(
                        TapGesture(count: 2)
                            .onEnded {
                                withAnimation(.spring(response: 0.3)) {
                                    if scale > 1.0 {
                                        scale = 1.0
                                        lastScale = 1.0
                                        offset = .zero
                                        lastOffset = .zero
                                    } else {
                                        scale = 3.0
                                        lastScale = 3.0
                                    }
                                }
                            }
                    )
            } else {
                ContentUnavailableView {
                    Label("Image Not Found", systemImage: "photo.badge.exclamationmark")
                } description: {
                    Text(node.imageFileName)
                }
            }

            // Overlay controls
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Spacer()

                    // Node info badge
                    Text(node.label)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                // Bottom info bar
                HStack {
                    Label(
                        "(\(String(format: "%.2f", node.positionX)), \(String(format: "%.2f", node.positionY)), \(String(format: "%.2f", node.positionZ)))",
                        systemImage: "location.circle"
                    )
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))

                    Spacer()

                    Text("Pinch to zoom · Double-tap to reset")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            image = tourBundle.loadNodeImage(for: node)
            isLoading = false
        }
    }
}
