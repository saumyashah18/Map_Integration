# V2X Pedestrian Alert System - Code Flow Documentation

## 🎯 Overview
This document describes how data flows through the system, which APIs are called, and how each component interacts.

---

## 📱 Application Startup Flow

```
main.dart
  └─> V2XApp()
      └─> MaterialApp
          └─> MapScreen (Dashboard.dart)
              └─> initState() called
```

### Step 1: `main.dart`
- **Entry point** of the application
- Launches `V2XApp()` which is a MaterialApp
- Sets home to `MapScreen()` (from `Dashboard.dart`)

---

## 🚀 Screen Initialization Flow

### When MapScreen loads (initState in Dashboard.dart):

```
MapScreen._MapScreenState.initState()
│
├─> _mapController = MapController()
│   └─ Initializes flutter_map controller
│
├─> _initLocation()  ⭐ STARTS LOCATION TRACKING
│   │
│   ├─> _handleLocationPermission()
│   │   └─ Requests GPS location permission from OS
│   │
│   ├─> Geolocator.getCurrentPosition()
│   │   └─ Gets INITIAL vehicle location (lat, lon)
│   │   └─ setState() updates _currentLocation
│   │   └─ _mapController.move() centers map on vehicle
│   │
│   ├─> _startDistanceChecking()  ⭐ STARTS 5-SECOND TIMER
│   │   └─ Timer.periodic(Duration(seconds: 5))
│   │       └─ Calls _checkAllPedestrianDistances() every 5 seconds
│   │
│   └─> Geolocator.getPositionStream()  ⭐ CONTINUOUS GPS UPDATES
│       └─ Listening to GPS position changes
│           └─ On GPS update: Updates _currentLocation
│               └─ _apiService.updateLocation(lat, lon)  📡 API CALL
│               └─ _mapController.move() centers map on new location
│
├─> _fetchPedestriansFromBackend()  ⭐ FETCH PEDESTRIANS
│   │
│   └─> _apiService.fetchPedestrians()  📡 API CALL
│       │
│       ├─ Endpoint: GET https://frothy-bebe-sirenically.ngrok-free.dev/get-pedestrians
│       │
│       └─ On Success:
│           └─ Decode JSON response into List<Pedestrian>
│           └─ setState() updates _pedestrians list
│           └─ Call _checkAllPedestrianDistances()
│
└─> _startCacheCleanup()  ⭐ CACHE MAINTENANCE
    └─ Timer.periodic(Duration(minutes: 1))
        └─ Calls _distanceService.cleanCache()
            └─ Removes expired distance cache entries
```

---

## 🔍 Distance Calculation Flow (Every 5 seconds)

### Main Method: `_checkAllPedestrianDistances()`

