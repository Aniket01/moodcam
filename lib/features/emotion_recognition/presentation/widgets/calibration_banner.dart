import 'package:flutter/material.dart';
import '../../domain/models/analysis_result.dart';

class CalibrationBanner extends StatelessWidget {
  const CalibrationBanner(this.analysis, {super.key});

  final AnalysisResult analysis;

  @override
  Widget build(BuildContext context) {
    final windowLen = (analysis.metrics['windowLen'] ?? 0).toInt();
    const int baselineFrames = 10;
    final double progress = (windowLen / baselineFrames).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          const Text('⏳', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Calibrating personal baseline…',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.blue.withValues(alpha: 0.15),
                  color: Colors.blueAccent,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${(progress * 100).toStringAsFixed(0)}%',
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
