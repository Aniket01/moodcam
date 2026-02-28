import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../../data/services/camera_service.dart';
import '../../data/processors/face_pipeline_processor.dart';

class PipelineController extends ChangeNotifier {
  final CameraService _cameraService;
  late final FacePipelineProcessor _facePipelineProcessor;

  bool get isProcessing => _facePipelineProcessor.isProcessing;

  int frameCount = 0;
  DateTime? _rawFrameTime;
  DateTime? _lastProcessTime;
  final int minProcessingIntervalMs = 100;

  double currentFps = 0.0;
  bool faceDetected = false;
  List<double> currentBlendshapes = [];

  PipelineController(this._cameraService) {
    _facePipelineProcessor = FacePipelineProcessor(
      onBlendshapesOutput: (blendshapes) {
        currentBlendshapes = blendshapes;
        faceDetected = true;
        notifyListeners();
      },
      onFrameDropped: () {
        faceDetected = false;
        notifyListeners();
      },
    );
  }

  Future<void> initializeProcessor() async {
    await _facePipelineProcessor.initialize();
  }

  void startProcessing() {
    _cameraService.startStream((CameraImage image) async {
      final now = DateTime.now();

      // FPS Calculation
      // Runs on every camera callback BEFORE any throttle/drop guards so we
      // measure the true camera delivery rate.
      if (_rawFrameTime != null) {
        final diff = now.difference(_rawFrameTime!).inMilliseconds;
        if (diff > 0) {
          currentFps = 1000 / diff;
        }
      }
      _rawFrameTime = now;

      // Throttle gate: enforce minimum time between processed frames
      if (_lastProcessTime != null) {
        final sinceLast = now.difference(_lastProcessTime!).inMilliseconds;
        if (sinceLast < minProcessingIntervalMs) return;
      }

      // Drop gate: skip if the isolate is still crunching the last frame
      if (_facePipelineProcessor.isProcessing) return;
      _lastProcessTime = now;

      try {
        final cameraDesc = _cameraService.cameraDescription;

        if (cameraDesc != null) {
          // Process frame (ML Kit Face Mesh -> BlendShapes TFLite)
          await _facePipelineProcessor.processFrame(image, cameraDesc);
          frameCount++;
          notifyListeners();
        } else {
          if (kDebugMode) print('❌ Camera description is null');
        }
      } catch (e) {
        if (kDebugMode) print('❌ Error in startProcessing callback: $e');
      }
    });
  }

  void stopProcessing() {
    _cameraService.stopStream();
  }

  @override
  void dispose() {
    stopProcessing();
    _facePipelineProcessor.dispose();
    super.dispose();
  }
}
