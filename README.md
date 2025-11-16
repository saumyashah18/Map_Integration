# V2X Communication Integration
## Prototype Implementation
A lightweight prototype demonstrating real-time pedestrian–vehicle safety using GPS, simulated pedestrians, and a cloud-backed API. The system integrates a Flutter app, a Flask backend, and map-based visualization to test basic V2X-style safety messaging.

🚦 Features

1. Live vehicle GPS tracking in Flutter (OpenStreetMap)
2. Simulated pedestrian data via Flask API
3. Distance calculation + proximity alerts (<10 m)
4. REST endpoints for /update-location, /get-pedestrians and /delete-pedestrians
5. Clean modular Flutter code (UI → services → models → utils)

🧩 Architecture

1. Flutter App → Flask API → JSON DB (Firebase during dev)
2. Simulated V2X flow:
GPS → App → API → Map → Alerts

📡 Tech Stack

1. Flutter (frontend + map)
2. Flask (backend API)
3. Python (simulator, distance utils)
4. Firebase (dev storage)
5. OpenStreetMap (visualization)

🔧 Dependencies

-> Frontend (Flutter)
1. Flutter SDK (3.0+)
2. Dart SDK (bundled with Flutter)
3. Packages:  
geolocator 
http
flutter_map / leaflet
latlong2
Install with: flutter pub get and Run With : flutter run 

-> Backend [Flask API]
1. Python 3.9+
2. Flask
3. flask-cors
