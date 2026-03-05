import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/models/analysis_result.dart';
import '../../domain/models/basic_emotion.dart';
import '../../domain/models/emotion_result.dart';

//  LANDMARK INDEX CONSTANTS
abstract class LM {
  // 6-point EAR landmarks - left eye
  static const List<int> leftEyeEAR = [362, 385, 387, 263, 373, 380];

  // 6-point EAR landmarks - right eye
  static const List<int> rightEyeEAR = [33, 160, 158, 133, 153, 144];

  // 8-point MAR landmarks
  static const List<int> mouthMAR = [61, 291, 39, 181, 0, 17, 269, 405];

  // Nose tip
  static const int noseTip = 1;
}

//  GEOMETRIC HELPER FUNCTIONS
double _dist(List<double> a, List<double> b) {
  final dx = a[0] - b[0], dy = a[1] - b[1];
  return math.sqrt(dx * dx + dy * dy);
}

/// Eye Aspect Ratio (EAR)
double _computeEAR(List<List<double>> pts, List<int> idx) {
  return (_dist(pts[idx[1]], pts[idx[5]]) + _dist(pts[idx[2]], pts[idx[4]])) /
      (2.0 * _dist(pts[idx[0]], pts[idx[3]]) + 1e-6);
}

/// Mouth Aspect Ratio (MAR)
double _computeMAR(List<List<double>> pts, List<int> idx) {
  final width = _dist(pts[idx[0]], pts[idx[1]]) + 1e-6;
  final v =
      (_dist(pts[idx[2]], pts[idx[7]]) +
          _dist(pts[idx[3]], pts[idx[6]]) +
          _dist(pts[idx[4]], pts[idx[5]])) /
      3.0;
  return v / width;
}

double _clamp01(double v) => v.clamp(0.0, 1.0);

double _sigmoid(double x, {double gain = 10.0, double mid = 0.5}) =>
    1.0 / (1.0 + math.exp(-gain * (x - mid)));

//  ROLLING WINDOW
class _FrameSnapshot {
  final double ear;
  final double mar;
  final BasicEmotion emotion;

  const _FrameSnapshot({
    required this.ear,
    required this.mar,
    required this.emotion,
  });
}

//======================================================================
//  FACE ANALYSIS ENGINE
class FaceAnalysisEngine {
  /// Short adaptive baseline (1s at 10fps throttled rate)
  final int baselineFrames;

  /// Rolling window for stress analysis (6s)
  final int windowSize;

  /// Frames per second (throttled camera rate)
  final double fps;

  FaceAnalysisEngine({
    this.baselineFrames = 10,
    this.windowSize = 60,
    this.fps = 10,
  });

  //    Baseline state
  final List<double> _baselineEARSamples = [];
  final List<double> _baselineMARSamples = [];
  double _baselineEAR = 0.32;
  double _baselineMAR = 0.05;
  bool get isBaselineReady => _baselineEARSamples.length >= baselineFrames;

  //    Rolling window
  final Queue<_FrameSnapshot> _window = Queue();

  /// Feed each pipeline frame into the engine.
  ///
  /// [ferEmotions] - 7 floats from FER model
  /// [landmarks]   - 478 [x, y] pixel-coordinate pairs from ML Kit
  AnalysisResult analyze({
    required List<double> ferEmotions,
    required List<List<double>> landmarks,
    int imageWidth = 640,
    int imageHeight = 480,
  }) {
    assert(ferEmotions.length == 7, 'Expected 7 FER emotion probabilities');
    assert(landmarks.length == 478, 'Expected 478 landmarks');

    // Geometric features
    final double earL = _computeEAR(landmarks, LM.leftEyeEAR);
    final double earR = _computeEAR(landmarks, LM.rightEyeEAR);
    final double ear = (earL + earR) / 2.0;
    final double mar = _computeMAR(landmarks, LM.mouthMAR);

    // Baseline calibration and dynamic adaptation
    if (!isBaselineReady) {
      _baselineEARSamples.add(ear);
      _baselineMARSamples.add(mar);
      if (isBaselineReady) {
        _baselineEAR = _mean(_baselineEARSamples);
        _baselineMAR = _mean(_baselineMARSamples);
        debugPrint(
          '✅ Baseline ready — EAR: ${_baselineEAR.toStringAsFixed(3)}, '
          'MAR: ${_baselineMAR.toStringAsFixed(3)}',
        );
      }
    } else {
      // Dynamic rolling baseline: Slowly adapt to the user's natural resting face
      // Exponential Moving Average
      const double alpha = 0.005;
      _baselineEAR = (alpha * ear) + ((1.0 - alpha) * _baselineEAR);
      _baselineMAR = (alpha * mar) + ((1.0 - alpha) * _baselineMAR);
    }

    // Emotion classification from FER model
    final EmotionResult emotion = _classifyFEREmotion(ferEmotions);

    // Append snapshot
    final snap = _FrameSnapshot(ear: ear, mar: mar, emotion: emotion.emotion);
    _window.addLast(snap);
    if (_window.length > windowSize) _window.removeFirst();

    // Compute unified stress score
    final double stress = _computeStressScore(ear: ear, mar: mar);

    return AnalysisResult(
      emotion: emotion,
      stressScore: stress,
      isBaselineReady: isBaselineReady,
      metrics: {
        'ear': ear,
        'mar': mar,
        'baselineEAR': _baselineEAR,
        'baselineMAR': _baselineMAR,
        'windowLen': _window.length.toDouble(),
      },
    );
  }

