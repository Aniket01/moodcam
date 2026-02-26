import 'dart:io';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class ImageConverter {
  static InputImage? convertCameraImage(
    CameraImage image,
    CameraDescription camera,
  ) {
    // 1. Calculate the rotation based on the physical hardware sensor
    final rotation = InputImageRotationValue.fromRawValue(
      camera.sensorOrientation,
    );
    if (rotation == null) {
      if (kDebugMode) print('❌ Image rotation is null');
      return null;
    }

    // 2. Determine the format based on platform and planes
    // Android typically uses YUV_420_888 (3 planes), iOS uses BGRA8888 (1 plane)
    InputImageFormat? format;

    if (Platform.isAndroid && image.planes.length == 3) {
      format = InputImageFormat.yuv_420_888;
      if (kDebugMode) print('Android YUV_420_888 detected (3 planes)');
    } else if (Platform.isIOS && image.planes.length == 1) {
      format = InputImageFormat.bgra8888;
      if (kDebugMode) print('iOS BGRA8888 detected (1 plane)');
    } else {
      // Fallback: try to detect from enum
      final detectedFormat = InputImageFormatValue.fromRawValue(
        image.format.raw,
      );
      if (detectedFormat == InputImageFormat.yuv_420_888 ||
          detectedFormat == InputImageFormat.bgra8888) {
        format = detectedFormat;
        if (kDebugMode) {
          print('Format detected from enum: $format (raw=${image.format.raw})');
        }
      }
    }

    if (format == null) {
      if (kDebugMode) {
        print(
          '❌ Unable to determine format. Planes: ${image.planes.length}, Raw: ${image.format.raw}',
        );
      }
      return null;
    }

    // 3. Convert/flatten the byte planes into the format ML Kit expects.
    // On Android the camera often provides YUV_420_888 (3 planes). ML Kit
    // expects NV21-like layout (Y plane followed by interleaved VU).
    try {
      Uint8List bytes;
      int bytesPerRow;

      if (format == InputImageFormat.yuv_420_888 && Platform.isAndroid) {
        final int width = image.width;
        final int height = image.height;
        final Plane yPlane = image.planes[0];
        final Plane uPlane = image.planes[1];
        final Plane vPlane = image.planes[2];

        final int yRowStride = yPlane.bytesPerRow;
        final int yPixelStride = yPlane.bytesPerPixel ?? 1;

        final int uvRowStride = uPlane.bytesPerRow;
        final int uvPixelStride = uPlane.bytesPerPixel ?? 1;

        final int ySize = width * height;
        final int uvSize = width * height ~/ 2;
        final Uint8List nv21 = Uint8List(ySize + uvSize);

        // Copy Y plane
        int dstIndex = 0;
        if (yPixelStride == 1 && yRowStride == width) {
          nv21.setRange(0, ySize, yPlane.bytes);
          dstIndex = ySize;
        } else {
          for (int row = 0; row < height; row++) {
            int srcRowStart = row * yRowStride;
            if (yPixelStride == 1) {
              nv21.setRange(
                dstIndex,
                dstIndex + width,
                yPlane.bytes.sublist(srcRowStart, srcRowStart + width),
              );
              dstIndex += width;
            } else {
              for (int col = 0; col < width; col++) {
                nv21[dstIndex++] =
                    yPlane.bytes[srcRowStart + col * yPixelStride];
              }
            }
          }
        }

        // Interleave V and U to produce NV21 (VU order)
        for (int row = 0; row < height ~/ 2; row++) {
          int uvRowStart = row * uvRowStride;
          for (int col = 0; col < width ~/ 2; col++) {
            final int uIndex = uvRowStart + col * uvPixelStride;
            final int vIndex =
                row * vPlane.bytesPerRow + col * (vPlane.bytesPerPixel ?? 1);
            nv21[dstIndex++] = vPlane.bytes[vIndex];
            nv21[dstIndex++] = uPlane.bytes[uIndex];
          }
        }

        bytes = nv21;
        bytesPerRow = width;
        if (kDebugMode) {
          print(
            '📊 Converted to NV21: ${width}x${height}, bytes.length=${bytes.length}',
          );
        }
      } else {
        // iOS BGRA or fallback: concatenate planes as before
        final WriteBuffer allBytes = WriteBuffer();
        for (final Plane plane in image.planes) {
          allBytes.putUint8List(plane.bytes);
        }
        bytes = allBytes.done().buffer.asUint8List();
        bytesPerRow = image.planes[0].bytesPerRow;
        if (kDebugMode) {
          print(
            'Using concatenated bytes: ${image.width}x${image.height}, bytes.length=${bytes.length}',
          );
        }
      }

      final usedFormat =
          (format == InputImageFormat.yuv_420_888 && Platform.isAndroid)
          ? InputImageFormat.nv21
          : format;

      if (kDebugMode) {
        print(
          'Passing to ML Kit: format=$usedFormat, bytesPerRow=$bytesPerRow',
        );
      }

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: usedFormat,
          bytesPerRow: bytesPerRow,
        ),
      );
    } catch (e) {
      if (kDebugMode) print('❌ Failed to create InputImage: $e');
      return null;
    }
  }
}
