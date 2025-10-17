## V2X Pedestrian Alert — quick AI agent guide

Purpose: Help an AI coding agent become productive quickly while editing the Flutter V2X app in this repo.

High-level architecture
- Single Flutter app located at `flutter_app/v2x_application`.
- UI entry: `lib/main.dart` → launches `lib/screens/map_screen.dart` (the map + vehicle/pedestrian UI).
- Backend integration: `lib/services/api_service.dart` communicates with a Flask backend using three endpoints: `/get-pedestrians`, `/update-location`, `/update-pedestrian`.

Key data shapes and contracts
- `ApiService.fetchPedestrians()` returns a List of maps: each item expected to contain `{ "id": "p1", "lat": <double>, "lon": <double> }` (UI expects `lat`/`lon`).
- A typed model now exists at `lib/models/pedestrian.dart` (class `Pedestrian` with `uid`, `lat`, `lon`, `timestamp`). Backend JSON may use `id`/`_id`/`uid` and timestamps as ISO strings or epoch ms — `Pedestrian.fromMap` normalizes them.

Important implementation patterns to follow
- Map + location handling: `lib/screens/map_screen.dart` uses `geolocator`'s position stream and `flutter_map`'s `MapController`.
  - It uses `WidgetsBinding.instance.addPostFrameCallback` before calling `_mapController.move(...)` to avoid controller-not-ready errors. Mirror that pattern when moving the camera.
  - Location permission flow is explicit: check service, request permissions, and surface errors via `ScaffoldMessenger.of(context).showSnackBar(...)`.
- Network handling: `lib/services/api_service.dart` defensively checks for HTML responses (common when a temporary ngrok URL redirects to an auth/error page) and throws a clear FormatException including a response snippet. When calling the API, prefer catching and surfacing that message.
- Debugging/logging: this project prefers `debugPrint(...)` (and sometimes `print`) for quick logs — keep that pattern when adding instrumentation.

Project-specific conventions
- Keep API base URL in `lib/services/api_service.dart` (static const `baseUrl`). The repo currently uses an ephemeral ngrok URL — update it for local testing or CI.
- Prefer using the typed `Pedestrian` model in new logic; existing API helpers still accept raw Maps. `Pedestrian.toMap()` serializes `timestamp` as ISO string.
- Distance helpers live in `lib/utils/distance_calculator.dart`: use `distanceMeters()` (Haversine) for geodesic distance and `displacementMeters()`/`displacementLength()` for equirectangular displacement and vector math.
- A developer-side example direct Mongo client is available at `lib/services/mongo_client_example.dart` using `mongo_dart`. The canonical app path is via the Flask backend; the mongo example is optional for prototyping.
- Linting & analysis: `analysis_options.yaml` + `flutter_lints` are enabled. Run `flutter analyze` and fix offenses to keep changes consistent with the repo style.

Developer workflows & commands
- Get dependencies:
  - `flutter pub get` (run from `flutter_app/v2x_application` or the repo root that contains the Flutter project)
- Run locally:
  - `flutter run` (specify device with `-d <id>` as needed)
  - On iOS simulators, ensure pods are installed: `cd ios && pod install`
- Build:
  - Android APK: `flutter build apk`
  - iOS: `flutter build ios` (macOS + Xcode required)
- Tests and static checks:
  - `flutter test`
  - `flutter analyze`

Integration & troubleshooting tips
- If `fetchPedestrians()` throws a FormatException with HTML snippet, check that `ApiService.baseUrl` points to the correct backend and that ngrok (or reverse-proxy) isn't serving an auth/interstitial page.
- To simulate location in an emulator, use the platform emulator's location controls (Android Studio or Xcode). The app expects location updates and uses a small `distanceFilter` (3m) in `map_screen`.
- If Map movement is not working, ensure the `MapController` has been initialized and use `addPostFrameCallback` as in `lib/screens/map_screen.dart`.

Files you will edit most often
- UI: `lib/screens/map_screen.dart`
- Network: `lib/services/api_service.dart` (now contains CRUD: `createPedestrian`, `getPedestrian`, `updatePedestrianById`, `deletePedestrian`, plus `queryByDistance` and `queryByDisplacement`).
- Models/helpers: `lib/models/pedestrian.dart`, `lib/utils/distance_calculator.dart`
- Optional DB helper: `lib/services/mongo_client_example.dart` (direct Mongo demos using `mongo_dart`).
- Entry point: `lib/main.dart`

Where to be conservative and why
- Do not change the API contract shape for `fetchPedestrians()` without updating the Map rendering logic; the UI maps expect list items with `lat` and `lon` keys.
- Prefer preserving visible user-facing error messages (SnackBars) rather than replacing them with silent logs.

If you need clarification
- Ask for current backend endpoint, preferred environment variable strategy (the code currently uses a hard-coded `baseUrl`), and whether typed `Pedestrian` models should be introduced now or later.

---
Please review and tell me if you want more details (example snippets, preferred env strategy, or tests to accompany changes).