```
_checkAllPedestrianDistances()
│
├─> Guard: if (_currentLocation == null || _pedestrians.isEmpty) return
│
├─> Build PedestrianLocation list from _pedestrians
│   └─ Converts StaticPedestrian objects to PedestrianLocation objects
│
├─> _distanceService.calculateDistancesToMultiplePedestrians()  ⭐ MAIN DISTANCE API
│   │
│   └─ File: lib/services/optimized_distance_service.dart
│       │
│       ├─ Check cache for distances
│       │   └─ If all cached: return cached distances immediately ✅ (FAST)
│       │
│       ├─ If NOT fully cached:
│       │   └─ Call _processBatch(vehicleLocation, pedestrians)
│       │
│       └─ _processBatch() Method:
│           │
│           ├─ Build OSRM Table API URL:
│           │   Endpoint: https://router.project-osrm.org/table/v1/driving
│           │   Payload: source=vehicle_location;ped1_location;ped2_location...
│           │   Annotations: distance,duration
│           │
│           ├─ Send HTTP GET request
│           │   └─ 10-second timeout
│           │
│           ├─ Parse JSON Response:
│           │   └─ data['distances'][0] = [0m, dist_to_ped1, dist_to_ped2...]
│           │   └─ data['durations'][0] = [0s, dur_to_ped1, dur_to_ped2...]
│           │
│           ├─ For each pedestrian:
│           │   └─ Store distance in results[ped.id] = distance_meters
│           │   └─ Cache result with 2-minute expiry
│           │
│           ├─ On Timeout/Error:
│           │   └─ Increment _failureCount
│           │   └─ If > 3 failures: Switch to A* fallback mode
│           │   └─ Call _calculateAStarDistances() for this batch
│           │
│           └─ Return results Map<String, double>
│
├─> Loop through each pedestrian and check distance:
│   │
│   ├─ Get distance from results
│   │   └─ Store in ped.lastDetectionDistance
│   │
│   ├─ Compare with threshold (2000.0 meters):
│   │   │
│   │   └─ if (distance <= 2000m):  ⚠️ WITHIN THRESHOLD
│   │       │
│   │       ├─ Set ped.isDetected = true
│   │       │
│   │       ├─> CREATE ALERT:
│   │       │   └─ PedestrianAlertData object
│   │       │       ├─ pedestrianId
│   │       │       ├─ pedestrianLocation
│   │       │       ├─ distanceMeters
│   │       │       ├─ durationSeconds (distance / 15.0)
│   │       │       ├─ detectionTime
│   │       │
│   │       ├─ Add alert to _activeAlerts list
│   │       │
│   │       ├─> _apiService.updatePedestrian()  📡 API CALL
│   │       │   │
│   │       │   ├─ Endpoint: POST https://frothy-bebe-sirenically.ngrok-free.dev/update-pedestrian
│   │       │   ├─ Payload: { id, lat, lon, pedestrians_count, rsuid, obuid, timestamp }
│   │       │   │
│   │       │   └─ Send alert to backend
│   │       │
│   │       └─ debugPrint('🚨 NEW ALERT: ...')
│   │
│   └─ else (distance > 2000m):  ✅ OUTSIDE THRESHOLD
│       └─ Set ped.isDetected = false
│
└─> setState() updates UI with latest alerts
```

---

## 🗺️ Map Rendering Flow

### In `build()` method of Dashboard.dart:

```
build(BuildContext context)
│
├─> Scaffold
│   └─> body: Stack (multiple layers)
│       │
│       ├─ Layer 1: FlutterMap
│       │   ├─> TileLayer
│       │   │   └─ OpenStreetMap tiles (base map)
│       │   │
│       │   ├─ PolylineLayer (if _routePoints is not empty)
│       │   │   └─ Draws blue polyline with route waypoints
│       │   │
│       │   └─ MarkerLayer
│       │       ├─ Vehicle Marker (blue car icon) at _currentLocation
│       │       │
│       │       └─ For each pedestrian:
│       │           ├─ Pedestrian Marker (orange/red person icon)
│       │           │
│       │           ├─ GestureDetector (tap to request route)
│       │           │   └─ onTap: _showRouteToPedestrian(ped)  ⭐ ROUTE REQUEST
│       │           │       │
│       │           │       ├─> AStarPathfinder.getRoute(vehicle, pedestrian)
│       │           │       │   │
│       │           │       │   ├─ File: lib/utils/astar_pathfinder.dart
│       │           │       │   ├─ Calls OSRM Route API
│       │           │       │   ├─ Endpoint: https://router.project-osrm.org/route/v1/driving
│       │           │       │   │
│       │           │       │   └─ Returns RouteData:
│       │           │       │       ├─ waypoints: List<LatLng>  (route coordinates)
│       │           │       │       ├─ distanceMeters: double
│       │           │       │       └─ durationSeconds: double
│       │           │       │
│       │           │       ├─ setState():
│       │           │       │   ├─ _currentRoute = route
│       │           │       │   └─ _routePoints = route.waypoints
│       │           │       │
│       │           │       └─ Map centers on route
│       │           │
│       │           └─ Distance badge shows: "X.Xkm"
│       │
│       ├─ Layer 2: Alerts Panel (top-right)
│       │   └─ Shows _activeAlerts list
│       │       ├─ Display count: "Collision Alerts (N)"
│       │       └─ For each alert: show distance, ETA, pedestrian ID
│       │
│       ├─ Layer 3: System Status Panel (bottom-left)
│       │   ├─ Pedestrian count
│       │   ├─ Distance service status
│       │   └─ GPS coordinates
│       │
│       └─ Layer 4: Action Buttons (bottom-right)
│           ├─ Add 1 Pedestrian  → _spawnProxyPedestrian()
│           └─ Add 5 Pedestrians → _spawnMultiplePedestrians(5)
│
└─> App Bar with actions
    ├─ Add 1 Pedestrian
    ├─ Add 5 Pedestrians
    ├─ Refresh from Backend
    ├─ Clear Route
    └─ Clear All
```

