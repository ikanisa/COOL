import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/momo_qr_payload.dart';
import '../../core/providers/app_access_provider.dart';
import '../../core/services/app_access_service.dart';
import '../../core/theme/cool_foundations.dart';
import '../../features/momo/providers/momo_service_provider.dart';
import 'cool_skeleton.dart';
import 'cool_button.dart';
import 'cool_toast.dart';
import '../../core/l10n/l10n.dart';

part 'qr_scanner_screen_logic.dart';
part 'qr_scanner_screen_widgets.dart';

/// Scan mode for the QR scanner.
enum QrScanMode { ticket, momo }

/// Full-screen QR scanner using `mobile_scanner`.
class QrScannerScreen extends ConsumerStatefulWidget {
  const QrScannerScreen({
    required this.mode,
    this.ticketScanningEnabled = true,
    this.client,
    this.ticketScannerAvailabilityLoader,
    super.key,
  });

  final QrScanMode mode;
  final SupabaseClient? client;
  final bool ticketScanningEnabled;
  final Future<TicketScannerAvailability> Function()?
  ticketScannerAvailabilityLoader;

  @override
  ConsumerState<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen>
    with WidgetsBindingObserver {
  late final AppAccessService _appAccessService = ref.read(
    appAccessServiceProvider,
  );
  final MobileScannerController _controller = MobileScannerController(
    autoZoom: true,
    cameraResolution: const Size(1920, 1080),
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    formats: const [BarcodeFormat.qrCode],
  );

  bool _hasScanned = false;
  bool _isClosing = false;
  String _momoStatusLabel = 'Align QR inside frame';
  AppAccessSnapshot? _cameraAccess;
  TicketScannerAvailability? _ticketScannerAvailability;
  bool _refreshOnResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCameraAccess();
    if (widget.mode == QrScanMode.ticket && widget.ticketScanningEnabled) {
      _loadTicketScannerAvailability();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_refreshOnResume) {
      return;
    }
    _refreshOnResume = false;
    _loadCameraAccess();
  }

