import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/section_title.dart';
import '../models/credit_dashboard.dart';
import '../providers/credit_provider.dart';

const _creditScoreMin = 300;
const _creditScoreMax = 850;

class CreditScoreScreen extends ConsumerStatefulWidget {
  const CreditScoreScreen({super.key});

  @override
  ConsumerState<CreditScoreScreen> createState() => _CreditScoreScreenState();
}

class _CreditScoreScreenState extends ConsumerState<CreditScoreScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ringController;
  late final Animation<double> _ringAnimation;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _ringAnimation = CurvedAnimation(
      parent: _ringController,
      curve: Curves.easeOutCubic,
    );
    _ringController.forward();
  }

  @override
  void dispose() {
    _ringController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashboardAsync = ref.watch(creditDashboardProvider);
    final canRefresh = ref.watch(creditDashboardProvider).valueOrNull != null;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          IconButton(
            onPressed: !_isRefreshing && canRefresh ? _refreshReport : null,
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
        title: Text(
          'Credit',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ),
      body: CoolScreenBackground(
        primaryColor: AppColors.purple,
        secondaryColor: AppColors.yellow,
        child: dashboardAsync.when(
          data: (dashboard) => _CreditScoreBody(
            dashboard: dashboard,
            ringAnimation: _ringAnimation,
          ),
          loading: () => const _CreditScoreLoadingState(),
          error: (error, _) => _CreditScoreErrorState(error: error.toString()),
        ),
      ),
    );
  }

  Future<void> _refreshReport() async {
    if (_isRefreshing) {
      return;
    }

    setState(() => _isRefreshing = true);
    try {
      await ref.read(creditRepositoryProvider).refreshMyScore();
      ref.invalidate(creditDashboardProvider);
      if (mounted) {
        CoolToast.success(context, 'Credit report refreshed.');
      }
    } catch (error) {
      if (mounted) {
        CoolToast.error(context, 'Could not refresh report: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }
}

class _CreditScoreBody extends StatelessWidget {
  const _CreditScoreBody({
    required this.dashboard,
    required this.ringAnimation,
  });

  final CreditDashboard? dashboard;
  final Animation<double> ringAnimation;

  @override
  Widget build(BuildContext context) {
    final data = dashboard;
    final hasReport = data?.hasReport == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          if (!hasReport)
            _InfoBanner(
              icon: Icons.credit_score_outlined,
              message:
                  'Score available after verified activity.',
            )
          else if (data?.lastUpdated != null)
            _InfoBanner(
              icon: Icons.check_circle_outline_rounded,
              message:
                  'Updated ${DateFormat('d MMM yyyy').format(data!.lastUpdated!.toLocal())}.',
            ),
          const SizedBox(height: 12),
          _ScoreHeroCard(dashboard: data, animation: ringAnimation),
          const SizedBox(height: 22),
          _HowToImproveCard(dashboard: data),
          const SizedBox(height: 22),
          if (hasReport) ...[
            const SectionTitle(title: 'Top factors'),
            const SizedBox(height: 10),
            _ScoreFactors(
              factors: (data?.factors ?? const [])
                  .take(3)
                  .toList(growable: false),
            ),
            const SizedBox(height: 22),
            const SectionTitle(title: 'Report details'),
            const SizedBox(height: 10),
            _ScoreExplanationCard(dashboard: data),
            const SizedBox(height: 22),
          ],
          const SectionTitle(title: 'Readiness'),
          const SizedBox(height: 10),
          _ApplicationReadinessEntryCard(dashboard: data),
          if (hasReport && (data?.history.isNotEmpty ?? false)) ...[
            const SizedBox(height: 22),
            const SectionTitle(title: 'History'),
            const SizedBox(height: 10),
            _ScoreHistoryChart(history: data?.history ?? const []),
          ],
        ],
      ),
    );
  }
}

