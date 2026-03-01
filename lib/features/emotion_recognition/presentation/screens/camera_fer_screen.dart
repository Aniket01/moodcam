import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/services/camera_service.dart';
import '../../domain/models/analysis_result.dart';
import '../../domain/models/basic_emotion.dart';
import '../state/pipeline_controller.dart';

// ─── Emotion display helpers ──────────────────────────────────────────────────

/// Emoji for each basic emotion.
String _emotionEmoji(BasicEmotion e) {
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

/// Accent colour for each basic emotion.
Color _emotionColor(BasicEmotion e) {
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

// ─── Screen ───────────────────────────────────────────────────────────────────

class CameraFERScreen extends StatefulWidget {
  const CameraFERScreen({super.key});

  @override
  State<CameraFERScreen> createState() => _CameraFERScreenState();
}

class _CameraFERScreenState extends State<CameraFERScreen>
    with WidgetsBindingObserver {
  final CameraService _cameraService = CameraService();
  late final PipelineController _pipelineController;
  bool _isCameraInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pipelineController = PipelineController(_cameraService);
    _initCameraAndStream();
  }

  Future<void> _initCameraAndStream() async {
    try {
      await _cameraService.initialize();
      await _pipelineController.initializeProcessor();

      if (mounted) {
        setState(() => _isCameraInitialized = true);
        _pipelineController.startProcessing();
      }
    } catch (e) {
      debugPrint('[Screen] ❌ Error initialising camera: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _cameraService.dispose();
      if (mounted) setState(() => _isCameraInitialized = false);
      return;
    }

    if (state == AppLifecycleState.resumed) {
      final controller = _cameraService.controller;
      if (controller == null || !controller.value.isInitialized) {
        _initCameraAndStream();
      } else {
        if (mounted) setState(() => _isCameraInitialized = true);
      }
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized || _cameraService.controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final controller = _cameraService.controller!;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Camera feed
            Center(
              child: AspectRatio(
                aspectRatio: 1 / controller.value.aspectRatio,
                child: CameraPreview(controller),
              ),
            ),

            // Top-left debug chip (FPS + face detection status)
            Positioned(
              top: 16,
              left: 16,
              child: ListenableBuilder(
                listenable: _pipelineController,
                builder: (context, _) => _TopStatusChip(
                  fps: _pipelineController.currentFps,
                  faceDetected: _pipelineController.faceDetected,
                ),
              ),
            ),

            // Bottom analysis overlay
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ListenableBuilder(
                listenable: _pipelineController,
                builder: (context, _) => _AnalysisOverlay(
                  faceDetected: _pipelineController.faceDetected,
                  analysis: _pipelineController.currentAnalysis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Top status chip ──────────────────────────────────────────────────────────

class _TopStatusChip extends StatelessWidget {
  const _TopStatusChip({required this.fps, required this.faceDetected});

  final double fps;
  final bool faceDetected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${fps.toStringAsFixed(1)} FPS',
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            faceDetected ? Icons.face : Icons.face_retouching_off,
            color: faceDetected ? Colors.greenAccent : Colors.redAccent,
            size: 18,
          ),
          const SizedBox(width: 4),
          Text(
            faceDetected ? 'Face' : 'No Face',
            style: TextStyle(
              color: faceDetected ? Colors.greenAccent : Colors.redAccent,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Main analysis overlay ────────────────────────────────────────────────────

class _AnalysisOverlay extends StatelessWidget {
  const _AnalysisOverlay({required this.faceDetected, required this.analysis});

  final bool faceDetected;
  final AnalysisResult? analysis;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!faceDetected || analysis == null) ...[
            _NoFaceRow(),
          ] else ...[
            if (!analysis!.isBaselineReady) _CalibrationBanner(analysis!),
            const SizedBox(height: 10),
            _EmotionRow(analysis!),
            const SizedBox(height: 14),
            _MarkerBar(
              label: 'Stress',
              emoji: '😤',
              value: analysis!.stressScore,
              color: Colors.redAccent,
            ),
            // Show debug metrics panel only in debug builds
            if (kDebugMode) ...[
              const SizedBox(height: 12),
              _DebugMetricsPanel(analysis!),
            ],
          ],
        ],
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _NoFaceRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '👁️  Point your camera at a face',
        style: TextStyle(color: Colors.white60, fontSize: 15),
      ),
    );
  }
}

class _CalibrationBanner extends StatelessWidget {
  const _CalibrationBanner(this.analysis);
  final AnalysisResult analysis;

  @override
  Widget build(BuildContext context) {
    final windowLen = (analysis.metrics['windowLen'] ?? 0).toInt();
    const int baselineFrames = 10;
    final double progress = (windowLen / baselineFrames).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          const Text('⏳', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Calibrating personal baseline…',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white12,
                  color: Colors.tealAccent,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(progress * 100).toStringAsFixed(0)}%',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _EmotionRow extends StatelessWidget {
  const _EmotionRow(this.analysis);
  final AnalysisResult analysis;

  @override
  Widget build(BuildContext context) {
    final emotion = analysis.emotion.emotion;
    final confidence = analysis.emotion.confidence;
    final color = _emotionColor(emotion);

    return Row(
      children: [
        Text(_emotionEmoji(emotion), style: const TextStyle(fontSize: 42)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                emotion.name.toUpperCase(),
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 4),
              // Confidence bar
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: confidence,
                        minHeight: 6,
                        backgroundColor: Colors.white12,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(confidence * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MarkerBar extends StatelessWidget {
  const _MarkerBar({
    required this.label,
    required this.emoji,
    required this.value,
    required this.color,
  });

  final String label;
  final String emoji;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        SizedBox(
          width: 58,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 8,
              backgroundColor: Colors.white10,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${(value * 100).toStringAsFixed(0)}%',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Expanded debug metrics table — only compiled and displayed in debug mode.
class _DebugMetricsPanel extends StatelessWidget {
  const _DebugMetricsPanel(this.analysis);
  final AnalysisResult analysis;

  @override
  Widget build(BuildContext context) {
    final m = analysis.metrics;
    final rows = <MapEntry<String, String>>[
      MapEntry('EAR', (m['ear'] ?? 0).toStringAsFixed(3)),
      MapEntry('MAR', (m['mar'] ?? 0).toStringAsFixed(3)),
      MapEntry('baseEAR', (m['baselineEAR'] ?? 0).toStringAsFixed(3)),
      MapEntry('baseMAR', (m['baselineMAR'] ?? 0).toStringAsFixed(3)),
      MapEntry('win', '${(m['windowLen'] ?? 0).toInt()} fr'),
    ];

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: rows
            .map(
              (e) => RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 11),
                  children: [
                    TextSpan(
                      text: '${e.key}: ',
                      style: const TextStyle(color: Colors.white38),
                    ),
                    TextSpan(
                      text: e.value,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
