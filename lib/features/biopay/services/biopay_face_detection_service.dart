import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../models/biopay_face_frame_analysis.dart';

class BiopayFaceDetectionService {
  BiopayFaceDetectionService()
    : _detector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          enableLandmarks: true,
          enableTracking: true,
          performanceMode: FaceDetectorMode.fast,
        ),
      );

  final FaceDetector _detector;
  int _stableCount = 0;

  Future<BiopayFaceFrameAnalysis> analyzeFrame({
    required CameraImage frame,
    required CameraDescription camera,
    required int stableFramesRequired,
  }) async {
    final rotationDegrees = _resolveRotationDegrees(camera);
    final inputImage = _buildInputImage(frame, rotationDegrees);
    final faces = await _detector.processImage(inputImage);

    final brightness = _estimateBrightness(frame);
    if (faces.length != 1) {
      _stableCount = 0;
      return BiopayFaceFrameAnalysis(
        guidance: faces.length > 1
            ? BiopayFaceGuidance.multipleFaces
            : BiopayFaceGuidance.searching,
        faceCount: faces.length,
        brightness: brightness,
        faceAreaRatio: 0,
        stableCount: _stableCount,
        rotationDegrees: rotationDegrees,
      );
    }

    final face = faces.first;
    final area = face.boundingBox.width * face.boundingBox.height;
    final areaRatio = area / (frame.width * frame.height);

    final guidance = _resolveGuidance(
      face: face,
      brightness: brightness,
      areaRatio: areaRatio,
    );

    if (guidance == BiopayFaceGuidance.stable) {
      _stableCount += 1;
      if (_stableCount >= stableFramesRequired) {
        return BiopayFaceFrameAnalysis(
          guidance: BiopayFaceGuidance.stable,
          face: face,
          faceCount: 1,
          brightness: brightness,
          faceAreaRatio: areaRatio,
          stableCount: _stableCount,
          rotationDegrees: rotationDegrees,
        );
      }
      return BiopayFaceFrameAnalysis(
        guidance: BiopayFaceGuidance.searching,
        face: face,
        faceCount: 1,
        brightness: brightness,
        faceAreaRatio: areaRatio,
        stableCount: _stableCount,
        rotationDegrees: rotationDegrees,
      );
    }

    _stableCount = 0;
    return BiopayFaceFrameAnalysis(
      guidance: guidance,
      face: face,
      faceCount: 1,
      brightness: brightness,
      faceAreaRatio: areaRatio,
      stableCount: _stableCount,
      rotationDegrees: rotationDegrees,
    );
  }

  Future<void> close() => _detector.close();

  BiopayFaceGuidance _resolveGuidance({
    required Face face,
    required double brightness,
    required double areaRatio,
  }) {
    if (brightness < 0.23) {
      return BiopayFaceGuidance.tooDark;
    }
    if (brightness > 0.88) {
      return BiopayFaceGuidance.tooBright;
    }
    if (areaRatio < 0.15) {
      return BiopayFaceGuidance.tooFar;
    }
    if ((face.headEulerAngleY ?? 0).abs() > 15) {
      return BiopayFaceGuidance.headTurned;
    }
    final leftEye = face.leftEyeOpenProbability;
    final rightEye = face.rightEyeOpenProbability;
    if ((leftEye != null && leftEye < 0.4) ||
        (rightEye != null && rightEye < 0.4)) {
      return BiopayFaceGuidance.eyesClosed;
    }
    return BiopayFaceGuidance.stable;
  }

  InputImage _buildInputImage(CameraImage frame, int rotationDegrees) {
    final inputImageFormat = InputImageFormatValue.fromRawValue(
      frame.format.raw,
    );
    if (inputImageFormat == null) {
      throw StateError('Unsupported BioPay camera image format.');
    }

    final bytes = _packPlaneBytes(frame);
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(frame.width.toDouble(), frame.height.toDouble()),
        rotation:
            InputImageRotationValue.fromRawValue(rotationDegrees) ??
            InputImageRotation.rotation0deg,
        format: inputImageFormat,
        bytesPerRow: frame.planes.first.bytesPerRow,
      ),
    );
  }

  Uint8List _packPlaneBytes(CameraImage frame) {
    if (Platform.isIOS) {
      return frame.planes.first.bytes;
    }

    final totalLength = frame.planes.fold<int>(
      0,
      (sum, plane) => sum + plane.bytes.length,
    );
    final bytes = Uint8List(totalLength);
    var offset = 0;
    for (final plane in frame.planes) {
      bytes.setRange(offset, offset + plane.bytes.length, plane.bytes);
      offset += plane.bytes.length;
    }
    return bytes;
  }

  double _estimateBrightness(CameraImage frame) {
    final lumaBytes = frame.planes.first.bytes;
    if (lumaBytes.isEmpty) {
      return 0;
    }
    const sampleStride = 16;
    var total = 0;
    var count = 0;
    for (var index = 0; index < lumaBytes.length; index += sampleStride) {
      total += lumaBytes[index];
      count += 1;
    }
    return (total / count) / 255.0;
  }

  int _resolveRotationDegrees(CameraDescription camera) {
    return camera.sensorOrientation % 360;
  }
}
