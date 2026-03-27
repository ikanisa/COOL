import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import '../models/biopay_model_contract.dart';

class BiopayFaceAlignmentService {
  static int get inputWidth => BiopayModelContract.expectedInputShape[1];
  static int get inputHeight => BiopayModelContract.expectedInputShape[2];

  Future<Float32List> extractAlignedFaceTensor({
    required CameraImage frame,
    required Face face,
    required int rotationDegrees,
  }) async {
    final image = _convertCameraImage(frame);
    final uprightImage = _rotateToUpright(image, rotationDegrees);
    final cropRect = _resolveCropRect(
      face.boundingBox,
      uprightImage.width,
      uprightImage.height,
    );

    var cropped = img.copyCrop(
      uprightImage,
      x: cropRect.left,
      y: cropRect.top,
      width: cropRect.width,
      height: cropRect.height,
    );
    final roll = face.headEulerAngleZ ?? 0;
    if (roll.abs() >= 2) {
      cropped = img.copyRotate(cropped, angle: -roll);
    }

    final resized = img.copyResize(
      cropped,
      width: inputWidth,
      height: inputHeight,
      interpolation: img.Interpolation.linear,
    );

    return _normaliseImage(resized);
  }

  img.Image _convertCameraImage(CameraImage frame) {
    return switch (frame.format.group) {
      ImageFormatGroup.bgra8888 => img.Image.fromBytes(
        width: frame.width,
        height: frame.height,
        bytes: frame.planes.first.bytes.buffer,
        order: img.ChannelOrder.bgra,
      ),
      ImageFormatGroup.nv21 => _convertNv21(frame),
      ImageFormatGroup.yuv420 => _convertYuv420(frame),
      _ => throw StateError(
        'Unsupported BioPay image format group: ${frame.format.group}',
      ),
    };
  }

  img.Image _convertNv21(CameraImage frame) {
    final image = img.Image(width: frame.width, height: frame.height);
    final plane = frame.planes.first;
    final bytes = plane.bytes;
    final yRowStride = plane.bytesPerRow;
    final yPlaneLength = yRowStride * frame.height;

    for (var h = 0; h < frame.height; h += 1) {
      final uvRowStart = yPlaneLength + (h ~/ 2) * yRowStride;
      for (var w = 0; w < frame.width; w += 1) {
        final yIndex = (h * yRowStride) + w;
        final uvIndex = uvRowStart + (w & ~1);

        final y = bytes[yIndex];
        final v = bytes[uvIndex];
        final u = bytes[uvIndex + 1];

        var r = (y + v * 1436 / 1024 - 179).round();
        var g = (y - u * 46549 / 131072 + 44 - v * 93604 / 131072 + 91).round();
        var b = (y + u * 1814 / 1024 - 227).round();

        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);
        image.setPixelRgb(w, h, r, g, b);
      }
    }

    return image;
  }

  img.Image _convertYuv420(CameraImage frame) {
    final image = img.Image(width: frame.width, height: frame.height);
    final yBuffer = frame.planes[0].bytes;
    final uBuffer = frame.planes[1].bytes;
    final vBuffer = frame.planes[2].bytes;
    final yRowStride = frame.planes[0].bytesPerRow;
    final yPixelStride = frame.planes[0].bytesPerPixel ?? 1;
    final uvRowStride = frame.planes[1].bytesPerRow;
    final uvPixelStride = frame.planes[1].bytesPerPixel ?? 1;

    for (var h = 0; h < frame.height; h += 1) {
      final uvh = h ~/ 2;
      for (var w = 0; w < frame.width; w += 1) {
        final uvw = w ~/ 2;
        final yIndex = (h * yRowStride) + (w * yPixelStride);
        final uvIndex = (uvh * uvRowStride) + (uvw * uvPixelStride);

        final y = yBuffer[yIndex];
        final u = uBuffer[uvIndex];
        final v = vBuffer[uvIndex];

        var r = (y + v * 1436 / 1024 - 179).round();
        var g = (y - u * 46549 / 131072 + 44 - v * 93604 / 131072 + 91).round();
        var b = (y + u * 1814 / 1024 - 227).round();

        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);
        image.setPixelRgb(w, h, r, g, b);
      }
    }

    return image;
  }

  img.Image _rotateToUpright(img.Image image, int rotationDegrees) {
    return switch (rotationDegrees % 360) {
      90 => img.copyRotate(image, angle: 90),
      180 => img.copyRotate(image, angle: 180),
      270 => img.copyRotate(image, angle: 270),
      _ => image,
    };
  }

  _CropRect _resolveCropRect(Rect faceRect, int imageWidth, int imageHeight) {
    final expandedWidth = faceRect.width * 1.45;
    final expandedHeight = faceRect.height * 1.65;
    final squareSize = math.max(expandedWidth, expandedHeight);
    final left = (faceRect.center.dx - squareSize / 2).round();
    final top = (faceRect.center.dy - squareSize / 2).round();
    final safeLeft = left.clamp(0, imageWidth - 1);
    final safeTop = top.clamp(0, imageHeight - 1);
    final safeWidth = squareSize.round().clamp(1, imageWidth - safeLeft);
    final safeHeight = squareSize.round().clamp(1, imageHeight - safeTop);
    return _CropRect(
      left: safeLeft,
      top: safeTop,
      width: safeWidth,
      height: safeHeight,
    );
  }

  Float32List _normaliseImage(img.Image image) {
    final tensor = Float32List(inputWidth * inputHeight * 3);
    var offset = 0;
    for (var y = 0; y < inputHeight; y += 1) {
      for (var x = 0; x < inputWidth; x += 1) {
        final pixel = image.getPixel(x, y);
        tensor[offset++] = (pixel.r / 127.5) - 1.0;
        tensor[offset++] = (pixel.g / 127.5) - 1.0;
        tensor[offset++] = (pixel.b / 127.5) - 1.0;
      }
    }
    return tensor;
  }
}

class _CropRect {
  const _CropRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final int left;
  final int top;
  final int width;
  final int height;
}
