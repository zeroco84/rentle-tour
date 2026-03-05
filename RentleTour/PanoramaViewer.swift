// PanoramaViewer.swift
// RentleTour
//
// Full-screen image viewer for captured 360° node photos.
// Displayed when a user taps a node in the Dollhouse view.
// Supports pinch-to-zoom and drag-to-pan for exploration.

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
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(RentleBrand.green)
                    Text("// loading_panorama")
                        .font(.custom("Courier", size: 12))
                        .foregroundStyle(RentleBrand.textSecondary)
                        .tracking(1)
                }
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
                VStack(spacing: 16) {
                    Text("✗ image_not_found")
                        .font(.custom("Courier", size: 14))
                        .foregroundStyle(Color(hex: "CF6679"))

                    Text(node.imageFileName)
                        .font(.custom("Courier", size: 12))
                        .foregroundStyle(RentleBrand.textSecondary)
                }
            }

            // Overlay controls
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Text("× close")
                            .font(.custom("Courier", size: 12))
                            .foregroundStyle(RentleBrand.green)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RentleBrand.background.opacity(0.85))
                            .overlay(Rectangle().stroke(RentleBrand.border, lineWidth: 1))
                    }

                    Spacer()

                    // Node info badge
                    Text(node.label.lowercased().replacingOccurrences(of: " ", with: "_"))
                        .font(.custom("Courier", size: 12))
                        .foregroundStyle(RentleBrand.textPrimary)
                        .tracking(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RentleBrand.background.opacity(0.85))
                        .overlay(Rectangle().stroke(RentleBrand.border, lineWidth: 1))
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                // Position info
                HStack {
                    Text("pos: (\(String(format: "%.2f", node.positionX)), \(String(format: "%.2f", node.positionY)), \(String(format: "%.2f", node.positionZ)))")
                        .font(.custom("Courier", size: 10))
                        .foregroundStyle(RentleBrand.textMuted)
                        .tracking(1)

                    Spacer()

                    Text("pinch to zoom · double-tap to reset")
                        .font(.custom("Courier", size: 10))
                        .foregroundStyle(RentleBrand.textMuted)
                        .tracking(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(RentleBrand.background.opacity(0.7))
            }
        }
        .preferredColorScheme(.dark)
        .task {
            // Load the image from the tour bundle
            image = tourBundle.loadNodeImage(for: node)
            isLoading = false
        }
    }
}
