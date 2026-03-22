import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/config/deep_link_config.dart';
import '../../../../core/providers/production_redesign_provider.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/providers/referral_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/cool_palette.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_toast.dart';
import '../../../../shared/widgets/rs_achievement_badge.dart';
import '../../../../shared/widgets/share_card.dart';
import '../models/rs_models.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/rayon_screen_scaffold.dart';
import '../../widgets/rayon_state_views.dart';
import '../../../../core/l10n/l10n.dart';

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
    final palette = context.coolPalette;
    final clubDetail = ref.watch(rayonClubDetailProvider(clubId));
    final useProductionRedesign = ref.watch(
      productionRedesignEnabledProvider(
        const ProductionRedesignScope(
          route: ProductionRedesignRoutes.rayonFanClubDetail,
          partner: 'rayon',
        ),
      ),
    );

    return RayonScreenScaffold(
      title: context.l10n.fanClub,
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
          final previewMemberCount = club.memberCount.clamp(0, 5);
          final earnedAchievements = detail.achievements
              .where((achievement) => achievement.isEarned)
              .length;

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (useProductionRedesign) ...[
                      _FanClubCommandCard(
                        club: club,
                        joined: joined,
                        earnedAchievements: earnedAchievements,
                      ),
                      const SizedBox(height: 18),
                    ],
                    _ClubOverviewCard(
                      clubName: club.name,
                      region: club.region,
                      bannerEmoji: club.bannerEmoji,
                      description: club.description,
                      memberCount: club.memberCount,
                      eventCount: club.eventCount,
                      rating: club.rating,
                      joined: joined,
                      onJoinTap: joined
                          ? () {
                              CoolToast.info(
                                context,
                                'Leave club coming soon.',
                              );
                            }
                          : () => _join(context, ref, club.id),
                    ),
                    const SizedBox(height: 22),
                    _SectionTitle(
                      label: context.l10n.membersPreview,
                      trailing: '${club.memberCount}',
                    ),
                    const SizedBox(height: 10),
                  ]),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == previewMemberCount - 1 ? 0 : 8,
                      ),
                      child: _MemberTile(index: index),
                    );
                  }, childCount: previewMemberCount),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (club.memberCount > 5) ...[
                      Semantics(
                        button: true,
                        label: 'View all ${club.memberCount} members',
                        child: GestureDetector(
                          onTap: () {},
                          child: Text(
                            'View all ${club.memberCount} members',
                            style: GoogleFonts.barlow(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: palette.accent,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                    ],
                    if (detail.achievements.isNotEmpty) ...[
                      _SectionTitle(label: context.l10n.moreDetails),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 16,
                        runSpacing: 14,
                        children: detail.achievements
                            .take(6)
                            .map((a) => RsAchievementBadge(achievement: a))
                            .toList(),
                      ),
                      const SizedBox(height: 22),
                    ],
                    ShareCard(
                      title: context.l10n.inviteSupporters,
                      icon: Icons.campaign_rounded,
                      message: 'Bring more fans into',
                      shareUrl: DeepLinkConfig.clubUri(club.id).toString(),
                      shareText: 'Join ${club.name} on Cool.',
                      sheetTitle: 'Share Fan Club',
                      sheetSubtitle: context.l10n.inviteSupportersToJoin,
                      analyticsTargetType: 'rayon_club',
                      resolveShareUrl: () => _buildShareUrl(ref, club.id),
                    ),
                  ]),
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

  static LinearGradient _regionGradient(String region) {
    final lower = region.toLowerCase();
    if (lower.contains('kigali')) {
      return const LinearGradient(
        colors: [Color(0xFF0A1A50), Color(0xFF0D2878)],
      );
    }
    if (lower.contains('north')) {
      return const LinearGradient(
        colors: [Color(0xFF071240), Color(0xFF0B1D5A)],
      );
    }
    if (lower.contains('south')) {
      return const LinearGradient(
        colors: [Color(0xFF0E1A4A), Color(0xFF152260)],
      );
    }
    return const LinearGradient(colors: [Color(0xFF091540), Color(0xFF0D1E6A)]);
  }
}

class _FanClubCommandCard extends StatelessWidget {
  const _FanClubCommandCard({
    required this.club,
    required this.joined,
    required this.earnedAchievements,
  });

