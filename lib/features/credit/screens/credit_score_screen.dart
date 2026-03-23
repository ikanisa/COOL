import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/providers/supabase_client_provider.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/cool_layout.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_glass_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/secure_screen_mixin.dart';
import '../models/credit_insights.dart';
import '../providers/credit_insights_provider.dart';

/// Agentic Credit Intelligence Screen.
///
/// Replaces static checklists with high-reasoning AI financial insights.
class CreditScoreScreen extends ConsumerWidget {
  const CreditScoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final insightsAsync = ref.watch(creditInsightsProvider);

    return SecureScreen(
      child: Scaffold(
        backgroundColor: colors.appBackground,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            onPressed: () => context.pop(),
            tooltip: 'Back',
            icon: Icon(Icons.arrow_back_rounded, color: colors.primaryText),
          ),
          title: Text(
            'Credit Agent',
            style: theme.textTheme.titleLarge?.copyWith(
              color: colors.primaryText,
            ),
          ),
          centerTitle: false,
          actions: [
            IconButton(
              onPressed: () => ref.invalidate(creditInsightsProvider),
              tooltip: 'Refresh',
              icon: Icon(
                Icons.refresh_rounded,
                color: colors.secondaryText,
                size: 20,
              ),
            ),
          ],
        ),
        body: CoolScreenBackground(
          child: SafeArea(
            top: false,
            child: insightsAsync.when(
              loading: () => const _LoadingState(),
              error: (err, stack) => _ErrorState(error: err.toString()),
              data: (insights) {
                if (insights == null) {
                  return const _EmptyState();
                }
                return _InsightsDashboard(insights: insights);
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _InsightsDashboard extends StatelessWidget {
  const _InsightsDashboard({required this.insights});

  final CreditInsights insights;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final insets = context.coolInsets;

    return SingleChildScrollView(
      padding: insets.fromLTRB(
        CoolSpace.x6,
        CoolSpace.x3,
        CoolSpace.x6,
        CoolLayout.rootBottomClearance,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Readiness Hero ──────────────────────────────
          _ReadinessHero(insights: insights),
          const SizedBox(height: CoolSpace.x6),

          // ── AI Spending Analysis ────────────────────────
          Text(
            'Spending analysis',
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          CoolCard(
            backgroundColor: colors.financialSurface,
            borderColor: colors.borderStrong,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: colors.accent,
                    ),
                    const SizedBox(width: CoolSpace.x2),
                    Text(
                      'AI AGENT INSIGHT',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.accent,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: CoolSpace.x3),
                Text(
                  insights.spendingAnalysis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.primaryText,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: CoolSpace.x6),

          // ── Key Strengths & Areas ───────────────────────
          _InsightGrids(insights: insights),
          const SizedBox(height: CoolSpace.x6),

          // ── Proactive Coaching ──────────────────────────
          Text(
            'Proactive coaching',
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          for (final tip in insights.proactiveTips) _CoachingCard(tip: tip),

          const SizedBox(height: CoolSpace.x7),

          // ── Credit Bridge Export ────────────────────────
          _CreditBridgeCard(insights: insights),
        ],
      ),
    );
  }
}

class _CreditBridgeCard extends StatefulWidget {
  const _CreditBridgeCard({required this.insights});
  final CreditInsights insights;

  @override
  State<_CreditBridgeCard> createState() => _CreditBridgeCardState();
}

class _CreditBridgeCardState extends State<_CreditBridgeCard> {
  bool _isGenerating = false;

  Future<void> _generateReport(WidgetRef ref) async {
    setState(() => _isGenerating = true);

    try {
      final client = ref.read(supabaseClientProvider);
      final response = await client.functions.invoke('create-financial-memo');

      if (response.data != null && response.data['success'] == true) {
        final _ = response.data['data']['doc_url'] as String;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.bankReportGeneratedIn),
              action: SnackBarAction(
                label: 'OPEN',
                onPressed: () {
                  // In production, use url_launcher to open the docUrl
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.failedToGenerateBank)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return CoolGlassCard(
      borderColor: colors.info.withValues(alpha: 0.15),
      padding: context.coolInsets.all(CoolSpace.x5),
      child: Column(
        children: [
          Icon(Icons.account_balance_rounded, color: colors.info, size: 32),
          const SizedBox(height: CoolSpace.x4),
          Text(
            'Official Bank Report',
            style: theme.textTheme.titleLarge?.copyWith(
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            'Generate a professional financial memo to use for loan applications at partner banks.',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.secondaryText,
              height: 1.45,
            ),
          ),
          const SizedBox(height: CoolSpace.x6),
          Consumer(
            builder: (context, ref, _) => CoolButton(
              label: 'Generate Google Doc',
              icon: Icons.description_rounded,
              isLoading: _isGenerating,
              onTap: () => _generateReport(ref),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadinessHero extends StatelessWidget {
  const _ReadinessHero({required this.insights});

  final CreditInsights insights;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final insets = context.coolInsets;
    final color = _readinessColor(insights.creditReadiness, colors);

    return CoolGlassCard(
      borderColor: colors.info.withValues(alpha: 0.2),
      padding: insets.all(CoolSpace.x5),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Credit Readiness',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x1),
                  Text(
                    insights.creditReadiness.toUpperCase(),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: color,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: insets.symmetric(
                  horizontal: CoolSpace.x3 + 2,
                  vertical: CoolSpace.x2,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: const BorderRadius.all(
                    Radius.circular(CoolRadii.xs),
                  ),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Text(
                      'EST. SCORE',
                      style: theme.textTheme.labelSmall?.copyWith(color: color),
                    ),
                    Text(
                      insights.estimatedScoreRange,
                      style: context.coolText.mono(
                        theme.textTheme.labelLarge,
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x5),
          _ScoreTrack(
            label: 'Savings Discipline',
            value: insights.savingsDisciplineScore / 100,
            color: colors.accent,
          ),
          const SizedBox(height: CoolSpace.x3),
          _ScoreTrack(
            label: 'Income Stability',
            value: insights.incomeStabilityScore / 100,
            color: colors.info,
          ),
        ],
      ),
    );
  }

  Color _readinessColor(String level, CoolSemanticColors colors) {
    return switch (level.toLowerCase()) {
      'excellent' => colors.accent,
      'high' => colors.info,
      'medium' => colors.warning,
      _ => colors.warning,
    };
  }
}

class _ScoreTrack extends StatelessWidget {
  const _ScoreTrack({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.primaryText,
              ),
            ),
            Text(
              '${(value * 100).toInt()}%',
              style: theme.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: CoolSpace.x1 + 2),
        ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.pill)),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 6,
            backgroundColor: color.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _InsightGrids extends StatelessWidget {
  const _InsightGrids({required this.insights});

  final CreditInsights insights;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _InsightList(
            title: 'STRENGTHS',
            items: insights.keyStrengths,
            color: colors.accent,
            icon: Icons.check_circle_outline_rounded,
          ),
        ),
        const SizedBox(width: CoolSpace.x4),
        Expanded(
          child: _InsightList(
            title: 'RISKS',
            items: insights.improvementAreas,
            color: colors.warning,
            icon: Icons.warning_amber_rounded,
          ),
        ),
      ],
    );
  }
}

class _InsightList extends StatelessWidget {
  const _InsightList({
    required this.title,
    required this.items,
    required this.color,
    required this.icon,
  });

  final String title;
  final List<String> items;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final insets = context.coolInsets;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.tertiaryText,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: CoolSpace.x2 + 2),
        for (final item in items)
          Padding(
            padding: insets.only(bottom: CoolSpace.x2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: CoolSpace.x1 + 2),
                Expanded(
                  child: Text(
                    item,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.secondaryText,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CoachingCard extends StatelessWidget {
  const _CoachingCard({required this.tip});

  final String tip;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final insets = context.coolInsets;
    return Container(
      margin: insets.only(bottom: CoolSpace.x2 + 2),
      padding: insets.all(CoolSpace.x4),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.sm)),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.info.withValues(alpha: 0.1),
            ),
            child: Icon(
              Icons.lightbulb_outline_rounded,
              size: 18,
              color: colors.info,
            ),
          ),
          const SizedBox(width: CoolSpace.x3 + 2),
          Expanded(
            child: Text(
              tip,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.primaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CircularProgressIndicator(
        color: context.coolSemanticColors.accent,
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(context.l10n.genericErrorText('loading insights: $error')),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(context.l10n.connectYourMomoTo));
  }
}