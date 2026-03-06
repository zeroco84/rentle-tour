// TourViewerScreen.swift
// RentleTour
//
// Full-screen viewer for processed 3D tours.
// Uses WKWebView + Google's <model-viewer> to render GLB models.
// Hotspots from tour_nav_graph placed on the 3D floor.
// Swift ↔ JS bridge via WKScriptMessageHandler.
// UI follows Apple iOS Human Interface Guidelines.

import SwiftUI
import WebKit

// MARK: - Tour Viewer Screen

struct TourViewerScreen: View {
    let tourData: ApartmentTourData

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var selectedPanoramaURL: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                // Web-based 3D viewer
                TourWebView(
                    tourData: tourData,
                    onHotspotTap: { nodeId, label, panoramaUrl in
                        if let url = panoramaUrl, !url.isEmpty {
                            selectedPanoramaURL = url
                        }
                    },
                    onLoadComplete: {
                        withAnimation(.easeOut(duration: 0.3)) {
                            isLoading = false
                        }
                    }
                )
                .ignoresSafeArea()

                // Loading overlay
                if isLoading {
                    ZStack {
                        Color.black.opacity(0.8)
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.3)
                                .tint(.white)
                            Text("Loading 3D Tour…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
                }
            }
            .navigationTitle(tourData.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - WKWebView Wrapper

struct TourWebView: UIViewRepresentable {
    let tourData: ApartmentTourData
    var onHotspotTap: (Int, String?, String?) -> Void
    var onLoadComplete: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onHotspotTap: onHotspotTap, onLoadComplete: onLoadComplete)
    }

    func makeUIView(context: Context) -> WKWebView {
        // Configure WKWebView with JS message handler
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // Register the Swift ↔ JS bridge
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "tourBridge")
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator

        // Load the local HTML template
        if let htmlURL = Bundle.main.url(forResource: "tour_viewer", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }

        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var webView: WKWebView?
        var onHotspotTap: (Int, String?, String?) -> Void
        var onLoadComplete: () -> Void
        private var hasInjectedData = false

        init(
            onHotspotTap: @escaping (Int, String?, String?) -> Void,
            onLoadComplete: @escaping () -> Void
        ) {
            self.onHotspotTap = onHotspotTap
            self.onLoadComplete = onLoadComplete
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !hasInjectedData else { return }
            hasInjectedData = true

            // Inject tour data into the web view
            injectTourData()
        }

        // MARK: WKScriptMessageHandler

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "tourBridge",
                  let body = message.body as? String,
                  let data = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            let action = json["action"] as? String

            switch action {
            case "hotspotTapped":
                let nodeId = json["nodeId"] as? Int ?? 0
                let label = json["label"] as? String
                let panoramaUrl = json["panoramaUrl"] as? String
                DispatchQueue.main.async { [self] in
                    onHotspotTap(nodeId, label, panoramaUrl)
                }

            case "modelLoaded":
                DispatchQueue.main.async { [self] in
                    onLoadComplete()
                }

            default:
                break
            }
        }

        // MARK: - Data Injection

        private func injectTourData() {
            // Build the tour data payload for JavaScript
            var payload: [String: Any] = [:]

            // modelUrl is set via getModelUrl() below

            // Override with the actual tour model URL
            if let modelUrl = getModelUrl() {
                payload["modelUrl"] = modelUrl
            }

            // Add navigation graph
            if let navGraph = getNavGraphData() {
                payload["navGraph"] = navGraph
            }

            // Convert to JSON string
            guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                return
            }

            // Escape for JavaScript
            let escapedJSON = jsonString
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")

            let js = "window.initTourFromSwift('\(escapedJSON)');"
            webView?.evaluateJavaScript(js) { _, error in
                if let error {
                    print("[TourViewer] JS injection error: \(error)")
                }
            }
        }

        private func getModelUrl() -> String? {
            // Get the URL from coordinator's parent context
            // We'll pass this through the view hierarchy
            return nil // Will be set via makeUIView context
        }

        private func getNavGraphData() -> [String: Any]? {
            return nil // Will be set via makeUIView context
        }
    }
}

