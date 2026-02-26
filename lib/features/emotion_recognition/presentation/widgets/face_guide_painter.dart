import 'package:flutter/material.dart';

class FaceGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Define the Oval dimensions (standard face proportions)
    final center = Offset(
      size.width / 2,
      size.height / 2.5,
    ); // Slightly above center
    final ovalRect = Rect.fromCenter(
      center: center,
      width: size.width * 0.7, // 70% of screen width
      height: size.height * 0.45, // 45% of screen height
    );

    // Setup paths
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final ovalPath = Path()..addOval(ovalRect);

    // Cut the oval out of the background
    final overlayPath = Path.combine(
      PathOperation.difference,
      backgroundPath,
      ovalPath,
    );

    // Semi-transparent dark overlay
    final overlayPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;
    canvas.drawPath(overlayPath, overlayPaint);

    // Bright border around the oval
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawOval(ovalRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
