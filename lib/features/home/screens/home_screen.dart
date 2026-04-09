import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_screen_background.dart';

import '../providers/home_dashboard_provider.dart';
import '../widgets/home_quick_services.dart';
import '../widgets/home_shared.dart';

// ─────────────────────────────────────────────────────────────────────
// HomeScreen — COOL dashboard (post-RS purge)
// Sections: App Bar → Welcome → Dashboard Stats → Quick Services
// ─────────────────────────────────────────────────────────────────────

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: colors.appBackground,
      body: CoolScreenBackground(
        child: Consumer(
          builder: (context, ref, _) {
            final dashboard = ref.watch(homeDashboardProvider).asData?.value;

            return CustomScrollView(
              slivers: [
                // ── 0. App Bar ──────────────────────────────────────
                SliverAppBar(
                  backgroundColor: colors.appBackground,
                  surfaceTintColor: Colors.transparent,
                  pinned: true,
                  floating: true,
                  elevation: 0,
                  leadingWidth: 72,
                  leading: Padding(
                    padding: const EdgeInsets.only(left: CoolSpace.x5),
                    child: Center(
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: colors.cardSurfaceStrong,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colors.border,
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          Icons.person_outline_rounded,
                          color: colors.accent,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'COOL',
                        style: context.coolText.mono(
                          Theme.of(context).textTheme.titleMedium,
                          fontWeight: FontWeight.w800,
                          color: colors.primaryText,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Content padding ────────────────────────────────
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    CoolSpace.x5,
                    CoolSpace.x3,
                    CoolSpace.x5,
                    CoolSpace.x8 + bottomPad + 80,
                  ),
                  sliver: SliverList.list(
                    children: [
                      // ── Dashboard Balance ──────────────────────
                      if (dashboard != null) ...[
                        HomeGlassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'TOTAL BALANCE',
                                style: context.coolText.mono(
                                  Theme.of(context).textTheme.labelSmall,
                                  fontWeight: FontWeight.w700,
                                  color: colors.secondaryText,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: CoolSpace.x2),
                              Text(
                                '${fmtAmt(dashboard.totalBalance)} RWF',
                                style: context.coolText.heroNumber(
                                  color: colors.primaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: CoolSpace.x5),
                      ],

                      // ── Quick Services ────────────────────────
                      const HomeQuickServices(),
                      const SizedBox(height: CoolSpace.x5),

                      // ── Groups CTA ────────────────────────────
                      HomeGlassCard(
                        onTap: () => context.push(AppRoutes.groups),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: colors.teamSurface,
                                borderRadius:
                                    BorderRadius.circular(CoolRadii.sm),
                                border: Border.all(color: colors.border),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.groups_rounded,
                                color: colors.success,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: CoolSpace.x4),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'CONTRIBUTION GROUPS',
                                    style: context.coolText.mono(
                                      Theme.of(context).textTheme.labelSmall,
                                      fontWeight: FontWeight.w700,
                                      color: colors.secondaryText,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Save together',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: colors.tertiaryText,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: colors.secondaryText,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: CoolSpace.x5),

                      // ── MoMo CTA ─────────────────────────────
                      HomeGlassCard(
                        onTap: () => context.push(AppRoutes.momo),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: colors.financialSurface,
                                borderRadius:
                                    BorderRadius.circular(CoolRadii.sm),
                                border: Border.all(color: colors.border),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.phone_android_rounded,
                                color: colors.warning,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: CoolSpace.x4),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'MOMO SMS PARSER',
                                    style: context.coolText.mono(
                                      Theme.of(context).textTheme.labelSmall,
                                      fontWeight: FontWeight.w700,
                                      color: colors.secondaryText,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Smart payment tracking',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: colors.tertiaryText,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: colors.secondaryText,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
