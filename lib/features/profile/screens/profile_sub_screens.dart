import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/notification_settings_provider.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/services/fcm_service.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/rs_colors.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../providers/profile_view_provider.dart';

part 'profile_sub_screens_account.dart';
part 'profile_sub_screens_support.dart';
part 'profile_sub_screens_about.dart';

// ═════════════════════════════════════════════════════════════════════
// REUSABLE SCAFFOLD (shared across all profile sub-screens)
// ═════════════════════════════════════════════════════════════════════

class _ProfileSubScaffold extends StatelessWidget {
  const _ProfileSubScaffold({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.slivers,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final topPad = MediaQuery.viewPaddingOf(context).top;
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: colors.appBackground,
      body: CoolScreenBackground(
        child: CustomScrollView(
          slivers: [
            // ── Header ───────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  CoolSpace.x4,
                  topPad + CoolSpace.x3,
                  CoolSpace.x4,
                  0,
                ),
                child: Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(CoolRadii.pill),
                      onTap: () {
                        if (context.canPop()) context.pop();
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: colors.primaryText,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: CoolSpace.x3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: context.coolText.rayonCondensed(
                              Theme.of(context).textTheme.headlineSmall,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            subtitle,
                            style: context.coolText.mono(
                              Theme.of(context).textTheme.labelSmall,
                              fontWeight: FontWeight.w700,
                              color: colors.secondaryText,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: RsColors.rsRed.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(icon, color: RsColors.rsRed, size: 22),
                    ),
                  ],
                ),
              ),
            ),

            // ── Body ─────────────────────────────────────────────
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                CoolSpace.x5,
                CoolSpace.x5,
                CoolSpace.x5,
                CoolSpace.x8 + bottomPad + 80,
              ),
              sliver: SliverList.list(children: slivers),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// SHARED BUILDING BLOCKS
// ═════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Text(
      label,
      style: context.coolText.mono(
        Theme.of(context).textTheme.labelSmall,
        fontWeight: FontWeight.w700,
        color: colors.secondaryText,
        letterSpacing: 2.0,
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: CoolSpace.x5,
        vertical: CoolSpace.x4,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CoolSpace.x3),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(CoolRadii.md),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: colors.primaryText, size: 20),
          ),
          const SizedBox(width: CoolSpace.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.coolText.mono(
                    Theme.of(context).textTheme.labelSmall,
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: context.coolText.mono(
                    Theme.of(context).textTheme.titleSmall,
                    fontWeight: FontWeight.w800,
                    color: valueColor ?? colors.primaryText,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, color: Colors.white.withValues(alpha: 0.06));
  }
}
