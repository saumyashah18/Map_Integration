import 'package:flutter/material.dart';
import 'screens/Dashboard.dart'; // Import your map screen


class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (X509Certificate cert, String host, int port) {
      // WARNING: dev-only. Replace host check or remove in production.
      return host == 'frothy-bebe-sirenically.ngrok-free.dev';
    };
    return client;
  }
}
void main() {
  runApp(const V2XApp());
}

class V2XApp extends StatelessWidget {
  const V2XApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'V2X Pedestrian Alert',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MapScreen(), // <- Launches the map screen
    );
  }
}