  void _applyState(VoidCallback updates) {
    if (!mounted) {
      return;
    }
    setState(updates);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final textTheme = Theme.of(context).textTheme;
    final space = context.coolSpace;
    if (widget.mode == QrScanMode.ticket && !widget.ticketScanningEnabled) {
      return Scaffold(
        backgroundColor: colors.appBackground,
        appBar: AppBar(
          title: Text(context.l10n.scanTicket),
          backgroundColor: colors.appBackground,
        ),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(space.x6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 42,
                  color: colors.secondaryText,
                ),
                SizedBox(height: space.x4),
                Text(
                  'Ticket scanning is limited',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
                SizedBox(height: space.x5),
                CoolButton(
                  label: context.l10n.goBack,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (widget.mode == QrScanMode.ticket &&
        widget.ticketScanningEnabled &&
        _ticketScannerAvailability == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CoolSkeleton(width: 52, height: 52, borderRadius: 26),
        ),
      );
    }

    final scannerAvailability = _ticketScannerAvailability;
    if (widget.mode == QrScanMode.ticket &&
        scannerAvailability != null &&
        !scannerAvailability.isReady) {
      return Scaffold(
        backgroundColor: colors.appBackground,
        appBar: AppBar(
          title: Text(context.l10n.scanTicket),
          backgroundColor: colors.appBackground,
        ),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(space.x6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 42,
                  color: colors.warning,
                ),
                SizedBox(height: space.x4),
                Text(
                  'Ticket scanner unavailable',
                  textAlign: TextAlign.center,
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
                SizedBox(height: space.x2),
                Text(
                  scannerAvailability.message ??
                      'Ticket scanning is temporarily unavailable.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.secondaryText,
                    height: 1.45,
                  ),
                ),
                SizedBox(height: space.x5),
                CoolButton(
                  label: context.l10n.goBack,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final cameraAccess = _cameraAccess;
    if (cameraAccess == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CoolSkeleton(width: 52, height: 52, borderRadius: 26),
        ),
      );
    }

    if (!cameraAccess.isReady) {
      final gate = switch (cameraAccess.kind) {
        AppAccessStateKind.disabledInApp => (
          title: 'Camera is off',
          message: 'Enable camera access to scan.',
          actionLabel: 'Enable Camera',
          onTap: _enableCameraAccess,
        ),
        AppAccessStateKind.blockedInSystem => (
          title: 'Camera is blocked',
          message: 'Open system settings.',
          actionLabel: 'Open Settings',
          onTap: _openCameraSettings,
        ),
        AppAccessStateKind.notAvailable => (
          title: 'Camera unavailable',
          message: 'This device cannot scan.',
          actionLabel: 'Go Back',
          onTap: () => Navigator.of(context).pop(),
        ),
        _ => (
          title: 'Allow camera access',
          message: 'Camera access is required.',
          actionLabel: 'Allow Camera',
          onTap: _enableCameraAccess,
        ),
      };

      return Scaffold(
        backgroundColor: colors.appBackground,
        appBar: AppBar(
          title: Text(
            widget.mode == QrScanMode.ticket ? 'Scan Ticket' : 'Scan MoMo QR',
          ),
          backgroundColor: colors.appBackground,
        ),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(space.x6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.camera_alt_outlined,
                  size: 42,
                  color: colors.secondaryText,
                ),
                SizedBox(height: space.x4),
                Text(
                  gate.title,
                  textAlign: TextAlign.center,
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
                SizedBox(height: space.x2),
                Text(
                  gate.message,
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.secondaryText,
                    height: 1.45,
                  ),
                ),
                SizedBox(height: space.x5),
                CoolButton(label: gate.actionLabel, onTap: gate.onTap),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _closeScanner();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final scanWindow = _scanWindowForSize(constraints.biggest);
            return Stack(
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  tapToFocus: true,
                ),
                IgnorePointer(
                  child: _ScannerOverlay(
                    mode: widget.mode,
                    scanWindow: scanWindow,
                  ),
                ),
                if (widget.mode == QrScanMode.momo)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: scanWindow.bottom - 26,
                    child: Column(
                      children: [
                        _MomoScannerStatusPill(label: _momoStatusLabel),
                        const SizedBox(height: CoolSpace.x8),
                        Text(
                          'HOLD THE QR WITHIN THE FRAME',
                          textAlign: TextAlign.center,
                          style: textTheme.labelLarge?.copyWith(
                            color: Colors.white.withValues(alpha: 0.48),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 3.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: space.x4,
                        vertical: space.x2,
                      ),
                      child: Row(
                        children: [
                          Semantics(
                            button: true,
                            label: 'Close scanner',
                            child: Material(
                              color: Colors.black.withValues(alpha: 0.42),
                              borderRadius: BorderRadius.circular(18),
                              child: IconButton(
                                onPressed: _closeScanner,
                                tooltip: context.l10n.closeScanner,
                                icon: const Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                          if (widget.mode == QrScanMode.ticket) ...[
                            const Spacer(),
                            Text(
                              'Scan Ticket',
                              style: textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const Spacer(),
                            Semantics(
                              button: true,
                              label: 'Toggle flashlight',
                              child: Material(
                                color: Colors.black.withValues(alpha: 0.5),
                                shape: const CircleBorder(),
                                child: IconButton(
                                  onPressed: () => _controller.toggleTorch(),
                                  tooltip: 'Toggle flashlight',
                                  icon: ValueListenableBuilder(
                                    valueListenable: _controller,
                                    builder: (_, state, child) {
                                      return Icon(
                                        state.torchState == TorchState.on
                                            ? Icons.flash_on_rounded
                                            : Icons.flash_off_rounded,
                                        color: Colors.white,
                                        size: 22,
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
