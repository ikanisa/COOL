import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/atmospheric_background.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../momo/providers/momo_service_provider.dart';
import '../../momo/services/nfc_service.dart';

/// Fullscreen NFC scan screen with gold accent and pulse animation.
///
/// Shows an animated NFC icon with status text while the device searches
/// for a nearby NFC-enabled phone. Reads COOL NDEF payloads and hands off
/// to the MoMo USSD dialer. Falls back to "not available" state
/// on devices without NFC capability.
class BiopayNfcScreen extends ConsumerStatefulWidget {
  const BiopayNfcScreen({super.key});

  @override
  ConsumerState<BiopayNfcScreen> createState() => _BiopayNfcScreenState();
}

class _BiopayNfcScreenState extends ConsumerState<BiopayNfcScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  String _statusText = 'SEARCHING FOR DEVICE...';
  String? _detailText;
  bool _isError = false;
  bool _isProcessing = false;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startNfcSession();
    });
  }

  @override
  void dispose() {
    unawaited(NfcService.cancelSession(reason: 'BioPay NFC scan closed'));
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _closeScreen() async {
    if (_isClosing) {
      return;
    }
    _isClosing = true;
    unawaited(NfcService.cancelSession(reason: 'BioPay NFC scan closed'));
    if (!mounted) {
      return;
    }
    context.go(AppRoutes.biopayHome);
  }

  Future<void> _startNfcSession() async {
    if (!mounted) return;
    setState(() {
      _statusText = 'SEARCHING FOR DEVICE...';
      _detailText = null;
      _isError = false;
      _isProcessing = false;
    });
    if (!_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }

    try {
      final status = await NfcService.checkAvailability();
      if (!mounted) return;

      if (status != NfcStatus.available) {
        _handleError(
          statusText: 'NFC NOT AVAILABLE',
          detailText: 'Turn on NFC or use another device.',
        );
        return;
      }

      final result = await NfcService.readTag();
      if (!mounted) return;

      if (!result.hasPaymentData) {
        _handleError(
          statusText: 'INVALID TAG',
          detailText: 'Use a valid BioPay or MoMo tap target.',
        );
        return;
      }

      setState(() {
        _statusText = 'HANDING OFF...';
        _detailText = null;
        _isProcessing = true;
      });

      await ref
          .read(momoServiceProvider)
          .initiatePayment(
            recipientMomo: result.recipientValue!,
            amount: int.tryParse(result.amount!) ?? 0,
            reference: 'NFC-${DateTime.now().millisecondsSinceEpoch}',
            recipientType: result.recipientType,
            countryCode: result.countryCode,
          );

      if (!mounted) return;
      CoolToast.success(context, 'Launching MoMo payment USSD.');
      if (context.canPop()) {
        context.pop();
      }
    } catch (e) {
      if (!mounted) return;
      _handleError(
        statusText: 'NFC READ FAILED',
        detailText: 'Keep both phones in contact and try again.',
      );
    }
  }

  void _handleError({required String statusText, String? detailText}) {
    _pulseController.stop();
    setState(() {
      _isError = true;
      _isProcessing = false;
      _statusText = statusText;
      _detailText = detailText;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final topPad = MediaQuery.viewPaddingOf(context).top;

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _closeScreen();
        }
      },
      child: Scaffold(
        backgroundColor: colors.appBackground,
        body: Stack(
          children: [
            const AtmosphericBackground(showGrid: true),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            colors.accentGold.withValues(alpha: 0.25),
                            colors.accentGold.withValues(alpha: 0.08),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isError
                              ? colors.danger.withValues(alpha: 0.12)
                              : colors.accentGold.withValues(alpha: 0.12),
                          border: Border.all(
                            color: _isError
                                ? colors.danger.withValues(alpha: 0.3)
                                : colors.accentGold.withValues(alpha: 0.3),
                            width: 2,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          _isError
                              ? Icons.error_outline_rounded
                              : _isProcessing
                              ? Icons.check_circle_outline_rounded
                              : Icons.nfc_rounded,
                          size: 42,
                          color: _isError ? colors.danger : colors.accentGold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Text(
                    _statusText,
                    style: context.coolText.mono(
                      Theme.of(context).textTheme.titleSmall,
                      fontWeight: FontWeight.w800,
                      color: _isError ? colors.danger : colors.secondaryText,
                      letterSpacing: 1.4,
                    ),
                  ),
                  if (_detailText != null) ...[
                    const SizedBox(height: 20),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 52),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(CoolRadii.lg),
                        border: Border.all(
                          color: _isError
                              ? colors.danger.withValues(alpha: 0.15)
                              : colors.accentGold.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Text(
                        _detailText!,
                        textAlign: TextAlign.center,
                        style: context.coolText.mono(
                          Theme.of(context).textTheme.labelSmall,
                          fontWeight: FontWeight.w600,
                          color: colors.secondaryText,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                  if (_isError) ...[
                    const SizedBox(height: 20),
                    CoolButton(label: 'Try Again', onTap: _startNfcSession),
                  ],
                ],
              ),
            ),
            Positioned(
              top: topPad + 12,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  Semantics(
                    button: true,
                    label: 'Close NFC scan',
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: const CircleBorder(),
                      child: IconButton(
                        onPressed: _closeScreen,
                        tooltip: 'Close NFC scan',
                        icon: Icon(
                          Icons.close_rounded,
                          color: colors.primaryText,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'NFC SCAN',
                      textAlign: TextAlign.center,
                      style: context.coolText.displayCondensed(
                        Theme.of(context).textTheme.titleLarge,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
