import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_scaffold.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../models/biopay_match_result.dart';
import '../providers/biopay_providers.dart';
import '../services/biopay_auth_gate_service.dart';

class BiopayConfirmScreen extends ConsumerStatefulWidget {
  const BiopayConfirmScreen({this.result, super.key});

  final BiopayMatchResult? result;

  @override
  ConsumerState<BiopayConfirmScreen> createState() =>
      _BiopayConfirmScreenState();
}

class _BiopayConfirmScreenState extends ConsumerState<BiopayConfirmScreen> {
  bool _isDialing = false;

  Future<void> _dial() async {
    final result = widget.result;
    if (_isDialing ||
        result == null ||
        !result.match ||
        result.profile == null) {
      return;
    }

    setState(() => _isDialing = true);
    try {
      final authResult = await ref
          .read(biopayAuthGateServiceProvider)
          .authorize(BiopayAuthAction.paymentHandoff);
      if (!mounted) {
        return;
      }
      if (!authResult.isAuthorized) {
        CoolToast.error(context, authResult.message);
        return;
      }

      // Create a server-issued payment intent (binds match to transaction).
      final intent = await ref
          .read(biopayRepositoryProvider)
          .createPaymentIntent(
            profilePublicId: result.profile!.publicId,
            matchScore: result.score,
          );
      if (!mounted) {
        return;
      }

      if (intent.isExpired) {
        CoolToast.error(context, 'Payment intent expired. Please try again.');
        return;
      }

      // Dial using the server-precomputed USSD code.
      final launched = await ref
          .read(biopayDialerServiceProvider)
          .dialIntent(intent);
      if (!mounted) {
        return;
      }

      if (!launched) {
        CoolToast.error(context, 'Could not open the MoMo dialer');
        return;
      }

      // Mark the intent as dialed (one-time use enforcement).
      await ref
          .read(biopayRepositoryProvider)
          .markIntentDialed(intent.intentId);

      if (!mounted) {
        return;
      }
      CoolToast.success(context, 'MoMo dialer opened');
    } catch (error) {
      if (mounted) {
        CoolToast.error(
          context,
          error is StateError
              ? error.message
              : 'Payment failed. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDialing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final result = widget.result;
    final profile = result?.profile;

    return CoolScreenScaffold(
      title: 'Confirm Payee',
      showBackButton: false,
      child: profile == null || result == null || !result.match
          ? CoolCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No BioPay match',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: colors.primaryText,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: space.x3),
                  Text(
                    'The scanner did not return a confident payee. Go back and try the scan again.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.secondaryText,
                      fontWeight: FontWeight.w500,
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: space.x5),
                  CoolButton(
                    label: 'Back to Scan',
                    onTap: () =>
                        context.go(AppRoutes.biopayScanLocation(mode: 'pay')),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CoolCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          if (result.cached)
                            _ConfirmBadge(
                              label: 'Cached preview',
                              color: colors.info,
                            ),
                          _ConfirmBadge(
                            label: 'Score ${result.score.toStringAsFixed(2)}',
                            color: colors.success,
                          ),
                        ],
                      ),
                      SizedBox(height: space.x4),
                      Text(
                        profile.displayName,
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: colors.primaryText,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                        ),
                      ),
                      SizedBox(height: space.x2),
                      Text(
                        '${profile.routeLabel}: ${profile.maskedRecipientValue}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colors.secondaryText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: space.x4),
                      Text(
                        'Confirm the name matches the person before you. MoMo checks it again before PIN entry.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.secondaryText,
                          fontWeight: FontWeight.w500,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: space.x5),
                CoolCard(
                  useGradient: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dial handoff',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colors.primaryText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: space.x2),
                      Text(
                        defaultTargetPlatform == TargetPlatform.iOS
                            ? 'iPhone opens the dialer with the USSD code filled in. Tap Call to continue.'
                            : 'Android should open MoMo ready for amount entry.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.secondaryText,
                          fontWeight: FontWeight.w500,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: space.x5),
                CoolButton(
                  label: 'Tap to Dial',
                  icon: Icons.call_rounded,
                  isLoading: _isDialing,
                  onTap: _dial,
                ),
                SizedBox(height: space.x3),
                CoolButton(
                  label: 'Cancel',
                  variant: CoolButtonVariant.secondary,
                  onTap: () => context.go(AppRoutes.biopayHome),
                ),
              ],
            ),
    );
  }
}

class _ConfirmBadge extends StatelessWidget {
  const _ConfirmBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.pill)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
