import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
//import 'package:moodcam/features/emotion_recognition/presentation/widgets/face_guide_painter.dart';
import '../../data/services/camera_service.dart';
import '../state/pipeline_controller.dart';

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
      // Initialize the Isolate processor before starting the stream
      await _pipelineController.initializeProcessor();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
        _pipelineController.startProcessing();
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
        _initCameraAndStream();
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

            /*
            Add later once the core functionality is working

            // Face Guide Overlay
            Positioned.fill(child: CustomPaint(painter: FaceGuidePainter())),

            */

            // FPS + face-detection status overlay
            Positioned(
              top: 20,
              left: 20,
              child: ListenableBuilder(
                listenable: _pipelineController,
                builder: (context, _) {
                  final detected = _pipelineController.faceDetected;
                  final bs = _pipelineController.currentBlendshapes;
                  final String bsOutput = bs.length >= 5
                      ? bs.take(5).map((e) => e.toStringAsFixed(3)).join(', ')
                      : '—';

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // FPS
                        Text(
                          'FPS: ${_pipelineController.currentFps.toStringAsFixed(1)}',
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Face detection status
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              detected ? Icons.face : Icons.face_retouching_off,
                              color: detected
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              detected ? 'Face Detected' : 'No Face',
                              style: TextStyle(
                                color: detected
                                    ? Colors.greenAccent
                                    : Colors.redAccent,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        // Blendshape values (only when face is present)
                        if (detected) ...[
                          const SizedBox(height: 4),
                          Text(
                            'BS [0-4]: $bsOutput',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
