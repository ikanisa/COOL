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
    this.face,
  });

  final BiopayFaceGuidance guidance;
  final Face? face;
  final int faceCount;
  final double brightness;
  final double faceAreaRatio;
  final int stableCount;
  final int rotationDegrees;

  bool get isStable => guidance == BiopayFaceGuidance.stable && face != null;
}
