import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/config/deep_link_config.dart';
import '../../../../core/providers/referral_providers.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_skeleton.dart';
import '../../../../shared/widgets/cool_toast.dart';
import '../../../../shared/widgets/rs_amount_selector.dart';
import '../../../../shared/widgets/rs_progress_bar.dart';
import '../../../../shared/widgets/share_card.dart';
import '../models/rs_models.dart';

import '../rayon_payment.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/rayon_screen_scaffold.dart';
import '../theme/rs_theme.dart';
import '../../../../core/l10n/l10n.dart';

part '../widgets/support_detail_parts.dart';

final supportDetailAmountProvider = StateProvider.autoDispose
    .family<int, String>((ref, initiativeId) {
      return 5000;
    });

final supportDetailPendingContributionIdProvider = StateProvider.autoDispose
    .family<String?, String>((ref, initiativeId) {
      return null;
    });

final supportDetailSubmittingProvider = StateProvider.autoDispose
    .family<bool, String>((ref, initiativeId) {
      return false;
    });

final supportDetailInitiativeProvider =
    Provider.family<AsyncValue<RsInitiative?>, String>((ref, initiativeId) {
      final initiatives = ref.watch(rayonInitiativesProvider);
      return initiatives.whenData((items) {
        for (final initiative in items) {
          if (initiative.id == initiativeId) {
            return initiative;
          }
        }
        return null;
      });
    });

class SupportDetailScreen extends StatelessWidget {
  const SupportDetailScreen({
    required this.initiativeId,
    this.referralParameters = const <String, String>{},
    super.key,
  });

  final String initiativeId;
  final Map<String, String> referralParameters;

  String? _resolveReferralInviteId(WidgetRef ref) {
    final fromRoute = referralParameters['ri']?.trim();
    if (fromRoute != null && fromRoute.isNotEmpty) {
      return fromRoute;
    }

    return ref.read(activeReferralAttributionProvider)?.inviteId;
  }

