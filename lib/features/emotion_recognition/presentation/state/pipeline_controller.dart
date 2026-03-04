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

  /// Latest measured average luminance (0-255) for the current face crop.
  double currentLuminosity = 0.0;

  bool _isLowLight = false;
  bool get isLowLight => _isLowLight;
  int _lowLightCounter = 0;
  static const double _lowLightOnThreshold = 40.0;
  static const double _lowLightOffThreshold = 140.0;
  static const int _lowLightFrameThreshold = 3;

  /// Latest analysis result from the engine; null before the first face frame.
  AnalysisResult? currentAnalysis;

  PipelineController(this._cameraService) {
    _facePipelineProcessor = FacePipelineProcessor(
      onAnalysisResult: (ferEmotions, landmarks, imgW, imgH, luminance) {
        try {
          final result = _analysisEngine.analyze(
            ferEmotions: ferEmotions,
            landmarks: landmarks,
            imageWidth: imgW,
            imageHeight: imgH,
          );
          currentAnalysis = result;
          faceDetected = true;

          // EMA smoothing
          if (currentLuminosity == 0.0) {
            // for the very first fram
            currentLuminosity = luminance;
          } else {
            // Smooth out noisy fluctuations
            currentLuminosity = (currentLuminosity * 0.8) + (luminance * 0.2);
          }

          // hysteresis and frame counting
          if (currentLuminosity < _lowLightOnThreshold) {
            _lowLightCounter++;
            if (_lowLightCounter >= _lowLightFrameThreshold) _isLowLight = true;
          } else {
            // always reset the counter if above the ON threshold
            _lowLightCounter = 0;

            // only turn off flash if Y > 140
            if (currentLuminosity > _lowLightOffThreshold) {
              _isLowLight = false;
            }
          }

          debugPrint(
            '[Controller] 🎭 Analysis — '
            'emotion: ${result.emotion}, '
            'stress: ${result.stressScore.toStringAsFixed(3)}, '
            'baseline: ${result.isBaselineReady ? "ready" : "calibrating"}, '
            'lum: ${currentLuminosity.toStringAsFixed(2)}',
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
          _analysisEngine.resetBaseline();
          debugPrint('[Controller] 👤 Face lost — baseline reset');
        }
        faceDetected = false;
        currentAnalysis = null;
        _isLowLight = false;
        _lowLightCounter = 0;
        currentLuminosity = 0;
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

      if (_rawFrameTime != null) {
        final diff = now.difference(_rawFrameTime!).inMilliseconds;
        if (diff > 0) {
          currentFps = 1000 / diff;
        }
      }
      _rawFrameTime = now;

      if (_lastProcessTime != null) {
        final sinceLast = now.difference(_lastProcessTime!).inMilliseconds;
        if (sinceLast < minProcessingIntervalMs) return;
      }

      if (_facePipelineProcessor.isProcessing) return;
      _lastProcessTime = now;

      try {
        final cameraDesc = _cameraService.cameraDescription;

        if (cameraDesc != null) {
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