class _CreditScoreLoadingState extends StatelessWidget {
  const _CreditScoreLoadingState();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(18, 8, 18, 96),
      child: Column(
        children: [
          CoolSkeleton.card(),
          SizedBox(height: 18),
          CoolSkeleton.card(),
          SizedBox(height: 18),
          CoolSkeleton.card(),
        ],
      ),
    );
  }
}

class _CreditScoreErrorState extends StatelessWidget {
  const _CreditScoreErrorState({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: CoolCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: AppColors.orange,
              ),
              const SizedBox(height: 12),
              Text(
                'Could not load your credit report.',
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error,
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.yellow.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.yellow.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.yellow),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.yellow,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreHeroCard extends StatelessWidget {
  const _ScoreHeroCard({required this.dashboard, required this.animation});

  final CreditDashboard? dashboard;
  final Animation<double> animation;

  String get _grade {
    final score = dashboard?.score;
    if (score == null) {
      return 'Report Pending';
    }

    switch (dashboard?.scoreBand) {
      case 'excellent':
        return 'Excellent';
      case 'good':
        return 'Good Standing';
      case 'building':
        return 'Building';
      default:
        return 'Limited History';
    }
  }

  String get _description {
    if (dashboard?.score == null) {
      return 'Verified M-Money and savings activity needed.';
    }

    final summary = dashboard?.summary?.trim();
    if (summary != null && summary.isNotEmpty) {
      return summary;
    }

    final score = dashboard!.score!;
    if (score >= 720) {
      return 'Wallet and savings activity looks strong.';
    }
    if (score >= 640) {
      return 'You are building a reliable financial track record.';
    }
    if (score >= 560) {
      return 'Steady activity will help improve your next report.';
    }
    return 'More verified activity is needed before your score can improve.';
  }

  @override
  Widget build(BuildContext context) {
    final score = dashboard?.score ?? 0;
    final hasReport = dashboard?.score != null;

    return CoolCard(
      backgroundColor: AppColors.surface,
      borderColor: AppColors.purple.withValues(alpha: 0.24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              return SizedBox(
                width: 108,
                height: 108,
                child: CustomPaint(
                  painter: _ScoreRingPainter(
                    progress: hasReport
                        ? _creditScoreProgress(score) * animation.value
                        : 0,
                  ),
                  child: Center(
                    child: Text(
                      hasReport ? '${(score * animation.value).round()}' : '--',
                      style: GoogleFonts.dmMono(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Credit score',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text3,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _grade,
                  style: GoogleFonts.dmSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.purple,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _description,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.text2,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  dashboard == null
                      ? 'Sign in to view your report.'
                      : _analysisFootnote(dashboard!),
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
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

class _ScoreRingPainter extends CustomPainter {
  _ScoreRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    const strokeWidth = 10.0;

    final bgPaint = Paint()
      ..color = AppColors.surface3
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi,
      false,
      bgPaint,
    );

    final scorePaint = Paint()
      ..color = AppColors.purple
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      scorePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScoreRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _ScoreFactors extends StatelessWidget {
  const _ScoreFactors({required this.factors});

  final List<CreditFactor> factors;

  @override
  Widget build(BuildContext context) {
    if (factors.isEmpty) {
      return CoolCard(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            'Factors appear after your first report.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.5,
            ),
          ),
        ),
      );
    }

    return Column(
      children: factors.map((factor) {
        final color = _factorColor(factor.score);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: CoolCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(factor.icon, size: 18, color: AppColors.text2),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          factor.label,
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      Text(
                        '${factor.score}/100',
                        style: GoogleFonts.dmMono(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: factor.score / 100,
                      minHeight: 6,
                      backgroundColor: AppColors.surface3,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Color _factorColor(int score) {
    if (score >= 75) return AppColors.accent;
    if (score >= 60) return AppColors.blue;
    if (score >= 45) return AppColors.yellow;
    return AppColors.orange;
  }
}

class _HowToImproveCard extends StatelessWidget {
  const _HowToImproveCard({required this.dashboard});

  final CreditDashboard? dashboard;

  @override
  Widget build(BuildContext context) {
    final items = _buildItems(dashboard);

    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Next steps',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 12),
          ...items.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    item.completed
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: item.completed ? AppColors.accent : AppColors.text3,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.text,
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: item.completed
                            ? AppColors.text
                            : AppColors.text2,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  List<_ImprovementItem> _buildItems(CreditDashboard? data) {
    if (data == null) {
      return const [
        _ImprovementItem('Sign in to view your report', false),
      ];
    }

    if (!data.hasReport) {
      return [
        _ImprovementItem(
          'Keep mobile-money activity flowing',
          data.statementCount > 0,
        ),
        _ImprovementItem(
          'Stay active in savings groups',
          data.groupContributionCount > 0,
        ),
        _ImprovementItem(
          'Build 2+ active months of history',
          data.activeMonthCount >= 2,
        ),
      ];
    }

    final recommendations = _reasonInsights(data)
        .map((item) => item.action)
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (recommendations.isEmpty) {
      return const [
        _ImprovementItem('Maintain your current savings consistency', true),
        _ImprovementItem('Keep your verified M-Money history active', true),
        _ImprovementItem('Stay active in your savings groups', true),
      ];
    }

    return recommendations
        .map(
          (item) => _ImprovementItem(
            item,
            item ==
                'Maintain current wallet, savings, and profile verification behaviour.',
          ),
        )
        .toList(growable: false);
  }
}

class _ApplicationReadinessEntryCard extends StatelessWidget {
  const _ApplicationReadinessEntryCard({required this.dashboard});

  final CreditDashboard? dashboard;

  @override
  Widget build(BuildContext context) {
    final title = dashboard?.hasReport == true
        ? 'Ready for a formal handoff'
        : 'Build readiness first';
    final detail = dashboard?.hasReport == true
        ? 'Prepare for your next finance conversation.'
        : 'See what still needs to be completed.';

    return CoolCard(
      borderColor: AppColors.blue.withValues(alpha: 0.24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          CoolButton(
            label: 'Open readiness',
            icon: Icons.assignment_turned_in_outlined,
            onTap: () => context.push(AppRoutes.creditReadiness),
          ),
        ],
      ),
    );
  }
}

class _ScoreExplanationCard extends StatelessWidget {
  const _ScoreExplanationCard({required this.dashboard});

  final CreditDashboard? dashboard;

  @override
  Widget build(BuildContext context) {
    final data = dashboard;
    if (data == null) {
      return CoolCard(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            'Sign in to view details.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.5,
            ),
          ),
        ),
      );
    }

    if (!data.hasReport) {
      return CoolCard(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            'Details appear after your first report.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.5,
            ),
          ),
        ),
      );
    }

    final insights = _reasonInsights(data);

    return CoolCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ReportMetaChip(
                  label: 'Window',
                  value: _scoringWindowLabel(data),
                  icon: Icons.calendar_month_rounded,
                ),
                _ReportMetaChip(
                  label: 'KYC',
                  value: _kycStatusLabel(data.kycStatus),
                  icon: Icons.verified_user_outlined,
                ),
                if ((data.scoreVersion?.trim().isNotEmpty ?? false))
                  _ReportMetaChip(
                    label: 'Engine',
                    value: data.scoreVersion!,
                    icon: Icons.tune_rounded,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _SnapshotStatTile(
                  label: 'Wallet In',
                  value:
                      '${_formatCurrency(data.creditTotal)} RWF\n${data.creditEntryCount} credits',
                  color: AppColors.accent,
                ),
                _SnapshotStatTile(
                  label: 'Wallet Out',
                  value:
                      '${_formatCurrency(data.debitTotal)} RWF\n${data.debitEntryCount} debits',
                  color: AppColors.orange,
                ),
                _SnapshotStatTile(
                  label: 'Savings',
                  value:
                      '${_formatCurrency(data.groupTotal)} RWF\n${data.groupContributionCount} contributions',
                  color: AppColors.blue,
                ),
                _SnapshotStatTile(
                  label: 'Average Save',
                  value:
                      '${_formatCurrency(data.averageGroupContribution)} RWF\n${data.activeMonthCount} active months',
                  color: AppColors.purple,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...insights.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ReasonInsightTile(item: item),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreHistoryChart extends StatelessWidget {
  const _ScoreHistoryChart({required this.history});

  final List<CreditHistoryPoint> history;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return CoolCard(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            'History appears after multiple reports.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
            ),
          ),
        ),
      );
    }

    final labels = history.map((point) => point.label).toList(growable: false);
    final values = history
        .map((point) => point.score.toDouble())
        .toList(growable: false);

    return CoolCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            SizedBox(
              height: 140,
              child: CustomPaint(
                size: const Size(double.infinity, 140),
                painter: _LineChartPainter(values: values),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: labels.map((label) {
                return Text(
                  label,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: AppColors.text3,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({required this.values});

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) {
      return;
    }

    final minVal = math.max(
      _creditScoreMin.toDouble(),
      values.reduce(math.min) - 25,
    );
    final maxVal = math.min(
      _creditScoreMax.toDouble(),
      values.reduce(math.max) + 25,
    );
    final range = math.max(1, maxVal - minVal);

    final gridPaint = Paint()
      ..color = AppColors.surface3
      ..strokeWidth = 1;

    for (var i = 0; i < 4; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : (i / (values.length - 1)) * size.width;
      final y = size.height - ((values[i] - minVal) / range) * size.height;
      points.add(Offset(x, y));
    }

    final fillPath = Path()
      ..moveTo(points.first.dx, size.height)
      ..lineTo(points.first.dx, points.first.dy);

    for (var i = 1; i < points.length; i++) {
      fillPath.lineTo(points[i].dx, points[i].dy);
    }

    fillPath
      ..lineTo(points.last.dx, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.accent.withValues(alpha: 0.15),
          AppColors.accent.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(linePath, linePaint);

    final dotPaint = Paint()..color = AppColors.accent;
    final dotBgPaint = Paint()..color = AppColors.surface2;

    for (final point in points) {
      canvas.drawCircle(point, 5, dotBgPaint);
      canvas.drawCircle(point, 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.values != values;
  }
}

class _ImprovementItem {
  const _ImprovementItem(this.text, this.completed);

  final String text;
  final bool completed;
}

class _ReasonInsight {
  const _ReasonInsight({
    required this.code,
    required this.title,
    required this.detail,
    required this.action,
    required this.icon,
    required this.color,
  });

  final String code;
  final String title;
  final String detail;
  final String action;
  final IconData icon;
  final Color color;
}

class _ReportMetaChip extends StatelessWidget {
  const _ReportMetaChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.text2),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SnapshotStatTile extends StatelessWidget {
  const _SnapshotStatTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 152,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.text3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.dmMono(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonInsightTile extends StatelessWidget {
  const _ReasonInsightTile({required this.item});

  final _ReasonInsight item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(item.icon, size: 18, color: item.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  item.detail,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2,
                    height: 1.45,
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

double _creditScoreProgress(int score) {
  final normalized =
      (score - _creditScoreMin) / (_creditScoreMax - _creditScoreMin);
  return normalized.clamp(0, 1).toDouble();
}

String _analysisFootnote(CreditDashboard dashboard) {
  final parts = <String>['${dashboard.statementCount} wallet entries analyzed'];
  if (dashboard.groupContributionCount > 0) {
    parts.add(
      '${dashboard.groupContributionCount} confirmed savings contributions',
    );
  }
  if (dashboard.activeMonthCount > 0) {
    parts.add('${dashboard.activeMonthCount} active months');
  }
  return parts.join(' • ');
}

String _formatCurrency(int amount) {
  return NumberFormat.decimalPattern('en_US').format(amount);
}

String _scoringWindowLabel(CreditDashboard dashboard) {
  final start = dashboard.periodStart?.toLocal();
  final end = dashboard.periodEnd?.toLocal();
  if (start == null || end == null) {
    return 'Latest available window';
  }
  final formatter = DateFormat('d MMM yyyy');
  return '${formatter.format(start)} - ${formatter.format(end)}';
}

String _kycStatusLabel(String? rawStatus) {
  switch (rawStatus) {
    case 'verified':
      return 'Verified';
    case 'pending_review':
      return 'Pending review';
    case 'rejected':
      return 'Rejected';
    default:
      return 'Unverified';
  }
}

List<_ReasonInsight> _reasonInsights(CreditDashboard dashboard) {
  if (!dashboard.hasReport) {
    return const <_ReasonInsight>[];
  }

  final codes = dashboard.reasonCodes.isEmpty
      ? const <String>['healthy_verified_history']
      : dashboard.reasonCodes.toSet().toList(growable: false);
  return codes
      .map((code) => _reasonInsightFor(code, dashboard))
      .toList(growable: false);
}

_ReasonInsight _reasonInsightFor(String code, CreditDashboard dashboard) {
  switch (code) {
    case 'wallet_activity_low':
      return _ReasonInsight(
        code: code,
        title: 'Wallet history is still thin',
        detail:
            'Only ${dashboard.statementCount} posted wallet entries were counted in this scoring window. More verified M-Money activity makes the score more dependable.',
        action:
            'Keep using posted M-Money transactions consistently across the next two months.',
        icon: Icons.account_balance_wallet_outlined,
        color: AppColors.orange,
      );
    case 'income_history_thin':
      return _ReasonInsight(
        code: code,
        title: 'Incoming cashflow needs more history',
        detail:
            '${dashboard.creditEntryCount} incoming wallet entries were detected. Regular incoming transfers over multiple months improve cashflow stability.',
        action:
            'Encourage regular incoming transfers or income deposits into the wallet.',
        icon: Icons.south_west_rounded,
        color: AppColors.yellow,
      );
    case 'savings_pattern_thin':
      return _ReasonInsight(
        code: code,
        title: 'Savings pattern is not yet consistent',
        detail:
            'Confirmed savings total is ${_formatCurrency(dashboard.groupTotal)} RWF with an average contribution of ${_formatCurrency(dashboard.averageGroupContribution)} RWF.',
        action:
            'Build a steadier savings pattern with repeated confirmed contributions.',
        icon: Icons.savings_outlined,
        color: AppColors.blue,
      );
    case 'group_savings_missing':
      return _ReasonInsight(
        code: code,
        title: 'No confirmed group savings found',
        detail:
            'The model did not find confirmed group-savings contributions inside the scoring window, so that reliability factor stayed limited.',
        action:
            'Start confirmed group savings contributions to unlock this factor.',
        icon: Icons.groups_2_outlined,
        color: AppColors.orange,
      );
    case 'group_activity_low':
      return _ReasonInsight(
        code: code,
        title: 'Group contribution activity is still light',
        detail:
            '${dashboard.groupContributionCount} confirmed contributions were counted. More months with group contributions strengthen group reliability.',
        action:
            'Increase the number of months with confirmed group contributions.',
        icon: Icons.groups_outlined,
        color: AppColors.yellow,
      );
    case 'profile_verification_needed':
      return _ReasonInsight(
        code: code,
        title: 'Profile verification is holding the score back',
        detail:
            'Official identity signals are not fully complete yet. Current KYC status is ${_kycStatusLabel(dashboard.kycStatus).toLowerCase()}.',
        action: 'Complete official-name, phone, and KYC verification.',
        icon: Icons.badge_outlined,
        color: AppColors.purple,
      );
    case 'healthy_verified_history':
    default:
      return _ReasonInsight(
        code: code,
        title: 'Verified behaviour looks healthy',
        detail:
            'Posted wallet activity, confirmed savings behaviour, and profile signals are all contributing positively in the current scoring window.',
        action:
            'Maintain current wallet, savings, and profile verification behaviour.',
        icon: Icons.verified_rounded,
        color: AppColors.accent,
      );
  }
}
