import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../data/services/camera_service.dart';

class CameraFERScreen extends StatefulWidget {
  const CameraFERScreen({super.key});

  @override
  State<CameraFERScreen> createState() => _CameraFERScreenState();
}

class _CameraFERScreenState extends State<CameraFERScreen>
    with WidgetsBindingObserver {
  final CameraService _cameraService = CameraService();
  bool _isCameraInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      await _cameraService.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
      // Handle permission denied or hardware errors here
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle lifecycle changes robustly: always dispose when backgrounded
    // and always attempt to reinitialize when resumed.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _cameraService.dispose();
      if (mounted) setState(() => _isCameraInitialized = false);
      return;
    }

    if (state == AppLifecycleState.resumed) {
      // Only initialize if not already initialized
      final controller = _cameraService.controller;
      if (controller == null || !controller.value.isInitialized) {
        _initCamera();
      } else {
        if (mounted) setState(() => _isCameraInitialized = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized || _cameraService.controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final controller = _cameraService.controller!;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The camera feed
            Center(
              child: AspectRatio(
                aspectRatio: 1 / controller.value.aspectRatio,
                child: CameraPreview(controller),
              ),
            ),

            // Placeholder for ML overlays (Bounding boxes, text)
            const Positioned.fill(
              child: Center(
                child: Text(
                  'ML Overlay Placeholder',
                  style: TextStyle(color: Colors.green, fontSize: 24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
