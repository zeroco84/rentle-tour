# RentleTour

> Matterport-style 3D property scanning for iOS — built with SwiftUI, RoomPlan, ARKit, and RealityKit.

RentleTour is an open-source iOS app that lets property managers scan apartments with LiDAR, automatically capture high-resolution textures and 360° panoramic nodes, and upload the resulting tour bundle to a cloud processing pipeline that produces web-ready 3D virtual tours.

---

## Features

### 🏠 LiDAR Room Scanning
- Multi-room scanning via Apple's [RoomPlan](https://developer.apple.com/documentation/roomplan) framework
- Real-time 3D reconstruction as you walk through rooms
- `StructureBuilder` merges multiple room scans into one unified model
- Export as industry-standard `.usdz` file

### 📸 Automatic Texture & Panorama Capture
- **Auto-Texture Capture** — Continuously captures high-resolution texture frames during scanning using spatial triggers:
  - Distance trigger: every **0.5m** of device movement
  - Rotation trigger: every **45°** of device rotation
  - Sharpness filter rejects motion-blurred frames (checks exposure duration + AR tracking state)
  - All image processing (CVPixelBuffer → JPEG) on a background utility queue for 60fps scanning
- **Auto-360° Node Capture** — Automatically places panoramic nodes at wider intervals:
  - Distance trigger: every **2.0m** of device movement
  - Rotation trigger: every **90°** of device rotation
  - Only triggers when AR tracking is in `.normal` state
  - Manual "Capture 360°" button available as override for extra control
- **Room Type Tagging** — Dropdown selector for room types (Living Room, Kitchen, Bathroom, Bedroom, Other) during scanning

### 🏘️ Dollhouse Viewer
- RealityKit-powered non-AR "dollhouse" view of the scanned space
- Pulsing green spheres at each 360° capture node
- Tap a sphere → smooth camera fly-into animation → full-screen panorama viewer
- SceneKit-based equirectangular 360° image viewer with drag-to-look and inertia

### 🌐 In-App Tour Viewer
- View processed 3D tours directly within the app
- `WKWebView` + Google's [`<model-viewer>`](https://modelviewer.dev/) for GLB rendering
- Hotspots from the tour navigation graph placed on the 3D floor with pulse animations
- Camera fly-to interpolation when tapping hotspots
- Panorama mode toggle with canvas-based equirectangular panorama viewer
- Swift ↔ JavaScript bridge via `WKScriptMessageHandler`

### ☁️ Cloud Upload & Processing Pipeline
- Uploads full `.rentletour` ZIP bundle (not just `.usdz`)
- Handles `202 Accepted` for asynchronous processing
- Background polling for processing status updates
- Background upload support with iOS `URLSession` background transfers
- Network-aware queuing with automatic retry on reconnection

### 🔍 Apartment Selector
- Searchable apartment picker connected to the backend API
- Debounced search (300ms) via `GET /api/v1/admin/inspections/search_apartments`
- Shows building name, apartment number, and tenant details

### 🔐 Authentication
- JWT-based login via the admin API
- Keychain-backed token persistence with auto-login on launch
- Two-step login: subdomain → credentials (multi-tenant support)

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

## Architecture

