import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/deep_link_config.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/providers/referral_providers.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_toast.dart';
import '../providers/rayon_sports_provider.dart';
import '../../../../shared/widgets/core_app_scaffold.dart';
import '../widgets/rayon_state_views.dart';

class FanClubDetailScreen extends ConsumerWidget {
  const FanClubDetailScreen({
    required this.clubId,
    this.referralParameters = const <String, String>{},
    super.key,
  });

  final String clubId;
  final Map<String, String> referralParameters;

  String? _resolveReferralInviteId(WidgetRef ref) {
    final fromRoute = referralParameters['ri']?.trim();
    if (fromRoute != null && fromRoute.isNotEmpty) {
      return fromRoute;
    }

    return ref.read(activeReferralAttributionProvider)?.inviteId;
  }

  Future<String> _buildShareUrl(WidgetRef ref, String clubId) async {
    final baseUri = DeepLinkConfig.clubUri(clubId);

    try {
      final referralLink = await ref
          .read(referralRepositoryProvider)
          .createInviteLink(
            inviteCode: 'RAYON-CLUB-$clubId',
            baseUri: baseUri,
            shareChannel: 'qr_sheet',
            campaignId: 'rayon_clubs',
          );
      return referralLink.uri.toString();
    } catch (_) {
      return baseUri.toString();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clubDetail = ref.watch(rayonClubDetailProvider(clubId));
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    return CoreAppScaffold(
      title: 'FAN CLUB',
      fallbackLocation: AppRoutes.rayonClubs,
      scrollable: false,
      child: clubDetail.when(
        data: (detail) {
          final club = detail.club;
          if (club == null) {
            return RayonErrorView(
              message: 'Club not found.',
              onRetry: () => ref.invalidate(rayonClubDetailProvider(clubId)),
            );
          }

          final joined = detail.joined;
          final memberCount = club.memberCount;

          return Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ─── Top action row ─────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: joined
                                ? () => context.push(AppRoutes.rayonSupport)
                                : () => _join(context, ref, club.id),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(CoolRadii.lg),
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.add,
                                    color: Colors.black,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    joined ? 'CONTRIBUTE' : 'JOIN',
                                    style: text.rayonCondensed(
                                      theme.textTheme.titleMedium,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.black,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: colors.cardSurfaceStrong,
                            borderRadius: BorderRadius.circular(CoolRadii.lg),
                            border: Border.all(color: colors.borderStrong),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.more_horiz,
                            color: colors.secondaryText,
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: CoolSpace.x6),

                    // ─── Members header ────────────────────────
                    Row(
                      children: [
                        Text(
                          'MEMBERS ($memberCount)',
                          style: text.mono(
                            theme.textTheme.labelSmall,
                            fontWeight: FontWeight.w700,
                            color: colors.secondaryText,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'SHOW ALL',
                          style: text.mono(
                            theme.textTheme.labelSmall,
                            fontWeight: FontWeight.w700,
                            color: colors.primaryText,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: CoolSpace.x3),

                    // ─── Member cards ──────────────────────────
                    for (var i = 0; i < memberCount.clamp(0, 3); i++) ...[
                      _MemberCard(
                        memberId: _mockMemberIds[i % _mockMemberIds.length],
                        totalRwf: _mockTotals[i % _mockTotals.length],
                        isTopMember: i == 0,
                      ),
                      if (i < memberCount.clamp(0, 3) - 1)
                        const SizedBox(height: 10),
                    ],
                    const SizedBox(height: CoolSpace.x6),

                    // ─── Invite friends ────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(CoolRadii.md),
                        border: Border.all(
                          color: colors.borderStrong,
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.person_add_alt_1_outlined,
                            color: colors.secondaryText,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'INVITE FRIENDS',
                            style: text.mono(
                              theme.textTheme.labelMedium,
                              fontWeight: FontWeight.w700,
                              color: colors.secondaryText,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x7),

                    // ─── Recent activity header ────────────────
                    Row(
                      children: [
                        Text(
                          'RECENT ACTIVITY',
                          style: text.mono(
                            theme.textTheme.labelSmall,
                            fontWeight: FontWeight.w700,
                            color: colors.secondaryText,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'VIEW LEDGER',
                          style: text.mono(
                            theme.textTheme.labelSmall,
                            fontWeight: FontWeight.w700,
                            color: colors.primaryText,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: CoolSpace.x4),

                    // ─── Activity rows ─────────────────────────
                    const _ActivityRow(
                      memberId: '882942',
                      timeAgo: '2 HOURS AGO',
                      amount: '+50,000 RWF',
                    ),
                    const SizedBox(height: CoolSpace.x3),
                    const _ActivityRow(
                      memberId: '112934',
                      timeAgo: 'YESTERDAY',
                      amount: '+50,000 RWF',
                    ),
                  ],
                ),
              ),

              // ─── Share FAB ─────────────────────────────────
              Positioned(
                right: 16,
                bottom: 24,
                child: GestureDetector(
                  onTap: () async {
                    await _buildShareUrl(ref, club.id);
                    if (!context.mounted) return;
                    // Share functionality handled via platform sheet
                    CoolToast.info(context, 'Share link copied.');
                  },
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.share_rounded,
                      color: Colors.black,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        loading: RayonLoadingView.new,
        error: (error, _) => RayonErrorView(
          message: error.toString(),
          onRetry: () {
            ref.invalidate(rayonFanClubsProvider);
            ref.invalidate(rayonJoinedClubIdsProvider);
            ref.invalidate(rayonUserAchievementsProvider);
            ref.invalidate(rayonClubDetailProvider(clubId));
          },
        ),
      ),
    );
  }

  Future<void> _join(BuildContext context, WidgetRef ref, String id) async {
    final notifier = ref.read(rayonSportsProvider.notifier);

    try {
      final referralInviteId = _resolveReferralInviteId(ref);
      final message = await notifier.joinClub(id);
      ref.invalidate(rayonFanClubsProvider);
      ref.invalidate(rayonJoinedClubIdsProvider);
      ref.invalidate(rayonClubDirectoryProvider);
      ref.invalidate(rayonClubDetailProvider(clubId));
      if (referralInviteId != null && referralInviteId.isNotEmpty) {
        try {
          await ref
              .read(referralRepositoryProvider)
              .activateInvite(
                inviteId: referralInviteId,
                qualifyingEventType: 'rayon_club_joined',
                qualifyingEventId: id,
                inviterPoints: 120,
                inviteePoints: 50,
              );
          ref
              .read(activeReferralAttributionProvider.notifier)
              .clearIfMatches(referralInviteId);
        } catch (_) {
          // Club join should still succeed if referral activation fails.
        }
      }
      if (!context.mounted) return;
      CoolToast.info(context, message);
    } catch (error) {
      if (!context.mounted) return;
      CoolToast.error(context, error.toString());
    }
  }
}

// ─── Mock data for member preview ─────────────────────────────────────────

const _mockMemberIds = ['882942', '112934', '449283'];
const _mockTotals = [150000, 100000, 100000];

// ─── Member card ──────────────────────────────────────────────────────────

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.memberId,
    required this.totalRwf,
    required this.isTopMember,
  });

  final String memberId;
  final int totalRwf;
  final bool isTopMember;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final formatted = _formatCompact(totalRwf);

    return CoolCard(
      backgroundColor: colors.cardSurface,
      borderColor: colors.borderStrong,
      child: Row(
        children: [
          // Shield icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.cardSurfaceStrong,
              borderRadius: BorderRadius.circular(CoolRadii.sm),
              border: Border.all(color: colors.borderStrong),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.groups_outlined,
              color: colors.secondaryText,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          // ID + total
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      memberId,
                      style: text.rayonCondensed(
                        theme.textTheme.titleMedium,
                        fontWeight: FontWeight.w900,
                        color: colors.primaryText,
                      ),
                    ),
                    if (isTopMember) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.verified,
                        color: RsColors.rsGoldLight,
                        size: 18,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'TOTAL: $formatted RWF',
                  style: text.mono(
                    theme.textTheme.bodySmall,
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: colors.tertiaryText,
            size: 22,
          ),
        ],
      ),
    );
  }
}

// ─── Activity row ─────────────────────────────────────────────────────────

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.memberId,
    required this.timeAgo,
    required this.amount,
  });

  final String memberId;
  final String timeAgo;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    return Row(
      children: [
        // Clipboard icon box
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors.cardSurfaceStrong,
            borderRadius: BorderRadius.circular(CoolRadii.sm),
            border: Border.all(color: colors.borderStrong),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.receipt_long_outlined,
            color: colors.secondaryText,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        // ID + time
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                memberId,
                style: text.rayonCondensed(
                  theme.textTheme.titleSmall,
                  fontWeight: FontWeight.w900,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                timeAgo,
                style: text.mono(
                  theme.textTheme.bodySmall,
                  fontWeight: FontWeight.w600,
                  color: colors.tertiaryText,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        // Amount
        Text(
          amount,
          style: text.mono(
            theme.textTheme.bodyMedium,
            fontWeight: FontWeight.w700,
            color: colors.primaryText,
          ),
        ),
      ],
    );
  }
}

// ─── Formatting ───────────────────────────────────────────────────────────

String _formatCompact(int amount) {
  if (amount >= 1000) {
    final value = (amount / 1000).truncate();
    return '$value,000';
  }
  return '$amount';
}
