import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_card.dart';
import '../models/credit_dashboard.dart';

const creditScoreMin = 300;
const creditScoreMax = 850;

double creditScoreProgress(int score) {
  final normalized = (score - creditScoreMin) / (creditScoreMax - creditScoreMin);
  return normalized.clamp(0, 1).toDouble();
}

/// Hero card with animated score ring and grade description.
class ScoreHeroCard extends StatelessWidget {
  const ScoreHeroCard({
    required this.dashboard,
    required this.animation,
    super.key,
  });

  final CreditDashboard? dashboard;
  final Animation<double> animation;

  String get _grade {
    final score = dashboard?.score;
    if (score == null) return 'Report Pending';

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
    if (summary != null && summary.isNotEmpty) return summary;

    final score = dashboard!.score!;
    if (score >= 720) return 'Wallet and savings activity looks strong.';
    if (score >= 640) return 'You are building a reliable financial track record.';
    if (score >= 560) return 'Steady activity will help improve your next report.';
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
                  painter: ScoreRingPainter(
                    progress: hasReport
                        ? creditScoreProgress(score) * animation.value
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
                      : analysisFootnote(dashboard!),
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

/// Animated ring painter for the credit score hero.
class ScoreRingPainter extends CustomPainter {
  ScoreRingPainter({required this.progress});

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
  bool shouldRepaint(covariant ScoreRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Score factors list with progress bars.
class ScoreFactors extends StatelessWidget {
  const ScoreFactors({required this.factors, super.key});

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

/// Score history line chart.
class ScoreHistoryChart extends StatelessWidget {
  const ScoreHistoryChart({required this.history, super.key});

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
    if (values.isEmpty) return;

    final minVal = math.max(
      creditScoreMin.toDouble(),
      values.reduce(math.min) - 25,
    );
    final maxVal = math.min(
      creditScoreMax.toDouble(),
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

// ── Helpers ──────────────────────────────────────────────────────────────

String analysisFootnote(CreditDashboard dashboard) {
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