### System Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          iOS App (RentleTour)                          │
│                                                                         │
│  ┌──────────────┐  ┌───────────────┐  ┌──────────────────────────────┐ │
│  │ RoomPlan     │  │ Auto-Texture  │  │ SpatialCapture               │ │
│  │ Scanner      │──│ Capture       │──│ Manager (360° Nodes)         │ │
│  │              │  │ Manager       │  │                              │ │
│  └──────┬───────┘  └───────┬───────┘  └──────────────┬───────────────┘ │
│         │                  │                          │                 │
│         ▼                  ▼                          ▼                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                     TourBundle (.rentletour ZIP)                 │   │
│  │  structure.usdz + tour_data.json + panoramas/ + textures/       │   │
│  └────────────────────────────┬────────────────────────────────────┘   │
│                               │                                        │
│  ┌────────────────────────────▼────────────────────────────────────┐   │
│  │              TourUploadService (multipart upload)               │   │
│  │              BackgroundUploadManager (offline queue)             │   │
│  └────────────────────────────┬────────────────────────────────────┘   │
└───────────────────────────────┼────────────────────────────────────────┘
                                │ POST /api/v1/admin/apartments/:id/virtual_tour
                                │ (application/zip, returns 202 Accepted)
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                       Rails Backend (Render)                            │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │  VirtualToursController#create                                    │ │
│  │  1. Attach ZIP to apartment via ActiveStorage (S3)                │ │
│  │  2. Set apartment.tour_processing_status = "queued"               │ │
│  │  3. Enqueue SQS message with { apartment_id, s3_key, callback }  │ │
│  │  4. Return 202 Accepted                                           │ │
│  └───────────────────────────────┬───────────────────────────────────┘ │
│                                  │                                      │
│  ┌───────────────────────────────▼───────────────────────────────────┐ │
│  │  TourCallbacksController (POST /api/v1/internal/tour_callback)    │ │
│  │  Receives status updates from Fargate: processing → completed     │ │
│  │  Updates apartment with model_url, nav_graph, panorama_urls       │ │
│  └───────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────┬──────────────────────────────────────┘
                                   │ SQS Message
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    AWS Fargate (Tour Processor)                         │
│                                                                         │
│  Python worker polling SQS queue:                                       │
│  1. Download ZIP from S3                                                │
│  2. Extract .usdz + textures + panoramas                                │
│  3. Convert USDZ → GLB (via usd2glb / trimesh)                         │
│  4. Stitch textures into WebP panoramas                                 │
│  5. Build navigation graph from tour_data.json node positions           │
│  6. Upload processed assets (GLB, panoramas) to S3/CDN                  │
│  7. POST callback to Rails with { status, model_url, nav_graph }        │
│                                                                         │
│  Cost: ~$0.007/tour, spin-up on demand, pay per second                  │
└─────────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     S3 / CloudFront CDN                                 │
│                                                                         │
│  /tours/{apartment_id}/                                                 │
│  ├── model.glb              # Web-ready 3D model                        │
│  ├── nav_graph.json          # Node positions + edges                   │
│  └── panoramas/                                                         │
│      ├── node_001.webp       # Stitched 360° panorama                   │
│      └── ...                                                            │
└─────────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                 Tour Viewer (in-app or web listing)                     │
│                                                                         │
│  Google <model-viewer> component renders GLB with:                      │
│  - Camera controls (orbit, zoom, pan)                                   │
│  - Hotspots from nav_graph positioned on the 3D floor                   │
│  - Click hotspot → camera fly-to + panorama viewer toggle               │
│  - Equirectangular canvas viewer for 360° panoramas                     │
└─────────────────────────────────────────────────────────────────────────┘
```

### State Management

```
RentleTourApp
  ├── AuthManager (@StateObject)          — auth state, token, user
  └── ScanManager (@StateObject)          — rooms, export URLs, apartment ID, upload status
       ├── TourBundle                     — in-memory tour data with disk-backed images
       ├── AutoTextureCaptureManager      — ARSession observer, spatial triggers, auto-capture
       └── SpatialCaptureManager          — 360° node position + image capture
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
  │                  (auto-texture + auto-360° running)
  │                  (manual 360° capture button available)
  │                       │ done
  │                       ▼
  │                  Review Screen
  │                  ├── Merge & Export
  │                  ├── Upload Tour ──→ 202 Accepted ──→ Status Polling
  │                  ├── View 3D Model (Dollhouse)
  │                  ├── Share File
  │                  └── Share Tour Bundle
  │                       │
  │                  Dollhouse Viewer
  │                       │ tap node
  │                       ▼
  │                  Panorama Viewer (360°)
  │
  │              ──→ Browse Tours ──→ Tour Viewer (WKWebView + model-viewer)
  │
  └─ Not Authenticated ──→ Login Screen
                            ├── Step 1: Subdomain
                            └── Step 2: Credentials
```

---

## Project Structure

```
RentleTour/
├── RentleTourApp.swift                # App entry point, splash screen, auth gating
├── EnvironmentConfig.swift            # Build-time environment selection (staging/production)
│
├── Auth
│   ├── AuthService.swift              # JWT login, Keychain persistence, auto-login
│   └── LoginView.swift                # Two-step login (subdomain → credentials)
│
├── Apartment Selection
│   ├── ApartmentService.swift         # API client + ApartmentDTO (incl. tour status fields)
│   └── ApartmentPickerView.swift      # Searchable apartment picker sheet
│
├── Scanning
│   ├── RoomCaptureController.swift    # ScanManager: room storage, merge, export, upload
│   ├── RoomPlanView.swift             # UIViewRepresentable for RoomCaptureView + overlays
│   ├── SpatialCaptureManager.swift    # 360° node capture (ARFrame position + image)
│   └── AutoTextureCaptureManager.swift# Auto-capture engine (textures + nodes via ARSession)
│
├── Tour Data
│   ├── TourDataModel.swift            # TourNode, TextureFrame, TourManifest, TourBundle
│   └── TourBundleExporter.swift       # .rentletour ZIP export
│
├── Upload & Processing
│   ├── TourUploadService.swift        # Multipart ZIP upload, 202 handling
│   ├── TourProcessingService.swift    # Status polling (queued → processing → completed)
│   ├── BackgroundUploadManager.swift  # Offline queue, background URLSession transfers
│   ├── NetworkMonitor.swift           # NWPathMonitor wrapper for connectivity state
│   └── SyncCenterView.swift           # Upload queue management UI
│
├── Tour Viewing
│   ├── TourService.swift              # Fetch processed tour data from backend
│   ├── TourViewerScreen.swift         # WKWebView + model-viewer wrapper + JS bridge
│   └── tour_viewer.html               # model-viewer template (bundled resource)
│
├── Viewers
│   ├── DollhouseViewer.swift          # RealityKit 3D dollhouse with node spheres
│   └── PanoramaViewer.swift           # SceneKit 360° equirectangular viewer
│
├── UI
│   └── ContentView.swift              # Landing screen, review, tour browser, property cards
│
└── Resources
    ├── Info.plist                      # Camera permission, environment variable
    └── Assets.xcassets/               # App icon, accent color
