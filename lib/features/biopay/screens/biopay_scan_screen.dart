import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';

import '../../../core/providers/app_access_provider.dart';
import '../../../core/providers/engagement_providers.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/services/app_access_service.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/user_error.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../admin/providers/admin_workspace_access_provider.dart';
import '../../auth/widgets/require_verified_user.dart';
import '../../profile/widgets/profile_app_access_sheet.dart';
import '../models/biopay_enrollment_draft.dart';
import '../models/biopay_face_frame_analysis.dart';
import '../providers/biopay_providers.dart';
import '../services/biopay_auth_gate_service.dart';
import '../services/biopay_camera_selection.dart';
import '../services/biopay_embedding_service.dart';
import '../services/biopay_face_alignment_service.dart';
import '../services/biopay_face_detection_service.dart';
import '../services/biopay_liveness_service.dart';
import '../widgets/biopay_payee_confirmation_sheet.dart';
import '../widgets/biopay_scanner_shell.dart';

part 'biopay_scan_screen_footer.dart';
part 'biopay_scan_screen_lifecycle.dart';
part 'biopay_scan_screen_processing.dart';
part 'biopay_scan_screen_view.dart';

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

  /// Singleton embedding service from the provider (lazy-loaded once, shared).
  BiopayEmbeddingService get _embeddingService =>
      ref.read(biopayEmbeddingProvider).requireValue;
  final List<Float32List> _enrollmentEmbeddings = <Float32List>[];
  late final BiopayLivenessService _livenessService;
  late CameraLensDirection _selectedLensDirection;

  List<CameraDescription> _availableCameras = const <CameraDescription>[];
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
  String _statusLabel = '';
  String _helperText = '';
  BiopayScannerTone _tone = BiopayScannerTone.searching;
  DateTime? _lastEnrollmentCaptureAt;
  DateTime? _lastMatchAttemptAt;
  DateTime? _lastFrameProcessedAt;
  bool _cameraInitTraceStarted = false;
  bool _pipelineWarmTraceStarted = false;
  bool _startupTraceCompleted = false;
  bool _firstFrameRecorded = false;
  bool _didCheckStartupAccess = false;

  @override
  void initState() {
    super.initState();
    ref.read(performanceServiceProvider).startTrace('biopay_scan_startup');
    _livenessService = BiopayLivenessService(
      mode: widget.mode == BiopayScanMode.enroll
          ? BiopayLivenessMode.enrollment
          : BiopayLivenessMode.payment,
    );
    _selectedLensDirection = biopayDefaultLensDirection(
      isEnrollMode: widget.mode == BiopayScanMode.enroll,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Initialize localized labels now that context is available.
      final l10n = context.l10n;
      _statusLabel = l10n.biopayScanPreparingCamera;
      _helperText = l10n.biopayScanLoadingServices;
      _prepareStartupAccess();
    });
  }

  @override
  void dispose() {
    _finishStartupTrace(phase: 'dispose');
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
      _availableCameras = cameras;

      final camera = selectBiopayCamera(
        cameras: cameras,
        preferredLensDirection: _selectedLensDirection,
      );
      _selectedLensDirection = camera.lensDirection;

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

  bool get _canSwitchEnrollmentCamera =>
      widget.mode == BiopayScanMode.enroll &&
      biopayEnrollmentSupportsCameraSwitch(_availableCameras);

  String get _cameraSwitchLabel =>
      _selectedLensDirection == CameraLensDirection.front ? 'Front' : 'Rear';

  String get _cameraSwitchTooltip =>
      _selectedLensDirection == CameraLensDirection.front
      ? 'Switch to rear camera'
      : 'Switch to front camera';

  Future<void> _switchEnrollmentCamera() async {
    if (!_canSwitchEnrollmentCamera || _isInitializingCamera || _isSubmitting) {
      return;
    }

    final nextLensDirection = biopayNextEnrollmentLensDirection(
      currentLensDirection: _selectedLensDirection,
      cameras: _availableCameras,
    );
    if (nextLensDirection == null) {
      return;
    }

    final l10n = context.l10n;
    setState(() {
      _selectedLensDirection = nextLensDirection;
      _isInitializingCamera = true;
      _isProcessingFrame = false;
      _isEmbeddingReady = false;
      _cameraError = null;
      _pipelineError = null;
      _tone = BiopayScannerTone.searching;
      _capturedEnrollmentFrames = 0;
      _enrollmentEmbeddings.clear();
      _lastEnrollmentCaptureAt = null;
      _lastFrameProcessedAt = null;
      _statusLabel = l10n.biopayScanPreparingCamera;
      _helperText = l10n.biopayScanLoadingServices;
    });

    _livenessService.reset();
    await _stopCameraPipeline();
    if (!mounted) {
      return;
    }
    await _initializeCamera();
  }

  void _retryPipeline() {
    setState(() {
      _pipelineError = null;
      _cameraError = null;
      _isEmbeddingReady = false;
      _pipelineWarmTraceStarted = false;
      final l10n = context.l10n;
      _statusLabel = l10n.biopayScanPreparingCamera;
      _helperText = l10n.biopayScanLoadingServices;
      _tone = BiopayScannerTone.searching;
    });
    _warmPipeline();
  }

  Future<void> _warmPipeline() async {
    if (!_pipelineWarmTraceStarted) {
      _pipelineWarmTraceStarted = true;
      ref
          .read(performanceServiceProvider)
          .startTrace('biopay_embedding_warmup');
    }

    // Trigger the singleton provider (lazy-load on first access).
    try {
      await ref.read(biopayEmbeddingProvider.future);
    } catch (_) {
      // Error will be surfaced through the provider's AsyncValue state below.
    }

    if (!mounted) {
      return;
    }

    final embeddingState = ref.read(biopayEmbeddingProvider);
    final ready = embeddingState.hasValue;
    final errorMessage = embeddingState.error?.toString();

    setState(() {
      _isEmbeddingReady = ready;
      _pipelineError = ready ? null : errorMessage;
      final l10n = context.l10n;
      _statusLabel = widget.mode == BiopayScanMode.enroll
          ? l10n.biopayScanAlignFace
          : l10n.biopayScanPointAtPayee;
      _helperText = widget.mode == BiopayScanMode.enroll
          ? l10n.biopayScanEnrollHelper
          : l10n.biopayScanPayHelper;
      _tone = BiopayScannerTone.searching;
    });
    unawaited(
      _stopTrace(
        'biopay_embedding_warmup',
        attributes: <String, String>{
          'mode': widget.mode.name,
          'ready': ready ? 'true' : 'false',
          if (!ready && errorMessage != null) 'error': errorMessage,
        },
      ),
    );
    if (!ready) {
      _finishStartupTrace(phase: 'pipeline_error', error: errorMessage);
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

  Future<void> _prepareStartupAccess() async {
    if (_didCheckStartupAccess || !mounted) {
      return;
    }
    _didCheckStartupAccess = true;

    if (widget.mode != BiopayScanMode.enroll) {
      unawaited(_loadCameraState());
      return;
    }

    final allowed = await requireVerifiedUser(
      context,
      ref,
      feature: WhatsAppProtectedFeature.faceRegistration,
    );
    if (!mounted) {
      return;
    }

    if (allowed) {
      unawaited(_loadCameraState());
      return;
    }

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

  @override
  Widget build(BuildContext context) => _buildScannerView(context);
}
