import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/engagement_providers.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_scaffold.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/biopay_providers.dart';

class BiopayHomeScreen extends ConsumerWidget {
  const BiopayHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final modelIssueAsync = ref.watch(biopayModelAssetIssueProvider);
    final profileAsync = ref.watch(biopayProfileProvider);
    final authState = ref.watch(authProvider);
    final enabled = ref.watch(
      featureFlagsStateProvider.select(
        (flags) =>
            flags.isBiopayEnabled(isAdmin: authState.user?.isAdmin ?? false),
      ),
    );
    final modelIssue = modelIssueAsync.valueOrNull;
    final canOpenBiopay = enabled && modelIssue == null;

    return CoolScreenScaffold(
      title: 'BioPay',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoolCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Register your face. Get paid. Scan a face. Pay instantly.',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w900,
                    height: 1.08,
                  ),
                ),
                SizedBox(height: space.x3),
                Text(
                  'BioPay uses your signed-in profile and verified wallet route. No phone OTP required.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.secondaryText,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: space.x4),
                const Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _BiopayChip(label: 'Supabase-first'),
                    _BiopayChip(label: 'No image gallery writes'),
                    _BiopayChip(label: 'MoMo dialer handoff'),
                  ],
                ),
                SizedBox(height: space.x5),
                CoolButton(
                  label: 'Register My Face',
                  icon: Icons.badge_outlined,
                  onTap: canOpenBiopay
                      ? () => context.push(AppRoutes.biopayRegister)
                      : null,
                ),
                SizedBox(height: space.x3),
                CoolButton(
                  label: 'Scan to Pay',
                  variant: CoolButtonVariant.secondary,
                  icon: Icons.face_retouching_natural_rounded,
                  onTap: canOpenBiopay
                      ? () => context.push(
                          AppRoutes.biopayScanLocation(mode: 'pay'),
                        )
                      : null,
                ),
              ],
            ),
          ),
          if (modelIssue != null) ...[
            SizedBox(height: space.x5),
            CoolCard(
              borderColor: colors.warning.withValues(alpha: 0.42),
              useGradient: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Model asset required',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.primaryText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: space.x2),
                  Text(
                    modelIssue,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.secondaryText,
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: space.x5),
          profileAsync.when(
            data: (profile) => profile == null
                ? CoolCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Enrollment status',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colors.primaryText,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: space.x2),
                        Text(
                          'No BioPay enrollment yet. Use your wallet route, review consent, then capture your face.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.secondaryText,
                            fontWeight: FontWeight.w500,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  )
                : CoolCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                profile.displayName,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: colors.primaryText,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: colors.success.withValues(alpha: 0.14),
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(CoolRadii.pill),
                                ),
                              ),
                              child: Text(
                                'ID ${profile.publicId}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colors.success,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: space.x2),
                        Text(
                          '${profile.routeLabel}: ${profile.maskedRecipientValue}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.secondaryText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: space.x2),
                        Text(
                          'Scan, confirm the payee, then let MoMo verify the account name before PIN entry.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.secondaryText,
                            fontWeight: FontWeight.w500,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => CoolCard(
              child: Text(
                'BioPay enrollment status is not available yet. Apply the Supabase migration and functions first.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BiopayChip extends StatelessWidget {
  const _BiopayChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.pill)),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: colors.secondaryText,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
