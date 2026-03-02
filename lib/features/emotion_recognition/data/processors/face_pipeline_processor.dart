import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';
import 'package:moodcam/core/constants/k_left_eye_contour.dart';
import 'package:moodcam/core/constants/k_right_eye_contour.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:math' as math;
import 'dart:isolate';

// ----------------------------------------------------------------------------
// Isolate Payload Structures
// ----------------------------------------------------------------------------

class IsolateInitData {
  final SendPort sendPort;
  final Uint8List ferModel;

  IsolateInitData(this.sendPort, this.ferModel);
}

class IsolateFrameData {
  // Raw CameraImage planar data
  final List<Uint8List> planeBytes;
  final List<int> planeBytesPerRow;
  final List<int?> planeBytesPerPixel;

  final int width;
  final int height;
  final ImageFormatGroup format;
  final int sensorOrientation;

  // Face bounding box & landmarks
  final Rect boundingBox;
  final List<List<double>> landmarks478;

  IsolateFrameData({
    required this.planeBytes,
    required this.planeBytesPerRow,
    required this.planeBytesPerPixel,
    required this.width,
    required this.height,
    required this.format,
    required this.sensorOrientation,
    required this.boundingBox,
    required this.landmarks478,
  });
}

class IsolateResultData {
  final List<double> ferEmotions;
  final int imageWidth;
  final int imageHeight;
  final List<List<double>> landmarks478;

  IsolateResultData(
    this.ferEmotions,
    this.imageWidth,
    this.imageHeight,
    this.landmarks478,
  );
}

// ----------------------------------------------------------------------------
// FacePipelineProcessor
// ----------------------------------------------------------------------------

class FacePipelineProcessor {
  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  /// Called after FER + ML Kit inference with the 7-class emotion probabilities,
  /// full 478-point [x, y] landmark list in pixel coordinates, plus image dims.
  final void Function(
    List<double> ferEmotions,
    List<List<double>> landmarks,
    int imageWidth,
    int imageHeight,
  )?
  onAnalysisResult;

  final VoidCallback? onFrameDropped;

  late final FaceMeshDetector _meshDetector;

  // Isolate Management
  Isolate? _tfliteIsolate;
  SendPort? _isolateSendPort;
  late final ReceivePort _mainReceivePort;

  FacePipelineProcessor({this.onAnalysisResult, this.onFrameDropped});

  Future<void> initialize() async {
    _meshDetector = FaceMeshDetector(option: FaceMeshDetectorOptions.faceMesh);

    // Read YOLO FER int8 model bytes
    final ferBytes = (await rootBundle.load(
      'assets/models/yolo_fer_int8.tflite',
    )).buffer.asUint8List();

    // Setup communication port
    _mainReceivePort = ReceivePort();
    _mainReceivePort.listen(_handleIsolateMessage);

    // Spawn Isolate
    _tfliteIsolate = await Isolate.spawn(
      _tfliteIsolateEntry,
      IsolateInitData(_mainReceivePort.sendPort, ferBytes),
    );

    debugPrint('✅ Isolate spawned — YOLO FER int8 model loaded.');
  }

  void _handleIsolateMessage(dynamic message) {
    if (message is SendPort) {
      _isolateSendPort = message;
      debugPrint('[Pipeline] 🟢 Isolate SendPort received.');
    } else if (message is IsolateResultData) {
      _isProcessing = false;

      onAnalysisResult?.call(
        message.ferEmotions,
        message.landmarks478,
        message.imageWidth,
        message.imageHeight,
      );
    } else if (message == "ERROR") {
      _isProcessing = false;
      debugPrint('[Pipeline] ❌ Isolate returned error.');
      onFrameDropped?.call();
    }
  }

  Future<void> processFrame(CameraImage image, CameraDescription camera) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      // Convert CameraImage to InputImage (NV21)
      final inputImage = _toInputImage(image, camera);
      if (inputImage == null) {
        _isProcessing = false;
        onFrameDropped?.call();
        return;
      }

      // Run ML Kit Face Mesh
      final meshes = await _meshDetector.processImage(inputImage);
      if (meshes.isEmpty) {
        _isProcessing = false;
        onFrameDropped?.call();
        return;
      }

