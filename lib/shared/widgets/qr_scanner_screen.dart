import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import 'cool_button.dart';

/// Scan mode for the QR scanner.
enum QrScanMode { ticket, momo }

/// Full-screen QR scanner using `mobile_scanner`.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({
    required this.mode,
    this.ticketScanningEnabled = true,
    super.key,
  });

  final QrScanMode mode;
  final bool ticketScanningEnabled;

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _hasScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
      final response = await Supabase.instance.client.functions.invoke(
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
        message: 'Unable to verify this ticket right now.',
      );
    }
  }

  void _handleMomoScan(String qrData) {
    if (qrData.startsWith('momo://')) {
      final phone = qrData.replaceFirst('momo://', '');
      Navigator.pop(context, phone);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Not a valid MoMo QR code')));
      setState(() => _hasScanned = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == QrScanMode.ticket && !widget.ticketScanningEnabled) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: const Text('Scan Ticket'),
          backgroundColor: AppColors.bg,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 42,
                  color: AppColors.text2,
                ),
                const SizedBox(height: 16),
                Text(
                  'Ticket scanning is limited to authorized admins and partner gate staff.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 20),
                CoolButton(
                  label: 'Go Back',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          _ScannerOverlay(mode: widget.mode),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    GestureDetector(
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
                    const Spacer(),
                    Text(
                      widget.mode == QrScanMode.ticket
                          ? 'Scan Ticket'
                          : 'Scan MoMo QR',
                      style: GoogleFonts.dmSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
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
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    widget.mode == QrScanMode.ticket
                        ? 'Point camera at the signed ticket QR code to verify it with the backend'
                        : 'Scan a MoMo QR code to send money',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
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
  const _ScannerOverlay({required this.mode});

  final QrScanMode mode;

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        Colors.black.withValues(alpha: 0.5),
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
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ],
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
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            result.isValid ? '✅' : '❌',
            style: const TextStyle(fontSize: 48),
          ),
          const SizedBox(height: 12),
          Text(
            result.isValid ? 'Valid Ticket' : 'Invalid Ticket',
            style: GoogleFonts.dmSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: result.isValid ? AppColors.accent : AppColors.red,
            ),
          ),
          if (result.message != null) ...[
            const SizedBox(height: 6),
            Text(
              result.message!,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.text2),
            ),
          ],
          if (result.matchTitle != null ||
              result.seatType != null ||
              result.ticketId != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (result.matchTitle != null)
                    Text(
                      result.matchTitle!,
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  if (result.seatType != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      result.seatType!.toUpperCase(),
                      style: GoogleFonts.dmMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                  if (result.ticketId != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Ticket: ${result.ticketId}',
                      style: GoogleFonts.dmMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text3,
                      ),
                    ),
                  ],
                  if ((result.pointsAwarded ?? 0) > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '+${result.pointsAwarded} attendance points',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
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
