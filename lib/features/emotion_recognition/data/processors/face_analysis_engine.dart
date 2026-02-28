import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/models/analysis_result.dart';
import '../../domain/models/basic_emotion.dart';
import '../../domain/models/emotion_result.dart';

//  BLENDSHAPE INDEX CONSTANTS
abstract class BS {
  static const int browDownLeft = 1;
  static const int browDownRight = 2;
  static const int browInnerUp = 3; // furrowed inner brows
  static const int browOuterUpLeft = 4;
  static const int browOuterUpRight = 5;
  static const int cheekPuff = 6;
  static const int eyeBlinkLeft = 9;
  static const int eyeBlinkRight = 10;
  static const int eyeSquintLeft = 19;
  static const int eyeSquintRight = 20;
  static const int eyeWideLeft = 21;
  static const int eyeWideRight = 22;
  static const int jawOpen = 25;
  static const int mouthFrownLeft = 30;
  static const int mouthFrownRight = 31;
  static const int mouthFunnel = 32;
  static const int mouthPucker = 38;
  static const int mouthSmileLeft = 44;
  static const int mouthSmileRight = 45;
  static const int mouthStretchLeft = 46;
  static const int mouthStretchRight = 47;
  static const int mouthUpperUpLeft = 48;
  static const int mouthUpperUpRight = 49;
  static const int noseSneerLeft = 50;
  static const int noseSneerRight = 51;
}

//  LANDMARK INDEX CONSTANTS
abstract class LM {
  // 6-point EAR landmarks - left eye
  static const List<int> leftEyeEAR = [362, 385, 387, 263, 373, 380];

  // 6-point EAR landmarks - right eye
  static const List<int> rightEyeEAR = [33, 160, 158, 133, 153, 144];

  // 8-point MAR landmarks
  static const List<int> mouthMAR = [61, 291, 39, 181, 0, 17, 269, 405];

  // Nose tip - for jitter detection
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

//  ROLLING WINDOW  - stores per-frame metric snapshots
class _FrameSnapshot {
  final double ear; // average eye aspect ratio
  final double mar; // mouth aspect ratio
  final double browFurrow;
  final double smileScore;
  final double frownScore;
  final BasicEmotion emotion;
  final double noseTipX;
  final double noseTipY;

  const _FrameSnapshot({
    required this.ear,
    required this.mar,
    required this.browFurrow,
    required this.smileScore,
    required this.frownScore,
    required this.emotion,
    required this.noseTipX,
    required this.noseTipY,
  });
}

//======================================================================
//  FACE ANALYSIS ENGINE - main class to attach to FacePipelineProcessor
class FaceAnalysisEngine {
  //    Configuration

  /// Number of frames used to build the personal baseline (5s at 30 fps)
  final int baselineFrames;

  /// Rolling window for fatigue/stress analysis (6s at 30 fps)
  final int windowSize;

  /// Frames per second of the camera
  final double fps;

  FaceAnalysisEngine({
    this.baselineFrames = 150,
    this.windowSize = 180,
    this.fps = 30,
  });

  //    Baseline state
  final List<double> _baselineEARSamples = [];
  final List<double> _baselineMARSamples = [];
  double _baselineEAR = 0.32; // sensible default until calibrated
  double _baselineMAR = 0.05;
  bool get isBaselineReady => _baselineEARSamples.length >= baselineFrames;

  //    Rolling window
  final Queue<_FrameSnapshot> _window = Queue();

  //    Public API

