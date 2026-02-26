import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectionService {
  late final FaceDetector _faceDetector;

  FaceDetectionService() {
    // We set performanceMode to fast. We do not need landmarks or classification
    final options = FaceDetectorOptions(
      enableContours: false,
      enableLandmarks: false,
      enableClassification: false,
      enableTracking: false,
      performanceMode: FaceDetectorMode.fast,
    );
    _faceDetector = FaceDetector(options: options);
  }

  Future<Face?> detectFace(InputImage inputImage) async {
    try {
      final faces = await _faceDetector.processImage(inputImage);

      // For facial expression recognition, we enforce a strict rule:
      // Only process the frame if exactly ONE face is visible.
      if (faces.length == 1) {
        return faces.first;
      }

      // Discard frames with 0 faces or crowds
      return null;
    } catch (e) {
      if (kDebugMode) print('❌ Face detection error: $e');
      return null;
    }
  }

  void dispose() {
    _faceDetector.close();
  }
}
