import "basic_emotion.dart";

class EmotionResult {
  final BasicEmotion emotion;
  final double confidence; // 0-1
  const EmotionResult(this.emotion, this.confidence);

  @override
  String toString() =>
      '${emotion.name} (${(confidence * 100).toStringAsFixed(1)}%)';
}