  final RsFanClub club;
  final bool joined;
  final int earnedAchievements;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      gradient: FanClubDetailScreen._regionGradient(club.region),
      borderColor: AppColors.rsBlueBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chapter Operations Brief',
                      style: GoogleFonts.barlow(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Supporter identity, local chapter growth, and matchday readiness are tracked from a single verified club profile.',
                      style: GoogleFonts.barlow(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.76),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _FanClubDetailPill(
                icon: joined ? Icons.verified_rounded : Icons.group_add_rounded,
                label: joined ? 'Joined chapter' : 'Membership open',
                highlighted: true,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _FanClubDetailMetric(
                  label: 'Members',
                  value: '${club.memberCount}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FanClubDetailMetric(
                  label: 'Events',
                  value: '${club.eventCount}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FanClubDetailMetric(
                  label: 'Achievements',
                  value: '$earnedAchievements',
                  highlight: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FanClubDetailPill(
                icon: Icons.place_outlined,
                label: club.region,
              ),
              _FanClubDetailPill(
                icon: Icons.workspace_premium_outlined,
                label: club.rating <= 0
                    ? 'New chapter'
                    : 'Rating ${club.rating.toStringAsFixed(1)}',
              ),
              const _FanClubDetailPill(
                icon: Icons.share_outlined,
                label: 'Invite-supported growth enabled',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClubOverviewCard extends StatelessWidget {
  const _ClubOverviewCard({
    required this.clubName,
    required this.region,
    required this.bannerEmoji,
    required this.description,
    required this.memberCount,
    required this.eventCount,
    required this.rating,
    required this.joined,
    required this.onJoinTap,
  });

  final String clubName;
  final String region;
  final String bannerEmoji;
  final String description;
  final int memberCount;
  final int eventCount;
  final double rating;
  final bool joined;
  final VoidCallback onJoinTap;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      gradient: FanClubDetailScreen._regionGradient(region),
      borderColor: RsColors.rsBlueBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.rsWhite.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.rsWhite.withValues(alpha: 0.14),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(bannerEmoji, style: const TextStyle(fontSize: 30)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      region.toUpperCase(),
                      style: GoogleFonts.dmMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.rsGoldLight,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      clubName,
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: AppColors.rsWhite,
                        height: 0.95,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _JoinLeaveButton(joined: joined, onTap: onJoinTap),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            description,
            style: GoogleFonts.barlow(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.rsWhite.withValues(alpha: 0.82),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatTile(label: 'Members', value: '$memberCount'),
              const SizedBox(width: 10),
              _StatTile(label: 'Events', value: '$eventCount'),
              const SizedBox(width: 10),
              _StatTile(
                label: context.l10n.rating,
                value: rating <= 0 ? 'New' : rating.toStringAsFixed(1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FanClubDetailMetric extends StatelessWidget {
  const _FanClubDetailMetric({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.rsGold.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlight
              ? AppColors.rsGold.withValues(alpha: 0.34)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: GoogleFonts.barlowCondensed(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: highlight ? AppColors.rsGoldLight : Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.barlow(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section title ────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label, this.trailing});

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.barlowCondensed(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.rsWhite,
            letterSpacing: 0.5,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Text(
            trailing!,
            style: GoogleFonts.dmMono(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: palette.text3,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Join / Leave button ──────────────────────────────────────────────

class _JoinLeaveButton extends StatelessWidget {
  const _JoinLeaveButton({required this.joined, required this.onTap});

  final bool joined;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Semantics(
      button: true,
      label: joined ? 'Already joined club' : 'Join club',
      child: GestureDetector(
        onTap: joined ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: joined ? RsColors.rsBlueGlow : RsColors.rsBlue,
            borderRadius: BorderRadius.circular(30),
            border: joined ? Border.all(color: RsColors.rsBlueBorder) : null,
          ),
          child: Text(
            joined ? '✓ Joined' : 'Join',
            style: GoogleFonts.barlowCondensed(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: joined ? palette.blue : AppColors.rsWhite,
            ),
          ),
        ),
      ),
    );
  }
}

class _FanClubDetailPill extends StatelessWidget {
  const _FanClubDetailPill({
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: highlighted
            ? AppColors.rsGold.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: highlighted
              ? AppColors.rsGold.withValues(alpha: 0.34)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: highlighted ? AppColors.rsGoldLight : AppColors.rsBluePale,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.barlow(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: highlighted
                  ? AppColors.rsGoldLight
                  : Colors.white.withValues(alpha: 0.82),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stat tile ────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Expanded(
      child: CoolCard(
        gradient: AppColors.cardGradient,
        borderColor: RsColors.rsBlueBorder,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Text(
                value,
                style: GoogleFonts.dmMono(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: RsColors.rsGoldLight,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.barlow(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: palette.text3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Member tile placeholder ──────────────────────────────────────────

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: palette.surface3,
            child: Text(
              '${index + 1}',
              style: GoogleFonts.dmMono(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: palette.text2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Member ${index + 1}',
                  style: GoogleFonts.barlow(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                  ),
                ),
                Text(
                  'Joined recently',
                  style: GoogleFonts.barlow(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: palette.text3,
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
