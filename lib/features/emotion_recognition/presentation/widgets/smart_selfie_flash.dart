import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'face_guide_painter.dart';

class SmartSelfieFlash extends StatefulWidget {
  final bool isLowLight;
  final Widget cameraPreview;

  const SmartSelfieFlash({
    super.key,
    required this.isLowLight,
    required this.cameraPreview,
  });

  @override
  State<SmartSelfieFlash> createState() => _SmartSelfieFlashState();
}

class _SmartSelfieFlashState extends State<SmartSelfieFlash> {
  @override
  void didUpdateWidget(covariant SmartSelfieFlash oldWidget) {
    super.didUpdateWidget(oldWidget);
    // trigger brightness change only when boolean flag actually flips
    if (widget.isLowLight != oldWidget.isLowLight) {
      _handleBrightnessChange(widget.isLowLight);
    }
  }

  Future<void> _handleBrightnessChange(bool isLowLight) async {
    try {
      if (isLowLight) {
        await ScreenBrightness().setApplicationScreenBrightness(1.0);
      } else {
        // return to original brightness
        await ScreenBrightness().resetApplicationScreenBrightness();
      }
    } catch (e) {
      debugPrint('❌Failed to adjust application brightness: $e');
    }
  }

  @override
  void dispose() {
    ScreenBrightness().resetApplicationScreenBrightness();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.cameraPreview,

        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: widget.isLowLight ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: CustomPaint(painter: FaceGuidePainter()),
            ),
          ),
        ),
      ],
    );
  }
}
