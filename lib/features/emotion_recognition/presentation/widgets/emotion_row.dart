import 'package:flutter/material.dart';
import '../../domain/models/analysis_result.dart';
import '../../domain/models/basic_emotion.dart';

String emotionEmoji(BasicEmotion e) {
  switch (e) {
    case BasicEmotion.happy:
      return '😄';
    case BasicEmotion.sad:
      return '😢';
    case BasicEmotion.angry:
      return '😠';
    case BasicEmotion.surprised:
      return '😲';
    case BasicEmotion.fearful:
      return '😨';
    case BasicEmotion.disgusted:
      return '🤢';
    case BasicEmotion.neutral:
      return '😐';
  }
}

Color emotionColor(BasicEmotion e) {
  switch (e) {
    case BasicEmotion.happy:
      return Colors.amber;
    case BasicEmotion.sad:
      return Colors.blueAccent;
    case BasicEmotion.angry:
      return Colors.redAccent;
    case BasicEmotion.surprised:
      return Colors.orangeAccent;
    case BasicEmotion.fearful:
      return Colors.purpleAccent;
    case BasicEmotion.disgusted:
      return Colors.greenAccent;
    case BasicEmotion.neutral:
      return Colors.grey;
  }
}

class EmotionRow extends StatelessWidget {
  const EmotionRow(this.analysis, {super.key});

  final AnalysisResult analysis;

  @override
  Widget build(BuildContext context) {
    final emotion = analysis.emotion.emotion;
    final color = emotionColor(emotion);

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Text(
            emotionEmoji(emotion),
            style: const TextStyle(fontSize: 42),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Current Emotion',
                style: TextStyle(
                  color: Colors.black45,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                emotion.name.toUpperCase(),
                style: TextStyle(
                  color: color,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
