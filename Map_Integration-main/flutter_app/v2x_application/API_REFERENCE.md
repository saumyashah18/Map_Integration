# API Reference - V2X Pedestrian Alert System

## 📚 Complete API Documentation

This document lists all public APIs (methods & classes) in each file and how they are called.

---

## 📄 File: `lib/main.dart`

### Classes
None (entry point only)

### Functions
```dart
void main()
```
- **Purpose**: Application entry point
- **Called by**: Flutter runtime
- **What it does**: Runs the app with `V2XApp()`

### Widgets
```dart
class V2XApp extends StatelessWidget
```
- **Purpose**: Root widget of the application
- **Called by**: `main()` → `runApp()`
- **Methods**:
  - `build(BuildContext context)` → Returns MaterialApp with MapScreen

---

## 🗺️ File: `lib/screens/Dashboard.dart`

### Main Widget
```dart
class MapScreen extends StatefulWidget
```
- **Purpose**: Main UI screen with map and pedestrian management
- **Created by**: `main.dart` → `V2XApp.build()`

### State Class
```dart
class _MapScreenState extends State<MapScreen>
```

#### Public Lifecycle Methods

| Method | Called By | Purpose |
|---|---|---|
| `initState()` | Flutter | Initialize location, fetch pedestrians, start timers |
| `dispose()` | Flutter | Clean up subscriptions and timers |
| `build(BuildContext)` | Flutter | Render UI (map, markers, alerts, panels) |

#### Private Methods (Called Internally)

| Method | Called From | Purpose |
|---|---|---|
| `_handleLocationPermission()` | `_initLocation()` | Request GPS permission from OS |
| `_initLocation()` | `initState()` | Get initial GPS location, start continuous GPS stream |
| `_startDistanceChecking()` | `_initLocation()` | Start 5-second timer for distance calculations |
| `_fetchPedestriansFromBackend()` | `initState()` | Fetch pedestrian list from backend API |
| `_checkAllPedestrianDistances()` | Timer (5s), `_fetchPedestriansFromBackend()` | **Main loop**: Calculate distances, detect collisions, create alerts |
| `_spawnProxyPedestrian()` | User button tap | Add single random pedestrian to map |
| `_spawnMultiplePedestrians(int count)` | User button tap | Add multiple pedestrians in a loop |
| `_showRouteToPedestrian(ped)` | User tap on marker | Request A* route and draw on map |
| `_clearRoute()` | User button tap | Clear displayed route |
| `_startCacheCleanup()` | `initState()` | Start 1-minute timer to clean distance cache |

#### API Calls Made from Dashboard

```dart
// 1. Location API (Geolocator)
Geolocator.isLocationServiceEnabled()
Geolocator.checkPermission()
Geolocator.requestPermission()
Geolocator.getCurrentPosition()
Geolocator.getPositionStream()

// 2. Backend API Service
_apiService.fetchPedestrians()           // Get pedestrian list
_apiService.updateLocation(lat, lon)     // Send vehicle GPS
_apiService.updatePedestrian(lat, lon)   // Send alert when detected
_apiService.snapToRoad(location)         // Snap pedestrian to road

// 3. Distance Service
_distanceService.calculateDistancesToMultiplePedestrians(vehicle, pedestrians)
_distanceService.cleanCache()
_distanceService.clearCache()
_distanceService.getStatusInfo()

// 4. A* Routing Service
AStarPathfinder.getRoute(start, goal)
```

#### Classes Used

```dart
class PedestrianAlertData
```
- **Fields**:
  - `String pedestrianId`
  - `LatLng pedestrianLocation`
  - `double distanceMeters`
  - `double durationSeconds`
  - `DateTime detectionTime`
  - `bool isNew`

---

## 🚗 File: `lib/services/api_service.dart`

### Main Class
```dart
class ApiService
```

#### Public Methods

##### 1. Fetch Pedestrians
```dart
Future<List<Pedestrian>> fetchPedestrians()
```
- **Called by**: `Dashboard._checkAllPedestrianDistances()`
- **Endpoint**: `GET https://frothy-bebe-sirenically.ngrok-free.dev/get-pedestrians`
- **Returns**: List of pedestrian objects
- **Usage**:
  ```dart
  final List<Pedestrian> pedestrians = await _apiService.fetchPedestrians();
  ```

