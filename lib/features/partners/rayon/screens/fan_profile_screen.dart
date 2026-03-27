import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../core/theme/rs_text_styles.dart';
import '../../../../features/auth/models/user_profile.dart';
import '../../../../features/auth/providers/auth_provider.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_toast.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_skeleton.dart';
import '../../../../shared/widgets/rs_achievement_badge.dart';
import '../../../../shared/widgets/rs_progress_bar.dart';
import '../models/rs_models.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../../../shared/widgets/core_app_scaffold.dart';
import '../widgets/rs_tier_badge.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../shared/widgets/cool_bottom_sheet.dart';

part '../widgets/fan_profile_parts.dart';

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
    final ordersAsync = ref.watch(rayonShopOrdersProvider);
    final user = ref.watch(currentUserProvider);

    return CoreAppScaffold(
      title: context.l10n.fanProfile,
      fallbackLocation: AppRoutes.rayonHome,
      scrollable: false,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 96),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                membershipAsync.when(
                  data: (membership) => _ProfileHero(
                    membership: membership,
                    user: user,
                    isRecoveringMembership: _isRecoveringMembership,
                    onRecoverMembership: () => _ensureMembership(context),
                  ),
                  loading: () => const CoolSkeleton.card(),
                  error: (error, stackTrace) => _ProfileHero(
                    membership: null,
                    user: user,
                    isRecoveringMembership: _isRecoveringMembership,
                    onRecoverMembership: () => _ensureMembership(context),
                  ),
                ),
                const SizedBox(height: CoolSpace.x7),
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 12),
                  child: Text(
                    'ACHIEVEMENTS'.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: RsColors.rsWhite.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                achievementsAsync.when(
                  data: (achievements) => SizedBox(
                    height: 120,
                    child: achievements.isEmpty
                        ? const _EmptyStrip(
                            message: 'No achievements unlocked yet.',
                          )
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: achievements.length,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            separatorBuilder: (context, index) =>
                                const SizedBox(width: 16),
                            itemBuilder: (context, index) => RsAchievementBadge(
                              achievement: achievements[index],
                            ),
                          ),
                  ),
                  loading: () => const SizedBox(
                    height: 120,
                    child: _AchievementSkeletonRow(),
                  ),
                  error: (error, stackTrace) => const SizedBox(
                    height: 120,
                    child: _EmptyStrip(message: 'Achievements unavailable.'),
                  ),
                ),
                const SizedBox(height: CoolSpace.x7),
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 12),
                  child: Text(
                    'RECENT ORDERS'.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: RsColors.rsWhite.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                _RecentOrdersSection(ordersAsync: ordersAsync),
                const SizedBox(height: CoolSpace.x7),
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
    );
  }
}
