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
    return const TicketScannerAvailability(
      isReady: false,
      message:
          'Ticket scanning is no longer available in COOL. Use MoMo QR instead.',
    );
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

    _applyState(() {
      _hasScanned = true;
      if (widget.mode == QrScanMode.momo) {
        _momoStatusLabel = 'QR Detected';
      }
    });

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
    return const _TicketScanResult(
      isValid: false,
      status: 'unavailable',
      message: 'Ticket scanning is no longer available in COOL.',
    );
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
  });

  final bool isValid;
  final String status;
  final String? message;
}
