import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../../data/services/camera_service.dart';
import '../../data/services/face_detection_service.dart';
import '../../../../core/utils/image_converter.dart';

class PipelineController extends ChangeNotifier {
  final CameraService _cameraService;
  final FaceDetectionService _faceDetectionService = FaceDetectionService();

  bool isProcessing = false;
  int frameCount = 0;
  DateTime? _lastFrameTime;
  DateTime? _lastProcessTime; // <-- new
  final int minProcessingIntervalMs =
      100; // target ~10 FPS (tune: 66 for ~15fps)

  double currentFps = 0.0;

  PipelineController(this._cameraService);

  void startProcessing() {
    _cameraService.startStream((CameraImage image) async {
      final now = DateTime.now();

      // Throttle gate: enforce minimum time between processed frames
      if (_lastProcessTime != null) {
        final sinceLast = now.difference(_lastProcessTime!).inMilliseconds;
        if (sinceLast < minProcessingIntervalMs) return;
      }

      // The Throttle Gate: Drop frames if we are currently busy
      if (isProcessing) return;
      isProcessing = true;
      _lastProcessTime = now;

      try {
        // Calculate current FPS for testing
        if (_lastFrameTime != null) {
          final diff = now.difference(_lastFrameTime!).inMilliseconds;
          if (diff > 0) {
            currentFps = 1000 / diff;
            notifyListeners(); // Tell the UI to update the FPS text
          }
        }
        _lastFrameTime = now;

        // Get camera hardware description
        final cameraDesc = _cameraService.cameraDescription;

        if (cameraDesc != null) {
          // convert raw bytes to ML kit format
          final inputImage = ImageConverter.convertCameraImage(
            image,
            cameraDesc,
          );

          // detect face
          if (inputImage != null) {
            final face = await _faceDetectionService.detectFace(inputImage);
            if (kDebugMode) {
              if (face != null) {
                print(
                  '✅ Face found at: ${face.boundingBox} | FPS: ${currentFps.toStringAsFixed(1)}',
                );
              } else {
                print(
                  '⚠️ No single face detected. | FPS: ${currentFps.toStringAsFixed(1)}',
                );
              }
            }
          } else {
            if (kDebugMode) {
              print(
                '❌ InputImage conversion failed for frame $frameCount | FPS: ${currentFps.toStringAsFixed(1)}',
              );
            }
          }
        } else {
          if (kDebugMode) print('❌ Camera description is null');
        }
      } catch (e) {
        if (kDebugMode) print('❌ Error in startProcessing callback: $e');
      } finally {
        frameCount++;
        isProcessing = false;
      }
    });
  }

  void stopProcessing() {
    _cameraService.stopStream();
    _faceDetectionService.dispose();
    isProcessing = false;
  }
}
