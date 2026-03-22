import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_skeleton.dart';
import '../../../../shared/widgets/rs_initiative_card.dart';

import '../../providers/rayon_sports_provider.dart';
import '../../widgets/rayon_screen_scaffold.dart';
import '../../../../core/l10n/l10n.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final theme = Theme.of(context);
        final initiativesAsync = ref.watch(rayonInitiativesProvider);
        final summaryAsync = ref.watch(rayonInitiativesSummaryProvider);

        return RayonScreenScaffold(
          title: context.l10n.supportClub,
          fallbackLocation: AppRoutes.rayonHome,
          scrollable: false,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _SupportIntroCard(summary: summaryAsync.valueOrNull),
                    const SizedBox(height: CoolSpace.x7),
                    Text(
                      'Active Causes',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x4),
                  ]),
                ),
              ),
              ...initiativesAsync.when(
                loading: () => <Widget>[
                  const SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(child: CoolSkeletonList()),
                  ),
                ],
                error: (error, stackTrace) => <Widget>[
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(
                      child: _StateCard(
                        icon: Icons.warning_amber_rounded,
                        title: 'Failed to load causes',
                        subtitle: 'Pull to retry',
                        actionLabel: 'Retry',
                        onTap: () => ref.invalidate(rayonInitiativesProvider),
                      ),
                    ),
                  ),
                ],
                data: (initiatives) {
                  if (initiatives.isEmpty) {
                    return const <Widget>[
                      SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverToBoxAdapter(
                          child: _EmptyInitiativesState(),
                        ),
                      ),
                    ];
                  }

                  return <Widget>[
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final initiative = initiatives[index];
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: index == initiatives.length - 1 ? 0 : 14,
                            ),
                            child: RsInitiativeCard(
                              initiative: initiative,
                              onTap: () => context.push(
                                '/partners/rayon-sports/support/${initiative.id}',
                              ),
                              onSupportTap: () => context.push(
                                '/partners/rayon-sports/support/${initiative.id}',
                              ),
                            ),
                          );
                        }, childCount: initiatives.length),
                      ),
                    ),
                  ];
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        );
      },
    );
  }
}

class _SupportIntroCard extends StatelessWidget {
  const _SupportIntroCard({required this.summary});

  final RayonInitiativesSummary? summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return CoolCard(
      borderColor: colors.borderStrong,
      gradient: AppColors.cardGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Official support network',
            style: theme.textTheme.labelLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.74),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          Text(
            'Club causes, verified giving, and visible impact for every contribution.',
            style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: CoolSpace.x3),
          Text(
            'Each initiative is structured for fast scanning, credible fundraising, and direct supporter action.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: CoolSpace.x6),
          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  value: summary == null
                      ? '--'
                      : _formatRwf(summary!.totalRaised),
                  label: 'Raised',
                  surfaceColor: colors.financialSurface,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryMetric(
                  value: summary == null
                      ? '--'
                      : _compactCount(summary!.totalSupporters),
                  label: 'Supporters',
                  surfaceColor: colors.proximitySurface,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryMetric(
                  value: summary == null ? '--' : '${summary!.activeCauses}',
                  label: 'Causes',
                  surfaceColor: colors.teamSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.value,
    required this.label,
    required this.surfaceColor,
  });

  final String value;
  final String label;
  final Color surfaceColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(CoolSpace.x4),
      decoration: BoxDecoration(
        color: surfaceColor.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(CoolRadii.md),
        border: Border.all(color: colors.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontFamily: GoogleFonts.dmMono().fontFamily,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyInitiativesState extends StatelessWidget {
  const _EmptyInitiativesState();

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return CoolCard(
      backgroundColor: colors.cardSurfaceStrong.withValues(alpha: 0.86),
      borderColor: colors.borderStrong,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CoolSpace.x3),
        child: Column(
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: colors.teamSurface,
                borderRadius: BorderRadius.circular(CoolRadii.lg),
                border: Border.all(color: colors.borderStrong),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.stadium_rounded,
                size: 34,
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: CoolSpace.x5),
            Text(
              'No active causes right now',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: CoolSpace.x2),
            Text(
              'Check back soon for new fundraising programs and club-backed initiatives.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.secondaryText,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return CoolCard(
      borderColor: colors.borderStrong,
      backgroundColor: colors.cardSurfaceStrong.withValues(alpha: 0.86),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CoolSpace.x3),
        child: Column(
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: colors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(CoolRadii.lg),
                border: Border.all(
                  color: colors.warning.withValues(alpha: 0.2),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 34, color: colors.warning),
            ),
            const SizedBox(height: CoolSpace.x5),
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: CoolSpace.x2),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.secondaryText,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: CoolSpace.x5),
            CoolButton(
              label: actionLabel,
              variant: CoolButtonVariant.secondary,
              fullWidth: false,
              onTap: onTap,
            ),
          ],
        ),
      ),
    );
  }
}

String _formatRwf(int amount) {
  return 'RWF ${NumberFormat.decimalPattern('en').format(amount)}';
}

String _compactCount(int count) {
  if (count >= 1000000) {
    return NumberFormat.compact(locale: 'en').format(count);
  }
  if (count >= 1000) {
    return NumberFormat.compact(locale: 'en').format(count);
  }
  return '$count';
}
