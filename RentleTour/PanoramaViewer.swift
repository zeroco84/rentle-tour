// PanoramaViewer.swift
// RentleTour
//
// Full-screen equirectangular 360° image viewer.
// Displayed when a user taps a node in the Dollhouse view.
// Supports pan and zoom gestures for immersive exploration.

import SwiftUI
import SceneKit

// MARK: - Panorama Viewer Screen

struct PanoramaViewerScreen: View {
    let node: TourNode
    let tourBundle: TourBundle

    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var isLoading = true

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
                // SceneKit panorama sphere
                PanoramaSphereView(image: image)
                    .ignoresSafeArea()
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

                    Text("drag to look around")
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

// MARK: - Panorama Sphere (SceneKit)

/// Renders an image on the inside of a sphere for 360° viewing.
/// The camera sits at the center; the user rotates by dragging.
struct PanoramaSphereView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView(frame: .zero)
        scnView.backgroundColor = .black
        scnView.allowsCameraControl = true
        scnView.defaultCameraController.interactionMode = .orbitTurntable
        scnView.defaultCameraController.inertiaEnabled = true
        scnView.antialiasingMode = .multisampling4X

        let scene = SCNScene()

        // Create the panorama sphere
        let sphere = SCNSphere(radius: 20)
        sphere.segmentCount = 96

        // Map the image to the inside of the sphere
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.isDoubleSided = true
        material.cullMode = .front  // Render inside face only

        sphere.materials = [material]
        let sphereNode = SCNNode(geometry: sphere)

        // Flip the sphere so texture maps correctly on the inside
        sphereNode.scale = SCNVector3(-1, 1, 1)

        scene.rootNode.addChildNode(sphereNode)

        // Camera at the center of the sphere
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 75
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.zFar = 50
        cameraNode.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(cameraNode)

        scnView.scene = scene
        scnView.pointOfView = cameraNode

        // Ambient light
        let light = SCNLight()
        light.type = .ambient
        light.intensity = 1000
        let lightNode = SCNNode()
        lightNode.light = light
        scene.rootNode.addChildNode(lightNode)

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}
