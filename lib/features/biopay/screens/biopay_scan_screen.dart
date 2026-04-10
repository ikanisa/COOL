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
import '../../../core/utils/user_error.dart';
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
import '../widgets/biopay_payee_confirmation_sheet.dart';
import '../widgets/biopay_scanner_shell.dart';

part 'biopay_scan_screen_footer.dart';
part 'biopay_scan_screen_processing.dart';

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
  bool _cameraInitTraceStarted = false;
  bool _pipelineWarmTraceStarted = false;
  bool _startupTraceCompleted = false;
  bool _firstFrameRecorded = false;

  @override
  void initState() {
    super.initState();
    ref.read(performanceServiceProvider).startTrace('biopay_scan_startup');
    _livenessService = BiopayLivenessService(
      mode: widget.mode == BiopayScanMode.enroll
          ? BiopayLivenessMode.enrollment
          : BiopayLivenessMode.payment,
    );
    unawaited(_loadCameraState());
  }

  @override
  void dispose() {
    _finishStartupTrace(phase: 'dispose');
    _embeddingService.dispose();
    unawaited(_faceDetectionService.close());
    final controller = _controller;
    _controller = null;
    controller?.dispose();
    super.dispose();
  }

  Future<void> _stopTrace(
    String name, {
    Map<String, int>? metrics,
    Map<String, String>? attributes,
  }) {
    return ref
        .read(performanceServiceProvider)
        .stopTrace(name, metrics: metrics, attributes: attributes);
  }

  void _finishStartupTrace({required String phase, String? error}) {
    if (_startupTraceCompleted) {
      return;
    }
    _startupTraceCompleted = true;
    unawaited(
      _stopTrace(
        'biopay_scan_startup',
        attributes: <String, String>{
          'mode': widget.mode.name,
          'phase': phase,
          if (error != null && error.isNotEmpty) 'error': error,
        },
      ),
    );
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
      if (!_cameraInitTraceStarted) {
        _cameraInitTraceStarted = true;
        ref
            .read(performanceServiceProvider)
            .startTrace('biopay_camera_initialize');
      }
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
      unawaited(
        _stopTrace(
          'biopay_camera_initialize',
          attributes: <String, String>{
            'mode': widget.mode.name,
            'lens_direction': camera.lensDirection.name,
          },
        ),
      );
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
      unawaited(
        _stopTrace(
          'biopay_camera_initialize',
          attributes: <String, String>{
            'mode': widget.mode.name,
            'status': 'error',
          },
        ),
      );
      _finishStartupTrace(phase: 'camera_error', error: error.toString());
    }
  }

  Future<void> _warmPipeline() async {
    if (!_pipelineWarmTraceStarted) {
      _pipelineWarmTraceStarted = true;
      ref
          .read(performanceServiceProvider)
          .startTrace('biopay_embedding_warmup');
    }
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
    unawaited(
      _stopTrace(
        'biopay_embedding_warmup',
        attributes: <String, String>{
          'mode': widget.mode.name,
          'ready': ready ? 'true' : 'false',
          if (!ready && _embeddingService.initializationError != null)
            'error': _embeddingService.initializationError!,
        },
      ),
    );
    if (!ready) {
      _finishStartupTrace(
        phase: 'pipeline_error',
        error: _embeddingService.initializationError,
      );
    }
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
    if (!_firstFrameRecorded) {
      _firstFrameRecorded = true;
      _finishStartupTrace(phase: 'first_frame');
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

  void _updateScannerState(VoidCallback updates) {
    if (!mounted) {
      return;
    }
    setState(updates);
  }

  Future<void> _processFrame(CameraImage frame) =>
      _processBiopayFrame(this, frame);

  void _applyAnalysisFeedback(
    BiopayFaceFrameAnalysis analysis,
    int stableFramesRequired,
  ) => _applyBiopayAnalysisFeedback(this, analysis, stableFramesRequired);

  Future<void> _handleEnrollmentEmbedding(Float32List embedding) =>
      _handleBiopayEnrollmentEmbedding(this, embedding);

  Future<void> _handleMatchEmbedding(Float32List embedding) =>
      _handleBiopayMatchEmbedding(this, embedding);

  void _setScannerState({
    required BiopayScannerTone tone,
    required String statusLabel,
    required String helperText,
  }) => _setBiopayScannerState(
    this,
    tone: tone,
    statusLabel: statusLabel,
    helperText: helperText,
  );

  BiopayScannerTone _scannerToneForLiveness(
    BiopayLivenessFeedbackLevel level,
  ) => _scannerToneForBiopayLiveness(level);

  Widget? _buildScannerFooter(
    BuildContext context, {
    required bool enabled,
    required bool isCameraReady,
  }) => _buildBiopayScannerFooter(
    this,
    context,
    enabled: enabled,
    isCameraReady: isCameraReady,
  );

  @override
  Widget build(BuildContext context) {
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

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _closeScanner();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Only show the scanner shell (oval, dots, camera preview)
            // when the camera is ready or camera access is needed.
            // During initial loading, show a clean black screen.
            if (isCameraReady || !_isInitializingCamera)
              Positioned.fill(
                child: BiopayScannerShell(
                  controller: _controller,
                  isCameraReady: isCameraReady,
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

            // Clean centered loading state during camera initialization
            if (_isInitializingCamera)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white54,
                            ),
                          ),
                        ),
                        SizedBox(height: 20),
                        Text(
                          'Preparing camera…',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Back button — always visible
            Positioned(
              top: MediaQuery.viewPaddingOf(context).top + CoolSpace.x4,
              left: CoolSpace.x4,
              child: Material(
                color: Colors.black.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  onTap: _closeScanner,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
