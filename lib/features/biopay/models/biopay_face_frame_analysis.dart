import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

enum BiopayFaceGuidance {
  searching,
  multipleFaces,
  tooDark,
  tooBright,
  tooFar,
  headTurned,
  eyesClosed,
  stable,
}

class BiopayFaceFrameAnalysis {
  const BiopayFaceFrameAnalysis({
    required this.guidance,
    required this.faceCount,
    required this.brightness,
    required this.faceAreaRatio,
    required this.stableCount,
    required this.rotationDegrees,
    this.headYaw,
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
    this.face,
  });

  final BiopayFaceGuidance guidance;
  final Face? face;
  final int faceCount;
  final double brightness;
  final double faceAreaRatio;
  final int stableCount;
  final int rotationDegrees;
  final double? headYaw;
  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;

  bool get isStable => guidance == BiopayFaceGuidance.stable && face != null;
  double get absHeadYaw => (headYaw ?? 0).abs();
}
