import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;

import '../../shared/repositories/collect_repository.dart';
import '../../shared/providers/collect_app_state.dart';
import '../../shared/widgets/collect_components.dart';
import '../status/native_permission_sheets.dart';
import 'group_link_screen.dart';

class GroupQrScannerScreen extends ConsumerStatefulWidget {
  const GroupQrScannerScreen({super.key});

  @override
  ConsumerState<GroupQrScannerScreen> createState() =>
      _GroupQrScannerScreenState();
}

class _GroupQrScannerScreenState extends ConsumerState<GroupQrScannerScreen>
    with WidgetsBindingObserver {
  static const _mobileEvidenceMode = bool.fromEnvironment(
    'COLLECT_MOBILE_EVIDENCE_MODE',
  );

  late final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
    autoZoom: true,
    autoStart: false,
  );
  bool _joining = false;
  bool _scanning = false;
  bool _starting = false;
  String? _error;
  Timer? _startTimeout;

  bool get _scannerAvailable => !kIsWeb && !_mobileEvidenceMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScanning());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _startTimeout?.cancel();
    _scanner.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_resumeScanningAfterSettings());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Scaffold(
      backgroundColor: CollectColors.publicBlack,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _ScannerViewport(
            controller: _scanner,
            joining: _joining,
            scanning: _scanning,
            starting: _starting,
            scannerAvailable: _scannerAvailable,
            evidenceMode: _mobileEvidenceMode,
            onDetect: _onDetect,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(CollectSpacing.x4),
              child: Row(
                children: [
                  _ScannerIconButton(
                    icon: Icons.close_rounded,
                    label: 'Close scanner',
                    onTap: () => context.go('/groups'),
                  ),
                  const Spacer(),
                  _ScannerIconButton(
                    icon: Icons.flashlight_on_rounded,
                    label: 'Torch',
                    onTap: _toggleTorch,
                  ),
                ],
              ),
            ),
          ),
          if (_error != null)
            Positioned(
              left: CollectSpacing.x4,
              right: CollectSpacing.x4,
              bottom: MediaQuery.paddingOf(context).bottom + CollectSpacing.x4,
              child: Material(
                color: colors.danger.withValues(alpha: 0.92),
                borderRadius: CollectRadius.panelBorder,
                child: Padding(
                  padding: const EdgeInsets.all(CollectSpacing.x3),
                  child: Text(
                    _error!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.surfaceReadable,
                      fontWeight: CollectTypography.weightBold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _startScanning() async {
    if (_starting || _scanning) return;
    if (!_scannerAvailable) {
      setState(() {
        _starting = false;
        _scanning = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _starting = true;
      _error = null;
    });
    _startTimeout?.cancel();
    try {
      final cameraPermission = await permissions.Permission.camera.request();
      if (!mounted) return;
      if (!cameraPermission.isGranted) {
        _startTimeout?.cancel();
        ref.read(cameraPermissionStatusProvider.notifier).state =
            CollectDevicePermissionStatus.denied;
        setState(() {
          _starting = false;
          _scanning = false;
          _error =
              'Camera permission is off. Allow access to scan a group QR code.';
        });
        await showCameraAccessSheet(
          context,
          onRetry: () => unawaited(_startScanning()),
        );
        return;
      }
      // This provider represents the OS permission decision, not camera
      // hardware availability. Keep the two states distinct so a granted
      // permission is not misreported as denied when a Simulator or device
      // camera cannot start.
      ref.read(cameraPermissionStatusProvider.notifier).state =
          CollectDevicePermissionStatus.granted;
      _startTimeout = Timer(const Duration(seconds: 8), () {
        if (!mounted || !_starting) return;
        setState(() {
          _starting = false;
          _scanning = false;
          _error =
              'Camera did not start. Check camera permission or open Collect on your phone.';
        });
      });
      await _scanner.start();
      if (!mounted) return;
      _startTimeout?.cancel();
      setState(() {
        _starting = false;
        _scanning = true;
        _error = null;
      });
    } on MobileScannerException catch (error) {
      if (!mounted) return;
      _startTimeout?.cancel();
      final permissionDenied =
          error.errorCode == MobileScannerErrorCode.permissionDenied;
      if (permissionDenied) {
        ref.read(cameraPermissionStatusProvider.notifier).state =
            CollectDevicePermissionStatus.denied;
      }
      setState(() {
        _starting = false;
        _scanning = false;
        _error = permissionDenied
            ? 'Camera permission is off. Allow access to scan a group QR code.'
            : _scannerErrorMessage(error);
      });
      if (permissionDenied && mounted) {
        await showCameraAccessSheet(
          context,
          onRetry: () => unawaited(_startScanning()),
        );
      }
    } catch (_) {
      if (!mounted) return;
      _startTimeout?.cancel();
      setState(() {
        _starting = false;
        _scanning = false;
        _error = 'Camera unavailable. Try again or use a group link.';
      });
    }
  }

  Future<void> _resumeScanningAfterSettings() async {
    if (!_scannerAvailable || _starting || _scanning) return;
    final cameraPermission = await permissions.Permission.camera.status;
    if (!mounted || !cameraPermission.isGranted || _starting || _scanning) {
      return;
    }
    ref.read(cameraPermissionStatusProvider.notifier).state =
        CollectDevicePermissionStatus.granted;
    await _startScanning();
  }

  Future<void> _toggleTorch() async {
    if (!_scannerAvailable) {
      setState(() => _error = 'Torch is available in the mobile app.');
      return;
    }
    try {
      await _scanner.toggleTorch();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Torch unavailable.');
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_joining || !_scanning) return;
    final value = _firstCaptureValue(capture);
    if (value != null) {
      _openValue(value);
      return;
    }
  }

  String? _firstCaptureValue(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  Future<void> _openValue(String value) async {
    final slug = collectGroupSlugFromInput(value);
    if (slug.isEmpty) {
      setState(() => _error = 'Use a Collect group QR code.');
      return;
    }
    setState(() {
      _joining = true;
      _error = null;
    });
    await _scanner.stop();
    try {
      final collection = await ref
          .read(collectRepositoryProvider.notifier)
          .joinGroupBySlug(slug);
      if (!mounted) return;
      context.go('/groups/${collection.id}');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _scanning = false;
        _error =
            'Could not open this group. Check the QR code or connection and try again.';
      });
    }
  }
}

class _ScannerViewport extends StatelessWidget {
  const _ScannerViewport({
    required this.controller,
    required this.joining,
    required this.scanning,
    required this.starting,
    required this.scannerAvailable,
    required this.evidenceMode,
    required this.onDetect,
  });

  final MobileScannerController controller;
  final bool joining;
  final bool scanning;
  final bool starting;
  final bool scannerAvailable;
  final bool evidenceMode;
  final void Function(BarcodeCapture capture) onDetect;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'QR scanner',
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: CollectColors.publicBlack),
          if (scannerAvailable) ...[
            MobileScanner(
              controller: controller,
              fit: BoxFit.cover,
              tapToFocus: true,
              onDetect: onDetect,
              errorBuilder: (context, error) =>
                  _ScannerUnavailable(error: _scannerErrorMessage(error)),
            ),
            const _ScannerScrim(),
            const _ScanGuide(),
          ] else
            _ScannerUnavailable(
              error: evidenceMode
                  ? 'Camera preview is disabled in fixture evidence mode.'
                  : 'QR scanning is available in the mobile app. Open Collect on your phone or use a group link.',
              showRecoveryAction: false,
            ),
          if (starting)
            ColoredBox(
              color: context.collectColors.cameraScrim,
              child: const Center(
                child: CircularProgressIndicator.adaptive(
                  backgroundColor: CollectColors.brandPaper,
                ),
              ),
            ),
          if (joining)
            ColoredBox(
              color: context.collectColors.cameraScrim,
              child: const Center(
                child: CircularProgressIndicator.adaptive(
                  backgroundColor: CollectColors.brandPaper,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _scannerErrorMessage(MobileScannerException error) {
  return switch (error.errorCode) {
    MobileScannerErrorCode.permissionDenied =>
      'Camera permission is off. Allow access to scan a group QR code.',
    MobileScannerErrorCode.unsupported =>
      'QR scanning is not supported on this device. Use a group link instead.',
    MobileScannerErrorCode.controllerInitializing =>
      'Camera is still starting. Wait a moment and try again.',
    _ => 'Camera unavailable. Try again or use a group link.',
  };
}

class _ScannerIconButton extends StatelessWidget {
  const _ScannerIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: CollectRadius.pillBorder,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.strongPanelSurface.withValues(alpha: 0.62),
              shape: BoxShape.circle,
              border: Border.all(
                color: colors.onImagePrimary.withValues(alpha: 0.16),
              ),
            ),
            child: SizedBox.square(
              dimension: CollectSpacing.iconTarget,
              child: Icon(icon, color: colors.onImagePrimary, size: 21),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScannerScrim extends StatelessWidget {
  const _ScannerScrim();

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CustomPaint(
      painter: _ScannerScrimPainter(
        scrim: CollectColors.publicBlack.withValues(alpha: 0.44),
        border: colors.actionColor,
      ),
    );
  }
}

class _ScanGuide extends StatelessWidget {
  const _ScanGuide();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _ScannerFramePainter(
          color: context.collectColors.actionColor,
          beamColor: context.collectColors.onImagePrimary,
        ),
      ),
    );
  }
}

class _ScannerScrimPainter extends CustomPainter {
  const _ScannerScrimPainter({required this.scrim, required this.border});

  final Color scrim;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final scanRect = _scanWindowRect(size);
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(30)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = scrim);
    canvas.drawRRect(
      RRect.fromRectAndRadius(scanRect, const Radius.circular(30)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = border.withValues(alpha: 0.22),
    );
  }

  @override
  bool shouldRepaint(covariant _ScannerScrimPainter oldDelegate) {
    return scrim != oldDelegate.scrim || border != oldDelegate.border;
  }
}

class _ScannerFramePainter extends CustomPainter {
  const _ScannerFramePainter({required this.color, required this.beamColor});

  final Color color;
  final Color beamColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = _scanWindowRect(size);
    final corner = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const length = 42.0;

    void drawCorner(Offset origin, double dx, double dy) {
      canvas
        ..drawLine(origin, origin.translate(dx * length, 0), corner)
        ..drawLine(origin, origin.translate(0, dy * length), corner);
    }

    drawCorner(rect.topLeft.translate(10, 10), 1, 1);
    drawCorner(rect.topRight.translate(-10, 10), -1, 1);
    drawCorner(rect.bottomLeft.translate(10, -10), 1, -1);
    drawCorner(rect.bottomRight.translate(-10, -10), -1, -1);

    final beamY = rect.top + rect.height * 0.54;
    final beam = Paint()
      ..color = beamColor.withValues(alpha: 0.78)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(rect.left + 26, beamY),
      Offset(rect.right - 26, beamY),
      beam,
    );
  }

  @override
  bool shouldRepaint(covariant _ScannerFramePainter oldDelegate) {
    return color != oldDelegate.color || beamColor != oldDelegate.beamColor;
  }
}

Rect _scanWindowRect(Size size) {
  final inset = size.width * 0.11;
  final windowSize = size.width - inset * 2;
  final top = (size.height - windowSize) * 0.50;
  return Rect.fromLTWH(inset, top, windowSize, windowSize);
}

class _ScannerUnavailable extends StatelessWidget {
  const _ScannerUnavailable({this.error, this.showRecoveryAction = true});

  final String? error;
  final bool showRecoveryAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return ColoredBox(
      color: colors.canvas,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(CollectSpacing.x4),
          child: CollectCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InfoSecurityBanner(
                  title: 'Camera unavailable',
                  message: error ?? 'Tap Scan to request camera access.',
                  tone: CollectStatusTone.warning,
                ),
                if (showRecoveryAction) ...[
                  CollectSpacing.gap16,
                  CollectButton(
                    label: 'Recover camera access',
                    icon: CollectIcons.qr,
                    onPressed: () => showCameraAccessSheet(
                      context,
                      onRetry: () => context.go('/groups/scan'),
                    ),
                    expand: true,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