---

## 👣 Pedestrian Addition Flow

### When user taps "Add Pedestrian":

```
_spawnProxyPedestrian()
│
├─ Generate random offset near current location
│   └─ testLocation = _currentLocation ± offset
│
├─ _apiService.snapToRoad(testLocation)  📡 API CALL
│   │
│   ├─ Endpoint: https://router.project-osrm.org/nearest/v1/driving
│   ├─ Snaps coordinate to nearest street
│   │
│   └─ Returns: snappedLocation (on actual road)
│
├─ Create StaticPedestrian object
│   └─ id: ped_${timestamp}
│   └─ roadLocation: snappedLocation
│
├─ setState() adds to _pedestrians list
│
└─ Call _checkAllPedestrianDistances()
    └─ Immediately calculates distance to new pedestrian
```

---

## 📡 API Calls Summary

| API | File | Purpose | Endpoint |
|---|---|---|---|
| **fetchPedestrians()** | api_service.dart | Get pedestrian list | GET /get-pedestrians |
| **updateLocation()** | api_service.dart | Send vehicle GPS | POST /update-location |
| **updatePedestrian()** | api_service.dart | Send alert when ped detected | POST /update-pedestrian |
| **OSRM Table API** | optimized_distance_service.dart | Batch distance calc | GET /table/v1/driving |
| **OSRM Route API** | astar_pathfinder.dart | Get A* route with waypoints | GET /route/v1/driving |
| **OSRM Nearest API** | api_service.dart | Snap to road | GET /nearest/v1/driving |

---

## 🔄 Caching Strategy

### Distance Cache (optimized_distance_service.dart):

```
_distanceCache = Map<String, CachedDistance>

Cache Key: "lat1.123,lon1.456->lat2.789,lon2.012"
Cache Value: CachedDistance(
    distanceMeters: 1396.2,
    durationSeconds: 93.0,
    timestamp: DateTime.now()
)

Expiry: 120 seconds (2 minutes)
Cleanup: Every 1 minute via Timer

Cache Hit: ✅ Return cached distance (FAST - no API call)
Cache Miss: ❌ Call OSRM Table API and cache result
```

---

## ⚡ Fallback Chain

### When OSRM Table API fails:

```
_processBatch() fails (timeout/error)
│
├─ Increment _failureCount
│
├─ If _failureCount < 3:
│   └─ Return empty (will retry next cycle)
│
└─ If _failureCount >= 3:
    └─ Switch to A* fallback mode (_useAStarFallback = true)
        │
        └─ _calculateAStarDistances() for next requests
            │
            └─ For each pedestrian:
                ├─ AStarPathfinder.calculateRoadDistance(vehicle, ped)
                │   ├─ Uses OSRM Route API
                │   └─ Returns: road distance (meters)
                │
                └─ Cache result and return
```

---

## 🎬 Complete User Interaction Example

### Scenario: User adds pedestrian and then views route

```
1. User taps "Add 1 Pedestrian" button
   └─> _spawnProxyPedestrian()
       └─> Snaps to road using OSRM Nearest API
       └─> Adds to _pedestrians
       └─> Calls _checkAllPedestrianDistances()

2. Distance check runs (5-sec timer)
   └─> OSRM Table API called
   └─> Distance calculated: 1396m
   └─> Within threshold (2000m): Alert created!
   └─> updatePedestrian() called to notify backend

3. UI updates:
   └─> Pedestrian marker appears on map (red, within threshold)
   └─> Alert card appears in top-right panel
   └─> Distance shown: "1.4km"

4. User taps pedestrian marker to view route
   └─> _showRouteToPedestrian(ped)
   └─> AStarPathfinder.getRoute() called
   └─> OSRM Route API returns waypoints
   └─> Blue polyline drawn on map

5. User taps "Clear Route" button
   └─> _clearRoute()
   └─> Polyline disappears
```