      final FaceMesh mesh = meshes.first;
      final List<FaceMeshPoint> pts = mesh.points;

      if (pts.length < 468) {
        _isProcessing = false;
        onFrameDropped?.call();
        return;
      }

      // Build the full 478-point array (468 real + 10 iris synthesized)
      final List<List<double>> all478 = List.generate(478, (i) {
        if (i < 468) {
          final p = pts[i];
          return [p.x.toDouble(), p.y.toDouble()];
        }
        return [0.0, 0.0];
      });

      _synthesizeIris(all478, kRightEyeContour, 468);
      _synthesizeIris(all478, kLeftEyeContour, 473);

      final int imgW = image.width;
      final int imgH = image.height;

      // Ensure Isolate is ready
      if (_isolateSendPort == null) {
        _isProcessing = false;
        return;
      }

      // Serialize image plane buffers
      List<Uint8List> planeBytes = [];
      List<int> planeBytesPerRow = [];
      List<int?> planeBytesPerPixel = [];

      for (var plane in image.planes) {
        planeBytes.add(plane.bytes);
        planeBytesPerRow.add(plane.bytesPerRow);
        planeBytesPerPixel.add(plane.bytesPerPixel);
      }

      final isolatePayload = IsolateFrameData(
        planeBytes: planeBytes,
        planeBytesPerRow: planeBytesPerRow,
        planeBytesPerPixel: planeBytesPerPixel,
        width: imgW,
        height: imgH,
        format: image.format.group,
        sensorOrientation: camera.sensorOrientation,
        boundingBox: mesh.boundingBox,
        landmarks478: all478,
      );

      _isolateSendPort!.send(isolatePayload);
    } catch (e, stack) {
      _isProcessing = false;
      debugPrint('[Pipeline] ❌ processFrame error: $e\n$stack');
      onFrameDropped?.call();
    }
  }

  /// Synthesize 5 iris points (center + 4 cardinal) from eye contour.
  void _synthesizeIris(
    List<List<double>> all478,
    List<int> eyeContour,
    int startIdx,
  ) {
    double cx = 0, cy = 0;
    for (final idx in eyeContour) {
      cx += all478[idx][0];
      cy += all478[idx][1];
    }
    cx /= eyeContour.length;
    cy /= eyeContour.length;
    all478[startIdx] = [cx, cy];

    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final idx in eyeContour) {
      final x = all478[idx][0], y = all478[idx][1];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    final double rx = (maxX - minX) / 4;
    final double ry = (maxY - minY) / 4;
    all478[startIdx + 1] = [cx + rx, cy];
    all478[startIdx + 2] = [cx, cy - ry];
    all478[startIdx + 3] = [cx - rx, cy];
    all478[startIdx + 4] = [cx, cy + ry];
  }

  /// Convert YUV420 -> NV21
  InputImage? _toInputImage(CameraImage image, CameraDescription camera) {
    final rotation = InputImageRotationValue.fromRawValue(
      camera.sensorOrientation,
    );
    if (rotation == null) return null;

    final int w = image.width, h = image.height;
    final int ySize = w * h;
    final Uint8List nv21 = Uint8List(ySize + w * h ~/ 2);

    final yPlane = image.planes[0];
    for (int row = 0; row < h; row++) {
      nv21.setRange(
        row * w,
        row * w + w,
        yPlane.bytes,
        row * yPlane.bytesPerRow,
      );
    }

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
    _mainReceivePort.close();
    _tfliteIsolate?.kill(priority: Isolate.immediate);
  }
}

// ----------------------------------------------------------------------------
// Isolate Entry Point (runs entirely off the main thread)
// ----------------------------------------------------------------------------