```

---

## API Contracts

### iOS App → Backend

| Method | Endpoint | Purpose | Response |
|---|---|---|---|
| `POST` | `/api/v1/admin/login` | Admin authentication | `200` + JWT token |
| `POST` | `/api/v1/technician/login` | Technician auth (fallback) | `200` + JWT token |
| `DELETE` | `/api/v1/admin/logout` | Server-side logout | `200` |
| `GET` | `/api/v1/admin/inspections/search_apartments?q=` | Apartment search | `200` + array |
| `POST` | `/api/v1/admin/apartments/:id/virtual_tour` | Upload `.rentletour` ZIP | **`202 Accepted`** |
| `GET` | `/api/v1/admin/apartments/:id/virtual_tour/status` | Poll processing status | `200` + status JSON |
| `GET` | `/api/v1/admin/apartments/:id/tour` | Fetch processed tour data | `200` + tour JSON |
| `GET` | `/api/v1/admin/apartments/with_tours` | List apartments with tours | `200` + array |

### Upload Request Format

```http
POST /api/v1/admin/apartments/895/virtual_tour
Authorization: Bearer <jwt_token>
Content-Type: multipart/form-data

file: <PropertyName_2026-03-06T13-33-04Z.rentletour>  (application/zip)
```

### Upload Response (202 Accepted)

```json
{
  "status": "queued",
  "message": "Tour uploaded and queued for processing",
  "apartment_id": 895
}
```

### Processing Status Response

```json
{
  "status": "completed",
  "apartment_id": 895,
  "tour_model_url": "https://cdn.example.com/tours/895/model.glb",
  "tour_nav_graph": {
    "nodes": [
      {
        "id": 1,
        "label": "Living Room",
        "position": [1.2, 0.0, -3.4],
        "panorama_url": "https://cdn.example.com/tours/895/panoramas/node_001.webp"
      }
    ],
    "edges": [[0, 1], [1, 2]]
  }
}
```

### Fargate → Backend Callback

```http
POST /api/v1/internal/tour_callback
X-Rentle-Task-Secret: <shared_secret>
Content-Type: application/json

{
  "apartment_id": 895,
  "status": "completed",
  "tour_model_url": "https://cdn.../model.glb",
  "tour_nav_graph": { ... },
  "tour_panorama_urls": ["https://cdn.../node_001.webp", ...]
}
```

---

## Tour Bundle Format (`.rentletour`)

A ZIP archive containing all scan data:

```
PropertyName_Tour.rentletour
├── structure.usdz             # 3D model of the scanned space
├── tour_data.json             # Manifest (see below)
├── panoramas/
│   ├── node_001_a1b2c3d4.jpg  # 360° capture with world-space position
│   ├── node_002_e5f6g7h8.jpg
│   └── ...
├── textures/
│   ├── tex_0001_i9j0k1l2.jpg  # Auto-captured texture frame
│   ├── tex_0002_m3n4o5p6.jpg
│   └── ...
└── objects/                    # (Optional) High-detail texture captures
    ├── fireplace.usdz
    └── ...
