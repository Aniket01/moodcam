import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../../data/services/camera_service.dart';

class PipelineController extends ChangeNotifier {
  final CameraService _cameraService;

  bool isProcessing = false;
  int frameCount = 0;
  DateTime? _lastFrameTime;
  double currentFps = 0.0;

  PipelineController(this._cameraService);

  void startProcessing() {
    _cameraService.startStream((CameraImage image) async {
      // The Throttle Gate: Drop frames if we are currently busy
      if (isProcessing) return;
      isProcessing = true;

      // Calculate current FPS for testing
      final now = DateTime.now();
      if (_lastFrameTime != null) {
        final diff = now.difference(_lastFrameTime!).inMilliseconds;
        if (diff > 0) {
          currentFps = 1000 / diff;
          notifyListeners(); // Tell the UI to update the FPS text
        }
      }
      _lastFrameTime = now;

      // MOCK TEST CASE: Simulate heavy ML processing (100ms)
      await Future.delayed(const Duration(milliseconds: 100));

      if (kDebugMode) {
        print(
          'Processed frame $frameCount | FPS: ${currentFps.toStringAsFixed(1)}',
        );
      }

      frameCount++;

      // Release the lock to accept the next frame
      isProcessing = false;
    });
  }

  void stopProcessing() {
    _cameraService.stopStream();
    isProcessing = false;
  }
}