  /// Feed each pipeline frame into the engine.
  ///
  /// [blendshapes] - 52 floats from TFLite model
  /// [landmarks]   - 478 [x, y] pixel-coordinate pairs from ML Kit
  AnalysisResult analyze({
    required List<double> blendshapes,
    required List<List<double>> landmarks,
    int imageWidth = 640,
    int imageHeight = 480,
  }) {
    assert(blendshapes.length == 52, 'Expected 52 blendshapes');
    assert(landmarks.length == 478, 'Expected 478 landmarks');

    final bs = blendshapes;

    // Geometric features
    final double earL = _computeEAR(landmarks, LM.leftEyeEAR);
    final double earR = _computeEAR(landmarks, LM.rightEyeEAR);
    final double ear = (earL + earR) / 2.0;
    final double mar = _computeMAR(landmarks, LM.mouthMAR);

    final double noseTipX = landmarks[LM.noseTip][0] / imageWidth;
    final double noseTipY = landmarks[LM.noseTip][1] / imageHeight;

    // Blendshape-derived scalars
    final double blink = (bs[BS.eyeBlinkLeft] + bs[BS.eyeBlinkRight]) / 2;
    final double browFurrow =
        (bs[BS.browDownLeft] + bs[BS.browDownRight] + bs[BS.browInnerUp]) / 3;
    final double browRaise =
        (bs[BS.browOuterUpLeft] + bs[BS.browOuterUpRight]) / 2;
    final double smile = (bs[BS.mouthSmileLeft] + bs[BS.mouthSmileRight]) / 2;
    final double frown = (bs[BS.mouthFrownLeft] + bs[BS.mouthFrownRight]) / 2;
    final double noseSneer = (bs[BS.noseSneerLeft] + bs[BS.noseSneerRight]) / 2;
    // ignore: unused_local_variable
    final double eyeSquint = (bs[BS.eyeSquintLeft] + bs[BS.eyeSquintRight]) / 2;
    final double eyeWide = (bs[BS.eyeWideLeft] + bs[BS.eyeWideRight]) / 2;
    final double jawOpen = bs[BS.jawOpen];
    final double mouthStretch =
        (bs[BS.mouthStretchLeft] + bs[BS.mouthStretchRight]) / 2;

    // Baseline calibration
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
    }

    // Normalised EAR/MAR relative to personal baseline
    final double relEAR = ear / (_baselineEAR + 1e-6); // <1 = closing
    final double relMAR = mar / (_baselineMAR + 1e-6); // >1 = opening

    // Emotion classification
    final EmotionResult emotion = _classifyEmotion(
      smile: smile,
      frown: frown,
      browFurrow: browFurrow,
      browRaise: browRaise,
      eyeWide: eyeWide,
      noseSneer: noseSneer,
      jawOpen: jawOpen,
      mouthStretch: mouthStretch,
      blink: blink,
    );

    // Append frame snapshot to rolling window
    final snap = _FrameSnapshot(
      ear: ear,
      mar: mar,
      browFurrow: browFurrow,
      smileScore: smile,
      frownScore: frown,
      emotion: emotion.emotion,
      noseTipX: noseTipX,
      noseTipY: noseTipY,
    );
    _window.addLast(snap);
    if (_window.length > windowSize) _window.removeFirst();

    // Compute fatigue score
    final double fatigue = _computeFatigueScore(relEAR, relMAR);

    // Compute stress score
    final double stress = _computeStressScore(
      browFurrow: browFurrow,
      relEAR: relEAR,
    );

    return AnalysisResult(
      emotion: emotion,
      fatigueScore: fatigue,
      stressScore: stress,
      isBaselineReady: isBaselineReady,
      metrics: {
        'ear': ear,
        'mar': mar,
        'relEAR': relEAR,
        'relMAR': relMAR,
        'browFurrow': browFurrow,
        'smile': smile,
        'frown': frown,
        'baselineEAR': _baselineEAR,
        'baselineMAR': _baselineMAR,
        'windowLen': _window.length.toDouble(),
      },
    );
  }

