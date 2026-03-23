import 'dart:math' as math;

import '../models/biopay_face_frame_analysis.dart';

enum BiopayLivenessMode { enrollment, payment }

enum BiopayLivenessFeedbackLevel { searching, ready, blocked }

class BiopayLivenessAssessment {
  const BiopayLivenessAssessment({
    required this.level,
    required this.statusLabel,
    required this.helperText,
  });

  final BiopayLivenessFeedbackLevel level;
  final String statusLabel;
  final String helperText;
}

enum _BiopayLivenessStep { blink, turnSide, recenter }

class BiopayLivenessService {
  BiopayLivenessService({required this.mode, int maxFramesWithoutProgress = 45})
    : _maxFramesWithoutProgress = maxFramesWithoutProgress;

  static const challengeVersion = 'challenge_pad_v1';
  static const _eyesOpenThreshold = 0.68;
  static const _eyesClosedThreshold = 0.36;
  static const _headTurnThreshold = 18.0;
  static const _recenterThreshold = 8.0;

  final BiopayLivenessMode mode;
  final int _maxFramesWithoutProgress;

  bool _isSatisfied = false;
  bool _blinkArmed = false;
  bool _blinkClosedObserved = false;
  int _stepIndex = 0;
  int _framesEvaluated = 0;
  int _framesWithoutProgress = 0;
  double _maxAbsHeadYaw = 0;
  DateTime? _completedAt;

  bool get isSatisfied => _isSatisfied;

  Map<String, Object?>? get submissionMetadata {
    if (!_isSatisfied || _completedAt == null) {
      return null;
    }

    return <String, Object?>{
      'version': challengeVersion,
      'mode': mode.name,
      'result': 'passed',
      'completed_steps': _requiredSteps
          .map((step) => _stepCode(step))
          .toList(growable: false),
      'frames_evaluated': _framesEvaluated,
      'max_abs_head_yaw': double.parse(_maxAbsHeadYaw.toStringAsFixed(2)),
      'blink_detected': true,
      'completed_at': _completedAt!.toUtc().toIso8601String(),
    };
  }

  void reset() {
    _isSatisfied = false;
    _blinkArmed = false;
    _blinkClosedObserved = false;
    _stepIndex = 0;
    _framesEvaluated = 0;
    _framesWithoutProgress = 0;
    _maxAbsHeadYaw = 0;
    _completedAt = null;
  }

  BiopayLivenessAssessment? evaluate(BiopayFaceFrameAnalysis analysis) {
    if (_isSatisfied) {
      return null;
    }

    if (!_canEvaluateChallenge(analysis)) {
      reset();
      return null;
    }

    _framesEvaluated += 1;
    _maxAbsHeadYaw = math.max(_maxAbsHeadYaw, analysis.absHeadYaw);

    final step = _requiredSteps[_stepIndex];
    final advanced = switch (step) {
      _BiopayLivenessStep.blink => _advanceBlink(analysis),
      _BiopayLivenessStep.turnSide => _advanceTurnSide(analysis),
      _BiopayLivenessStep.recenter => _advanceRecenter(analysis),
    };

    if (advanced) {
      _framesWithoutProgress = 0;
      _stepIndex += 1;
      if (_stepIndex >= _requiredSteps.length) {
        _isSatisfied = true;
        _completedAt = DateTime.now();
        return null;
      }
      return _buildAssessment(_requiredSteps[_stepIndex], analysis);
    } else {
      _framesWithoutProgress += 1;
      if (_framesWithoutProgress >= _maxFramesWithoutProgress) {
        reset();
        return const BiopayLivenessAssessment(
          level: BiopayLivenessFeedbackLevel.blocked,
          statusLabel: 'Liveness challenge restarted',
          helperText:
              'BioPay did not observe the required live movement. Re-center your face and follow the prompt again.',
        );
      }
    }

    return _buildAssessment(step, analysis);
  }

  List<_BiopayLivenessStep> get _requiredSteps =>
      mode == BiopayLivenessMode.enrollment
      ? const <_BiopayLivenessStep>[
          _BiopayLivenessStep.blink,
          _BiopayLivenessStep.turnSide,
          _BiopayLivenessStep.recenter,
        ]
      : const <_BiopayLivenessStep>[
          _BiopayLivenessStep.blink,
          _BiopayLivenessStep.turnSide,
        ];

