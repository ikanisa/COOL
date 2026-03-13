import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/config/deep_link_config.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/providers/referral_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../core/theme/rs_text_styles.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_toast.dart';
import '../../../../shared/widgets/share_card.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_screen_background.dart';
import '../../../../shared/widgets/cool_skeleton.dart';
import '../../../../shared/widgets/rs_amount_selector.dart';
import '../../../../shared/widgets/rs_progress_bar.dart';
import '../models/rs_models.dart';

import '../rayon_payment.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/partner_navigation.dart';
import '../theme/rs_theme.dart';

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
        final membership = ref.watch(rayonUserMembershipProvider).valueOrNull;
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
        final referralInviteId = _resolveReferralInviteId(ref);

        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: buildPartnerBackButton(
              context,
              fallbackLocation: AppRoutes.rayonSupport,
            ),
            title: Text(
              'Support Club',
              style: RsTextStyles.sectionTitle(color: RsColors.rsWhite),
            ),
            actions: buildPartnerAppBarActions(context),
          ),
          body: CoolScreenBackground(
            primaryColor: RsColors.rsBlue,
            secondaryColor: RsColors.rsGold,
            child: initiativeAsync.when(
              loading: () => const _DetailLoadingState(),
              error: (error, stackTrace) => _DetailStateCard(
                icon: Icons.warning_amber_rounded,
                title: 'Unable to load this cause',
                subtitle: 'Please try again in a moment.',
                actionLabel: 'Back',
                onTap: () => popOrGo(context, AppRoutes.rayonSupport),
              ),
              data: (initiative) {
                if (initiative == null) {
                  return _DetailStateCard(
                    icon: Icons.search_off_rounded,
                    title: 'Initiative not found',
                    subtitle: 'This cause may have expired or moved.',
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

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 96),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DetailHero(
                        initiative: initiative,
                        categoryColor: categoryColor,
                      ),
                      const SizedBox(height: 18),
                      _CategoryPill(
                        label: initiative.category.value.toUpperCase(),
                        color: categoryColor,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        initiative.title,
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          color: RsColors.rsWhite,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        initiative.description,
                        style: GoogleFonts.barlow(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text2,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _ProgressCard(
                        initiative: initiative,
                        categoryColor: categoryColor,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Choose Amount',
                        style: RsTextStyles.sectionTitle(
                          color: RsColors.rsWhite,
                        ),
                      ),
                      const SizedBox(height: 12),
                      CoolCard(
                        borderColor: AppColors.border2,
                        child: RsAmountSelector(
                          amounts: const [1000, 2000, 5000, 10000, 20000],
                          allowCustom: true,
                          selectedAmount: selectedAmount,
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
                        ),
                      ),
                      const SizedBox(height: 20),
                      _PerksCard(),
                      const SizedBox(height: 16),
                      _MomoInfoBanner(
                        amount: selectedAmount,
                        tier: membership?.tier ?? FanTier.blue,
                        paymentRoute: paymentRoute,
                      ),
                      const SizedBox(height: 16),
                      CoolButton(
                        label: paymentRoute == null
                            ? 'Support ${_formatRwf(selectedAmount)}'
                            : 'Support ${paymentRoute.amountLabel(selectedAmount)} via ${paymentRoute.providerLabel}',
                        icon: Icons.favorite_border_rounded,
                        isLoading: isSubmitting,
                        onTap: () async {
                          final notifier = ref.read(
                            rayonSportsProvider.notifier,
                          );
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
                                .state = result
                                .contributionId;
                            if (referralInviteId != null &&
                                referralInviteId.isNotEmpty) {
                              ref
                                  .read(
                                    activeReferralAttributionProvider.notifier,
                                  )
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
                        },
                      ),
                      if (pendingContribution != null &&
                          pendingContribution.status.toLowerCase() ==
                              'pending') ...[
                        const SizedBox(height: 16),
                        _PendingContributionCard(
                          contribution: pendingContribution,
                          onRefreshStatus: () => ref.invalidate(
                            rayonRecentContributorsProvider(initiative.id),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        'Recent Support Activity',
                        style: RsTextStyles.sectionTitle(
                          color: RsColors.rsWhite,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _RecentSupportersCard(
                        contributionsAsync: contributionsAsync,
                        onRefreshStatus: () => ref.invalidate(
                          rayonRecentContributorsProvider(initiative.id),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Share initiative ──────────────────────
                      ShareCard(
                        title: 'Share this initiative',
                        icon: Icons.link_rounded,
                        subtitle: initiative.title,
                        shareUrl: DeepLinkConfig.initiativeUri(
                          initiative.id,
                        ).toString(),
                        shareText: 'Support ${initiative.title} on Cool!',
                        sheetTitle: 'Share Initiative',
                        sheetSubtitle:
                            'Invite supporters to back ${initiative.title}.',
                        analyticsTargetType: 'rayon_support',
                        resolveShareUrl: () => _buildShareUrl(ref, initiative),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _DetailHero extends StatelessWidget {
  const _DetailHero({required this.initiative, required this.categoryColor});

  final RsInitiative initiative;
  final Color categoryColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: 140,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    categoryColor.withValues(alpha: 0.68),
                    RsColors.rsBlue,
                    const Color(0xFF091331),
                  ],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
            ),
            Positioned(
              right: 18,
              top: 6,
              child: Icon(
                _categoryIcon(initiative.category.value),
                size: 82,
                color: AppColors.rsWhite.withValues(alpha: 0.92),
              ),
            ),
            Positioned(
              left: 18,
              bottom: 18,
              child: Text(
                'Rayon Sports Cause',
                style: GoogleFonts.barlow(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.rsWhite.withValues(alpha: 0.85),
                  letterSpacing: 0.4,
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      AppColors.surface.withValues(alpha: 0.22),
                      AppColors.surface,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.initiative, required this.categoryColor});

  final RsInitiative initiative;
  final Color categoryColor;

  @override
  Widget build(BuildContext context) {
    final percentage = (initiative.progress * 100).round();

    return CoolCard(
      borderColor: AppColors.border2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatRwf(initiative.raisedAmount),
            style: GoogleFonts.dmMono(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.blue,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'of ${_formatRwf(initiative.targetAmount)} goal',
            style: GoogleFonts.barlow(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
            ),
          ),
          const SizedBox(height: 14),
          RsProgressBar(
            progress: initiative.progress,
            fillColor: categoryColor,
            height: 8,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '${NumberFormat.decimalPattern('en').format(initiative.supporterCount)} supporters',
                style: GoogleFonts.barlow(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text2,
                ),
              ),
              const Spacer(),
              Text(
                '$percentage% funded',
                textAlign: TextAlign.right,
                style: GoogleFonts.dmMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: categoryColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PerksCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CoolCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [RsColors.rsGold.withValues(alpha: 0.18), AppColors.surface2],
      ),
      borderColor: RsColors.rsGold.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Supporter Perks',
            style: GoogleFonts.barlowCondensed(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: RsColors.rsGoldLight,
            ),
          ),
          const SizedBox(height: 14),
          const _PerkRow(threshold: '1,000+', perk: 'Supporter badge'),
          const SizedBox(height: 10),
          const _PerkRow(threshold: '5,000+', perk: 'Name on plaque'),
          const SizedBox(height: 10),
          const _PerkRow(
            threshold: '20,000+',
            perk: 'VIP opening ceremony invite',
          ),
        ],
      ),
    );
  }
}

class _PerkRow extends StatelessWidget {
  const _PerkRow({required this.threshold, required this.perk});

  final String threshold;
  final String perk;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: RsColors.rsGold.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            threshold,
            style: GoogleFonts.dmMono(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: RsColors.rsGoldLight,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            perk,
            style: GoogleFonts.barlow(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: RsColors.rsWhite,
            ),
          ),
        ),
      ],
    );
  }
}

class _MomoInfoBanner extends StatelessWidget {
  const _MomoInfoBanner({
    required this.amount,
    required this.tier,
    this.paymentRoute,
  });

  final int amount;
  final FanTier tier;
  final PartnerPaymentRoute? paymentRoute;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [RsColors.rsBlue.withValues(alpha: 0.28), AppColors.surface2],
      ),
      borderColor: RsColors.rsBlueBorder,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: RsColors.rsBlueGlow,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.phone_in_talk_rounded,
              color: RsColors.rsWhite,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Payment info',
                  style: RsTextStyles.sectionTitle(color: RsColors.rsWhite),
                ),
                const SizedBox(height: 6),
                Text(
                  paymentRoute == null
                      ? 'Backend payment routing is not active for this checkout yet.'
                      : 'Pay to ${paymentRoute!.payToLabel} · Amount ${paymentRoute!.amountLabel(amount)} · Fees ${paymentRoute!.feesLabel()}. Receipt follows after SMS reconciliation for ${paymentRoute!.reconciliationLabel}.',
                  style: GoogleFonts.barlow(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentSupportersCard extends StatelessWidget {
  const _RecentSupportersCard({
    required this.contributionsAsync,
    required this.onRefreshStatus,
  });

  final AsyncValue<List<RsInitiativeContribution>> contributionsAsync;
  final VoidCallback onRefreshStatus;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      borderColor: AppColors.border2,
      child: contributionsAsync.when(
        data: (contributions) {
          if (contributions.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Text(
                  'Support activity will appear here after the first contribution.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.barlow(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2,
                    height: 1.4,
                  ),
                ),
              ),
            );
          }

          return Column(
            children: [
              for (var i = 0; i < contributions.length; i++) ...[
                _SupporterRow(contribution: contributions[i]),
                if (i < contributions.length - 1)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1, color: AppColors.border),
                  ),
              ],
            ],
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              CoolSkeleton(
                width: double.infinity,
                height: 52,
                borderRadius: 14,
              ),
              SizedBox(height: 12),
              CoolSkeleton(
                width: double.infinity,
                height: 52,
                borderRadius: 14,
              ),
              SizedBox(height: 12),
              CoolSkeleton(
                width: double.infinity,
                height: 52,
                borderRadius: 14,
              ),
            ],
          ),
        ),
        error: (error, _) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Text(
                'Recent support activity could not be loaded.',
                textAlign: TextAlign.center,
                style: GoogleFonts.barlow(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text2,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onRefreshStatus,
                icon: const Icon(Icons.sync_rounded, size: 18),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupporterRow extends StatelessWidget {
  const _SupporterRow({required this.contribution});

  final RsInitiativeContribution contribution;

  @override
  Widget build(BuildContext context) {
    final supporterName = contribution.supporterName ?? 'Supporter';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [RsColors.rsBlueLight, RsColors.rsBlue],
            ),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: RsColors.rsBlueBorder),
          ),
          alignment: Alignment.center,
          child: Text(
            _initials(supporterName),
            style: GoogleFonts.barlowCondensed(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: RsColors.rsWhite,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                supporterName,
                style: GoogleFonts.barlow(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: RsColors.rsWhite,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_contributionStatusLabel(contribution.status)} • ${DateFormat('dd MMM, HH:mm').format(contribution.createdAt)}',
                style: GoogleFonts.barlow(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _contributionStatusColor(contribution.status),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          _formatRwf(contribution.amount),
          style: GoogleFonts.dmMono(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.blue,
          ),
        ),
      ],
    );
  }
}

class _PendingContributionCard extends StatelessWidget {
  const _PendingContributionCard({
    required this.contribution,
    required this.onRefreshStatus,
  });

  final RsInitiativeContribution contribution;
  final VoidCallback onRefreshStatus;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      borderColor: RsColors.rsGold.withValues(alpha: 0.28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Payment Status',
                style: RsTextStyles.sectionTitle(color: RsColors.rsWhite),
              ),
              const Spacer(),
              _ContributionStatusChip(status: contribution.status),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Pending until MoMo confirms ${contribution.momoReference}.',
            style: GoogleFonts.barlow(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          _PendingContributionMeta(
            label: 'Amount',
            value: _formatRwf(contribution.amount),
          ),
          _PendingContributionMeta(
            label: 'MoMo ref',
            value: contribution.momoReference,
          ),
          _PendingContributionMeta(
            label: 'Started',
            value: DateFormat('dd MMM, HH:mm').format(contribution.createdAt),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onRefreshStatus,
            icon: const Icon(Icons.sync_rounded, size: 18),
            label: const Text('Refresh payment status'),
          ),
        ],
      ),
    );
  }
}

