import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'features/emotion_recognition/presentation/screens/camera_fer_screen.dart';

void main() {
  // Ensure the native bridge is initialized before using the camera
  WidgetsFlutterBinding.ensureInitialized();

  // Lock app to portrait mode
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const FERApp());
}

class FERApp extends StatelessWidget {
  const FERApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Emotion Recognition',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const CameraFERScreen(),
    );
  }
}
