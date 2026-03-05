import 'package:flutter/material.dart';

class TopStatusChip extends StatelessWidget {
  const TopStatusChip({
    super.key,
    required this.fps,
    required this.faceDetected,
  });

  final double fps;
  final bool faceDetected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${fps.toStringAsFixed(1)} FPS',
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            faceDetected ? Icons.face : Icons.face_retouching_off,
            color: faceDetected ? Colors.green : Colors.redAccent,
            size: 18,
          ),
          const SizedBox(width: 4),
          Text(
            faceDetected ? 'Face' : 'No Face',
            style: TextStyle(
              color: faceDetected ? Colors.green : Colors.redAccent,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