class _PendingContributionMeta extends StatelessWidget {
  const _PendingContributionMeta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: GoogleFonts.barlow(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.text3,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: GoogleFonts.dmMono(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContributionStatusChip extends StatelessWidget {
  const _ContributionStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _contributionStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        _contributionStatusLabel(status).toUpperCase(),
        style: GoogleFonts.barlow(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.barlow(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _DetailStateCard extends StatelessWidget {
  const _DetailStateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: CoolCard(
          borderColor: AppColors.border2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: AppColors.text2),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: RsTextStyles.sectionTitle(color: RsColors.rsWhite),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.barlow(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text2,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: onTap,
                child: Text(
                  actionLabel,
                  style: GoogleFonts.barlow(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailLoadingState extends StatelessWidget {
  const _DetailLoadingState();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 96),
      child: const Column(
        children: [
          CoolSkeleton(width: double.infinity, height: 140, borderRadius: 22),
          SizedBox(height: 18),
          CoolSkeleton(width: 120, height: 28, borderRadius: 999),
          SizedBox(height: 14),
          CoolSkeleton(width: double.infinity, height: 100, borderRadius: 18),
          SizedBox(height: 18),
          CoolSkeleton.card(),
          SizedBox(height: 18),
          CoolSkeleton.card(),
          SizedBox(height: 18),
          CoolSkeleton.card(),
        ],
      ),
    );
  }
}

RsInitiativeContribution? _findContributionById(
  List<RsInitiativeContribution>? contributions,
  String? contributionId,
) {
  if (contributions == null ||
      contributionId == null ||
      contributionId.isEmpty) {
    return null;
  }

  for (final contribution in contributions) {
    if (contribution.id == contributionId) {
      return contribution;
    }
  }

  return null;
}

String _contributionStatusLabel(String status) {
  switch (status.toLowerCase()) {
    case 'confirmed':
      return 'Confirmed';
    case 'failed':
      return 'Failed';
    case 'cancelled':
      return 'Cancelled';
    default:
      return 'Pending';
  }
}

Color _contributionStatusColor(String status) {
  switch (status.toLowerCase()) {
    case 'confirmed':
      return AppColors.accent;
    case 'failed':
      return const Color(0xFFFF7A7A);
    case 'cancelled':
      return AppColors.text3;
    default:
      return RsColors.rsGoldLight;
  }
}

String _formatRwf(int amount) {
  return 'RWF ${NumberFormat.decimalPattern('en').format(amount)}';
}

IconData _categoryIcon(String category) {
  switch (category.toLowerCase()) {
    case 'youth':
      return Icons.child_care_rounded;
    case 'matchday':
      return Icons.stadium_rounded;
    case 'infrastructure':
      return Icons.construction_rounded;
    case 'charity':
      return Icons.favorite_rounded;
    default:
      return Icons.handshake_rounded;
  }
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);

  if (parts.isEmpty) {
    return 'RS';
  }
  if (parts.length == 1) {
    return parts.first
        .substring(0, math.min(2, parts.first.length))
        .toUpperCase();
  }
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