---

## 📊 Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     EXTERNAL SYSTEMS                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Backend Server (ngrok)      │  OSRM Routing Engine              │
│  • get-pedestrians           │  • Table API (batch distance)     │
│  • update-location           │  • Route API (A* with waypoints)  │
│  • update-pedestrian         │  • Nearest API (snap to road)     │
│                              │                                   │
│  GPS (Geolocator)            │  OpenStreetMap Tiles              │
│  • getCurrentPosition()       │  • Base layer for map             │
│  • getPositionStream()       │                                   │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
                                  ↕ HTTP
                             (API Calls)
┌─────────────────────────────────────────────────────────────────┐
│                      APP SERVICES LAYER                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  api_service.dart                                                │
│  • fetchPedestrians()      ←→  Backend                            │
│  • updateLocation()        ←→  Backend                            │
│  • updatePedestrian()      ←→  Backend                            │
│  • snapToRoad()            ←→  OSRM Nearest API                  │
│                                                                   │
│  optimized_distance_service.dart                                 │
│  • calculateDistancesToMultiplePedestrians()  ←→  OSRM Table API │
│  • _calculateAStarDistances()  ←→  OSRM Route API (fallback)      │
│  • Cache management        (in-memory)                            │
│                                                                   │
│  astar_pathfinder.dart                                           │
│  • getRoute()              ←→  OSRM Route API                    │
│  • calculateRoadDistance() ←→  OSRM Route API                    │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
                                  ↕
┌─────────────────────────────────────────────────────────────────┐
│                       UI LAYER (Dashboard)                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  • Map (flutter_map)                                             │
│    - Vehicle marker                                              │
│    - Pedestrian markers                                          │
│    - Route polyline                                              │
│                                                                   │
│  • Alert Panel                                                   │
│    - Shows detected pedestrians                                  │
│    - Distance & ETA                                              │
│                                                                   │
│  • Action Buttons                                                │
│    - Add pedestrian (random)                                     │
│    - Tap marker for route                                        │
│    - Clear alerts                                                │
│                                                                   │
│  • Status Panel                                                  │
│    - GPS location                                                │
│    - Cache status                                                │
│    - Pedestrian count                                            │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔐 Thread Safety & Timers

```
Timers running concurrently:

1. _positionSub (GPS listener)
   └─ Fires whenever location changes (continuous)
   └─ Updates _currentLocation
   └─ Calls updateLocation() to backend

2. _distanceCheckTimer
   └─ Fires every 5 seconds
   └─ Calls _checkAllPedestrianDistances()
   └─ Calculates distances for all pedestrians

3. _cacheCleanupTimer
   └─ Fires every 1 minute
   └─ Calls cleanCache()
   └─ Removes expired cache entries

All state updates use setState() to trigger UI rebuild safely.
```

---

## 📈 Performance Optimizations

1. **Batching**: Multiple pedestrian distances in single OSRM Table API call (not 1 call per pedestrian)
2. **Caching**: Distance results cached for 2 minutes (avoid redundant API calls)
3. **Fallback**: Switch to A* only after 3+ consecutive failures (saves API quota)
4. **Rate Limiting**: 1-second minimum between batch requests
5. **Exponential Backoff**: Wait time increases on repeated failures (2^n seconds)

---

## 🚨 Error Handling

| Scenario | Handling |
|---|---|
| No GPS permission | Use fallback center location |
| GPS unavailable | Use last known location |
| Backend unreachable | Silently fail, retry next cycle |
| OSRM Table timeout | Switch to A* fallback after 3 attempts |
| OSRM Route error | Return distance ∞ (unreachable) |
| Invalid JSON response | Catch exception, log error |