  bool _canEvaluateChallenge(BiopayFaceFrameAnalysis analysis) {
    if (analysis.faceCount != 1) {
      return false;
    }

    return switch (analysis.guidance) {
      BiopayFaceGuidance.multipleFaces => false,
      BiopayFaceGuidance.tooDark => false,
      BiopayFaceGuidance.tooBright => false,
      BiopayFaceGuidance.tooFar => false,
      _ => true,
    };
  }

  bool _advanceBlink(BiopayFaceFrameAnalysis analysis) {
    if (_eyesAreOpen(analysis)) {
      if (_blinkArmed && _blinkClosedObserved) {
        return true;
      }
      _blinkArmed = true;
      return false;
    }

    if (_blinkArmed && _eyesAreClosed(analysis)) {
      _blinkClosedObserved = true;
    }
    return false;
  }

  bool _advanceTurnSide(BiopayFaceFrameAnalysis analysis) {
    return analysis.absHeadYaw >= _headTurnThreshold;
  }

  bool _advanceRecenter(BiopayFaceFrameAnalysis analysis) {
    return analysis.absHeadYaw <= _recenterThreshold && _eyesAreOpen(analysis);
  }

  BiopayLivenessAssessment _buildAssessment(
    _BiopayLivenessStep step,
    BiopayFaceFrameAnalysis analysis,
  ) {
    return switch (step) {
      _BiopayLivenessStep.blink => _buildBlinkAssessment(analysis),
      _BiopayLivenessStep.turnSide => const BiopayLivenessAssessment(
        level: BiopayLivenessFeedbackLevel.ready,
        statusLabel: 'Turn your head slightly',
        helperText:
            'BioPay needs a small head turn to reject flat or replayed face presentations.',
      ),
      _BiopayLivenessStep.recenter => const BiopayLivenessAssessment(
        level: BiopayLivenessFeedbackLevel.ready,
        statusLabel: 'Look straight again',
        helperText:
            'Center your face in the oval so BioPay can finish the live challenge and continue.',
      ),
    };
  }

  BiopayLivenessAssessment _buildBlinkAssessment(
    BiopayFaceFrameAnalysis analysis,
  ) {
    if (analysis.leftEyeOpenProbability == null ||
        analysis.rightEyeOpenProbability == null) {
      return const BiopayLivenessAssessment(
        level: BiopayLivenessFeedbackLevel.blocked,
        statusLabel: 'Keep both eyes visible',
        helperText:
            'BioPay could not read both eyes clearly enough to run the live blink challenge.',
      );
    }

    if (!_blinkArmed) {
      return const BiopayLivenessAssessment(
        level: BiopayLivenessFeedbackLevel.searching,
        statusLabel: 'Hold steady with eyes open',
        helperText:
            'BioPay is arming the live blink challenge before it allows a capture.',
      );
    }

    if (!_blinkClosedObserved) {
      return const BiopayLivenessAssessment(
        level: BiopayLivenessFeedbackLevel.ready,
        statusLabel: 'Blink once',
        helperText:
            'A quick natural blink helps BioPay confirm a live face before capture.',
      );
    }

    return const BiopayLivenessAssessment(
      level: BiopayLivenessFeedbackLevel.ready,
      statusLabel: 'Open your eyes again',
      helperText:
          'BioPay detected the blink and is waiting for your eyes to reopen to finish the challenge.',
    );
  }

  bool _eyesAreOpen(BiopayFaceFrameAnalysis analysis) {
    final left = analysis.leftEyeOpenProbability;
    final right = analysis.rightEyeOpenProbability;
    return left != null &&
        right != null &&
        left >= _eyesOpenThreshold &&
        right >= _eyesOpenThreshold;
  }

  bool _eyesAreClosed(BiopayFaceFrameAnalysis analysis) {
    final left = analysis.leftEyeOpenProbability;
    final right = analysis.rightEyeOpenProbability;
    return left != null &&
        right != null &&
        left <= _eyesClosedThreshold &&
        right <= _eyesClosedThreshold;
  }

  String _stepCode(_BiopayLivenessStep step) {
    return switch (step) {
      _BiopayLivenessStep.blink => 'blink',
      _BiopayLivenessStep.turnSide => 'turn_side',
      _BiopayLivenessStep.recenter => 'recenter',
    };
  }
}
