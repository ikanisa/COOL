import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../models/credit_insights.dart';
import '../providers/credit_insights_provider.dart';

/// Agentic Credit Intelligence Screen.
/// 
/// Replaces static checklists with high-reasoning AI financial insights.
class CreditScoreScreen extends ConsumerWidget {
  const CreditScoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.coolPalette;
    final insightsAsync = ref.watch(creditInsightsProvider);

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: Icon(Icons.arrow_back_rounded, color: palette.text),
        ),
        title: Text(
          'Credit Agent',
          style: GoogleFonts.dmSans(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: palette.text,
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(creditInsightsProvider),
            icon: Icon(Icons.refresh_rounded, color: palette.text2, size: 20),
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
              if (insights == null) return const _EmptyState();
              return _InsightsDashboard(insights: insights);
            },
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
    final palette = context.coolPalette;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Readiness Hero ──────────────────────────────
          _ReadinessHero(insights: insights),
          const SizedBox(height: 24),

          // ── AI Spending Analysis ────────────────────────
          Text(
            'Spending analysis',
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 12),
          CoolCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Text(
                      'AI AGENT INSIGHT',
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.accent,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  insights.spendingAnalysis,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: palette.text,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Key Strengths & Areas ───────────────────────
          _InsightGrids(insights: insights),
          const SizedBox(height: 24),

          // ── Proactive Coaching ──────────────────────────
          Text(
            'Proactive coaching',
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 12),
          for (final tip in insights.proactiveTips)
            _CoachingCard(tip: tip),

          const SizedBox(height: 32),

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
        final docUrl = response.data['data']['doc_url'] as String;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Bank Report generated in Google Docs!'),
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
          const SnackBar(content: Text('Failed to generate bank report.')),
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
    final palette = context.coolPalette;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          const Icon(Icons.account_balance_rounded, color: AppColors.blue, size: 32),
          const SizedBox(height: 16),
          Text(
            'Official Bank Report',
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Generate a professional financial memo to use for loan applications at partner banks.',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: palette.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 24),
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
    final palette = context.coolPalette;
    final color = _readinessColor(insights.creditReadiness);

    return CoolCard(
      gradient: AppColors.blueGradient,
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
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: palette.text2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    insights.creditReadiness.toUpperCase(),
                    style: GoogleFonts.dmSans(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: color,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Text(
                      'EST. SCORE',
                      style: GoogleFonts.dmSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    Text(
                      insights.estimatedScoreRange,
                      style: GoogleFonts.dmSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _ScoreTrack(
            label: 'Savings Discipline',
            value: insights.savingsDisciplineScore / 100,
            color: AppColors.accent,
          ),
          const SizedBox(height: 12),
          _ScoreTrack(
            label: 'Income Stability',
            value: insights.incomeStabilityScore / 100,
            color: AppColors.blue,
          ),
        ],
      ),
    );
  }

  Color _readinessColor(String level) {
    return switch (level.toLowerCase()) {
      'excellent' => AppColors.accent,
      'high' => AppColors.blue,
      'medium' => AppColors.yellow,
      _ => AppColors.orange,
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
    final palette = context.coolPalette;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: palette.text,
              ),
            ),
            Text(
              '${(value * 100).toInt()}%',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _InsightList(
            title: 'STRENGTHS',
            items: insights.keyStrengths,
            color: AppColors.accent,
            icon: Icons.check_circle_outline_rounded,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _InsightList(
            title: 'RISKS',
            items: insights.improvementAreas,
            color: AppColors.orange,
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
    final palette = context.coolPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.dmSans(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: palette.text3,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 10),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: palette.text2,
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
    final palette = context.coolPalette;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.blue.withValues(alpha: 0.1),
            ),
            child: const Icon(Icons.lightbulb_outline_rounded, size: 18, color: AppColors.blue),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              tip,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: palette.text,
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
    return const Center(child: CircularProgressIndicator(color: AppColors.accent));
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('Error loading insights: $error'));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Connect your MoMo to see AI insights.'));
  }
}
