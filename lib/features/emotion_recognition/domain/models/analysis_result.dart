import 'emotion_result.dart';

class AnalysisResult {
  /// Discrete emotion + confidence
  final EmotionResult emotion;

  /// Continuous fatigue score 0 (alert) → 1 (very fatigued)
  final double fatigueScore;

  /// Continuous stress score 0 (relaxed) → 1 (highly stressed)
  final double stressScore;

  /// Whether the baseline calibration period is complete
  final bool isBaselineReady;

  /// Internal metrics exposed for debugging / UI display
  final Map<String, double> metrics;

  const AnalysisResult({
    required this.emotion,
    required this.fatigueScore,
    required this.stressScore,
    required this.isBaselineReady,
    this.metrics = const {},
  });
}