// MARK: - Enhanced TourWebView with data passing

struct TourModelWebView: UIViewRepresentable {
    let modelURL: String
    let navGraph: NavGraphDTO?
    var onHotspotTap: (Int, String?, String?) -> Void
    var onLoadComplete: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            modelURL: modelURL,
            navGraph: navGraph,
            onHotspotTap: onHotspotTap,
            onLoadComplete: onLoadComplete
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "tourBridge")
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator

        if let htmlURL = Bundle.main.url(forResource: "tour_viewer", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }

        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var webView: WKWebView?
        let modelURL: String
        let navGraph: NavGraphDTO?
        var onHotspotTap: (Int, String?, String?) -> Void
        var onLoadComplete: () -> Void
        private var hasInjectedData = false

        init(
            modelURL: String,
            navGraph: NavGraphDTO?,
            onHotspotTap: @escaping (Int, String?, String?) -> Void,
            onLoadComplete: @escaping () -> Void
        ) {
            self.modelURL = modelURL
            self.navGraph = navGraph
            self.onHotspotTap = onHotspotTap
            self.onLoadComplete = onLoadComplete
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !hasInjectedData else { return }
            hasInjectedData = true

            var payload: [String: Any] = ["modelUrl": modelURL]

            if let navGraph {
                var graphDict: [String: Any] = [:]
                graphDict["nodes"] = navGraph.nodes.map { node -> [String: Any] in
                    var dict: [String: Any] = [
                        "id": node.id,
                        "position": node.position.map { Double($0) },
                        "panorama_url": node.panoramaUrl
                    ]
                    if let label = node.label {
                        dict["label"] = label
                    }
                    return dict
                }
                graphDict["edges"] = navGraph.edges.map { $0.map { Int($0) } }
                payload["navGraph"] = graphDict
            }

            guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                return
            }

            let escapedJSON = jsonString
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")

            let js = "window.initTourFromSwift('\(escapedJSON)');"
            webView.evaluateJavaScript(js) { [weak self] _, error in
                if let error {
                    print("[TourViewer] JS error: \(error)")
                }
                DispatchQueue.main.async {
                    self?.onLoadComplete()
                }
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "tourBridge",
                  let body = message.body as? String,
                  let data = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            if json["action"] as? String == "hotspotTapped" {
                let nodeId = json["nodeId"] as? Int ?? 0
                let label = json["label"] as? String
                let panoramaUrl = json["panoramaUrl"] as? String
                DispatchQueue.main.async { [self] in
                    onHotspotTap(nodeId, label, panoramaUrl)
                }
            }
        }
    }
}

// MARK: - Processed Tour Viewer (uses TourModelWebView)

struct ProcessedTourViewer: View {
    let tourData: ApartmentTourData

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                if let modelUrl = tourData.tourModelUrl {
                    TourModelWebView(
                        modelURL: modelUrl,
                        navGraph: tourData.tourNavGraph,
                        onHotspotTap: { nodeId, label, panoramaUrl in
                            print("[TourViewer] Hotspot tapped: \(label ?? "unknown")")
                        },
                        onLoadComplete: {
                            withAnimation { isLoading = false }
                        }
                    )
                    .ignoresSafeArea()
                } else {
                    ContentUnavailableView {
                        Label("No Tour Data", systemImage: "view.3d")
                    } description: {
                        Text("The 3D model for this tour is not available yet.")
                    }
                }

                if isLoading && tourData.tourModelUrl != nil {
                    ZStack {
                        Color.black.opacity(0.8)
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.3)
                                .tint(.white)
                            Text("Loading 3D Tour…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .ignoresSafeArea()
                }
            }
            .navigationTitle(tourData.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