##### 2. Update Vehicle Location
```dart
Future<void> updateLocation(double lat, double lon)
```
- **Called by**: `Dashboard` (GPS listener)
- **Endpoint**: `POST https://frothy-bebe-sirenically.ngrok-free.dev/update-location`
- **Payload**:
  ```json
  {
    "id": "vehicle1",
    "lat": 22.991929,
    "lon": 72.539674,
    "timestamp": "2025-11-16T10:30:45.123Z"
  }
  ```
- **Usage**:
  ```dart
  await _apiService.updateLocation(22.991929, 72.539674);
  ```

##### 3. Send Pedestrian Alert
```dart
Future<void> updatePedestrian(
  double lat,
  double lon, {
  String pedestrianId = "pedestrian1",
  String rsuId = "RSU1",
  String obuId = "OBU1",
  int pedestriansCount = 1,
})
```
- **Called by**: `Dashboard._checkAllPedestrianDistances()` (when collision detected)
- **Endpoint**: `POST https://frothy-bebe-sirenically.ngrok-free.dev/update-pedestrian`
- **Payload**:
  ```json
  {
    "id": "ped_1763269517291",
    "lat": 22.98635,
    "lon": 72.534636,
    "pedestrians_count": 1,
    "rsuid": "RSU1",
    "obuid": "OBU1",
    "timestamp": "2025-11-16T10:30:45.123Z"
  }
  ```
- **Usage**:
  ```dart
  await _apiService.updatePedestrian(
    22.98635,
    72.534636,
    pedestrianId: 'ped_1763269517291',
  );
  ```

##### 4. Snap to Road
```dart
Future<LatLng?> snapToRoad(LatLng coordinate)
```
- **Called by**: `Dashboard._spawnProxyPedestrian()`
- **Endpoint**: `GET https://router.project-osrm.org/nearest/v1/driving/lon,lat`
- **Returns**: `LatLng?` (snapped coordinate or null if failed)
- **Usage**:
  ```dart
  final snappedLocation = await _apiService.snapToRoad(testLocation);
  if (snappedLocation != null) {
    // Use snapped location
  }
  ```

##### 5. Calculate Real Road Distance (Unused but available)
```dart
Future<RealDistanceResult> calculateRealRoadDistance(LatLng start, LatLng end)
```
- **Currently unused** (functionality moved to `OptimizedDistanceService`)
- **Endpoint**: `GET https://router.project-osrm.org/route/v1/driving/lon1,lat1;lon2,lat2`
- **Returns**: `RealDistanceResult` object

##### 6. Check Pedestrian Proximity (Unused but available)
```dart
Future<ProximityCheckResult> checkPedestrianProximity(
  LatLng vehicleLocation,
  LatLng pedestrianLocation,
  double thresholdMeters,
)
```
- **Currently unused** (replaced by `OptimizedDistanceService`)
- **Returns**: `ProximityCheckResult` object

#### Result Classes

```dart
class RealDistanceResult
```
- **Fields**:
  - `double distanceMeters`
  - `double durationSeconds`
  - `bool success`
  - `String? errorMessage`
- **Getters**:
  - `double distanceKm` → meters / 1000
  - `double durationMinutes` → seconds / 60

```dart
class ProximityCheckResult
```
- **Fields**:
  - `bool isNearby`
  - `double distanceMeters`
  - `double durationSeconds`
  - `String? error`
- **Getters**:
  - `double distanceKm`
  - `double durationMinutes`

#### Data Models

```dart
class Pedestrian
```
- **Factory Constructor**: `Pedestrian.fromMap(Map<String, dynamic>)`
- **Fields**: id, lat, lon, timestamp

---

## 📏 File: `lib/services/optimized_distance_service.dart`

### Main Class
```dart
class OptimizedDistanceService
```

#### Configuration Constants
```dart
static const String osrmTableUrl = "https://router.project-osrm.org/table/v1/driving"
static const int cacheExpirySeconds = 120          // 2 minutes
static const int minRequestIntervalMs = 1000        // 1 second
```

