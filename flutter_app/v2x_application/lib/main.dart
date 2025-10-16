import 'package:flutter/material.dart';
import 'screens/map_screen.dart'; // Import your map screen

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
