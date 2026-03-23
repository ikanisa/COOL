import 'package:cool_app/features/biopay/models/biopay_face_frame_analysis.dart';
import 'package:cool_app/features/biopay/services/biopay_liveness_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BiopayLivenessService', () {
    test('payment mode requires a blink and head turn before capture', () {
      final service = BiopayLivenessService(mode: BiopayLivenessMode.payment);

      expect(
        service.evaluate(_analysis()),
        isA<BiopayLivenessAssessment>().having(
          (assessment) => assessment.statusLabel,
          'statusLabel',
          'Blink once',
        ),
      );

      service.evaluate(
        _analysis(
          guidance: BiopayFaceGuidance.eyesClosed,
          leftEyeOpenProbability: 0.18,
          rightEyeOpenProbability: 0.21,
        ),
      );

      expect(service.isSatisfied, isFalse);
      expect(
        service.evaluate(_analysis()),
        isA<BiopayLivenessAssessment>().having(
          (assessment) => assessment.statusLabel,
          'statusLabel',
          'Turn your head slightly',
        ),
      );

      service.evaluate(
        _analysis(guidance: BiopayFaceGuidance.headTurned, headYaw: 22),
      );

      expect(service.isSatisfied, isTrue);
      expect(service.submissionMetadata?['result'], 'passed');
      expect(service.submissionMetadata?['completed_steps'], const <String>[
        'blink',
        'turn_side',
      ]);
    });

    test('enrollment mode requires recentering after the head turn', () {
      final service = BiopayLivenessService(
        mode: BiopayLivenessMode.enrollment,
      );

      service.evaluate(_analysis());
      service.evaluate(
        _analysis(
          guidance: BiopayFaceGuidance.eyesClosed,
          leftEyeOpenProbability: 0.14,
          rightEyeOpenProbability: 0.19,
        ),
      );
      service.evaluate(_analysis());
      service.evaluate(
        _analysis(guidance: BiopayFaceGuidance.headTurned, headYaw: 24),
      );

      expect(service.isSatisfied, isFalse);
      expect(service.evaluate(_analysis()), isNull);
      expect(service.isSatisfied, isTrue);
      expect(service.submissionMetadata?['completed_steps'], const <String>[
        'blink',
        'turn_side',
        'recenter',
      ]);
    });

    test('resets the challenge when progress stalls for too long', () {
      final service = BiopayLivenessService(
        mode: BiopayLivenessMode.payment,
        maxFramesWithoutProgress: 1,
      );

      final assessment = service.evaluate(_analysis());

      expect(assessment, isNotNull);
      expect(assessment?.statusLabel, 'Liveness challenge restarted');
      expect(service.isSatisfied, isFalse);
      expect(service.submissionMetadata, isNull);
    });
  });
}

BiopayFaceFrameAnalysis _analysis({
  BiopayFaceGuidance guidance = BiopayFaceGuidance.stable,
  int faceCount = 1,
  double brightness = 0.54,
  double faceAreaRatio = 0.24,
  int stableCount = 3,
  int rotationDegrees = 0,
  double? headYaw = 0,
  double? leftEyeOpenProbability = 0.92,
  double? rightEyeOpenProbability = 0.9,
}) {
  return BiopayFaceFrameAnalysis(
    guidance: guidance,
    faceCount: faceCount,
    brightness: brightness,
    faceAreaRatio: faceAreaRatio,
    stableCount: stableCount,
    rotationDegrees: rotationDegrees,
    headYaw: headYaw,
    leftEyeOpenProbability: leftEyeOpenProbability,
    rightEyeOpenProbability: rightEyeOpenProbability,
  );
}
