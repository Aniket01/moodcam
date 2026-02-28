import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../../data/processors/face_analysis_engine.dart';
import '../../data/processors/face_pipeline_processor.dart';
import '../../data/services/camera_service.dart';
import '../../domain/models/analysis_result.dart';

class PipelineController extends ChangeNotifier {
  final CameraService _cameraService;
  late final FacePipelineProcessor _facePipelineProcessor;

  final FaceAnalysisEngine _analysisEngine = FaceAnalysisEngine();

  bool get isProcessing => _facePipelineProcessor.isProcessing;

  int frameCount = 0;
  DateTime? _rawFrameTime;
  DateTime? _lastProcessTime;
  final int minProcessingIntervalMs = 100;

  double currentFps = 0.0;
  bool faceDetected = false;
  List<double> currentBlendshapes = [];

  /// Latest analysis result from the engine; null before the first face frame.
  AnalysisResult? currentAnalysis;

  PipelineController(this._cameraService) {
    _facePipelineProcessor = FacePipelineProcessor(
      onBlendshapesOutput: (blendshapes) {
        // Kept for backward compatibility — UI can still read raw blendshapes.
        currentBlendshapes = blendshapes;
        faceDetected = true;
        // notifyListeners() is called from onAnalysisResult below.
      },

      onAnalysisResult: (blendshapes, landmarks, imgW, imgH) {
        try {
          final result = _analysisEngine.analyze(
            blendshapes: blendshapes,
            landmarks: landmarks,
            imageWidth: imgW,
            imageHeight: imgH,
          );
          currentAnalysis = result;
          faceDetected = true;

          debugPrint(
            '[Controller] 🎭 Analysis — '
            'emotion: ${result.emotion}, '
            'fatigue: ${result.fatigueScore.toStringAsFixed(3)}, '
            'stress: ${result.stressScore.toStringAsFixed(3)}, '
            'baseline: ${result.isBaselineReady ? "ready" : "calibrating (${_analysisEngine.baselineFrames - (result.metrics['windowLen'] ?? 0).round()} frames left)"}',
          );
        } catch (e, stack) {
          debugPrint(
            '[Controller] ❌ FaceAnalysisEngine.analyze error: $e\n$stack',
          );
        }
        notifyListeners();
      },

      onFrameDropped: () {
        if (faceDetected) {
          // Face was visible before — reset the personal baseline so the engine
          // starts fresh when the face reappears (e.g. after the user looks away).
          _analysisEngine.resetBaseline();
          debugPrint('[Controller] 👤 Face lost — baseline reset');
        }
        faceDetected = false;
        currentAnalysis = null;
        notifyListeners();
      },
    );
  }

  Future<void> initializeProcessor() async {
    debugPrint('[Controller] 🔧 Initialising FacePipelineProcessor…');
    await _facePipelineProcessor.initialize();
    debugPrint('[Controller] ✅ FacePipelineProcessor ready');
  }

  void startProcessing() {
    debugPrint('[Controller] ▶️  Starting camera stream processing');
    _cameraService.startStream((CameraImage image) async {
      final now = DateTime.now();

      // FPS Calculation — runs on every camera callback BEFORE throttle guards
      // so we measure the true camera delivery rate.
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

      // Drop gate: skip if the processor is still crunching the last frame
      if (_facePipelineProcessor.isProcessing) return;
      _lastProcessTime = now;

      try {
        final cameraDesc = _cameraService.cameraDescription;

        if (cameraDesc != null) {
          // Process frame (ML Kit Face Mesh → BlendShapes TFLite → Analysis)
          await _facePipelineProcessor.processFrame(image, cameraDesc);
          frameCount++;
          notifyListeners();
        } else {
          debugPrint('[Controller] ❌ Camera description is null');
        }
      } catch (e) {
        debugPrint('[Controller] ❌ Error in startProcessing callback: $e');
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
