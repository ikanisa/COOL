import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../core/theme/rs_text_styles.dart';
import '../../../../features/auth/models/user_profile.dart';
import '../../../../features/auth/providers/auth_provider.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_toast.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_screen_background.dart';
import '../../../../shared/widgets/cool_skeleton.dart';
import '../../../../shared/widgets/rs_achievement_badge.dart';
import '../../../../shared/widgets/rs_progress_bar.dart';
import '../models/rs_models.dart';
import '../rayon_payment.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/partner_navigation.dart';
import '../widgets/rs_tier_badge.dart';

class FanProfileScreen extends ConsumerStatefulWidget {
  const FanProfileScreen({super.key});

  @override
  ConsumerState<FanProfileScreen> createState() => _FanProfileScreenState();
}

class _FanProfileScreenState extends ConsumerState<FanProfileScreen> {
  bool _isRecoveringMembership = false;

  Future<void> _ensureMembership(BuildContext context) async {
    if (_isRecoveringMembership) {
      return;
    }

    setState(() => _isRecoveringMembership = true);
    final notifier = ref.read(rayonSportsProvider.notifier);

    try {
      final result = await notifier.ensureMembership();
      ref.invalidate(rayonUserMembershipProvider);
      ref.invalidate(rayonUserAchievementsProvider);

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
      if (mounted) {
        setState(() => _isRecoveringMembership = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final membershipAsync = ref.watch(rayonUserMembershipProvider);
    final achievementsAsync = ref.watch(rayonUserAchievementsProvider);
    final ticketsAsync = ref.watch(rayonUserTicketsProvider);
    final ordersAsync = ref.watch(rayonShopOrdersProvider);
    final paymentRoute = ref.watch(rayonPaymentRouteProvider).valueOrNull;
    final user = ref.watch(currentUserProvider);

    final tickets = ticketsAsync.valueOrNull ?? const <RsTicket>[];

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CoolScreenBackground(
        primaryColor: RsColors.rsBlue,
        secondaryColor: RsColors.rsGold,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 0,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: buildPartnerBackButton(
                context,
                fallbackLocation: AppRoutes.rayonHome,
              ),
              title: Text(
                'Fan Profile',
                style: RsTextStyles.sectionTitle(color: RsColors.rsWhite),
              ),
              actions: buildPartnerAppBarActions(context),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 96),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  membershipAsync.when(
                    data: (membership) => _ProfileHero(
                      membership: membership,
                      user: user,
                      matchesAttended: _matchesAttended(tickets),
                      isRecoveringMembership: _isRecoveringMembership,
                      onRecoverMembership: () => _ensureMembership(context),
                    ),
                    loading: () => const CoolSkeleton.card(),
                    error: (error, stackTrace) => _ProfileHero(
                      membership: null,
                      user: user,
                      matchesAttended: _matchesAttended(tickets),
                      isRecoveringMembership: _isRecoveringMembership,
                      onRecoverMembership: () => _ensureMembership(context),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Achievements',
                    style: RsTextStyles.sectionTitle(color: RsColors.rsWhite),
                  ),
                  const SizedBox(height: 12),
                  achievementsAsync.when(
                    data: (achievements) => SizedBox(
                      height: 106,
                      child: achievements.isEmpty
                          ? const _EmptyStrip(
                              message: 'No achievements unlocked yet.',
                            )
                          : ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: achievements.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(width: 14),
                              itemBuilder: (context, index) =>
                                  RsAchievementBadge(
                                    achievement: achievements[index],
                                  ),
                            ),
                    ),
                    loading: () => const SizedBox(
                      height: 106,
                      child: _AchievementSkeletonRow(),
                    ),
                    error: (error, stackTrace) => const SizedBox(
                      height: 106,
                      child: _EmptyStrip(message: 'Achievements unavailable.'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Recent Orders',
                    style: RsTextStyles.sectionTitle(color: RsColors.rsWhite),
                  ),
                  const SizedBox(height: 12),
                  _RecentOrdersSection(
                    ordersAsync: ordersAsync,
                    paymentRoute: paymentRoute,
                  ),
                  const SizedBox(height: 24),
                  membershipAsync.when(
                    data: (membership) =>
                        _PerksAccessCard(membership: membership, user: user),
                    loading: () => const CoolSkeleton.card(),
                    error: (error, stackTrace) =>
                        _PerksAccessCard(membership: null, user: user),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.membership,
    required this.user,
    required this.matchesAttended,
    required this.isRecoveringMembership,
    required this.onRecoverMembership,
  });

  final RsFanMembership? membership;
  final UserProfile? user;
  final int matchesAttended;
  final bool isRecoveringMembership;
  final Future<void> Function() onRecoverMembership;

  @override
  Widget build(BuildContext context) {
    final fanName = membership?.displayName ?? user?.displayUserId ?? '000000';
    final tier = membership?.tier ?? FanTier.blue;
    final chapter = membership?.chapter ?? 'Official membership pending';
    final joinedYear = membership?.joinedAt.year;
    final fanId = _displayId(user, membership);
    final initials = _initials(fanName);
    final progressMeta = membership == null
        ? null
        : _progressMeta(membership!.points, tier);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RsColors.rsHeroGradient,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: RsColors.rsBlueBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
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
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [RsColors.rsBlueLight, RsColors.rsBlue],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: AppColors.rsWhite, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initials,
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: AppColors.rsWhite,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fanName,
                          style: GoogleFonts.barlow(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.rsWhite,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          fanId,
                          style: GoogleFonts.dmMono(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            RsTierBadge(tier: tier),
                            const SizedBox(width: 10),
                            _ChapterChip(label: chapter),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (progressMeta != null)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Fan Points',
                            style: GoogleFonts.barlow(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.rsWhite,
                            ),
                          ),
                          const Spacer(),
                          Flexible(
                            child: Text(
                              '${progressMeta.current} / ${progressMeta.threshold} pts → ${progressMeta.targetTierLabel}',
                              textAlign: TextAlign.end,
                              style: GoogleFonts.dmMono(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.rsGoldLight,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      RsProgressBar(
                        progress: progressMeta.progress,
                        fillColor: RsColors.rsGold,
                        height: 10,
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No membership found yet. Tickets and shop still work.',
                        style: GoogleFonts.barlow(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.rsWhite,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 14),
                      CoolButton(
                        label: 'Create / Restore Membership',
                        onTap: () {
                          onRecoverMembership();
                        },
                        isLoading: isRecoveringMembership,
                        icon: Icons.verified_user_outlined,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 18),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _StatCell(
                        value: '$matchesAttended',
                        label: 'Matches attended',
                      ),
                    ),
                    _divider(),
                    Expanded(
                      child: _StatCell(
                        value: _tierName(tier).toUpperCase(),
                        label: 'Tier',
                      ),
                    ),
                    _divider(),
                    Expanded(
                      child: _StatCell(
                        value: joinedYear == null
                            ? 'Pending'
                            : '${DateTime.now().year - joinedYear + 1}',
                        label: joinedYear == null
                            ? 'Membership'
                            : 'Years member',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(width: 1, height: 48, color: AppColors.border);
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      child: Column(
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.rsWhite,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.text3,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChapterChip extends StatelessWidget {
  const _ChapterChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.rsWhite.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: GoogleFonts.barlow(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.rsWhite.withValues(alpha: 0.82),
          ),
        ),
      ),
    );
  }
}

class _PerksAccessCard extends StatelessWidget {
  const _PerksAccessCard({required this.membership, required this.user});

  final RsFanMembership? membership;
  final UserProfile? user;

  @override
  Widget build(BuildContext context) {
    final tier = membership?.tier ?? FanTier.blue;
    final currentTierIndex = FanTier.values.indexOf(tier);
    final benefits = _benefitsForDisplay(tier);
    final fanId = _displayId(user, membership);
    final hasMembership = membership != null;

    return CoolCard(
      gradient: AppColors.cardGradient,
      borderColor: AppColors.rsBlueBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Perks & access',
                  style: RsTextStyles.sectionTitle(color: RsColors.rsWhite),
                ),
              ),
              if (hasMembership) RsTierBadge(tier: tier),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hasMembership
                ? 'Your membership is ready for supporter pricing, match access, and club checkpoints.'
                : 'Create membership to unlock supporter pricing and stadium access.',
            style: GoogleFonts.barlow(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          ...benefits.map((benefit) {
            final active = currentTierIndex >= benefit.minTierIndex;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PerkRow(benefit: benefit, active: active),
            );
          }),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border2),
            ),
            child: Row(
              children: [
                if (hasMembership)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.rsWhite,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: QrImageView(
                        data: fanId,
                        size: 88,
                        backgroundColor: Colors.transparent,
                        eyeStyle: const QrEyeStyle(
                          color: RsColors.rsBlue,
                          eyeShape: QrEyeShape.square,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          color: RsColors.rsBlue,
                          dataModuleShape: QrDataModuleShape.square,
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    width: 108,
                    height: 108,
                    decoration: BoxDecoration(
                      color: AppColors.surface3,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border2),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.qr_code_2_rounded,
                      size: 42,
                      color: AppColors.text3,
                    ),
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasMembership ? 'Fan access QR' : 'Fan access pending',
                        style: GoogleFonts.barlow(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.rsWhite,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        hasMembership
                            ? '$fanId • ${_tierName(tier).toUpperCase()}'
                            : 'QR appears once membership is created.',
                        style: GoogleFonts.dmMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: hasMembership
                              ? AppColors.accent
                              : AppColors.text2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        hasMembership
                            ? 'Show this at stadium gates and member checkpoints.'
                            : 'Tickets and shop still work while membership is pending.',
                        style: GoogleFonts.barlow(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text2,
                          height: 1.4,
                        ),
                      ),
                    ],
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

class _PerkRow extends StatelessWidget {
  const _PerkRow({required this.benefit, required this.active});

  final _BenefitItem benefit;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(benefit.icon, size: 22, color: AppColors.text2),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  benefit.title,
                  style: GoogleFonts.barlow(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.rsWhite,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  benefit.subtitle,
                  style: GoogleFonts.barlow(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: active ? AppColors.accentGlow : AppColors.surface3,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: active
                    ? AppColors.accent.withValues(alpha: 0.35)
                    : AppColors.border,
              ),
            ),
            child: Text(
              active ? 'Active' : 'Upgrade',
              style: GoogleFonts.barlow(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: active ? AppColors.accent : AppColors.text3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStrip extends StatelessWidget {
  const _EmptyStrip({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      gradient: AppColors.cardGradient,
      borderColor: AppColors.rsBlueBorder,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentOrdersSection extends StatelessWidget {
  const _RecentOrdersSection({
    required this.ordersAsync,
    required this.paymentRoute,
  });

  final AsyncValue<List<RsShopOrder>> ordersAsync;
  final PartnerPaymentRoute? paymentRoute;

  @override
  Widget build(BuildContext context) {
    return ordersAsync.when(
      data: (orders) {
        if (orders.isEmpty) {
          return const _EmptyStrip(message: 'No shop orders yet.');
        }

        final recentOrders = orders.take(3).toList(growable: false);
        return Column(
          children: recentOrders
              .map(
                (order) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _OrderStatusCard(
                    order: order,
                    paymentRoute: paymentRoute,
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
      loading: () => const CoolSkeleton.card(),
      error: (error, stackTrace) => const _EmptyStrip(
        message: 'Order history is temporarily unavailable.',
      ),
    );
  }
}

class _OrderStatusCard extends StatelessWidget {
  const _OrderStatusCard({required this.order, required this.paymentRoute});

  final RsShopOrder order;
  final PartnerPaymentRoute? paymentRoute;

  @override
  Widget build(BuildContext context) {
    final color = _orderStatusColor(order.status);

    return CoolCard(
      gradient: AppColors.cardGradient,
      borderColor: AppColors.rsBlueBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Order ${order.status.label.toUpperCase()}',
                  style: GoogleFonts.barlow(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.rsWhite,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color.withValues(alpha: 0.28)),
                ),
                child: Text(
                  order.status.label,
                  style: GoogleFonts.barlow(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${_formatRwf(order.total)} • ${DateFormat('dd MMM, HH:mm').format(order.createdAt)}',
            style: GoogleFonts.dmMono(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            order.deliveryAddress,
            style: GoogleFonts.barlow(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _orderStatusCopy(order.status, paymentRoute),
            style: GoogleFonts.barlow(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementSkeletonRow extends StatelessWidget {
  const _AchievementSkeletonRow();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: 4,
      separatorBuilder: (context, index) => const SizedBox(width: 14),
      itemBuilder: (context, index) => const Column(
        children: [
          CoolSkeleton(width: 56, height: 56, borderRadius: 28),
          SizedBox(height: 8),
          CoolSkeleton(width: 64, height: 14, borderRadius: 6),
        ],
      ),
    );
  }
}

class _ProgressMeta {
  const _ProgressMeta({
    required this.current,
    required this.threshold,
    required this.targetTierLabel,
    required this.progress,
  });

  final int current;
  final int threshold;
  final String targetTierLabel;
  final double progress;
}

class _BenefitItem {
  const _BenefitItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.minTierIndex,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int minTierIndex;
}

_ProgressMeta _progressMeta(int points, FanTier tier) {
  switch (tier) {
    case FanTier.blue:
      return _ProgressMeta(
        current: points,
        threshold: 1000,
        targetTierLabel: 'Silver',
        progress: (points / 1000).clamp(0, 1).toDouble(),
      );
    case FanTier.silver:
      return _ProgressMeta(
        current: points,
        threshold: 2000,
        targetTierLabel: 'Gold',
        progress: (points / 2000).clamp(0, 1).toDouble(),
      );
    case FanTier.gold:
      return _ProgressMeta(
        current: points,
        threshold: 5000,
        targetTierLabel: 'Platinum',
        progress: (points / 5000).clamp(0, 1).toDouble(),
      );
    case FanTier.platinum:
      return _ProgressMeta(
        current: points,
        threshold: 5000,
        targetTierLabel: 'Platinum',
        progress: 1,
      );
  }
}

int _matchesAttended(List<RsTicket> tickets) {
  if (tickets.isEmpty) {
    return 0;
  }
  return tickets.where((ticket) => ticket.status == RsTicketStatus.used).length;
}

String _displayId(UserProfile? user, RsFanMembership? membership) {
  if (membership != null && membership.membershipNumber.isNotEmpty) {
    return membership.membershipNumber;
  }
  return user?.displayUserId ?? 'Membership pending';
}

String _initials(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return 'RS';
  }
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  return trimmed.substring(0, trimmed.length >= 2 ? 2 : 1).toUpperCase();
}

String _tierName(FanTier tier) => switch (tier) {
  FanTier.blue => 'Blue',
  FanTier.silver => 'Silver',
  FanTier.gold => 'Gold',
  FanTier.platinum => 'Platinum',
};

List<_BenefitItem> _benefitsForDisplay(FanTier tier) {
  final gold = <_BenefitItem>[
    const _BenefitItem(
      icon: Icons.confirmation_number_rounded,
      title: 'Priority Tickets',
      subtitle: 'Get earlier access to on-sale match entries.',
      minTierIndex: 2,
    ),
    const _BenefitItem(
      icon: Icons.shopping_bag_rounded,
      title: '10% Shop',
      subtitle: 'Unlock supporter pricing on official club gear.',
      minTierIndex: 2,
    ),
    const _BenefitItem(
      icon: Icons.auto_awesome_rounded,
      title: 'VIP Events',
      subtitle: 'Access select fan sessions and special event queues.',
      minTierIndex: 2,
    ),
  ];

  if (tier == FanTier.platinum) {
    return <_BenefitItem>[
      ...gold,
      const _BenefitItem(
        icon: Icons.handshake_rounded,
        title: 'Meet & Greet',
        subtitle: 'Join premium player and club meetups when available.',
        minTierIndex: 3,
      ),
      const _BenefitItem(
        icon: Icons.checkroom_rounded,
        title: 'Free Kit',
        subtitle: 'Receive one complimentary official kit each season.',
        minTierIndex: 3,
      ),
    ];
  }

  return gold;
}

String _formatRwf(int amount) {
  return '${NumberFormat.decimalPattern('en').format(amount)} RWF';
}

Color _orderStatusColor(OrderStatus status) {
  return switch (status) {
    OrderStatus.pending => RsColors.rsGoldLight,
    OrderStatus.confirmed => AppColors.accent,
    OrderStatus.shipped => RsColors.rsBluePale,
    OrderStatus.delivered => AppColors.rsWhite,
    OrderStatus.cancelled => AppColors.text3,
  };
}

String _orderStatusCopy(OrderStatus status, PartnerPaymentRoute? paymentRoute) {
  return switch (status) {
    OrderStatus.pending =>
      paymentRoute == null
          ? 'Waiting for payment confirmation before fulfillment starts.'
          : 'Waiting for SMS reconciliation for ${paymentRoute.reconciliationLabel} before fulfillment starts.',
    OrderStatus.confirmed =>
      'Payment confirmed. Order is queued for processing.',
    OrderStatus.shipped => 'Order has left the shop and is on the way.',
    OrderStatus.delivered => 'Order marked as delivered.',
    OrderStatus.cancelled => 'Order was cancelled before completion.',
  };
}