#### Public Methods

##### 1. Calculate Distances to Multiple Pedestrians (MAIN API)
```dart
Future<Map<String, double>> calculateDistancesToMultiplePedestrians(
  LatLng vehicleLocation,
  List<PedestrianLocation> pedestrians,
)
```
- **Called by**: `Dashboard._checkAllPedestrianDistances()` (every 5 seconds)
- **Strategy**:
  1. Check cache for cached distances
  2. If all cached: return cached immediately ✅
  3. If not cached: call `_processBatch()` → OSRM Table API
  4. On timeout: switch to A* fallback → `_calculateAStarDistances()`
- **Returns**: `Map<String, double>` → `{pedestrianId: distanceMeters}`
- **Usage**:
  ```dart
  final distances = await _distanceService.calculateDistancesToMultiplePedestrians(
    _currentLocation!,
    pedestrianLocations,
  );
  
  // distances = {
  //   'ped_1234': 1396.5,
  //   'ped_5678': 2482.3,
  // }
  ```

##### 2. Calculate Distances Using A* (Alternative API)
```dart
Future<Map<String, double>> calculateDistancesUsingAStar(
  LatLng vehicleLocation,
  List<PedestrianLocation> pedestrians, {
  int concurrency = 4,
})
```
- **Called by**: User can call directly for A* routing
- **Strategy**:
  - Per-pair A* routing (slower but road-aware)
  - Concurrent batch processing (default 4 simultaneous requests)
  - With small delays between batches
- **Returns**: `Map<String, double>` → `{pedestrianId: distanceMeters}`
- **Usage**:
  ```dart
  final distances = await _distanceService.calculateDistancesUsingAStar(
    vehicle,
    pedestrians,
    concurrency: 8,  // More concurrent requests
  );
  ```

##### 3. Clean Expired Cache
```dart
void cleanCache()
```
- **Called by**: `Dashboard` (1-minute timer via `_startCacheCleanup()`)
- **Purpose**: Remove cache entries older than 120 seconds
- **Usage**:
  ```dart
  _distanceService.cleanCache();
  // Output: 🧹 Cleaned cache: 5 → 4 entries
  ```

##### 4. Clear All Cache
```dart
void clearCache()
```
- **Called by**: `Dashboard` (user "Clear All" button)
- **Purpose**: Remove all cache entries and reset state
- **Resets**:
  - `_distanceCache` (empty)
  - `_failureCount` (to 0)
  - `_backoffUntil` (to null)
  - `_useAStarFallback` (to false)
- **Usage**:
  ```dart
  _distanceService.clearCache();
  // Output: 🗑️ Cache cleared, state reset
  ```

##### 5. Get Status Information
```dart
String getStatusInfo()
```
- **Called by**: `Dashboard` (status panel)
- **Returns**: Status string with mode, cache size, backoff status
- **Example**:
  ```dart
  final status = _distanceService.getStatusInfo();
  // Returns: "Mode: OSRM API | Cache: 5 | Backoff: No"
  // or:      "Mode: A* Fallback | Cache: 3 | Backoff: Yes (15s)"
  ```
- **Usage**:
  ```dart
  Text(_distanceService.getStatusInfo())
  ```

#### Private Methods (Internal Use)

| Method | Called From | Purpose |
|---|---|---|
| `_processBatch()` | `calculateDistancesToMultiplePedestrians()` | Call OSRM Table API for a batch of pedestrians |
| `_calculateAStarDistances()` | Fallback path, `calculateDistancesUsingAStar()` | Per-pair A* routing via OSRM Route API |
| `_getCachedOrAStarDistances()` | Backoff timeout | Get cached or compute A* for backup period |
| `_enforceRateLimit()` | `_processBatch()` | Wait 1 second between batch requests |
| `_getCacheKey()` | Cache operations | Generate unique cache key from coordinates |

#### Helper Classes

```dart
class PedestrianLocation
```
- **Fields**:
  - `String id` → Pedestrian ID
  - `LatLng location` → Coordinates