  /// Reset baseline when mode changes or face disappears.
  void resetBaseline() {
    _baselineEARSamples.clear();
    _baselineMARSamples.clear();
    _window.clear();
    debugPrint('🔄 FaceAnalysisEngine baseline reset');
  }

  // =======================================================================
  //  EMOTION CLASSIFIER (Custom FER Model)
  // =======================================================================

  EmotionResult _classifyFEREmotion(List<double> ferEmotions) {
    if (ferEmotions.length != 7) {
      return EmotionResult(BasicEmotion.neutral, 0.0);
    }

    // Ordered classes: Anger, Disgust, Fear, Happiness, Neutral, Sadness, Surprise
    final Map<int, BasicEmotion> classMap = {
      0: BasicEmotion.angry,
      1: BasicEmotion.disgusted,
      2: BasicEmotion.fearful,
      3: BasicEmotion.happy,
      4: BasicEmotion.neutral,
      5: BasicEmotion.sad,
      6: BasicEmotion.surprised,
    };

    int bestIdx = 4;
    double bestScore = 0.0;
    for (int i = 0; i < 7; i++) {
      if (ferEmotions[i] > bestScore) {
        bestScore = ferEmotions[i];
        bestIdx = i;
      }
    }

    return EmotionResult(classMap[bestIdx]!, bestScore);
  }

  // ======================================================================
  //  STRESS SCORE
  //  A single unified metric combining multiple markers.
  //
  //  Markers                    | weight | rationale
  //  -------------------------------------------------------------------
  //  Sustained negative emotion |  0.35  | sad/angry/fearful/disgusted
  //  Squinting (eye tension)    |  0.25  | orbicularis oculi engagement
  //  PERCLOS (EAR drop)         |  0.20  | drowsiness / fatigue marker
  //  Yawning (MAR spike)        |  0.10  | fatigue / disengagement
  //  High blink rate            |  0.10  | stress-induced blink surge
  // ======================================================================

  double _computeStressScore({required double ear, required double mar}) {
    if (_window.isEmpty) return 0.0;

    final snaps = _window.toList();
    final int n = snaps.length;

    //  Sustained negative emotion
    const negativeEmotions = {
      BasicEmotion.angry,
      BasicEmotion.sad,
      BasicEmotion.fearful,
      BasicEmotion.disgusted,
    };
    final int negFrames = snaps
        .where((s) => negativeEmotions.contains(s.emotion))
        .length;
    final double negScore = negFrames / n;

    //  Squinting: sustained slight eye closure (80–95% of baseline)
    const double squintLow = 0.80, squintHigh = 0.95;
    final int squintFrames = snaps
        .where(
          (s) =>
              s.ear < _baselineEAR * squintHigh &&
              s.ear > _baselineEAR * squintLow,
        )
        .length;
    final double squintScore = squintFrames / n;

    //  PERCLOS: fraction of frames where EAR < 80% of baseline
    const double perclosThreshold = 0.80;
    final int closedFrames = snaps
        .where((s) => s.ear < _baselineEAR * perclosThreshold)
        .length;
    final double perclos = closedFrames / n;

    //  Yawning: MAR > 150% of baseline
    const double yawnMARRatio = 1.5;
    final int yawnFrames = snaps
        .where((s) => s.mar > _baselineMAR * yawnMARRatio)
        .length;
    final int yawnEquivalentFrames = (fps * 2).round();
    final double yawnScore = _clamp01(yawnFrames / (yawnEquivalentFrames + 1));

    //  High blink rate
    final double blinkRate =
        _countBlinkEvents(snaps) / (math.max(n / fps, 1.0));
    const double stressBlinkRate = 0.50;
    final double blinkSurge = _clamp01(blinkRate / stressBlinkRate);

    // Weighted sum
    final double raw =
        0.35 * negScore +
        0.25 * squintScore +
        0.20 * perclos +
        0.10 * yawnScore +
        0.10 * blinkSurge;

    // Softened sigmoid: mid shifted to 0.45, gain reduced to 5.0
    return _clamp01(_sigmoid(raw, gain: 5.0, mid: 0.45));
  }

  //  HELPERS
  int _countBlinkEvents(List<_FrameSnapshot> snaps) {
    final double closeThreshold = _baselineEAR * 0.65;
    final double openThreshold = _baselineEAR * 0.85;
    int blinks = 0;
    bool eyeClosed = false;
    for (final s in snaps) {
      if (!eyeClosed && s.ear < closeThreshold) {
        eyeClosed = true;
      } else if (eyeClosed && s.ear > openThreshold) {
        eyeClosed = false;
        blinks++;
      }
    }
    return blinks;
  }

  double _mean(List<double> values) {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }
}
