import 'package:flutter/material.dart';
import '../../domain/models/analysis_result.dart';
import 'no_face_row.dart';
import 'calibration_banner.dart';
import 'emotion_row.dart';
import 'marker_bar.dart';

class AnalysisOverlay extends StatelessWidget {
  const AnalysisOverlay({
    super.key,
    required this.faceDetected,
    required this.analysis,
  });

  final bool faceDetected;
  final AnalysisResult? analysis;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!faceDetected || analysis == null) ...[
            const NoFaceRow(),
          ] else ...[
            if (!analysis!.isBaselineReady) ...[
              CalibrationBanner(analysis!),
              const SizedBox(height: 16),
            ],
            EmotionRow(analysis!),
            const SizedBox(height: 20),
            MarkerBar(
              label: 'Stress',
              emoji: '😤',
              value: analysis!.stressScore,
              color: Colors.redAccent,
            ),
          ],
        ],
      ),
    );
  }
}
