part of 'biopay_scan_screen.dart';

Future<void> _processBiopayFrame(
  _BiopayScanScreenState state,
  CameraImage frame,
) async {
  final controller = state._controller;
  if (controller == null) {
    return;
  }

  try {
    final stableFramesRequired =
        state.ref.read(biopayStableFramesProvider).valueOrNull ?? 3;
    final analysis = await state._faceDetectionService.analyzeFrame(
      frame: frame,
      camera: controller.description,
      stableFramesRequired: stableFramesRequired,
    );

    if (!state.mounted) {
      return;
    }

    if (!state._isEmbeddingReady && analysis.faceCount == 1) {
      state._setScannerState(
        tone: BiopayScannerTone.error,
        statusLabel: 'Embedding model unavailable',
        helperText:
            state._pipelineError ??
            'BioPay face detection is live, but the TFLite model is not ready yet.',
      );
      return;
    }

    final livenessAssessment = state._livenessService.evaluate(analysis);
    if (livenessAssessment != null) {
      state._setScannerState(
        tone: state._scannerToneForLiveness(livenessAssessment.level),
        statusLabel: livenessAssessment.statusLabel,
        helperText: livenessAssessment.helperText,
      );
      return;
    }

    state._applyAnalysisFeedback(analysis, stableFramesRequired);
    if (!analysis.isStable) {
      return;
    }

    final alignedTensor = await state._faceAlignmentService
        .extractAlignedFaceTensor(
          frame: frame,
          face: analysis.face!,
          rotationDegrees: analysis.rotationDegrees,
        );
    final embedding = await state._embeddingService.embed(alignedTensor);

    if (state.widget.mode == BiopayScanMode.enroll) {
      await state._handleEnrollmentEmbedding(embedding);
    } else {
      await state._handleMatchEmbedding(embedding);
    }
  } catch (error) {
    if (!state.mounted) {
      return;
    }
    state._updateScannerState(() {
      state._pipelineError = error.toString();
    });
    state._setScannerState(
      tone: BiopayScannerTone.error,
      statusLabel: 'BioPay pipeline error',
      helperText: error.toString(),
    );
  }
}

void _applyBiopayAnalysisFeedback(
  _BiopayScanScreenState state,
  BiopayFaceFrameAnalysis analysis,
  int stableFramesRequired,
) {
  final isEnroll = state.widget.mode == BiopayScanMode.enroll;
  switch (analysis.guidance) {
    case BiopayFaceGuidance.multipleFaces:
      state._setScannerState(
        tone: BiopayScannerTone.blocked,
        statusLabel: 'One person only',
        helperText:
            'BioPay needs a single face in frame before it can continue.',
      );
      break;
    case BiopayFaceGuidance.tooDark:
      state._setScannerState(
        tone: BiopayScannerTone.blocked,
        statusLabel: 'Move to better light',
        helperText: 'The camera image is too dark for a stable BioPay capture.',
      );
      break;
    case BiopayFaceGuidance.tooBright:
      state._setScannerState(
        tone: BiopayScannerTone.blocked,
        statusLabel: 'Reduce glare',
        helperText: 'Turn away from direct sunlight or strong overhead glare.',
      );
      break;
    case BiopayFaceGuidance.tooFar:
      state._setScannerState(
        tone: BiopayScannerTone.blocked,
        statusLabel: 'Move closer',
        helperText:
            'The face is too small in frame for a reliable BioPay capture.',
      );
      break;
    case BiopayFaceGuidance.headTurned:
      state._setScannerState(
        tone: BiopayScannerTone.blocked,
        statusLabel: 'Look straight at the camera',
        helperText: 'BioPay needs a forward-facing scan before it can proceed.',
      );
      break;
    case BiopayFaceGuidance.eyesClosed:
      state._setScannerState(
        tone: BiopayScannerTone.blocked,
        statusLabel: 'Please open your eyes',
        helperText: 'BioPay needs a clearer face frame before it can continue.',
      );
      break;
    case BiopayFaceGuidance.stable:
      state._setScannerState(
        tone: BiopayScannerTone.ready,
        statusLabel: isEnroll
            ? 'Stable face locked'
            : 'Face locked. Matching...',
        helperText: isEnroll
            ? 'BioPay is collecting enrollment frame ${(state._capturedEnrollmentFrames + 1).clamp(1, 5)} of 5.'
            : 'BioPay is generating an embedding and checking Supabase for a match.',
      );
      break;
    case BiopayFaceGuidance.searching:
      state._setScannerState(
        tone: BiopayScannerTone.searching,
        statusLabel: analysis.faceCount == 1 && analysis.stableCount > 0
            ? 'Hold still... ${analysis.stableCount}/$stableFramesRequired'
            : (isEnroll
                  ? 'Align your face inside the oval'
                  : 'Point the camera at the payee\'s face'),
        helperText: analysis.faceCount == 1 && analysis.stableCount > 0
            ? 'BioPay has a face in frame and is waiting for a stable capture.'
            : (isEnroll
                  ? 'Keep one face centered. Frames stay in memory and never go to the gallery.'
                  : 'Keep one face centered. BioPay will show the payee name before any dial action.'),
      );
      break;
  }
}