void _tfliteIsolateEntry(IsolateInitData initData) {
  final ReceivePort receivePort = ReceivePort();
  final SendPort sendPort = initData.sendPort;

  sendPort.send(receivePort.sendPort);

  Interpreter? ferInterpreter;

  try {
    ferInterpreter = Interpreter.fromBuffer(initData.ferModel);
  } catch (e) {
    sendPort.send("ERROR");
    return;
  }

  receivePort.listen((message) {
    if (message is IsolateFrameData) {
      try {
        final imgW = message.width;
        final imgH = message.height;
        final all478 = message.landmarks478;

        // FER Model Inference
        List<double> ferEmotions = List<double>.filled(7, 0.0);
        img.Image? croppedImg = _cropAndConvertFaceToImageIso(message);

        if (croppedImg != null) {
          // Rotate if necessary to make face upright
          if (message.sensorOrientation != 0) {
            croppedImg = img.copyRotate(
              croppedImg,
              angle: message.sensorOrientation,
            );
          }

          final img.Image resizedImg = img.copyResize(
            croppedImg,
            width: 224,
            height: 224,
          );

          final dynamic inTensor = ferInterpreter?.getInputTensor(0);
          final String inTypeStr = inTensor?.type?.toString() ?? '';
          final bool inIsFloat = inTypeStr.toLowerCase().contains('float');
          double inScale = 0.0;
          int inZp = 0;
          try {
            final dynamic inQp = inTensor?.quantizationParams;
            if (inQp != null) {
              inScale = (inQp.scale as num).toDouble();
              inZp = (inQp.zeroPoint as num).toInt();
            }
          } catch (_) {}

          final dynamic outTensor = ferInterpreter?.getOutputTensor(0);
          final String outTypeStr = outTensor?.type?.toString() ?? '';
          final bool outIsInt = outTypeStr.toLowerCase().contains('int');
          double outScale = 0.0;
          int outZp = 0;
          try {
            final dynamic outQp = outTensor?.quantizationParams;
            if (outQp != null) {
              outScale = (outQp.scale as num).toDouble();
              outZp = (outQp.zeroPoint as num).toInt();
            }
          } catch (_) {}

          // Build input as nested List so tflite_flutter receives the expected shape ([1, H, W, C]).
          final List inputBuffer = List.generate(1, (_) {
            return List.generate(224, (yy) {
              return List.generate(224, (xx) {
                final dynamic pix = resizedImg.getPixel(xx, yy);
                int r = 0, g = 0, b = 0;
                if (pix is int) {
                  r = (pix >> 16) & 0xFF;
                  g = (pix >> 8) & 0xFF;
                  b = pix & 0xFF;
                } else {
                  final dynamic p = pix;
                  r = ((p.r ?? 0) as num).toInt();
                  g = ((p.g ?? 0) as num).toInt();
                  b = ((p.b ?? 0) as num).toInt();
                }
                r = r.clamp(0, 255);
                g = g.clamp(0, 255);
                b = b.clamp(0, 255);

                if (inIsFloat) {
                  // Normalize to [0, 1]
                  return [r / 255.0, g / 255.0, b / 255.0];
                } else {
                  if (inScale > 0.0) {
                    // Quantize based on scale and zeroPoint
                    int qr = ((r / inScale) + inZp).round();
                    int qg = ((g / inScale) + inZp).round();
                    int qb = ((b / inScale) + inZp).round();
                    return [qr, qg, qb];
                  } else {
                    return [r, g, b];
                  }
                }
              });
            });
          });

          // Allocate output buffer matching the interpreter's expected output type.
          final dynamic rawOutput = outIsInt
              ? List.generate(1, (_) => List<int>.filled(7, 0))
              : List.generate(1, (_) => List<double>.filled(7, 0.0));

          ferInterpreter?.run(inputBuffer, rawOutput);

          // Extract and dequantize logits
          List<double> logits = List<double>.filled(7, 0.0);
          if (outIsInt) {
            for (int i = 0; i < 7; i++) {
              double val = (rawOutput[0][i] as num).toDouble();
              if (outScale > 0.0) {
                logits[i] = (val - outZp) * outScale;
              } else {
                logits[i] = val;
              }
            }
          } else {
            for (int i = 0; i < 7; i++) {
              logits[i] = (rawOutput[0][i] as num).toDouble();
            }
          }

          // Apply softmax to get probabilities
          ferEmotions = _softmax(logits);
        }

        sendPort.send(IsolateResultData(ferEmotions, imgW, imgH, all478));
      } catch (e) {
        debugPrint('[Isolate] ❌ Inference error: $e');
        sendPort.send("ERROR");
      }
    }
  });
}

