import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';
import 'package:moodcam/core/constants/k_blendshape_landmark_indices.dart';
import 'package:moodcam/core/constants/k_left_eye_contour.dart';
import 'package:moodcam/core/constants/k_right_eye_contour.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class FacePipelineProcessor {
  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  final Function(List<double> blendshapes)? onBlendshapesOutput;

  /// Called after TFLite inference with both the 52 blendshape scores and the
  /// full 478-point [x, y] landmark list in pixel coordinates, plus the
  /// image dimensions needed to normalise landmarks.
  final void Function(
    List<double> blendshapes,
    List<List<double>> landmarks,
    int imageWidth,
    int imageHeight,
  )?
  onAnalysisResult;

  final VoidCallback? onFrameDropped;

  late final FaceMeshDetector _meshDetector;
  late final Interpreter _blendShapes;

  FacePipelineProcessor({
    this.onBlendshapesOutput,
    this.onAnalysisResult,
    this.onFrameDropped,
  });

  Future<void> initialize() async {
    _meshDetector = FaceMeshDetector(option: FaceMeshDetectorOptions.faceMesh);

    final bytes = (await rootBundle.load(
      'assets/models/blendShapes.tflite',
    )).buffer.asUint8List();
    _blendShapes = Interpreter.fromBuffer(bytes);

    debugPrint(
      'BlendShapes model loaded — '
      'input: ${_blendShapes.getInputTensors().map((t) => t.shape)}, '
      'output: ${_blendShapes.getOutputTensors().map((t) => t.shape)}',
    );
  }

  Future<void> processFrame(CameraImage image, CameraDescription camera) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      // Convert CameraImage → InputImage (NV21)
      final inputImage = _toInputImage(image, camera);
      if (inputImage == null) {
        debugPrint(
          '[Pipeline] ⚠️ _toInputImage returned null — unsupported rotation or format',
        );
        _isProcessing = false;
        onFrameDropped?.call();
        return;
      }

      // Run ML Kit Face Mesh
      final meshes = await _meshDetector.processImage(inputImage);
      if (meshes.isEmpty) {
        debugPrint(
          '[Pipeline] 🔍 ML Kit: no face meshes detected in this frame',
        );
        _isProcessing = false;
        onFrameDropped?.call();
        return;
      }

      final FaceMesh mesh = meshes.first;
      final List<FaceMeshPoint> pts = mesh.points;

      debugPrint(
        '[Pipeline] 🟢 ML Kit: ${pts.length} landmarks — '
        'bbox: left=${mesh.boundingBox.left.toStringAsFixed(1)}, '
        'top=${mesh.boundingBox.top.toStringAsFixed(1)}, '
        'w=${mesh.boundingBox.width.toStringAsFixed(1)}, '
        'h=${mesh.boundingBox.height.toStringAsFixed(1)}',
      );

      if (pts.length < 468) {
        debugPrint(
          '[Pipeline] ⚠️ ML Kit returned only ${pts.length} points (expected ≥468), dropping frame',
        );
        _isProcessing = false;
        onFrameDropped?.call();
        return;
      }

      //  Build the full 478-point array (468 real + 10 iris synthesized)
      //  Each point is [x, y] in pixel coordinates.
      final List<List<double>> all478 = List.generate(478, (i) {
        if (i < 468) {
          final p = pts[i];
          return [p.x.toDouble(), p.y.toDouble()];
        }
        return [0.0, 0.0]; // placeholder, filled below
      });

      // Synthesize iris points 468-477
      _synthesizeIris(all478, kRightEyeContour, 468); // right iris 468-472
      _synthesizeIris(all478, kLeftEyeContour, 473); // left iris 473-477

      // Select the 146-landmark subset & normalize to [0, 1]
      final int imgW = image.width;
      final int imgH = image.height;

      final Float32List bsInput = Float32List(1 * 146 * 2);
      for (int i = 0; i < 146; i++) {
        final idx = kBlendshapeLandmarkIndices[i];
        bsInput[i * 2] = all478[idx][0] / imgW;
        bsInput[i * 2 + 1] = all478[idx][1] / imgH;
      }

      // Run BlendShapes TFLite
      final output = List<double>.filled(52, 0.0);
      _blendShapes.run(bsInput.reshape([1, 146, 2]), output);

      final blendshapes = output.map((v) => (v as num).toDouble()).toList();

      // Debug: log a min/max summary of TFLite output
      final double bsMin = blendshapes.reduce((a, b) => a < b ? a : b);
      final double bsMax = blendshapes.reduce((a, b) => a > b ? a : b);
      debugPrint(
        '[Pipeline] 🧠 TFLite blendshapes — '
        'min: ${bsMin.toStringAsFixed(3)}, max: ${bsMax.toStringAsFixed(3)}, '
        'BS[0-4]: ${blendshapes.take(5).map((v) => v.toStringAsFixed(3)).join(', ')}',
      );

      _isProcessing = false;

      // Notify blendshape-only listener (kept for backward compatibility)
      onBlendshapesOutput?.call(blendshapes);

      // Notify analysis listener with full landmark set + image dimensions
      onAnalysisResult?.call(blendshapes, all478, imgW, imgH);
    } catch (e, stack) {
      _isProcessing = false;
      debugPrint('[Pipeline] ❌ processFrame error: $e\n$stack');
      onFrameDropped?.call();
    }
  }

  /// Synthesize 5 iris points (center + 4 cardinal) from eye contour.
  /// Writes into [all478] at indices [startIdx] through [startIdx + 4].
  void _synthesizeIris(
    List<List<double>> all478,
    List<int> eyeContour,
    int startIdx,
  ) {
    // Iris center = average of all contour points
    double cx = 0, cy = 0;
    for (final idx in eyeContour) {
      cx += all478[idx][0];
      cy += all478[idx][1];
    }
    cx /= eyeContour.length;
    cy /= eyeContour.length;
    all478[startIdx] = [cx, cy]; // iris center

    // 4 cardinal points: right, top, left, bottom of iris
    // Use contour extremes as approximations
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final idx in eyeContour) {
      final x = all478[idx][0], y = all478[idx][1];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    // Iris radius ≈ half the smaller eye dimension
    final double rx = (maxX - minX) / 4;
    final double ry = (maxY - minY) / 4;
    all478[startIdx + 1] = [cx + rx, cy]; // right
    all478[startIdx + 2] = [cx, cy - ry]; // top
    all478[startIdx + 3] = [cx - rx, cy]; // left
    all478[startIdx + 4] = [cx, cy + ry]; // bottom
  }

  /// Convert YUV420 to NV21
  InputImage? _toInputImage(CameraImage image, CameraDescription camera) {
    final rotation = InputImageRotationValue.fromRawValue(
      camera.sensorOrientation,
    );
    if (rotation == null) return null;

    // Build NV21 bytes from YUV420 planes
    final int w = image.width, h = image.height;
    final int ySize = w * h;
    final Uint8List nv21 = Uint8List(ySize + w * h ~/ 2);

    // Y plane (row-by-row to skip padding)
    final yPlane = image.planes[0];
    for (int row = 0; row < h; row++) {
      nv21.setRange(
        row * w,
        row * w + w,
        yPlane.bytes,
        row * yPlane.bytesPerRow,
      );
    }

    // Interleave V, U into NV21 order
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    int off = ySize;
    for (int row = 0; row < h ~/ 2; row++) {
      for (int col = 0; col < w ~/ 2; col++) {
        final ui = row * uPlane.bytesPerRow + col * (uPlane.bytesPerPixel ?? 1);
        final vi = row * vPlane.bytesPerRow + col * (vPlane.bytesPerPixel ?? 1);
        nv21[off++] = vPlane.bytes[vi];
        nv21[off++] = uPlane.bytes[ui];
      }
    }

    return InputImage.fromBytes(
      bytes: nv21,
      metadata: InputImageMetadata(
        size: Size(w.toDouble(), h.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: w,
      ),
    );
  }

  void dispose() {
    _meshDetector.close();
    _blendShapes.close();
  }
}
