import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../data/services/camera_service.dart';
import '../state/pipeline_controller.dart';
import '../widgets/smart_selfie_flash.dart';
import '../widgets/top_status_chip.dart';
import '../widgets/analysis_overlay.dart';

// Screen

class CameraFERScreen extends StatefulWidget {
  const CameraFERScreen({super.key});

  @override
  State<CameraFERScreen> createState() => _CameraFERScreenState();
}

class _CameraFERScreenState extends State<CameraFERScreen>
    with WidgetsBindingObserver {
  final CameraService _cameraService = CameraService();
  late final PipelineController _pipelineController;
  bool _isCameraInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pipelineController = PipelineController(_cameraService);
    _initCameraAndStream();
  }

  Future<void> _initCameraAndStream() async {
    try {
      await _cameraService.initialize();
      await _pipelineController.initializeProcessor();

      if (mounted) {
        setState(() => _isCameraInitialized = true);
        _pipelineController.startProcessing();
      }
    } catch (e) {
      debugPrint('[Screen] ❌ Error initialising camera: $e');
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
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _cameraService.dispose();
      if (mounted) setState(() => _isCameraInitialized = false);
      return;
    }

    if (state == AppLifecycleState.resumed) {
      final controller = _cameraService.controller;
      if (controller == null || !controller.value.isInitialized) {
        _initCameraAndStream();
      } else {
        if (mounted) setState(() => _isCameraInitialized = true);
      }
    }
  }

  // Build

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized || _cameraService.controller == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFF0F4F8),
        body: Center(
          child: CircularProgressIndicator(color: Colors.blueAccent),
        ),
      );
    }

    final controller = _cameraService.controller!;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: SafeArea(
        child: Column(
          children: [
            // Top debug chip (FPS + face detection status)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ListenableBuilder(
                  listenable: _pipelineController,
                  builder: (context, _) => TopStatusChip(
                    fps: _pipelineController.currentFps,
                    faceDetected: _pipelineController.faceDetected,
                  ),
                ),
              ),
            ),

            // Camera feed
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: AspectRatio(
                      aspectRatio: 1 / controller.value.aspectRatio,
                      child: Container(
                        color: Colors.black,
                        child: ListenableBuilder(
                          listenable: _pipelineController,
                          builder: (context, _) {
                            return SmartSelfieFlash(
                              isLowLight: _pipelineController.isLowLight,
                              cameraPreview: CameraPreview(controller),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Bottom analysis overlay
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ListenableBuilder(
                listenable: _pipelineController,
                builder: (context, _) => AnalysisOverlay(
                  faceDetected: _pipelineController.faceDetected,
                  analysis: _pipelineController.currentAnalysis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