```

### Manifest (`tour_data.json`)

```json
{
  "property_name": "31-101 Carlisle Gardens",
  "created_at": "2026-03-06T13:33:04Z",
  "room_count": 3,
  "room_names": ["Living Room", "Kitchen", "Bedroom"],
  "structure_file": "structure.usdz",
  "nodes": [
    {
      "id": 0,
      "label": "Node 1",
      "position_x": 1.23,
      "position_y": 0.45,
      "position_z": -2.67,
      "transform": [1,0,0,0, 0,1,0,0, 0,0,1,0, 1.23,0.45,-2.67,1],
      "image_file_name": "node_001_a1b2c3d4.jpg",
      "room_index": 0
    }
  ],
  "images": [
    {
      "image_file_name": "tex_0001_i9j0k1l2.jpg",
      "transform": [1,0,0,0, 0,1,0,0, 0,0,1,0, 0.5,1.2,-1.3,1],
      "room_index": 0,
      "exposure_duration": 0.016,
      "image_width": 4032,
      "image_height": 3024
    }
  ]
}
```

> **Note:** The `transform` array is a column-major flat representation of the `simd_float4x4` camera transform matrix from ARKit (RoomPlan coordinate system: Y-up, right-handed).

---

## Backend Setup (Bring Your Own)

RentleTour is designed to work with any backend that implements the API contracts above. Here's what's needed:

### Required Infrastructure

| Component | Purpose | Example |
|---|---|---|
| **Web Server** | API endpoints, authentication, ActiveStorage | Rails on Render/Heroku/Fly |
| **Object Storage** | Store raw ZIP bundles + processed assets | AWS S3, Cloudflare R2, GCS |
| **Message Queue** | Decouple upload from processing | AWS SQS, Redis, RabbitMQ |
| **Tour Processor** | Convert USDZ → GLB, stitch panoramas | AWS Fargate, Cloud Run, self-hosted |
| **CDN** | Serve processed GLB + panorama assets | CloudFront, Cloudflare |

### Required Database Columns

```sql
ALTER TABLE apartments ADD COLUMN tour_processing_status VARCHAR;
ALTER TABLE apartments ADD COLUMN tour_model_url VARCHAR;
ALTER TABLE apartments ADD COLUMN tour_nav_graph JSONB;
ALTER TABLE apartments ADD COLUMN tour_panorama_urls JSONB;
```

### Required Environment Variables (Backend)

| Variable | Purpose |
|---|---|
| `TOUR_PROCESSING_QUEUE_URL` | SQS queue URL for processing jobs |
| `TOUR_PROCESSING_CALLBACK_SECRET` | Shared secret for Fargate → Rails callbacks |
| `AWS_ACCESS_KEY_ID` | IAM credentials with S3 + SQS permissions |
| `AWS_SECRET_ACCESS_KEY` | IAM credentials |
| `AWS_REGION` | e.g. `eu-west-1` |

### IAM Permissions Required

The IAM user needs at minimum:
- `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject` on the tour storage bucket
- `sqs:SendMessage` on the processing queue

---

## Auto-Capture Configuration

The spatial trigger thresholds can be tuned in `AutoTextureCaptureManager.swift`:

| Parameter | Default | Description |
|---|---|---|
| `distanceThreshold` | `0.5m` | Min distance between texture captures |
| `rotationThreshold` | `45°` | Min rotation between texture captures |
| `minCaptureInterval` | `0.5s` | Rate limiter for texture captures |
| `maxExposureDuration` | `1/30s` | Reject frames with longer exposure (motion blur) |
| `jpegQuality` | `0.85` | JPEG compression for saved textures |
| `nodeDistanceThreshold` | `2.0m` | Min distance between auto-360° node captures |
| `nodeRotationThreshold` | `90°` | Min rotation between auto-360° node captures |
| `nodeMinInterval` | `3.0s` | Rate limiter for 360° node captures |
| `autoNodeCaptureEnabled` | `true` | Toggle automatic 360° node capture |

---

## Frameworks & Technologies

| Framework | Usage |
|---|---|
| **SwiftUI** | All UI screens and navigation |
| **RoomPlan** | LiDAR-based room scanning and structure merging |
| **RealityKit** | Dollhouse 3D viewer, model loading, camera animation |
| **ARKit** | World-space position capture via `ARFrame.camera.transform` |
| **SceneKit** | 360° panorama viewer (equirectangular sphere mapping) |
| **WebKit** | In-app tour viewer via WKWebView + JS bridge |
| **CoreImage** | GPU-backed pixel buffer → image conversion |
| **Security** | Keychain token storage |
| **Network** | NWPathMonitor for connectivity-aware uploads |

---

## Build Configurations

The app uses a custom `ENVIRONMENT` build setting injected via `Info.plist`:

| Configuration | `ENVIRONMENT` value | Behavior |
|---|---|---|
| Debug (Production) | `production` | Points to `<subdomain>.rentle.ai` |
| Debug (Staging) | `staging` | Points to `staging.<subdomain>.rentle.ai`, shows "(S)" suffix |

---

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## License

MIT License — see [LICENSE](LICENSE) for details.

© 2026 [Rentle.ai](https://rentle.ai)
