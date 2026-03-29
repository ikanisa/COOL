import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_access_provider.dart';
import '../../../core/providers/engagement_providers.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/services/app_access_service.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../auth/providers/auth_provider.dart';
import '../../profile/widgets/profile_app_access_sheet.dart';
import '../models/biopay_enrollment_draft.dart';
import '../models/biopay_face_frame_analysis.dart';
import '../providers/biopay_providers.dart';
import '../services/biopay_auth_gate_service.dart';
import '../services/biopay_embedding_service.dart';
import '../services/biopay_face_alignment_service.dart';
import '../services/biopay_face_detection_service.dart';
import '../services/biopay_liveness_service.dart';
import '../widgets/biopay_scanner_shell.dart';

enum BiopayScanMode { enroll, pay }

class BiopayScanScreen extends ConsumerStatefulWidget {
  const BiopayScanScreen({required this.mode, this.enrollmentDraft, super.key});

  final BiopayScanMode mode;
  final BiopayEnrollmentDraft? enrollmentDraft;

  @override
  ConsumerState<BiopayScanScreen> createState() => _BiopayScanScreenState();
}

class _BiopayScanScreenState extends ConsumerState<BiopayScanScreen> {
  final _faceDetectionService = BiopayFaceDetectionService();
  final _faceAlignmentService = BiopayFaceAlignmentService();
  final _embeddingService = BiopayEmbeddingService();
  final List<Float32List> _enrollmentEmbeddings = <Float32List>[];
  late final BiopayLivenessService _livenessService;

  CameraController? _controller;
  AppAccessSnapshot? _cameraSnapshot;
  bool _isInitializingCamera = true;
  bool _isProcessingFrame = false;
  bool _isSubmitting = false;
  bool _isEmbeddingReady = false;
  bool _isClosing = false;
  int _capturedEnrollmentFrames = 0;
  String? _cameraError;
  String? _pipelineError;
  String _statusLabel = 'Preparing secure camera...';
  String _helperText = 'Loading BioPay camera access and on-device services.';
  BiopayScannerTone _tone = BiopayScannerTone.searching;
  DateTime? _lastEnrollmentCaptureAt;
  DateTime? _lastMatchAttemptAt;
  DateTime? _lastFrameProcessedAt;

  @override
  void initState() {
    super.initState();
    _livenessService = BiopayLivenessService(
      mode: widget.mode == BiopayScanMode.enroll
          ? BiopayLivenessMode.enrollment
          : BiopayLivenessMode.payment,
    );
    unawaited(_loadCameraState());
  }

  @override
  void dispose() {
    _embeddingService.dispose();
    unawaited(_faceDetectionService.close());
    final controller = _controller;
    _controller = null;
    controller?.dispose();
    super.dispose();
  }

  Future<void> _loadCameraState() async {
    final service = ref.read(appAccessServiceProvider);
    final snapshot = await service.getSnapshot(AppAccessPermission.camera);
    if (!mounted) {
      return;
    }

    setState(() {
      _cameraSnapshot = snapshot;
      _cameraError = null;
    });

    if (snapshot.isReady) {
      await _initializeCamera();
      return;
    }

    setState(() => _isInitializingCamera = false);
  }

  Future<void> _requestCameraAccess() async {
    final service = ref.read(appAccessServiceProvider);
    setState(() {
      _isInitializingCamera = true;
      _cameraError = null;
    });

    final snapshot = await service.enableAndRequest(AppAccessPermission.camera);
    if (!mounted) {
      return;
    }

    setState(() => _cameraSnapshot = snapshot);
    if (snapshot.isReady) {
      await _initializeCamera();
      return;
    }
    setState(() => _isInitializingCamera = false);
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException(
          'no_camera',
          'No camera was found on this device.',
        );
      }

      final preferredLens = widget.mode == BiopayScanMode.enroll
          ? CameraLensDirection.front
          : CameraLensDirection.back;
      final camera = cameras.firstWhere(
        (candidate) => candidate.lensDirection == preferredLens,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.nv21,
      );

