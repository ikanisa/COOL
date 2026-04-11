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
import 'cool_button.dart';
import 'cool_floating_header_sliver.dart';
import 'cool_screen_background.dart';
import 'cool_skeleton.dart';
import 'cool_toast.dart';
import '../../core/l10n/l10n.dart';

part 'qr_scanner_screen_logic.dart';
part 'qr_scanner_screen_widgets.dart';

/// Scan mode for the QR scanner.
enum QrScanMode { momo }

/// Full-screen QR scanner using `mobile_scanner`.
class QrScannerScreen extends ConsumerStatefulWidget {
  const QrScannerScreen({required this.mode, this.client, super.key});

  final QrScanMode mode;
  final SupabaseClient? client;

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
  AppAccessSnapshot? _cameraAccess;
  bool _refreshOnResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCameraAccess();
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
    final l10n = context.l10n;
    final colors = context.coolSemanticColors;
    final textTheme = Theme.of(context).textTheme;
    final space = context.coolSpace;

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
          title: l10n.cameraIsOff,
          message: l10n.enableCameraAccessToScan,
          actionLabel: l10n.enableCamera,
          onTap: _enableCameraAccess,
        ),
        AppAccessStateKind.blockedInSystem => (
          title: l10n.cameraIsBlocked,
          message: l10n.openSystemSettingsPeriod,
          actionLabel: l10n.openSettings,
          onTap: _openCameraSettings,
        ),
        AppAccessStateKind.notAvailable => (
          title: l10n.cameraUnavailable,
          message: l10n.deviceCannotScan,
          actionLabel: l10n.goBack,
          onTap: () => Navigator.of(context).pop(),
        ),
        _ => (
          title: l10n.allowCameraAccess,
          message: l10n.cameraAccessRequired,
          actionLabel: l10n.allowCamera,
          onTap: _enableCameraAccess,
        ),
      };

      final backTooltip = MaterialLocalizations.of(context).backButtonTooltip;
      return CoolScreenBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: CustomScrollView(
            slivers: [
              CoolFloatingHeaderSliver(
                automaticallyImplyLeading: false,
                leading: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  tooltip: backTooltip,
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    color: colors.primaryText,
                  ),
                ),
                title: Text(l10n.scanMomoQr),
              ),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
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
              ),
            ],
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
                IgnorePointer(child: _ScannerOverlay(scanWindow: scanWindow)),
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
                            label: l10n.closeScanner,
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