Future<void> _handleBiopayEnrollmentEmbedding(
  _BiopayScanScreenState state,
  Float32List embedding,
) async {
  final draft = state.widget.enrollmentDraft;
  if (draft == null) {
    state._setScannerState(
      tone: BiopayScannerTone.error,
      statusLabel: 'Enrollment data missing',
      helperText:
          'BioPay did not receive the enrollment route payload. Go back and start registration again.',
    );
    return;
  }

  if (state._enrollmentEmbeddings.length < 5) {
    final now = DateTime.now();
    if (state._lastEnrollmentCaptureAt != null &&
        now.difference(state._lastEnrollmentCaptureAt!) <
            const Duration(milliseconds: 500)) {
      return;
    }

    state._lastEnrollmentCaptureAt = now;
    state._enrollmentEmbeddings.add(embedding);
    state._capturedEnrollmentFrames = state._enrollmentEmbeddings.length;
    HapticFeedback.mediumImpact();

    if (state._capturedEnrollmentFrames < 5) {
      state._setScannerState(
        tone: BiopayScannerTone.ready,
        statusLabel: 'Captured ${state._capturedEnrollmentFrames} of 5',
        helperText:
            'Keep your face steady. BioPay averages five captures for a more stable enrollment vector.',
      );
      state._updateScannerState(() {});
      return;
    }
  }

  state._isSubmitting = true;
  state._setScannerState(
    tone: BiopayScannerTone.ready,
    statusLabel: 'Finalizing enrollment',
    helperText:
        'BioPay is averaging the face embeddings and storing the profile in Supabase.',
  );

  try {
    final averaged = state._embeddingService.averageEmbeddings(
      state._enrollmentEmbeddings.take(5).toList(growable: false),
    );
    final authResult = await state.ref
        .read(biopayAuthGateServiceProvider)
        .authorize(BiopayAuthAction.enrollment);
    if (!state.mounted) {
      return;
    }
    if (!authResult.isAuthorized) {
      state._setScannerState(
        tone: BiopayScannerTone.blocked,
        statusLabel: 'Identity confirmation required',
        helperText: authResult.message,
      );
      CoolToast.error(state.context, authResult.message);
      return;
    }

    final profile = await state.ref
        .read(biopayRepositoryProvider)
        .enroll(
          draft: draft,
          embedding: averaged.toList(growable: false),
          liveness: state._livenessService.submissionMetadata,
        );
    state.ref.invalidate(biopayProfileProvider);
    if (!state.mounted) {
      return;
    }
    CoolToast.success(
      state.context,
      'BioPay enrolled for ${profile.displayName}',
    );
    state.context.go(
      AppRoutes.biopayEnrollmentSuccessLocation(publicId: profile.publicId),
    );
  } catch (error) {
    if (!state.mounted) {
      return;
    }
    state._setScannerState(
      tone: BiopayScannerTone.error,
      statusLabel: 'Enrollment failed',
      helperText: error.toString(),
    );
    CoolToast.error(state.context, error.toString());
  } finally {
    state._isSubmitting = false;
  }
}

Future<void> _handleBiopayMatchEmbedding(
  _BiopayScanScreenState state,
  Float32List embedding,
) async {
  final now = DateTime.now();
  if (state._lastMatchAttemptAt != null &&
      now.difference(state._lastMatchAttemptAt!) <
          const Duration(milliseconds: 900)) {
    return;
  }
  state._lastMatchAttemptAt = now;
  state._isSubmitting = true;

  final embeddingList = embedding.toList(growable: false);
  final matchThreshold =
      state.ref.read(biopayMatchThresholdProvider).valueOrNull ?? 0.72;

  try {
    state._setScannerState(
      tone: BiopayScannerTone.ready,
      statusLabel: 'Matching...',
      helperText:
          'BioPay is sending the face embedding to Supabase for a nearest-profile match.',
    );

    final result = await state.ref
        .read(biopayRepositoryProvider)
        .matchEmbedding(
          embeddingList,
          liveness: state._livenessService.submissionMetadata,
        );

    if (!state.mounted) {
      return;
    }

    if (!result.match ||
        result.profile == null ||
        result.score < matchThreshold) {
      state._setScannerState(
        tone: BiopayScannerTone.error,
        statusLabel: 'No confident match',
        helperText:
            'Keep the payee in frame and try again. BioPay did not clear the match threshold.',
      );
      return;
    }

    state._setScannerState(
      tone: BiopayScannerTone.ready,
      statusLabel: 'Match confirmed',
      helperText: 'Preparing secure dialer for handoff...',
    );

    final intent = await state.ref
        .read(biopayRepositoryProvider)
        .createPaymentIntent(
          profilePublicId: result.profile!.publicId,
          matchScore: result.score,
        );

    if (!state.mounted) {
      return;
    }

    if (intent.isExpired) {
      state._setScannerState(
        tone: BiopayScannerTone.error,
        statusLabel: 'Intent expired',
        helperText: 'The payment intent expired. Please try scanning again.',
      );
      return;
    }

    final launched = await state.ref
        .read(biopayDialerServiceProvider)
        .dialIntent(intent);

    if (!state.mounted) {
      return;
    }

    if (!launched) {
      state._setScannerState(
        tone: BiopayScannerTone.error,
        statusLabel: 'Dialer failed',
        helperText: 'Could not open the MoMo dialer.',
      );
      return;
    }

    await state.ref
        .read(biopayRepositoryProvider)
        .markIntentDialed(intent.intentId);

    if (!state.mounted) {
      return;
    }

    CoolToast.success(
      state.context,
      'MoMo dialer opened for ${result.profile!.displayName}',
    );
    state.context.go(AppRoutes.biopayHome);
  } catch (error) {
    if (!state.mounted) {
      return;
    }
    state._setScannerState(
      tone: BiopayScannerTone.error,
      statusLabel: 'Match failed',
      helperText: error.toString(),
    );
    CoolToast.error(state.context, error.toString());
  } finally {
    if (state.mounted) {
      state._updateScannerState(() => state._isSubmitting = false);
    }
  }
}
