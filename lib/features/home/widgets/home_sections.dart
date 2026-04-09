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

class HomeBackdrop extends StatelessWidget {
  const HomeBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(color: HomeVisualPalette.background),
        ),
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0xFF0A0D13),
                  HomeVisualPalette.background,
                  HomeVisualPalette.background,
                ],
                stops: <double>[0.0, 0.32, 1.0],
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.15, -0.9),
                radius: 0.95,
                colors: <Color>[
                  HomeVisualPalette.heroGlow.withValues(alpha: 0.26),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(1.15, -0.4),
                radius: 0.9,
                colors: <Color>[
                  HomeVisualPalette.heroStart.withValues(alpha: 0.10),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

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
                  color: HomeVisualPalette.success,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: HomeVisualPalette.background,
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
            // Space Grotesk — name is the identity anchor
            style: context.coolText.headline(
              theme.textTheme.headlineMedium,
              color: HomeVisualPalette.textPrimary,
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(40),
        onTap: onOpenWallet,
        // Claymorphic card: clip so inner overlay is constrained
        child: ClipRRect(
          borderRadius: BorderRadius.circular(40),
          child: DecoratedBox(
            decoration: BoxDecoration(
              // Richer multi-stop gradient — deep navy → electric indigo
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color(0xFF1A2B6B), // deep navy
                  HomeVisualPalette.heroStart,
                  HomeVisualPalette.heroEnd,
                  Color(0xFF2B1F8A), // electric indigo base
                ],
                stops: <double>[0.0, 0.38, 0.70, 1.0],
              ),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.22),
                width: 1.5,
              ),
              boxShadow: CoolShadows.claymorphicCard(
                glowColor: HomeVisualPalette.heroGlow,
                strength: 1.2,
              ),
            ),
            child: Stack(
              children: [
                // Inner top-edge highlight (claymorphic tactile cue)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(40),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Colors.white.withValues(alpha: 0.18),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // Bottom-left inner shadow (depth)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(40),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: <Color>[
                          Colors.black.withValues(alpha: 0.22),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // Card content
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CoolSpace.x6,
                    CoolSpace.x6,
                    CoolSpace.x6,
                    CoolSpace.x6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: CoolSpace.x4,
                          vertical: CoolSpace.x2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(CoolRadii.pill),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                        child: Text(
                          'SAVINGS BALANCE',
                          style: context.coolText.mono(
                            theme.textTheme.labelSmall,
                            color: Colors.white.withValues(alpha: 0.86),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: CoolSpace.x5),
                      // Space Grotesk w900 — maximum financial authority
                      Text(
                        '${fmtAmt(totalSavingsRwf)} RWF',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.coolText.headline(
                          theme.textTheme.displaySmall,
                          color: Colors.white,
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
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            // Space Grotesk — section headers command presence
            style: context.coolText.headline(
              Theme.of(context).textTheme.headlineSmall,
              color: HomeVisualPalette.textPrimary,
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
            color: HomeVisualPalette.surfaceMuted,
            borderRadius: BorderRadius.circular(CoolRadii.pill),
            border: Border.all(color: HomeVisualPalette.outline),
          ),
          child: Text(
            label,
            style: context.coolText.mono(
              Theme.of(context).textTheme.labelSmall,
              color: HomeVisualPalette.active,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
            ),
          ),
        ),
      ),
    );
  }
}