/// Softmax: convert raw logits -> probabilities that sum to 1.0
List<double> _softmax(List<double> logits) {
  final double maxLogit = logits.reduce(math.max);
  final List<double> exps = logits.map((v) => math.exp(v - maxLogit)).toList();
  final double sumExps = exps.reduce((a, b) => a + b);
  return exps.map((v) => v / sumExps).toList();
}

// Isolate helper: crop face region from raw plane bytes
img.Image? _cropAndConvertFaceToImageIso(IsolateFrameData data) {
  int rot = data.sensorOrientation;
  int rawW = data.width;
  int rawH = data.height;

  final Rect bbox = data.boundingBox;
  List<math.Point<int>> corners = [
    math.Point(bbox.left.floor(), bbox.top.floor()),
    math.Point(bbox.right.ceil(), bbox.top.floor()),
    math.Point(bbox.right.ceil(), bbox.bottom.ceil()),
    math.Point(bbox.left.floor(), bbox.bottom.ceil()),
  ];

  List<math.Point<int>> rawCorners = corners.map((p) {
    int x = p.x;
    int y = p.y;
    if (rot == 90) {
      return math.Point(y, rawH - 1 - x);
    } else if (rot == 270) {
      return math.Point(rawW - 1 - y, x);
    } else if (rot == 180) {
      return math.Point(rawW - 1 - x, rawH - 1 - y);
    }
    return p;
  }).toList();

  int minX = rawCorners.map((p) => p.x).reduce(math.min);
  int maxX = rawCorners.map((p) => p.x).reduce(math.max);
  int minY = rawCorners.map((p) => p.y).reduce(math.min);
  int maxY = rawCorners.map((p) => p.y).reduce(math.max);

  int startX = math.max(0, minX.clamp(0, rawW - 1));
  int startY = math.max(0, minY.clamp(0, rawH - 1));
  int endX = math.min(rawW, maxX.clamp(0, rawW));
  int endY = math.min(rawH, maxY.clamp(0, rawH));
  int cropW = endX - startX;
  int cropH = endY - startY;

  if (cropW <= 0 || cropH <= 0) return null;

  final img.Image result = img.Image(width: cropW, height: cropH);

  if (data.format == ImageFormatGroup.yuv420) {
    final int uvRowStride = data.planeBytesPerRow[1];
    final int uvPixelStride = data.planeBytesPerPixel[1] ?? 1;

    for (int y = 0; y < cropH; y++) {
      int imgY = startY + y;
      int pY = imgY * data.planeBytesPerRow[0] + startX;
      int pUV = (imgY >> 1) * uvRowStride + (startX >> 1) * uvPixelStride;

      for (int x = 0; x < cropW; x++) {
        final int yValue = data.planeBytes[0][pY++];
        final int uValue = data.planeBytes[1][pUV];
        final int vValue = data.planeBytes[2][pUV];

        if ((startX + x) % 2 == 1) pUV += uvPixelStride;

        int r = (yValue + 1.370705 * (vValue - 128)).round().clamp(0, 255);
        int g = (yValue - 0.337633 * (uValue - 128) - 0.698001 * (vValue - 128))
            .round()
            .clamp(0, 255);
        int b = (yValue + 1.732446 * (uValue - 128)).round().clamp(0, 255);

        result.setPixelRgb(x, y, r, g, b);
      }
    }
  } else if (data.format == ImageFormatGroup.bgra8888) {
    for (int y = 0; y < cropH; y++) {
      int imgY = startY + y;
      int p = (imgY * data.planeBytesPerRow[0]) + (startX * 4);
      for (int x = 0; x < cropW; x++) {
        int b = data.planeBytes[0][p++];
        int g = data.planeBytes[0][p++];
        int r = data.planeBytes[0][p++];
        p++; // skip alpha
        result.setPixelRgb(x, y, r, g, b);
      }
    }
  } else {
    return null;
  }
  return result;
}