  Future<String> _buildShareUrl(WidgetRef ref, RsInitiative initiative) async {
    final baseUri = DeepLinkConfig.initiativeUri(initiative.id);

    try {
      final referralLink = await ref
          .read(referralRepositoryProvider)
          .createInviteLink(
            inviteCode: 'RAYON-SUPPORT-${initiative.id}',
            baseUri: baseUri,
            shareChannel: 'qr_sheet',
            campaignId: 'rayon_support',
          );
      return referralLink.uri.toString();
    } catch (_) {
      return baseUri.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final initiativeAsync = ref.watch(
          supportDetailInitiativeProvider(initiativeId),
        );
        final paymentRoute = ref.watch(rayonPaymentRouteProvider).valueOrNull;
        final selectedAmount = ref.watch(
          supportDetailAmountProvider(initiativeId),
        );
        final contributionsAsync = ref.watch(
          rayonRecentContributorsProvider(initiativeId),
        );
        final pendingContributionId = ref.watch(
          supportDetailPendingContributionIdProvider(initiativeId),
        );
        final isSubmitting = ref.watch(
          supportDetailSubmittingProvider(initiativeId),
        );
        final colors = context.coolSemanticColors;
        final text = context.coolText;
        final theme = Theme.of(context);
        final referralInviteId = _resolveReferralInviteId(ref);

        return RayonScreenScaffold(
          title: 'Support Club',
          fallbackLocation: AppRoutes.rayonSupport,
          scrollable: false,
          child: initiativeAsync.when(
            loading: () => const _DetailLoadingState(),
            error: (error, stackTrace) => _DetailStateCard(
              icon: Icons.warning_amber_rounded,
              title: context.l10n.loadThisCauseFailed,
              subtitle: context.l10n.tryAgain,
              actionLabel: 'Back',
              onTap: () => context.go(AppRoutes.rayonSupport),
            ),
            data: (initiative) {
              if (initiative == null) {
                return _DetailStateCard(
                  icon: Icons.search_off_rounded,
                  title: context.l10n.initiativeNotFound,
                  subtitle: context.l10n.thisCauseMayHave,
                  actionLabel: 'Back to support',
                  onTap: () => context.go(AppRoutes.rayonSupport),
                );
              }

              final category = RsTheme.parseCategory(
                initiative.category.value.toLowerCase(),
              );
              final categoryColor = RsTheme.categoryColor(category);
              final pendingContribution = _findContributionById(
                contributionsAsync.valueOrNull,
                pendingContributionId,
              );
              final canSubmitSupport = paymentRoute != null;
              final supportCtaLabel = paymentRoute == null
                  ? 'Payment route unavailable'
                  : 'Support ${paymentRoute.amountLabel(selectedAmount)} via ${paymentRoute.providerLabel}';

              Future<void> submitSupport() async {
                final notifier = ref.read(rayonSportsProvider.notifier);
                ref
                        .read(
                          supportDetailSubmittingProvider(
                            initiativeId,
                          ).notifier,
                        )
                        .state =
                    true;
                try {
                  final result = await notifier.supportInitiative(
                    initiativeId: initiative.id,
                    amount: selectedAmount,
                    referralInviteId: referralInviteId,
                  );
                  ref
                          .read(
                            supportDetailPendingContributionIdProvider(
                              initiativeId,
                            ).notifier,
                          )
                          .state =
                      result.contributionId;
                  if (referralInviteId != null && referralInviteId.isNotEmpty) {
                    ref
                        .read(activeReferralAttributionProvider.notifier)
                        .clearIfMatches(referralInviteId);
                  }
                  ref.invalidate(
                    rayonRecentContributorsProvider(initiative.id),
                  );
                  // Points are awarded server-side after payment confirmation.
                  if (!context.mounted) {
                    return;
                  }
                  CoolToast.info(context, result.message);
                } catch (error) {
                  if (!context.mounted) {
                    return;
                  }
                  CoolToast.error(context, error.toString());
                } finally {
                  ref
                          .read(
                            supportDetailSubmittingProvider(
                              initiativeId,
                            ).notifier,
                          )
                          .state =
                      false;
                }
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 96),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SupportCommandCard(
                      initiative: initiative,
                      paymentRoute: paymentRoute,
                      amount: selectedAmount,
                    ),
                    const SizedBox(height: 18),
                    _DetailHero(
                      initiative: initiative,
                      categoryColor: categoryColor,
                    ),
                    const SizedBox(height: 18),
                    _CauseSummaryCard(
                      initiative: initiative,
                      categoryColor: categoryColor,
                    ),
                    const SizedBox(height: CoolSpace.x4),
                    _SupportCheckoutCard(
                      amount: selectedAmount,
                      paymentRoute: paymentRoute,
                      ctaLabel: supportCtaLabel,
                      isLoading: isSubmitting,
                      onAmountSelected: (amount) {
                        ref
                                .read(
                                  supportDetailAmountProvider(
                                    initiativeId,
                                  ).notifier,
                                )
                                .state =
                            amount;
                      },
                      onTap: canSubmitSupport ? submitSupport : null,
                    ),
                    if (pendingContribution != null &&
                        pendingContribution.status.toLowerCase() ==
                            'pending') ...[
                      const SizedBox(height: CoolSpace.x4),
                      _PendingContributionCard(
                        contribution: pendingContribution,
                        onRefreshStatus: () => ref.invalidate(
                          rayonRecentContributorsProvider(initiative.id),
                        ),
                      ),
                    ],
                    const SizedBox(height: CoolSpace.x6),
                    Text(
                      'More details',
                      style: text.rayonCondensed(
                        theme.textTheme.headlineSmall,
                        fontWeight: FontWeight.w900,
                        color: colors.primaryText,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x3),
                    _PerksCard(),
                    const SizedBox(height: CoolSpace.x4),
                    _RecentSupportersCard(
                      contributionsAsync: contributionsAsync,
                      onRefreshStatus: () => ref.invalidate(
                        rayonRecentContributorsProvider(initiative.id),
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x4),

                    // ── Share initiative ──────────────────────
                    ShareCard(
                      title: context.l10n.shareThisInitiative,
                      icon: Icons.link_rounded,
                      subtitle: initiative.title,
                      shareUrl: DeepLinkConfig.initiativeUri(
                        initiative.id,
                      ).toString(),
                      shareText: 'Support ${initiative.title} on Cool!',
                      sheetTitle: 'Share Initiative',
                      sheetSubtitle: 'Invite supporters to back this cause.',
                      analyticsTargetType: 'rayon_support',
                      resolveShareUrl: () => _buildShareUrl(ref, initiative),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
