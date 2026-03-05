# RentleTour

> Matterport-style 3D room scanning for landlords — built with SwiftUI, RoomPlan, and RealityKit.

RentleTour is a standalone iOS app that lets property managers scan apartments with LiDAR, capture 360° panoramic nodes, and upload the resulting 3D model directly to the [Rentle.ai](https://rentle.ai) platform.

---

## Screenshots

```
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│  ╔══╗  ╔══╗  ╔══╗│    │ > search          │    │ // review        │
│  ║▓▓║  ║░░║  ║▓▓║│    │ ┌───────────────┐ │    │ 3 room(s)        │
│  ╚══╝  ╚══╝  ╚══╝│    │ │hamilton ga... │ │    │                  │
│  ═══════════════ ││    │ └───────────────┘ │    │ [merge_and_      │
│  ▓▓▓▓▓ ░░░ ▓▓▓▓ ││    │                  │    │  export />]      │
│  r e n t l e .ai │    │ Hamilton Gardens │    │ [upload_tour />] │
│                  │    │   G-302 (Smith)  │    │ [share_file />]  │
│ [select_apart />]│    │   G-303 (Vacant) │    │                  │
└──────────────────┘    └──────────────────┘    └──────────────────┘
     Splash/Login         Apartment Picker         Review & Upload
```

## Features

### 🏠 LiDAR Room Scanning
- Multi-room scanning via Apple's [RoomPlan](https://developer.apple.com/documentation/roomplan) framework
- Real-time 3D reconstruction as you walk through rooms
- `StructureBuilder` merges multiple room scans into one unified model
- Export as industry-standard `.usdz` file

### 📍 Hybrid Capture Flow (Matterport-Style)
- **360° Spatial Anchoring** — Tap "Capture 360° View" during a scan to record the device's exact world-space position via `ARFrame.camera.transform`, along with a high-res camera snapshot
- **Object Capture** — Guided photo capture of specific surfaces (fireplace, kitchen island) for high-detail texture overlay
- **Tour Bundle Export** — Packages everything into a `.rentletour` ZIP containing:
  - `structure.usdz` — 3D model
  - `tour_data.json` — Manifest linking node coordinates to images
  - `panoramas/` — High-res 360° images
  - `objects/` — Texture capture models

### 🏘️ Dollhouse Viewer
- RealityKit-powered non-AR "dollhouse" view of the scanned space
- Pulsing green spheres at each 360° capture node
- Tap a sphere → smooth camera fly-into animation → full-screen panorama viewer
- SceneKit-based equirectangular 360° image viewer with drag-to-look and inertia

### 🔍 Apartment Selector
- Searchable apartment picker sheet connected to the Rentle backend
- Debounced search (300ms) via `GET /api/v1/admin/inspections/search_apartments`
- Shows building name, apartment number, and tenant details
- Selecting an apartment starts the scanner with the apartment pre-linked

### ☁️ Tour Upload
- Multipart `.usdz` upload via `POST /api/v1/admin/apartments/:id/virtual_tour`
- Upload progress states: idle → uploading (spinner) → ✓ uploaded / ✗ error (retry)
- Share sheet fallback for manual file sharing

### 🔐 Authentication
- JWT-based login via the Rentle admin API
- Keychain-backed token persistence with auto-login on launch
- Two-step login: subdomain → credentials (multi-tenant support)
- Animated boot sequence splash screen

---

## Requirements

| Requirement | Minimum |
|---|---|
| iOS | 17.0+ |
| Device | iPhone 12 Pro+ or iPad Pro 2020+ (LiDAR required) |
| Xcode | 15.2+ |
| Swift | 5.9+ |

---

## Getting Started

### 1. Clone the repo

```bash
git clone https://github.com/zeroco84/rentle-tour.git
cd rentle-tour
```

### 2. Open in Xcode

```bash
open RentleTour.xcodeproj
```

### 3. Select a scheme

| Scheme | Environment | API Base URL |
|---|---|---|
| **RentleTour** | Production | `https://<subdomain>.rentle.ai` |
| **RentleTour (Staging)** | Staging | `https://staging.<subdomain>.rentle.ai` |

### 4. Build & Run

Select your target device (must have LiDAR) and press ⌘R.

> **Note:** RoomPlan does not work in the iOS Simulator. You must run on a physical LiDAR-equipped device.

---

## Project Structure

```
RentleTour/
├── RentleTourApp.swift           # App entry point, splash screen, auth gating
├── EnvironmentConfig.swift       # Build-time environment selection (staging/production)
│
├── Auth
│   ├── AuthService.swift         # JWT login, Keychain persistence, auto-login
│   └── LoginView.swift           # Terminal-styled two-step login (subdomain → credentials)
│
├── Apartment Selection
│   ├── ApartmentService.swift    # API client for search_apartments endpoint
│   └── ApartmentPickerView.swift # Searchable apartment picker sheet
│
├── Scanning
│   ├── RoomCaptureController.swift  # ScanManager: room storage, merge, export, upload
│   ├── RoomPlanView.swift           # UIViewRepresentable for RoomCaptureView + 360° capture
│   └── SpatialCaptureManager.swift  # ARFrame position capture + image saving
│
├── Hybrid Capture
│   ├── TourDataModel.swift       # TourNode, CapturedObject, TourManifest, TourBundle
│   ├── ObjectCaptureView.swift   # Guided texture capture with processing pipeline
│   ├── TourBundleExporter.swift  # .rentletour ZIP export
│   └── TourUploadService.swift   # Multipart .usdz upload to backend
│
├── Viewers
│   ├── DollhouseViewer.swift     # RealityKit 3D dollhouse view with node spheres
│   └── PanoramaViewer.swift      # SceneKit 360° equirectangular image viewer
│
├── UI
│   └── ContentView.swift         # Landing screen, PropertyCard, ReviewScreen, RentleBrand colors
│
└── Resources
    ├── Info.plist                 # Camera permission, environment variable
    └── Assets.xcassets/          # App icon, accent color
```

---

## Architecture

### State Management

```
RentleTourApp
  ├── AuthManager (@StateObject)     — auth state, token, user
  └── ScanManager (@StateObject)     — rooms, export URLs, apartment ID, upload status
       ├── TourBundle                — in-memory tour data with disk-backed images
       └── SpatialCaptureManager     — ARFrame position + image capture
```

Both managers are injected via `@EnvironmentObject` and shared across all screens.

### App Flow

```
Splash (boot sequence + auto-login)
  │
  ├─ Authenticated ──→ Landing Screen
  │                       │
  │                  [+ new] tap
  │                       │
  │              Apartment Picker Sheet
  │                       │ select
  │                       ▼
  │                  LiDAR Scanner
  │                  (+ 360° capture button)
  │                       │ done
  │                       ▼
  │                  Review Screen
  │                  ├── merge_and_export />
  │                  ├── upload_tour />
  │                  ├── share_file />
  │                  ├── export_tour_bundle />
  │                  └── view_dollhouse />
  │                       │
  │                  Dollhouse Viewer
  │                       │ tap node
  │                       ▼
  │                  Panorama Viewer (360°)
  │
  └─ Not Authenticated ──→ Login Screen
                            ├── Step 1: Subdomain
                            └── Step 2: Credentials
```

### Build Configurations

The app uses a custom `ENVIRONMENT` build setting injected via `Info.plist`:

| Configuration | `ENVIRONMENT` value | Behavior |
|---|---|---|
| Debug (Production) | `production` | Points to `<subdomain>.rentle.ai` |
| Debug (Staging) | `staging` | Points to `staging.<subdomain>.rentle.ai`, shows "(S)" suffix |

---

## API Endpoints Used

| Method | Endpoint | Purpose |
|---|---|---|
| `POST` | `/api/v1/admin/login` | Admin authentication |
| `POST` | `/api/v1/technician/login` | Technician authentication (fallback) |
| `DELETE` | `/api/v1/admin/logout` | Server-side logout |
| `GET` | `/api/v1/admin/inspections/search_apartments?q=` | Apartment search |
| `POST` | `/api/v1/admin/apartments/:id/virtual_tour` | Upload .usdz tour file |

---

## Frameworks & Technologies

| Framework | Usage |
|---|---|
| **SwiftUI** | All UI screens and navigation |
| **RoomPlan** | LiDAR-based room scanning and structure merging |
| **RealityKit** | Dollhouse 3D viewer, model loading, camera animation |
| **ARKit** | World-space position capture via `ARFrame.camera.transform` |
| **SceneKit** | 360° panorama viewer (equirectangular sphere mapping) |
| **CoreImage** | Camera frame → UIImage conversion |
| **Security** | Keychain token storage |
| **Foundation** | NSFileCoordinator ZIP creation, multipart uploads |

---

## Design System

The UI follows a **terminal/hacker aesthetic** matching the Rentle-Assist companion app:

- **Colors:** Pure black backgrounds (`#0A0A0A`) with subtle blue radial glows, green accents (`#4CAF50`)
- **Typography:** Monospaced fonts (`Courier`, `.monospaced`) throughout
- **Borders:** Sharp rectangular borders — no rounded corners anywhere
- **Buttons:** `snake_case` labels with `/>` suffix (e.g., `upload_tour />`)
- **Status indicators:** Green ✓ success, orange pending, blue in-progress, red ✗ error
- **Animations:** Fade-in sequences, typing animation on splash, pulsing node spheres

Color constants are defined in `RentleBrand` (in `ContentView.swift`):

```swift
enum RentleBrand {
    static let background      = Color(hex: "0A0A0A")
    static let surface         = Color(hex: "0F0F0F")
    static let border          = Color(hex: "1E1E1E")
    static let textPrimary     = Color(hex: "E0E0E0")
    static let textSecondary   = Color(hex: "5C6370")
    static let green           = Color(hex: "4CAF50")
    static let blue            = Color(hex: "0A84FF")
    static let red             = Color(hex: "FF453A")
    static let orange          = Color(hex: "FF9F0A")
}
```

---

## Export Formats

### `.usdz` (Standard 3D Model)
Universal Scene Description format. Viewable in:
- Apple Quick Look
- Xcode
- Reality Composer
- Any USDZ-compatible viewer

### `.rentletour` (Custom Tour Bundle)
A ZIP archive containing:
```
PropertyName_Tour.rentletour
├── structure.usdz        # 3D model of the scanned space
├── tour_data.json         # Node positions, image filenames, metadata
├── panoramas/
│   ├── node_001.jpg       # 360° capture at position (x, y, z)
│   ├── node_002.jpg
│   └── ...
└── objects/
    ├── fireplace.usdz     # High-detail texture capture
    └── ...
```

---

## License

Proprietary — Rentle.ai © 2026
