// DollhouseViewer.swift
// RentleTour
//
// RealityKit-powered 'Dollhouse' view that loads the 3D model
// and places pulsing spheres at each 360° node location.
// Tapping a sphere triggers a smooth camera fly-into transition
// to the panorama viewer.

import SwiftUI
import RealityKit
import Combine

// MARK: - Dollhouse Viewer Screen

struct DollhouseViewerScreen: View {
    let tourBundle: TourBundle
    let usdzURL: URL?

    @Environment(\.dismiss) private var dismiss

    @State private var selectedNode: TourNode?
    @State private var showPanorama = false
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        ZStack {
            RentleBrand.background.ignoresSafeArea()

            if isLoading {
                loadingView
            } else if let error = loadError {
                errorView(error)
            } else {
                // RealityKit 3D view
                DollhouseRealityView(
                    usdzURL: usdzURL,
                    nodes: tourBundle.nodes,
                    onNodeTapped: { node in
                        selectedNode = node
                        showPanorama = true
                    },
                    onLoaded: {
                        isLoading = false
                    },
                    onError: { error in
                        loadError = error
                        isLoading = false
                    }
                )
                .ignoresSafeArea()
            }

            // Overlay controls
            VStack {
                topBar
                Spacer()
                bottomBar
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showPanorama) {
            if let node = selectedNode {
                PanoramaViewerScreen(
                    node: node,
                    tourBundle: tourBundle
                )
            }
        }
        .onAppear {
            // Brief load delay for UX
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isLoading = false
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Text("< back")
                    .font(.custom("Courier", size: 12))
                    .foregroundStyle(RentleBrand.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RentleBrand.background.opacity(0.85))
                    .overlay(Rectangle().stroke(RentleBrand.border, lineWidth: 1))
            }

            Spacer()

            Text("// dollhouse_view")
                .font(.custom("Courier", size: 12))
                .foregroundStyle(RentleBrand.textSecondary)
                .tracking(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RentleBrand.background.opacity(0.85))
                .overlay(Rectangle().stroke(RentleBrand.border, lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(RentleBrand.green)
                    .frame(width: 8, height: 8)
                    .shadow(color: RentleBrand.green.opacity(0.5), radius: 6)

                Text("nodes: \(tourBundle.nodes.count)")
                    .font(.custom("Courier", size: 11))
                    .foregroundStyle(RentleBrand.textSecondary)
                    .tracking(1)
            }

            Spacer()

            Text("tap a node to explore")
                .font(.custom("Courier", size: 11))
                .foregroundStyle(RentleBrand.textMuted)
                .tracking(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RentleBrand.background.opacity(0.85))
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            Text("// loading_3d_model")
                .font(.custom("Courier", size: 13))
                .foregroundStyle(RentleBrand.textSecondary)
                .tracking(1.5)

            ProgressView()
                .tint(RentleBrand.green)
        }
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Text("✗ load_error")
                .font(.custom("Courier", size: 14))
                .foregroundStyle(Color(hex: "CF6679"))

            Text(error)
                .font(.custom("Courier", size: 12))
                .foregroundStyle(RentleBrand.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
    }
}

// MARK: - RealityKit View (UIViewRepresentable)

struct DollhouseRealityView: UIViewRepresentable {
    let usdzURL: URL?
    let nodes: [TourNode]
    var onNodeTapped: ((TourNode) -> Void)?
    var onLoaded: (() -> Void)?
    var onError: ((String) -> Void)?

    func makeCoordinator() -> DollhouseCoordinator {
        DollhouseCoordinator(nodes: nodes, onNodeTapped: onNodeTapped)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.environment.background = .color(.black)
        arView.cameraMode = .nonAR
        arView.renderOptions = [.disableMotionBlur]

        context.coordinator.arView = arView

        // Load the USDZ model
        loadModel(in: arView, context: context)

        // Place node spheres
        placeNodeSpheres(in: arView, context: context)

        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(DollhouseCoordinator.handleTap(_:))
        )
        arView.addGestureRecognizer(tapGesture)

        // Set initial camera
        setupCamera(arView)

        onLoaded?()
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    // MARK: - Model Loading

    private func loadModel(in arView: ARView, context: Context) {
        guard let url = usdzURL, FileManager.default.fileExists(atPath: url.path) else {
            // If no USDZ, create a floor plane as placeholder
            let floor = ModelEntity(
                mesh: .generatePlane(width: 5, depth: 5),
                materials: [SimpleMaterial(color: UIColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1), isMetallic: false)]
            )
            let anchor = AnchorEntity(world: .zero)
            anchor.addChild(floor)
            arView.scene.anchors.append(anchor)
            return
        }