- **Constructor**:
  ```dart
  PedestrianLocation(id: 'ped_123', location: LatLng(23.0, 72.5))
  ```

```dart
class CachedDistance
```
- **Fields**:
  - `double distanceMeters`
  - `double durationSeconds`
  - `DateTime timestamp`
- **Method**:
  - `bool isExpired()` → Check if older than 120 seconds

---

## 🛣️ File: `lib/utils/astar_pathfinder.dart`

### Main Class
```dart
class AStarPathfinder
```

#### Constants
```dart
static const String osrmEndpoint = "https://router.project-osrm.org/route/v1/driving"
```

#### Public Static Methods

##### 1. Calculate Road Distance
```dart
static Future<double> calculateRoadDistance(LatLng start, LatLng goal)
```
- **Called by**: `OptimizedDistanceService` (fallback), `Dashboard` (on error)
- **Endpoint**: `GET https://router.project-osrm.org/route/v1/driving/lon1,lat1;lon2,lat2`
- **Returns**: `double` → distance in meters (or `double.infinity` on error)
- **Usage**:
  ```dart
  final distance = await AStarPathfinder.calculateRoadDistance(
    LatLng(22.99, 72.53),
    LatLng(23.00, 72.55),
  );
  // Returns: 2312.2 (meters)
  ```

##### 2. Get Full Route
```dart
static Future<RouteData> getRoute(LatLng start, LatLng goal)
```
- **Called by**: `Dashboard._showRouteToPedestrian()` (user taps marker)
- **Endpoint**: `GET https://router.project-osrm.org/route/v1/driving/...`
- **Returns**: `RouteData` object with waypoints, distance, duration
- **Usage**:
  ```dart
  final route = await AStarPathfinder.getRoute(vehicleLocation, pedestrianLocation);
  setState(() {
    _routePoints = route.waypoints;  // For drawing polyline
  });
  ```

##### 3. Straight-Line Distance (Heuristic Only)
```dart
static double straightLineDistance(LatLng a, LatLng b)
```
- **Called by**: Used in debugging/testing
- **Purpose**: Quick Haversine calculation (NOT road distance)
- **Returns**: `double` → meters (straight line)
- **Usage**:
  ```dart
  final straight = AStarPathfinder.straightLineDistance(a, b);
  final road = await AStarPathfinder.calculateRoadDistance(a, b);
  debugPrint('Road vs Straight: $road vs $straight');
  ```

#### Result Class

```dart
class RouteData
```
- **Fields**:
  - `List<LatLng> waypoints` → Route coordinates
  - `double distanceMeters` → Total road distance
  - `double durationSeconds` → Estimated travel time
- **Usage**:
  ```dart
  final route = RouteData(
    waypoints: [LatLng(...), LatLng(...), ...],
    distanceMeters: 2312.2,
    durationSeconds: 217.8,
  );
  ```

---

## 📍 File: `lib/models/StaticPedestrian.dart`

### Model Class
```dart
class StaticPedestrian
```
- **Purpose**: Data model for pedestrian in the system
- **Fields**:
  - `String id` → Unique identifier
  - `LatLng roadLocation` → GPS coordinates
  - `bool isDetected` → Is within collision threshold?
  - `double? lastDetectionDistance` → Last calculated distance (meters)

- **Constructor**:
  ```dart
  StaticPedestrian({
    required String id,
    required LatLng roadLocation,
    bool isDetected = false,
    double? lastDetectionDistance,
  })
  ```

- **Usage**:
  ```dart
  final pedestrian = StaticPedestrian(
    id: 'ped_1763269517291',
    roadLocation: LatLng(22.98635, 72.534636),
    isDetected: true,
    lastDetectionDistance: 1396.5,
  );
  ```

---

## 📡 File: `lib/models/RSU.dart`

### Model Classes

```dart
class Pedestrian
```
- **Fields**:
  - `String id`
  - `double lat`
  - `double lon`
  - `String? timestamp`

- **Factory Constructor**:
  ```dart
  factory Pedestrian.fromJson(Map<String, dynamic> json)
  ```

- **Usage**:
  ```dart
  final ped = Pedestrian(
    id: 'ped_123',
    lat: 22.9863,
    lon: 72.5346,
  );
  ```

