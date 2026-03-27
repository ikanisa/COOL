import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/rs_colors.dart';
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
  String _helperTitle = 'Hold phones back-to-back';
  String _helperDesc =
      'Keep both devices close until the transfer is confirmed.';
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
      _helperTitle = 'Hold phones back-to-back';
      _helperDesc = 'Keep both devices close until the transfer is confirmed.';
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
          title: 'Device unsupported',
          desc:
              'Your device does not support NFC or it is turned off in settings.',
        );
        return;
      }

      final result = await NfcService.readTag();
      if (!mounted) return;

      if (!result.hasPaymentData) {
        _handleError(
          statusText: 'INVALID TAG',
          title: 'No payment data found',
          desc:
              'The scanned NFC tag does not contain a valid BioPay or MoMo payload.',
        );
        return;
      }

      setState(() {
        _statusText = 'PROCESSING PAYMENT...';
        _helperTitle = 'Payload received';
        _helperDesc = 'Preparing the secure dialer for handoff...';
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
        title: 'Connection lost',
        desc:
            'Could not read the NFC tag. Make sure the devices stay in contact.',
      );
    }
  }

  void _handleError({
    required String statusText,
    required String title,
    required String desc,
  }) {
    _pulseController.stop();
    setState(() {
      _isError = true;
      _isProcessing = false;
      _statusText = statusText;
      _helperTitle = title;
      _helperDesc = desc;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final topPad = MediaQuery.viewPaddingOf(context).top;
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom;

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
                            RsColors.rsGold.withValues(alpha: 0.25),
                            RsColors.rsGold.withValues(alpha: 0.08),
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
                              : RsColors.rsGold.withValues(alpha: 0.12),
                          border: Border.all(
                            color: _isError
                                ? colors.danger.withValues(alpha: 0.3)
                                : RsColors.rsGold.withValues(alpha: 0.3),
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
                          color: _isError ? colors.danger : RsColors.rsGold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Text(
                    'PHONE TO PHONE',
                    style: context.coolText.rayonCondensed(
                      Theme.of(context).textTheme.headlineMedium,
                      fontWeight: FontWeight.w900,
                      color: _isError ? colors.danger : RsColors.rsGold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _statusText,
                    style: context.coolText.mono(
                      Theme.of(context).textTheme.labelSmall,
                      fontWeight: FontWeight.w700,
                      color: _isError ? colors.danger : colors.secondaryText,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(CoolRadii.lg),
                      border: Border.all(
                        color: _isError
                            ? colors.danger.withValues(alpha: 0.15)
                            : RsColors.rsGold.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _helperTitle,
                          textAlign: TextAlign.center,
                          style: context.coolText.mono(
                            Theme.of(context).textTheme.bodySmall,
                            fontWeight: FontWeight.w600,
                            color: colors.primaryText,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _helperDesc,
                          textAlign: TextAlign.center,
                          style: context.coolText.mono(
                            Theme.of(context).textTheme.labelSmall,
                            fontWeight: FontWeight.w600,
                            color: colors.secondaryText,
                            height: 1.5,
                          ),
                        ),
                        if (_isError) ...[
                          const SizedBox(height: 16),
                          CoolButton(
                            label: 'Try Again',
                            onTap: _startNfcSession,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: bottomPad + 32,
              left: 32,
              right: 32,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: RsColors.rsGold.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(CoolRadii.lg),
                  border: Border.all(
                    color: RsColors.rsGold.withValues(alpha: 0.20),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.contactless_outlined,
                      color: RsColors.rsGoldLight,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _isProcessing ? 'HANDING OFF...' : 'READY TO SCAN',
                      style: context.coolText.mono(
                        Theme.of(context).textTheme.labelSmall,
                        fontWeight: FontWeight.w800,
                        color: RsColors.rsGoldLight,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
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
                      style: context.coolText.rayonCondensed(
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
