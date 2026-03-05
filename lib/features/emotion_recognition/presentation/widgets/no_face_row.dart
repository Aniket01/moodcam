import 'package:flutter/material.dart';

class NoFaceRow extends StatelessWidget {
  const NoFaceRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '👁️  Point your camera at a face',
        style: TextStyle(
          color: Colors.black54,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