      await controller.initialize();
      try {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {
        // Best-effort only. The app shell is portrait-locked already.
      }
      final previous = _controller;
      _controller = controller;
      await previous?.dispose();

      if (!mounted) {
        return;
      }

      setState(() {
        _isInitializingCamera = false;
        _cameraError = null;
      });
      await _warmPipeline();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isInitializingCamera = false;
        _cameraError = error.toString();
        _tone = BiopayScannerTone.error;
      });
    }
  }

  Future<void> _warmPipeline() async {
    final ready = await _embeddingService.ensureInitialized();
    if (!mounted) {
      return;
    }

    setState(() {
      _isEmbeddingReady = ready;
      _pipelineError = ready ? null : _embeddingService.initializationError;
      _statusLabel = widget.mode == BiopayScanMode.enroll
          ? 'Align your face inside the oval'
          : 'Point the camera at the payee\'s face';
      _helperText = widget.mode == BiopayScanMode.enroll
          ? 'BioPay is analyzing live frames in memory only. Hold still when the oval turns green.'
          : 'BioPay is analyzing live frames in memory only. Keep one face centered for a fast match.';
      _tone = BiopayScannerTone.searching;
    });
    _livenessService.reset();

    final controller = _controller;
    if (controller == null || controller.value.isStreamingImages) {
      return;
    }
    await controller.startImageStream(_handleCameraFrame);
  }

  Future<void> _stopCameraPipeline() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // Best effort only. The image stream may already be stopping.
    }
    try {
      await controller.dispose();
    } catch (_) {
      // Best effort only. The controller may already be disposed.
    }
    if (identical(_controller, controller)) {
      _controller = null;
    }
  }

  Future<void> _closeScanner() async {
    if (_isClosing) {
      return;
    }
    _isClosing = true;
    await _stopCameraPipeline();
    if (!mounted) {
      return;
    }
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(AppRoutes.biopayHome);
  }

  void _handleCameraFrame(CameraImage frame) {
    if (!mounted ||
        _isProcessingFrame ||
        _isSubmitting ||
        _controller == null) {
      return;
    }
    final now = DateTime.now();
    if (_lastFrameProcessedAt != null &&
        now.difference(_lastFrameProcessedAt!) <
            const Duration(milliseconds: 120)) {
      return;
    }
    _lastFrameProcessedAt = now;
    _isProcessingFrame = true;
    unawaited(
      _processFrame(frame).whenComplete(() {
        _isProcessingFrame = false;
      }),
    );
  }

  Future<void> _processFrame(CameraImage frame) async {
    final controller = _controller;
    if (controller == null) {
      return;
    }

    try {
      final stableFramesRequired =
          ref.read(biopayStableFramesProvider).valueOrNull ?? 3;
      final analysis = await _faceDetectionService.analyzeFrame(
        frame: frame,
        camera: controller.description,
        stableFramesRequired: stableFramesRequired,
      );

      if (!mounted) {
        return;
      }

      if (!_isEmbeddingReady && analysis.faceCount == 1) {
        _setScannerState(
          tone: BiopayScannerTone.error,
          statusLabel: 'Embedding model unavailable',
          helperText:
              _pipelineError ??
              'BioPay face detection is live, but the TFLite model is not ready yet.',
        );
        return;
      }

      final livenessAssessment = _livenessService.evaluate(analysis);
      if (livenessAssessment != null) {
        _setScannerState(
          tone: _scannerToneForLiveness(livenessAssessment.level),
          statusLabel: livenessAssessment.statusLabel,
          helperText: livenessAssessment.helperText,
        );
        return;
      }

      _applyAnalysisFeedback(analysis, stableFramesRequired);
      if (!analysis.isStable) {
        return;
      }

      final alignedTensor = await _faceAlignmentService
          .extractAlignedFaceTensor(
            frame: frame,
            face: analysis.face!,
            rotationDegrees: analysis.rotationDegrees,
          );
      final embedding = await _embeddingService.embed(alignedTensor);

      if (widget.mode == BiopayScanMode.enroll) {
        await _handleEnrollmentEmbedding(embedding);
      } else {
        await _handleMatchEmbedding(embedding);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _pipelineError = error.toString();
      });
      _setScannerState(
        tone: BiopayScannerTone.error,
        statusLabel: 'BioPay pipeline error',
        helperText: error.toString(),
      );
    }
  }

  void _applyAnalysisFeedback(
    BiopayFaceFrameAnalysis analysis,
    int stableFramesRequired,
  ) {
    final isEnroll = widget.mode == BiopayScanMode.enroll;
    switch (analysis.guidance) {
      case BiopayFaceGuidance.multipleFaces:
        _setScannerState(
          tone: BiopayScannerTone.blocked,
          statusLabel: 'One person only',
          helperText:
              'BioPay needs a single face in frame before it can continue.',
        );
        break;
      case BiopayFaceGuidance.tooDark:
        _setScannerState(
          tone: BiopayScannerTone.blocked,
          statusLabel: 'Move to better light',
          helperText:
              'The camera image is too dark for a stable BioPay capture.',
        );
        break;
      case BiopayFaceGuidance.tooBright:
        _setScannerState(
          tone: BiopayScannerTone.blocked,
          statusLabel: 'Reduce glare',
          helperText:
              'Turn away from direct sunlight or strong overhead glare.',
        );
        break;
      case BiopayFaceGuidance.tooFar:
        _setScannerState(
          tone: BiopayScannerTone.blocked,
          statusLabel: 'Move closer',
          helperText:
              'The face is too small in frame for a reliable BioPay capture.',
        );
        break;
      case BiopayFaceGuidance.headTurned:
        _setScannerState(
          tone: BiopayScannerTone.blocked,
          statusLabel: 'Look straight at the camera',
          helperText:
              'BioPay needs a forward-facing scan before it can proceed.',
        );
        break;
      case BiopayFaceGuidance.eyesClosed:
        _setScannerState(
          tone: BiopayScannerTone.blocked,
          statusLabel: 'Please open your eyes',
          helperText:
              'BioPay needs a clearer face frame before it can continue.',
        );
        break;
      case BiopayFaceGuidance.stable:
        _setScannerState(
          tone: BiopayScannerTone.ready,
          statusLabel: isEnroll
              ? 'Stable face locked'
              : 'Face locked. Matching...',
          helperText: isEnroll
              ? 'BioPay is collecting enrollment frame ${(_capturedEnrollmentFrames + 1).clamp(1, 5)} of 5.'
              : 'BioPay is generating an embedding and checking Supabase for a match.',
        );
        break;
      case BiopayFaceGuidance.searching:
        _setScannerState(
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

  Future<void> _handleEnrollmentEmbedding(Float32List embedding) async {
    final draft = widget.enrollmentDraft;
    if (draft == null) {
      _setScannerState(
        tone: BiopayScannerTone.error,
        statusLabel: 'Enrollment data missing',
        helperText:
            'BioPay did not receive the enrollment route payload. Go back and start registration again.',
      );
      return;
    }

    if (_enrollmentEmbeddings.length < 5) {
      final now = DateTime.now();
      if (_lastEnrollmentCaptureAt != null &&
          now.difference(_lastEnrollmentCaptureAt!) <
              const Duration(milliseconds: 500)) {
        return;
      }

      _lastEnrollmentCaptureAt = now;
      _enrollmentEmbeddings.add(embedding);
      _capturedEnrollmentFrames = _enrollmentEmbeddings.length;

      // Haptic feedback on each capture
      HapticFeedback.mediumImpact();

      if (_capturedEnrollmentFrames < 5) {
        _setScannerState(
          tone: BiopayScannerTone.ready,
          statusLabel: 'Captured $_capturedEnrollmentFrames of 5',
          helperText:
              'Keep your face steady. BioPay averages five captures for a more stable enrollment vector.',
        );
        setState(() {});
        return;
      }
    }

    _isSubmitting = true;
    _setScannerState(
      tone: BiopayScannerTone.ready,
      statusLabel: 'Finalizing enrollment',
      helperText:
          'BioPay is averaging the face embeddings and storing the profile in Supabase.',
    );

    try {
      final averaged = _embeddingService.averageEmbeddings(
        _enrollmentEmbeddings.take(5).toList(growable: false),
      );
      final authResult = await ref
          .read(biopayAuthGateServiceProvider)
          .authorize(BiopayAuthAction.enrollment);
      if (!mounted) {
        return;
      }
      if (!authResult.isAuthorized) {
        _setScannerState(
          tone: BiopayScannerTone.blocked,
          statusLabel: 'Identity confirmation required',
          helperText: authResult.message,
        );
        CoolToast.error(context, authResult.message);
        return;
      }

      final profile = await ref
          .read(biopayRepositoryProvider)
          .enroll(
            draft: draft,
            embedding: averaged.toList(growable: false),
            liveness: _livenessService.submissionMetadata,
          );
      ref.invalidate(biopayProfileProvider);
      if (!mounted) {
        return;
      }
      CoolToast.success(context, 'BioPay enrolled for ${profile.displayName}');
      context.go(AppRoutes.biopayHome);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _setScannerState(
        tone: BiopayScannerTone.error,
        statusLabel: 'Enrollment failed',
        helperText: error.toString(),
      );
      CoolToast.error(context, error.toString());
    } finally {
      _isSubmitting = false;
    }
  }

  Future<void> _handleMatchEmbedding(Float32List embedding) async {
    final now = DateTime.now();
    if (_lastMatchAttemptAt != null &&
        now.difference(_lastMatchAttemptAt!) <
            const Duration(milliseconds: 900)) {
      return;
    }
    _lastMatchAttemptAt = now;
    _isSubmitting = true;

    final embeddingList = embedding.toList(growable: false);
    final matchThreshold =
        ref.read(biopayMatchThresholdProvider).valueOrNull ?? 0.72;

    try {
      _setScannerState(
        tone: BiopayScannerTone.ready,
        statusLabel: 'Matching...',
        helperText:
            'BioPay is sending the face embedding to Supabase for a nearest-profile match.',
      );

      final result = await ref
          .read(biopayRepositoryProvider)
          .matchEmbedding(
            embeddingList,
            liveness: _livenessService.submissionMetadata,
          );

      if (!mounted) {
        return;
      }

      if (!result.match ||
          result.profile == null ||
          result.score < matchThreshold) {
        _setScannerState(
          tone: BiopayScannerTone.error,
          statusLabel: 'No confident match',
          helperText:
              'Keep the payee in frame and try again. BioPay did not clear the match threshold.',
        );
        return;
      }

      _setScannerState(
        tone: BiopayScannerTone.ready,
        statusLabel: 'Match confirmed',
        helperText: 'Preparing secure dialer for handoff...',
      );

      final intent = await ref
          .read(biopayRepositoryProvider)
          .createPaymentIntent(
            profilePublicId: result.profile!.publicId,
            matchScore: result.score,
          );

      if (!mounted) {
        return;
      }

      if (intent.isExpired) {
        _setScannerState(
          tone: BiopayScannerTone.error,
          statusLabel: 'Intent expired',
          helperText: 'The payment intent expired. Please try scanning again.',
        );
        return;
      }

      final launched = await ref
          .read(biopayDialerServiceProvider)
          .dialIntent(intent);

      if (!mounted) {
        return;
      }

      if (!launched) {
        _setScannerState(
          tone: BiopayScannerTone.error,
          statusLabel: 'Dialer failed',
          helperText: 'Could not open the MoMo dialer.',
        );
        return;
      }

      await ref
          .read(biopayRepositoryProvider)
          .markIntentDialed(intent.intentId);

      if (!mounted) {
        return;
      }

      CoolToast.success(
        context,
        'MoMo dialer opened for ${result.profile!.displayName}',
      );
      context.go(AppRoutes.biopayHome);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _setScannerState(
        tone: BiopayScannerTone.error,
        statusLabel: 'Match failed',
        helperText: error.toString(),
      );
      CoolToast.error(context, error.toString());
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _setScannerState({
    required BiopayScannerTone tone,
    required String statusLabel,
    required String helperText,
  }) {
    if (!mounted) {
      return;
    }
    final needsUpdate =
        _tone != tone ||
        _statusLabel != statusLabel ||
        _helperText != helperText;
    if (!needsUpdate) {
      return;
    }
    setState(() {
      _tone = tone;
      _statusLabel = statusLabel;
      _helperText = helperText;
    });
  }

  BiopayScannerTone _scannerToneForLiveness(BiopayLivenessFeedbackLevel level) {
    return switch (level) {
      BiopayLivenessFeedbackLevel.searching => BiopayScannerTone.searching,
      BiopayLivenessFeedbackLevel.ready => BiopayScannerTone.ready,
      BiopayLivenessFeedbackLevel.blocked => BiopayScannerTone.blocked,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authProvider);
    final enabled = ref.watch(
      featureFlagsStateProvider.select(
        (flags) =>
            flags.isBiopayEnabled(isAdmin: authState.user?.isAdmin ?? false),
      ),
    );
    final isEnroll = widget.mode == BiopayScanMode.enroll;
    final snapshot = _cameraSnapshot;
    final isCameraReady =
        snapshot?.isReady == true &&
        _controller != null &&
        _controller!.value.isInitialized &&
        !_isInitializingCamera;

    final tone = _cameraError != null
        ? BiopayScannerTone.error
        : isCameraReady
        ? _tone
        : (snapshot?.kind == AppAccessStateKind.blockedInSystem ||
                  snapshot?.kind == AppAccessStateKind.disabledInApp
              ? BiopayScannerTone.blocked
              : BiopayScannerTone.searching);

    final statusLabel = _cameraError != null
        ? 'Camera unavailable'
        : isCameraReady
        ? _statusLabel
        : (isEnroll
              ? 'Camera access needed for enrollment'
              : 'Camera access needed for scanning');

    final helperText = _cameraError != null
        ? 'BioPay could not start the secure camera shell yet. Check app access and device camera state.'
        : isCameraReady
        ? _helperText
        : 'Enable camera access to continue. BioPay uses the existing Cool app access controls.';

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _closeScanner();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          leading: IconButton(
            onPressed: _closeScanner,
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(
            isEnroll ? 'Face Capture' : 'Scan to Pay',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: BiopayScannerShell(
                controller: _controller,
                isCameraReady: isCameraReady,
                statusLabel: statusLabel,
                helperText: helperText,
                tone: tone,
                sampleCount: _capturedEnrollmentFrames,
                totalSamples: 5,
                isEnrollMode: isEnroll,
                footer: _buildScannerFooter(
                  context,
                  enabled: enabled,
                  isCameraReady: isCameraReady,
                ),
              ),
            ),
            if (_isInitializingCamera)
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: const BorderRadius.all(
                      Radius.circular(CoolRadii.md),
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Preparing secure camera...',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget? _buildScannerFooter(
    BuildContext context, {
    required bool enabled,
    required bool isCameraReady,
  }) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final errorMessage = _cameraError ?? _pipelineError;

    if (!enabled) {
      return CoolCard(
        backgroundColor: Colors.black.withValues(alpha: 0.66),
        borderColor: Colors.white.withValues(alpha: 0.12),
        useGradient: false,
        child: Text(
          'BioPay unavailable',
          style: theme.textTheme.labelLarge?.copyWith(
            color: colors.warning,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    if (!isCameraReady) {
      return CoolCard(
        backgroundColor: Colors.black.withValues(alpha: 0.66),
        borderColor: Colors.white.withValues(alpha: 0.12),
        useGradient: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CoolButton(label: 'Enable Camera', onTap: _requestCameraAccess),
            SizedBox(height: space.x2),
            CoolButton(
              label: 'Manage Access',
              variant: CoolButtonVariant.secondary,
              onTap: () => ProfileAppAccessSheet.show(context),
            ),
            if (errorMessage != null) ...[
              SizedBox(height: space.x3),
              Text(
                errorMessage,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (errorMessage != null) {
      return CoolCard(
        backgroundColor: Colors.black.withValues(alpha: 0.66),
        borderColor: Colors.white.withValues(alpha: 0.12),
        useGradient: false,
        child: Text(
          errorMessage,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.danger,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    // Enrollment sample dots are now rendered inside BiopayScannerShell.
    // No separate footer needed for enrollment progress.

    return null;
  }
}
