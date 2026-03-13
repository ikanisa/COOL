import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/config/deep_link_config.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/providers/referral_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_toast.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/rs_achievement_badge.dart';
import '../../../../shared/widgets/share_card.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/rayon_screen_scaffold.dart';
import '../../widgets/rayon_state_views.dart';

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

    return RayonScreenScaffold(
      title: 'Fan Club',
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

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Container(
                      height: 64,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: _regionGradient(club.region),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        club.bannerEmoji,
                        style: const TextStyle(fontSize: 32),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: RsColors.rsBlueGlow,
                            border: Border.all(
                              color: RsColors.rsBlueBorder,
                              width: 1.2,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            club.bannerEmoji,
                            style: const TextStyle(fontSize: 20),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                club.name,
                                style: GoogleFonts.barlowCondensed(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.rsWhite,
                                ),
                              ),
                              Text(
                                club.region,
                                style: GoogleFonts.barlow(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: RsColors.rsBluePale,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _JoinLeaveButton(
                          joined: joined,
                          onTap: joined
                              ? () {
                                  CoolToast.info(
                                    context,
                                    'Leave club coming soon.',
                                  );
                                }
                              : () => _join(context, ref, club.id),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        _StatTile(
                          label: 'Members',
                          value: '${club.memberCount}',
                        ),
                        const SizedBox(width: 10),
                        _StatTile(label: 'Events', value: '${club.eventCount}'),
                        const SizedBox(width: 10),
                        _StatTile(
                          label: 'Rating',
                          value: club.rating > 0
                              ? club.rating.toStringAsFixed(1)
                              : '—',
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (club.description.isNotEmpty) ...[
                      Text(
                        club.description,
                        style: GoogleFonts.barlow(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text2,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 22),
                    ],
                    if (detail.achievements.isNotEmpty) ...[
                      _SectionTitle(label: 'Club Achievements'),
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
                    _SectionTitle(
                      label: 'Members',
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
                      GestureDetector(
                        onTap: () {},
                        child: Text(
                          'View all ${club.memberCount} members',
                          style: GoogleFonts.barlow(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                    ],
                    ShareCard(
                      title: 'Invite supporters',
                      icon: Icons.campaign_rounded,
                      subtitle: 'Bring more fans into ${club.name}.',
                      shareUrl: DeepLinkConfig.clubUri(club.id).toString(),
                      shareText: 'Join ${club.name} on Cool.',
                      sheetTitle: 'Share Fan Club',
                      sheetSubtitle: 'Invite supporters to join ${club.name}.',
                      analyticsTargetType: 'rayon_club',
                      resolveShareUrl: () => _buildShareUrl(ref, club.id),
                    ),
                    const SizedBox(height: 22),
                    CoolButton(
                      label: joined ? 'Already Joined' : 'Join This Club',
                      onTap: joined
                          ? () {}
                          : () => _join(context, ref, club.id),
                      icon: Icons.groups_2_outlined,
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

// ── Section title ────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label, this.trailing});

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
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
              color: AppColors.text3,
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
    return GestureDetector(
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
            color: joined ? AppColors.blue : Colors.white,
          ),
        ),
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
                  color: AppColors.text3,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.surface3,
            child: Text(
              '${index + 1}',
              style: GoogleFonts.dmMono(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.text2,
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
                    color: AppColors.text,
                  ),
                ),
                Text(
                  'Joined recently',
                  style: GoogleFonts.barlow(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text3,
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