  /// Reset baseline - call when the user's face first appears on screen.
  void resetBaseline() {
    _baselineEARSamples.clear();
    _baselineMARSamples.clear();
    _window.clear();
    debugPrint('🔄 FaceAnalysisEngine baseline reset');
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  EMOTION CLASSIFIER
  //  Rule-based weighted scoring for the 7 basic emotions.
  //  Each emotion is represented by a weighted combination of blendshapes.
  //  The highest-scoring emotion above a minimum threshold wins.
  // ═══════════════════════════════════════════════════════════════════════

  EmotionResult _classifyEmotion({
    required double smile,
    required double frown,
    required double browFurrow,
    required double browRaise,
    required double eyeWide,
    required double noseSneer,
    required double jawOpen,
    required double mouthStretch,
    required double blink,
  }) {
    // Score functions: weighted sums → normalised 0-1
    final scores = <BasicEmotion, double>{
      BasicEmotion.happy: _clamp01(
        0.60 * smile + 0.20 * (1 - frown) + 0.20 * blink, // gentle squint-smile
      ),
      BasicEmotion.sad: _clamp01(
        0.45 * frown + 0.30 * browFurrow + 0.25 * (1 - smile),
      ),
      BasicEmotion.angry: _clamp01(
        0.35 * browFurrow +
            0.30 * noseSneer +
            0.20 * (1 - smile) +
            0.15 * frown,
      ),
      BasicEmotion.surprised: _clamp01(
        0.40 * eyeWide + 0.30 * browRaise + 0.30 * jawOpen,
      ),
      BasicEmotion.fearful: _clamp01(
        0.35 * eyeWide +
            0.30 * browRaise +
            0.20 * mouthStretch +
            0.15 * (1 - smile),
      ),
      BasicEmotion.disgusted: _clamp01(
        0.40 * noseSneer + 0.35 * browFurrow + 0.25 * (1 - smile),
      ),
      BasicEmotion.neutral: _clamp01(
        // Neutral = absence of all strong signals
        1.0 -
            (smile * 0.3 +
                frown * 0.2 +
                browFurrow * 0.2 +
                eyeWide * 0.15 +
                noseSneer * 0.15),
      ),
    };

    BasicEmotion best = BasicEmotion.neutral;
    double bestScore = 0.0;
    for (final entry in scores.entries) {
      if (entry.value > bestScore) {
        bestScore = entry.value;
        best = entry.key;
      }
    }

    // Enforce minimum confidence - fall back to neutral if ambiguous
    const double minConfidence = 0.35;
    if (best != BasicEmotion.neutral && bestScore < minConfidence) {
      return EmotionResult(BasicEmotion.neutral, scores[BasicEmotion.neutral]!);
    }

    return EmotionResult(best, bestScore);
  }

  // ======================================================================
  //  FATIGUE SCORE
  //  Combines multiple markers with time-aware weighting.
  //
  //  Markers            | weight | rationale
  //  ---------------------------------------------------------------------
  //  PERCLOS (EAR drop) |  0.40  | gold-standard drowsiness measure
  //  Yawning frequency  |  0.30  | slow-wave onset marker
  //  Blink rate drop    |  0.20  | lid-lag / microsleep precursor
  //  Prolonged sad/neut |  0.10  | cognitive fatigue correlate
  // =======================================================================

  double _computeFatigueScore(double relEAR, double relMAR) {
    if (_window.isEmpty) return 0.0;

    final snaps = _window.toList();
    final int n = snaps.length;

    // PERCLOS: fraction of frames where EAR < 80 % of baseline
    // i.e. eye is at least 20 % more closed than personal baseline
    const double perclosThreshold = 0.80;
    final int closedFrames = snaps
        .where((s) => s.ear < _baselineEAR * perclosThreshold)
        .length;
    final double perclos = closedFrames / n;

    // Yawning: frames in window with MAR > 150 % of baseline
    // Sustained jaw-open > ~2s counts as a yawn event
    const double yawnMARRatio = 1.5;
    final int yawnFrames = snaps
        .where((s) => s.mar > _baselineMAR * yawnMARRatio)
        .length;

    // Normalise by window - a 3s yawn in a 6s window = 0.5 raw,
    // we cap at ~2s per window as "full" fatigue signal
    final int yawnEquivalentFrames = (fps * 2).round();
    final double yawnScore = _clamp01(yawnFrames / (yawnEquivalentFrames + 1));

    // Blink rate drop (indicate fatigue/microsleeps)
    // Count leading-edge blink events in the window
    final double blinkRate = _countBlinkEvents(snaps) / (n / fps);

    // Typical alert blink rate ≈ 0.25/s (15 /min);
    // Signal fires when rate < half baseline (~0.12 /s)
    const double alertBlinkRate = 0.25;
    final double blinkRateDrop = _clamp01(1.0 - (blinkRate / alertBlinkRate));

    // Prolonged neutral/sad (emotional flat-line or cognitive fatigue)
    final int emotionFlatFrames = snaps
        .where(
          (s) =>
              s.emotion == BasicEmotion.neutral ||
              s.emotion == BasicEmotion.sad,
        )
        .length;
    final double emotionFlat = emotionFlatFrames / n;

    // == Weighted sum ========================================================
    final double raw =
        0.40 * perclos +
        0.30 * yawnScore +
        0.20 * blinkRateDrop +
        0.10 * emotionFlat;

    // Smooth with sigmoid so the score rises sharply only when markers align
    return _clamp01(_sigmoid(raw, gain: 8.0, mid: 0.30));
  }

  // ========================================================================
  //  STRESS SCORE
  //  Combines brow-furrow, eye-tension, negative emotion persistence,
  //  and head micro-jitter.
  //
  //  Markers               | weight | rationale
  //  ---------------------------------------------------------------------
  //  Brow-furrow intensity |  0.30  | period of intense focus/stress
  //  Neg-emotion streak    |  0.25  | sustained angry/sad/fearful
  //  Eye-tension (squint)  |  0.20  | orbicularis oculi engagement
  //  Head micro-jitter     |  0.15  | SNS-driven micro-tremor
  //  High blink rate       |  0.10  | stress-induced blink surge
  // ========================================================================

  double _computeStressScore({
    required double browFurrow,
    required double relEAR,
  }) {
    if (_window.isEmpty) return 0.0;

    final snaps = _window.toList();
    final int n = snaps.length;

    //  Brow-furrow mean across window
    final double furrowMean = _mean(snaps.map((s) => s.browFurrow).toList());

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

    //  Eye tension: sustained squint (not blink)
    // We proxy eye tension from the EAR — a slight persistent closure
    // (80–95 % baseline) that isn't a full blink
    const double squintLow = 0.80, squintHigh = 0.95;
    final int squintFrames = snaps
        .where(
          (s) =>
              s.ear < _baselineEAR * squintHigh &&
              s.ear > _baselineEAR * squintLow,
        )
        .length;
    final double eyeTension = squintFrames / n;

    //  Head micro-jitter
    final double jitter = _computeHeadJitter(snaps);

    //  High blink rate (stress surge — opposite of fatigue signal)
    final double blinkRate = _countBlinkEvents(snaps) / (n / fps);
    // Stress blink rate > ~0.5 /s (30 /min)
    const double stressBlinkRate = 0.50;
    final double blinkSurge = _clamp01(blinkRate / stressBlinkRate);

    // == Weighted sum ============================================
    final double raw =
        0.30 * furrowMean +
        0.25 * negScore +
        0.20 * eyeTension +
        0.15 * jitter +
        0.10 * blinkSurge;

    return _clamp01(_sigmoid(raw, gain: 8.0, mid: 0.25));
  }

  //  HELPERS
  // ================================================================

  /// Count leading-edge blink events: EAR drops below a closure threshold
  /// then rises above an open threshold (debounced to avoid double-counting).
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

  /// Compute normalised head jitter from nose-tip trajectory variance.
  /// High-frequency positional variance (frame-to-frame) = micro-tremor.
  double _computeHeadJitter(List<_FrameSnapshot> snaps) {
    if (snaps.length < 2) return 0.0;
    double sumSq = 0.0;
    for (int i = 1; i < snaps.length; i++) {
      final dx = snaps[i].noseTipX - snaps[i - 1].noseTipX;
      final dy = snaps[i].noseTipY - snaps[i - 1].noseTipY;
      sumSq += dx * dx + dy * dy;
    }
    final double rms = math.sqrt(sumSq / (snaps.length - 1));
    // Normalise: rms > 0.01 (1 % of frame dimension per-frame) = high jitter
    return _clamp01(rms / 0.01);
  }

  double _mean(List<double> values) {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }
}