        Task {
            do {
                let entity = try Entity.load(contentsOf: url)
                let anchor = AnchorEntity(world: .zero)
                anchor.addChild(entity)
                await MainActor.run {
                    arView.scene.anchors.append(anchor)
                }
            } catch {
                await MainActor.run {
                    onError?("Failed to load 3D model: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Node Spheres

    private func placeNodeSpheres(in arView: ARView, context: Context) {
        let anchor = AnchorEntity(world: .zero)

        for (index, node) in nodes.enumerated() {
            // Create pulsing sphere
            let sphere = ModelEntity(
                mesh: .generateSphere(radius: 0.06),
                materials: [createNodeMaterial()]
            )
            sphere.position = node.position
            sphere.name = "node_\(index)"

            // Add collision for tap detection
            sphere.generateCollisionShapes(recursive: false)

            // Add to scene
            anchor.addChild(sphere)

            // Outer glow ring
            let ring = ModelEntity(
                mesh: .generateSphere(radius: 0.09),
                materials: [createGlowMaterial()]
            )
            ring.position = node.position
            ring.name = "ring_\(index)"
            anchor.addChild(ring)

            // Create pulsing animation
            addPulseAnimation(to: sphere, ring: ring, delay: Double(index) * 0.2)
        }

        context.coordinator.nodeAnchor = anchor
        arView.scene.anchors.append(anchor)
    }

    // MARK: - Materials

    private func createNodeMaterial() -> SimpleMaterial {
        var material = SimpleMaterial()
        material.color = .init(tint: UIColor(red: 0.3, green: 0.69, blue: 0.31, alpha: 1.0))
        material.metallic = .float(0.8)
        material.roughness = .float(0.2)
        return material
    }

    private func createGlowMaterial() -> SimpleMaterial {
        var material = SimpleMaterial()
        material.color = .init(tint: UIColor(red: 0.3, green: 0.69, blue: 0.31, alpha: 0.15))
        material.metallic = .float(0.0)
        material.roughness = .float(1.0)
        return material
    }

    // MARK: - Pulse Animation

    private func addPulseAnimation(to sphere: ModelEntity, ring: ModelEntity, delay: Double) {
        // Scale pulse on the sphere
        let scaleUp = Transform(scale: SIMD3<Float>(repeating: 1.3))
        let scaleDown = Transform(scale: SIMD3<Float>(repeating: 1.0))

        // Animate sphere scale
        sphere.move(to: scaleUp, relativeTo: sphere.parent, duration: 1.0)

        // Recurring pulse via timer
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                let isExpanded = sphere.scale.x > 1.1
                let target = isExpanded ? scaleDown : scaleUp
                sphere.move(to: target, relativeTo: sphere.parent, duration: 1.0)

                // Ring pulse — slightly larger and offset
                let ringUp = Transform(scale: SIMD3<Float>(repeating: 1.5))
                let ringDown = Transform(scale: SIMD3<Float>(repeating: 1.0))
                let ringTarget = isExpanded ? ringDown : ringUp
                ring.move(to: ringTarget, relativeTo: ring.parent, duration: 1.2)
            }
        }
    }

    // MARK: - Camera Setup

    private func setupCamera(_ arView: ARView) {
        // Position camera above and behind, looking down at the model
        let cameraEntity = PerspectiveCamera()
        cameraEntity.camera.fieldOfViewInDegrees = 60
        cameraEntity.position = SIMD3(0, 3.5, 3.5)
        cameraEntity.look(at: .zero, from: cameraEntity.position, relativeTo: nil)

        let cameraAnchor = AnchorEntity(world: .zero)
        cameraAnchor.addChild(cameraEntity)
        arView.scene.anchors.append(cameraAnchor)
    }
}

// MARK: - Coordinator (Handles taps and camera animation)

class DollhouseCoordinator {
    var arView: ARView?
    var nodeAnchor: AnchorEntity?
    let nodes: [TourNode]
    var onNodeTapped: ((TourNode) -> Void)?

    init(nodes: [TourNode], onNodeTapped: ((TourNode) -> Void)?) {
        self.nodes = nodes
        self.onNodeTapped = onNodeTapped
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let arView = arView else { return }
        let location = gesture.location(in: arView)

        // Ray cast to find tapped entity
        let results = arView.hitTest(location)

        for result in results {
            let entity = result.entity
            let name = entity.name
            if name.hasPrefix("node_"),
               let indexStr = name.split(separator: "_").last,
               let index = Int(indexStr),
               index < nodes.count {

                let node = nodes[index]

                // Fly camera toward the node
                flyToNode(node, in: arView) {
                    // After animation, show panorama
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.onNodeTapped?(node)
                    }
                }
                return
            }
        }
    }

    /// Smoothly animates the camera to fly into a node's position.
    private func flyToNode(_ node: TourNode, in arView: ARView, completion: @escaping () -> Void) {
        // Find the camera entity
        guard let cameraAnchor = arView.scene.anchors.first(where: { anchor in
            anchor.children.contains(where: { $0 is PerspectiveCamera })
        }),
        let camera = cameraAnchor.children.first(where: { $0 is PerspectiveCamera }) else {
            completion()
            return
        }

        // Target position: slightly above and in front of the node
        let targetPosition = SIMD3<Float>(
            node.positionX,
            node.positionY + 0.3,
            node.positionZ + 0.5
        )

        var targetTransform = camera.transform
        targetTransform.translation = targetPosition

        // Animate camera
        camera.move(to: targetTransform, relativeTo: nil, duration: 0.8, timingFunction: .easeInOut)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            completion()
        }
    }
}
