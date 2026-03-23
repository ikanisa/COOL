import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/momo_qr_payload.dart';
import '../../core/providers/app_access_provider.dart';
import '../../core/providers/supabase_client_provider.dart';
import '../../core/services/app_access_service.dart';
import '../../core/theme/cool_foundations.dart';
import '../../features/momo/providers/momo_service_provider.dart';
import 'cool_skeleton.dart';
import 'cool_button.dart';
import 'cool_toast.dart';
import '../../core/l10n/l10n.dart';

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

  Future<void> _loadCameraAccess() async {
    final snapshot = await _appAccessService.getSnapshot(
      AppAccessPermission.camera,
    );
    if (!mounted) {
      return;
    }
    setState(() => _cameraAccess = snapshot);
  }

  Future<void> _loadTicketScannerAvailability() async {
    final loader =
        widget.ticketScannerAvailabilityLoader ??
        _fetchTicketScannerAvailability;
    final availability = await loader();
    if (!mounted) {
      return;
    }
    setState(() => _ticketScannerAvailability = availability);
  }

  Future<TicketScannerAvailability> _fetchTicketScannerAvailability() async {
    try {
      final SupabaseClient client =
          widget.client ?? ref.read(supabaseClientProvider);
      final response = await client.functions.invoke(
        'rs-scan-ticket',
        body: const <String, dynamic>{'action': 'health'},
      );
      final data = _asMap(response.data);
      final ready = data['ready'] == true;
      final message = data['message']?.toString();
      if (ready && response.status < 400) {
        return TicketScannerAvailability(isReady: true, message: message);
      }
      return TicketScannerAvailability(
        isReady: false,
        message:
            message ??
            'Ticket scanner is temporarily unavailable. Try again later.',
      );
    } catch (_) {
      return const TicketScannerAvailability(
        isReady: false,
        message: 'Ticket scanner is temporarily unavailable. Try again later.',
      );
    }
  }

  Future<void> _enableCameraAccess() async {
    final snapshot = await _appAccessService.enableAndRequest(
      AppAccessPermission.camera,
    );
    if (!mounted) {
      return;
    }
    setState(() => _cameraAccess = snapshot);
  }

  Future<void> _openCameraSettings() async {
    _refreshOnResume = true;
    final opened = await _appAccessService.openSystemSettings(
      AppAccessPermission.camera,
    );
    if (!mounted) {
      return;
    }
    if (!opened) {
      _refreshOnResume = false;
    }
    if (!opened) {
      CoolToast.error(context, 'Could not open camera settings');
      return;
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final rawValue = barcodes.first.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    setState(() => _hasScanned = true);

    if (widget.mode == QrScanMode.ticket) {
      _handleTicketScan(rawValue);
    } else {
      _handleMomoScan(rawValue);
    }
  }

  Future<void> _handleTicketScan(String qrData) async {
    final result = await _verifyTicketWithBackend(qrData);
    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (_) => _TicketResultSheet(
        result: result,
        onDismiss: () {
          Navigator.pop(context);
          setState(() => _hasScanned = false);
        },
      ),
    );
  }

  Future<_TicketScanResult> _verifyTicketWithBackend(String qrData) async {
    try {
      final SupabaseClient client =
          widget.client ?? ref.read(supabaseClientProvider);
      final response = await client.functions.invoke(
        'rs-scan-ticket',
        body: <String, dynamic>{'qrData': qrData},
      );
      final data = _asMap(response.data);

      return _TicketScanResult(
        isValid: (data['status']?.toString() ?? '') == 'ok',
        status: data['status']?.toString() ?? 'invalid',
        message: data['message']?.toString(),
        ticketId: data['ticketId']?.toString(),
        matchTitle: data['matchTitle']?.toString(),
        seatType: data['seatType']?.toString(),
        pointsAwarded: data['pointsAwarded'] is num
            ? (data['pointsAwarded'] as num).toInt()
            : null,
      );
    } catch (_) {
      return const _TicketScanResult(
        isValid: false,
        status: 'error',
        message: 'verify this ticket failed',
      );
    }
  }

  Future<void> _handleMomoScan(String qrData) async {
    final trimmed = qrData.trim();
    final dialerUri = _tryParseDialerUri(trimmed);

    if (dialerUri != null) {
      await _launchDialerUri(dialerUri);
      return;
    }

    final payload = MomoQrPayload.tryParse(trimmed);
    if (payload == null) {
      if (mounted) {
        CoolToast.error(context, 'Not a valid MoMo QR code');
        setState(() => _hasScanned = false);
      }
      return;
    }

    if (payload.canLaunchImmediately) {
      await _launchPayloadPayment(payload);
      return;
    }

    if (!mounted) {
      return;
    }
    Navigator.pop(context, payload);
  }

  Uri? _tryParseDialerUri(String rawValue) {
    if (!rawValue.toLowerCase().startsWith('tel:')) {
      return null;
    }

    final uri = Uri.tryParse(rawValue);
    if (uri == null || uri.scheme != 'tel') {
      return null;
    }
    return uri;
  }

  Future<void> _launchDialerUri(Uri dialerUri) async {
    final launched = await launchUrl(
      dialerUri,
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) {
      return;
    }

    if (!launched) {
      CoolToast.error(context, 'Could not open the USSD dialer.');
      setState(() => _hasScanned = false);
      return;
    }

    CoolToast.success(context, 'Launching MoMo payment USSD.');
    Navigator.pop(context);
  }

  Future<void> _launchPayloadPayment(MomoQrPayload payload) async {
    try {
      await ref
          .read(momoServiceProvider)
          .initiatePayment(
            recipientMomo: payload.recipientValue,
            amount: payload.amount!,
            reference:
                payload.reference ??
                'QR-${DateTime.now().millisecondsSinceEpoch}',
            recipientType: payload.recipientType,
            countryCode: payload.countryCode,
          );
      if (!mounted) {
        return;
      }
      CoolToast.success(context, 'Launching MoMo payment USSD.');
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) {
        return;
      }
      CoolToast.error(context, 'Could not launch the MoMo payment flow.');
      setState(() => _hasScanned = false);
    }
  }

  Rect _scanWindowForSize(Size size) {
    final shortestSide = size.shortestSide;
    final edgeLength = widget.mode == QrScanMode.ticket
        ? shortestSide.clamp(250.0, 320.0)
        : shortestSide.clamp(280.0, 360.0);
    return Rect.fromCenter(
      center: size.center(Offset.zero),
      width: edgeLength,
      height: edgeLength,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final textTheme = Theme.of(context).textTheme;
    final space = context.coolSpace;
    final radii = context.coolRadii;
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
          title: context.l10n.cameraIsOffIn,
          message: 'Enable camera access',
          actionLabel: 'Enable Camera',
          onTap: _enableCameraAccess,
        ),
        AppAccessStateKind.blockedInSystem => (
          title: 'Camera is blocked in',
          message: 'Open system settings',
          actionLabel: 'Open Settings',
          onTap: _openCameraSettings,
        ),
        AppAccessStateKind.notAvailable => (
          title: 'Camera not available',
          message: 'This device does not',
          actionLabel: 'Go Back',
          onTap: () => Navigator.of(context).pop(),
        ),
        _ => (
          title: 'Allow camera access',
          message: 'COOL needs camera access',
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

    return Scaffold(
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
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          widget.mode == QrScanMode.ticket
                              ? 'Scan Ticket'
                              : 'Scan MoMo QR',
                          style: textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        Semantics(
                          button: true,
                          label: 'Toggle flashlight',
                          child: GestureDetector(
                            onTap: () => _controller.toggleTorch(),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: ValueListenableBuilder(
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
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      space.x6,
                      0,
                      space.x6,
                      space.x6,
                    ),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: space.x4 + 2,
                        vertical: space.x3 + 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.66),
                        borderRadius: BorderRadius.circular(radii.sm),
                      ),
                      child: Text(
                        widget.mode == QrScanMode.ticket
                            ? 'Keep the signed ticket centered inside the frame until verification completes.'
                            : 'Center the QR inside the frame. Tap the viewfinder to focus, or turn on the torch if glare washes out the code.',
                        textAlign: TextAlign.center,
                        style: textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<Object?, Object?>) {
    return value.map((key, entry) => MapEntry('$key', entry));
  }
  if (value is Map<String, dynamic>) {
    return value;
  }
  return const <String, dynamic>{};
}

class TicketScannerAvailability {
  const TicketScannerAvailability({required this.isReady, this.message});

  final bool isReady;
  final String? message;
}

class _TicketScanResult {
  const _TicketScanResult({
    required this.isValid,
    required this.status,
    this.message,
    this.ticketId,
    this.matchTitle,
    this.seatType,
    this.pointsAwarded,
  });

  final bool isValid;
  final String status;
  final String? message;
  final String? ticketId;
  final String? matchTitle;
  final String? seatType;
  final int? pointsAwarded;
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay({required this.mode, required this.scanWindow});

  final QrScanMode mode;
  final Rect scanWindow;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final textTheme = Theme.of(context).textTheme;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final accentColor = mode == QrScanMode.ticket
        ? Colors.white
        : colors.accent;
    return Stack(
      children: [
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.black.withValues(alpha: 0.56),
            BlendMode.srcOut,
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    backgroundBlendMode: BlendMode.dstOut,
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: scanWindow,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(radii.lg),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned.fromRect(
          rect: scanWindow,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radii.lg),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.24),
                width: 1.4,
              ),
            ),
            child: Stack(
              children: [
                _CornerMarker(alignment: Alignment.topLeft, color: accentColor),
                _CornerMarker(
                  alignment: Alignment.topRight,
                  color: accentColor,
                ),
                _CornerMarker(
                  alignment: Alignment.bottomLeft,
                  color: accentColor,
                ),
                _CornerMarker(
                  alignment: Alignment.bottomRight,
                  color: accentColor,
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: scanWindow.top - 34,
          left: scanWindow.left,
          right: scanWindow.right,
          child: Center(
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: space.x3,
                vertical: space.x1 + 2,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(radii.pill),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: Text(
                mode == QrScanMode.ticket
                    ? 'Signed ticket only'
                    : 'Dialer-ready QR',
                style: textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CornerMarker extends StatelessWidget {
  const _CornerMarker({required this.alignment, required this.color});

  final Alignment alignment;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isTop = alignment.y < 0;
    final isLeft = alignment.x < 0;

    return Align(
      alignment: alignment,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.only(
            topLeft: isTop && isLeft ? const Radius.circular(22) : Radius.zero,
            topRight: isTop && !isLeft
                ? const Radius.circular(22)
                : Radius.zero,
            bottomLeft: !isTop && isLeft
                ? const Radius.circular(22)
                : Radius.zero,
            bottomRight: !isTop && !isLeft
                ? const Radius.circular(22)
                : Radius.zero,
          ),
          border: Border(
            top: isTop ? BorderSide(color: color, width: 4) : BorderSide.none,
            bottom: !isTop
                ? BorderSide(color: color, width: 4)
                : BorderSide.none,
            left: isLeft ? BorderSide(color: color, width: 4) : BorderSide.none,
            right: !isLeft
                ? BorderSide(color: color, width: 4)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _TicketResultSheet extends StatelessWidget {
  const _TicketResultSheet({required this.result, required this.onDismiss});

  final _TicketScanResult result;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final textTheme = Theme.of(context).textTheme;
    final text = context.coolText;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    return Container(
      decoration: BoxDecoration(
        color: colors.elevatedBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(radii.lg)),
      ),
      padding: EdgeInsets.fromLTRB(
        space.x5 + 2,
        space.x4,
        space.x5 + 2,
        space.x8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.borderStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(height: space.x5),
          Text(result.isValid ? '✅' : '❌', style: textTheme.displaySmall),
          SizedBox(height: space.x3),
          Text(
            result.isValid ? 'Valid Ticket' : 'Invalid Ticket',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: result.isValid ? colors.accent : colors.danger,
            ),
          ),
          if (result.message != null) ...[
            SizedBox(height: space.x1 + 2),
            Text(
              result.message!,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: colors.secondaryText),
            ),
          ],
          if (result.matchTitle != null ||
              result.seatType != null ||
              result.ticketId != null) ...[
            SizedBox(height: space.x4),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(space.x3 + 2),
              decoration: BoxDecoration(
                color: colors.inputSurface,
                borderRadius: BorderRadius.circular(radii.sm),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (result.matchTitle != null)
                    Text(
                      result.matchTitle!,
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.primaryText,
                      ),
                    ),
                  if (result.seatType != null) ...[
                    SizedBox(height: space.x1),
                    Text(
                      result.seatType!.toUpperCase(),
                      style: text.mono(
                        textTheme.labelSmall,
                        fontWeight: FontWeight.w700,
                        color: colors.accent,
                      ),
                    ),
                  ],
                  if (result.ticketId != null) ...[
                    SizedBox(height: space.x1),
                    Text(
                      'Ticket: ${result.ticketId}',
                      style: text.mono(
                        textTheme.labelSmall,
                        fontWeight: FontWeight.w600,
                        color: colors.tertiaryText,
                      ),
                    ),
                  ],
                  if ((result.pointsAwarded ?? 0) > 0) ...[
                    SizedBox(height: space.x1),
                    Text(
                      '+${result.pointsAwarded} attendance points',
                      style: textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.accent,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          SizedBox(height: space.x5),
          CoolButton(
            label: 'Scan Another',
            variant: CoolButtonVariant.secondary,
            onTap: onDismiss,
          ),
        ],
      ),
    );
  }
}