import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_error_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../groups/group_flow_utils.dart';
import '../../groups/models/group.dart';
import '../models/home_dashboard_data.dart';
import 'home_shared.dart';

part 'home_communities_section.dart';
part 'home_operations_section.dart';
part 'home_sections_support.dart';


class HomeHeader extends StatelessWidget {
  const HomeHeader({
    required this.displayName,
    required this.initials,
    required this.avatarUrl,
    required this.onNotificationsTap,
    super.key,
  });

  final String displayName;
  final String initials;
  final String? avatarUrl;
  final VoidCallback onNotificationsTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;

    return Row(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            _ProfileAvatar(avatarUrl: avatarUrl, initials: initials),
            Positioned(
              right: -1,
              bottom: 2,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: colors.success,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.appBackground,
                    width: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: CoolSpace.x4),
        Expanded(
          child: Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.coolText.headline(
              theme.textTheme.headlineMedium,
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
        ),
        const SizedBox(width: CoolSpace.x3),
        _HomeIconButton(
          icon: Icons.notifications_none_rounded,
          onTap: onNotificationsTap,
        ),
      ],
    );
  }
}

class HomeSavingsHeroCard extends StatelessWidget {
  const HomeSavingsHeroCard({
    required this.totalSavingsRwf,
    required this.monthlyNetChange,
    required this.onOpenWallet,
    super.key,
  });

  final int totalSavingsRwf;
  final int? monthlyNetChange;
  final VoidCallback onOpenWallet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        onTap: onOpenWallet,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(CoolRadii.xl),
          child: DecoratedBox(
            decoration: BoxDecoration(
              // Hero gradient from tokens — no hardcoded values
              gradient: colors.heroGradient,
              borderRadius: BorderRadius.circular(CoolRadii.xl),
              boxShadow: CoolShadows.claymorphicCard(
                glowColor: colors.accentStrong,
                strength: 1.2,
              ),
            ),
            child: Stack(
              children: [
                // Inner top-edge highlight
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(CoolRadii.xl),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          colors.accentForeground.withValues(alpha: 0.18),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // Bottom inner shadow (depth)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(CoolRadii.xl),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: <Color>[
                          colors.shadowColor.withValues(alpha: 0.28),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // Card content
                Padding(
                  padding: const EdgeInsets.all(CoolSpace.x6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: CoolSpace.x4,
                          vertical: CoolSpace.x2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.accentForeground.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(CoolRadii.pill),
                        ),
                        child: Text(
                          'SAVINGS BALANCE',
                          style: context.coolText.mono(
                            theme.textTheme.labelSmall,
                            color: colors.accentForeground.withValues(alpha: 0.86),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: CoolSpace.x5),
                      Text(
                        '${fmtAmt(totalSavingsRwf)} RWF',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.coolText.headline(
                          theme.textTheme.displaySmall,
                          color: colors.accentForeground,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.8,
                          height: 0.92,
                        ),
                      ),
                      const SizedBox(height: CoolSpace.x5),
                      _MonthlyMovementPill(monthlyNetChange: monthlyNetChange),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({
    required this.title,
    this.trailing,
    super.key,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: context.coolText.headline(
              Theme.of(context).textTheme.headlineSmall,
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class HomeSectionActionPill extends StatelessWidget {
  const HomeSectionActionPill({
    required this.label,
    required this.onTap,
    super.key,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CoolRadii.pill),
        child: Ink(
          padding: const EdgeInsets.symmetric(
            horizontal: CoolSpace.x4,
            vertical: CoolSpace.x2,
          ),
          decoration: BoxDecoration(
            color: colors.appBackground,
            borderRadius: BorderRadius.circular(CoolRadii.pill),
          ),
          child: Text(
            label,
            style: context.coolText.mono(
              Theme.of(context).textTheme.labelSmall,
              color: colors.accent,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
            ),
          ),
        ),
      ),
    );
  }
}
