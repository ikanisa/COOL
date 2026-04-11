import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../momo/services/nfc_hce_service.dart';
import '../widgets/biopay_surface.dart';

/// Full-screen "Tap to Pay" waiting screen shown after NFC is activated.
///
/// Displays a large contactless icon with a pulsing animation and a
/// "Cancel Payment" button. Shown after the NFC HCE service starts
/// broadcasting the payment request — the user taps their phone on the
/// merchant's NFC reader to complete the payment.
class BiopayNfcTapScreen extends ConsumerStatefulWidget {
  const BiopayNfcTapScreen({super.key});

  @override
  ConsumerState<BiopayNfcTapScreen> createState() => _BiopayNfcTapScreenState();
}

class _BiopayNfcTapScreenState extends ConsumerState<BiopayNfcTapScreen>
    with SingleTickerProviderStateMixin {
  final _nfcHceService = NfcHceService.instance;
  late final AnimationController _pulseController;
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return CoolScreenBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CoolSpace.x4,
                  CoolSpace.x2,
                  CoolSpace.x4,
                  0,
                ),
                child: BiopayTopBar(
                  title: 'NFC Payment',
                  onBack: () => _cancel(context),
                ),
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Pulsing NFC icon ──
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final scale = 1.0 + (_pulseController.value * 0.06);
                          final glowOpacity =
                              0.08 + (_pulseController.value * 0.14);
                          return Transform.scale(
                            scale: scale,
                            child: Container(
                              width: 200,
                              height: 200,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: colors.glassSurface,
                                border: Border.all(
                                  color: colors.accent.withValues(
                                    alpha: 0.3 + (_pulseController.value * 0.2),
                                  ),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: colors.accent.withValues(
                                      alpha: glowOpacity,
                                    ),
                                    blurRadius: 48,
                                    spreadRadius: 8,
                                  ),
                                  ...CoolShadows.glass(strength: 0.32),
                                ],
                              ),
                              child: Icon(
                                Icons.contactless_rounded,
                                size: 80,
                                color: colors.accent,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: CoolSpace.x8),
                      Text(
                        'Tap to Pay',
                        style: context.coolText.display(
                          Theme.of(context).textTheme.displaySmall,
                          color: colors.primaryText,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.2,
                        ),
                      ),
                      const SizedBox(height: CoolSpace.x3),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: CoolSpace.x6,
                        ),
                        child: Text(
                          'Hold your phone near the NFC reader',
                          textAlign: TextAlign.center,
                          style: context.coolText.manrope(
                            Theme.of(context).textTheme.bodyLarge,
                            color: colors.secondaryText,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // ── Cancel button ──
              Padding(
                padding: EdgeInsets.fromLTRB(
                  CoolSpace.x6,
                  0,
                  CoolSpace.x6,
                  CoolSpace.x6 + MediaQuery.viewPaddingOf(context).bottom,
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(CoolRadii.pill),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: colors.glassSurface,
                        borderRadius: BorderRadius.circular(CoolRadii.pill),
                        border: Border.all(color: colors.borderStrong),
                        boxShadow: CoolShadows.glass(strength: 0.24),
                      ),
                      child: InkWell(
                        onTap: _isCancelling ? null : () => _cancel(context),
                        borderRadius: BorderRadius.circular(CoolRadii.pill),
                        child: Center(
                          child: _isCancelling
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      colors.secondaryText,
                                    ),
                                  ),
                                )
                              : Text(
                                  'Cancel Payment',
                                  style: context.coolText.headline(
                                    Theme.of(context).textTheme.titleMedium,
                                    color: colors.secondaryText,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _cancel(BuildContext context) async {
    if (_isCancelling) return;
    setState(() => _isCancelling = true);

    try {
      await _nfcHceService.stopPaymentRequest();
    } catch (_) {
      // Best-effort stop
    }

    if (!context.mounted) return;

    final nav = GoRouter.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.go(AppRoutes.biopayNfc);
    }
  }
}