---

## 🔗 API Call Chain Summary

### On App Start
```
main.dart
  ↓
V2XApp.build()
  ↓
MapScreen.initState()
  ├→ _initLocation()
  │   ├→ Geolocator.getCurrentPosition()
  │   ├→ Geolocator.getPositionStream()  [continuous GPS]
  │   └→ _startDistanceChecking()        [5-sec timer]
  │
  ├→ _fetchPedestriansFromBackend()
  │   └→ ApiService.fetchPedestrians()   📡 API: GET /get-pedestrians
  │
  └→ _startCacheCleanup()                [1-min timer]
```

### Every 5 Seconds (Main Loop)
```
_checkAllPedestrianDistances()
  └→ OptimizedDistanceService.calculateDistancesToMultiplePedestrians()
      ├→ Check cache
      ├→ _processBatch()
      │   └→ OSRM Table API 📡 (batch distances)
      │       └→ On timeout: _calculateAStarDistances()
      │           └→ AStarPathfinder.calculateRoadDistance() 📡 (per-pair)
      │
      └→ For each pedestrian:
          ├→ Compare distance vs 2000m threshold
          └→ If collision:
              └→ ApiService.updatePedestrian() 📡 API: POST /update-pedestrian
```

### On GPS Update (Continuous)
```
Geolocator.getPositionStream()
  └→ _currentLocation updated
      └→ ApiService.updateLocation() 📡 API: POST /update-location
      └→ _mapController.move() (center map)
```

### User Taps Pedestrian Marker
```
Dashboard.build()
  └→ GestureDetector.onTap()
      └→ _showRouteToPedestrian()
          └→ AStarPathfinder.getRoute() 📡 OSRM Route API
              └→ setState()
                  └→ _routePoints = route.waypoints
                      └→ PolylineLayer renders blue line
```

### User Adds Pedestrian
```
_spawnProxyPedestrian()
  ├→ ApiService.snapToRoad() 📡 OSRM Nearest API
  └→ _pedestrians.add(StaticPedestrian)
      └→ _checkAllPedestrianDistances()
```

---

## 📊 API Usage Matrix

| File | Method | Called By | Endpoint | Frequency |
|---|---|---|---|---|
| api_service.dart | fetchPedestrians() | initState() | GET /get-pedestrians | Once on startup |
| api_service.dart | updateLocation() | GPS listener | POST /update-location | Continuous (on move) |
| api_service.dart | updatePedestrian() | distance check | POST /update-pedestrian | When collision |
| api_service.dart | snapToRoad() | spawn pedestrian | OSRM Nearest | On demand |
| optimized_distance_service.dart | calculateDistancesToMultiplePedestrians() | 5-sec timer | OSRM Table | Every 5s |
| optimized_distance_service.dart | calculateDistancesUsingAStar() | Fallback | OSRM Route | On demand |
| optimized_distance_service.dart | cleanCache() | 1-min timer | (cache only) | Every 1m |
| optimized_distance_service.dart | clearCache() | User action | (cache only) | On demand |
| optimized_distance_service.dart | getStatusInfo() | UI render | (local) | Every frame |
| astar_pathfinder.dart | calculateRoadDistance() | Fallback | OSRM Route | On timeout |
| astar_pathfinder.dart | getRoute() | User tap | OSRM Route | On demand |
| astar_pathfinder.dart | straightLineDistance() | Testing | (local) | Testing only |

---

## 🎯 Key Takeaways

1. **Dashboard is the orchestrator**: All major business logic flows through `Dashboard._checkAllPedestrianDistances()`

2. **Three layers of APIs**:
   - **UI Layer** (Dashboard): User interaction, rendering
   - **Service Layer** (ApiService, OptimizedDistanceService): Business logic
   - **Utility Layer** (AStarPathfinder): Routing & distance calculation

3. **Async/Await pattern**: All external APIs use `Future` with `.then()` or `await`

4. **Fallback chain**: Table API → A* → Haversine (last resort)

5. **Caching**: 2-minute cache for distances to minimize API calls

6. **Rate limiting**: 1-second minimum between batch requests

