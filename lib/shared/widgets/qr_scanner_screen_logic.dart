part of 'qr_scanner_screen.dart';

extension _QrScannerScreenStateLogic on _QrScannerScreenState {
  Future<void> _loadCameraAccess() async {
    final snapshot = await _appAccessService.getSnapshot(
      AppAccessPermission.camera,
    );
    _applyState(() => _cameraAccess = snapshot);
  }

  Future<void> _loadTicketScannerAvailability() async {
    final loader =
        widget.ticketScannerAvailabilityLoader ??
        _fetchTicketScannerAvailability;
    final availability = await loader();
    _applyState(() => _ticketScannerAvailability = availability);
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
    _applyState(() => _cameraAccess = snapshot);
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
      CoolToast.error(context, 'Could not open camera settings');
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final rawValue = barcodes.first.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    _applyState(() => _hasScanned = true);

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
          _applyState(() => _hasScanned = false);
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
        _applyState(() => _hasScanned = false);
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
      _applyState(() => _hasScanned = false);
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
      _applyState(() => _hasScanned = false);
    }
  }

  Future<void> _closeScanner() async {
    if (_isClosing) {
      return;
    }
    _isClosing = true;
    try {
      await _controller.stop();
    } catch (_) {
      // Best effort only. The controller may already be stopping.
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
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
