import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_card.dart';
import '../models/credit_dashboard.dart';

const creditScoreMin = 300;
const creditScoreMax = 850;

double creditScoreProgress(int score) {
  final normalized =
      (score - creditScoreMin) / (creditScoreMax - creditScoreMin);
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
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final score = dashboard?.score ?? 0;
    final hasReport = dashboard?.score != null;
    final accentColor = _scoreBandColor(colors);

    return CoolCard(
      backgroundColor: colors.financialSurface,
      borderColor: colors.info.withValues(alpha: 0.2),
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
                    trackColor: colors.borderStrong,
                    valueColor: accentColor,
                  ),
                  child: Center(
                    child: Text(
                      hasReport ? '${(score * animation.value).round()}' : '--',
                      style: text.mono(
                        theme.textTheme.headlineMedium,
                        fontWeight: FontWeight.w800,
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          SizedBox(width: space.x5 - 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Credit score',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.tertiaryText,
                    letterSpacing: 0.6,
                  ),
                ),
                SizedBox(height: space.x1 + 2),
                Text(
                  _grade,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: accentColor,
                  ),
                ),
                SizedBox(height: space.x1 + 2),
                Text(
                  _description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                    height: 1.45,
                  ),
                ),
                SizedBox(height: space.x2 + 2),
                Text(
                  dashboard == null
                      ? 'Sign in to view your report.'
                      : analysisFootnote(dashboard!),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.tertiaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _scoreBandColor(CoolSemanticColors colors) {
    switch (dashboard?.scoreBand) {
      case 'excellent':
        return colors.success;
      case 'good':
        return colors.info;
      case 'building':
        return colors.warning;
      default:
        return colors.neutral;
    }
  }
}

/// Animated ring painter for the credit score hero.
class ScoreRingPainter extends CustomPainter {
  ScoreRingPainter({
    required this.progress,
    required this.trackColor,
    required this.valueColor,
  });

  final double progress;
  final Color trackColor;
  final Color valueColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    const strokeWidth = 10.0;

    final bgPaint = Paint()
      ..color = trackColor
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
      ..color = valueColor
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
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.valueColor != valueColor;
  }
}

/// Score factors list with progress bars.
class ScoreFactors extends StatelessWidget {
  const ScoreFactors({required this.factors, super.key});

  final List<CreditFactor> factors;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final insets = context.coolInsets;
    final theme = Theme.of(context);
    final space = context.coolSpace;
    if (factors.isEmpty) {
      return CoolCard(
        child: Padding(
          padding: insets.all(space.x5 - 2),
          child: Text(
            'Factors appear after your',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
              height: 1.5,
            ),
          ),
        ),
      );
    }

    return Column(
      children: factors.map((factor) {
        final color = _factorColor(factor.score, colors);
        return Padding(
          padding: insets.only(bottom: space.x2 + 2),
          child: CoolCard(
            child: Padding(
              padding: insets.all(space.x4),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(factor.icon, size: 18, color: colors.secondaryText),
                      SizedBox(width: space.x2 + 2),
                      Expanded(
                        child: Text(
                          factor.label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.primaryText,
                          ),
                        ),
                      ),
                      Text(
                        '${factor.score}/100',
                        style: context.coolText.mono(
                          theme.textTheme.labelMedium,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: space.x2 + 2),
                  ClipRRect(
                    borderRadius: const BorderRadius.all(
                      Radius.circular(CoolRadii.xs / 4),
                    ),
                    child: LinearProgressIndicator(
                      value: factor.score / 100,
                      minHeight: 6,
                      backgroundColor: colors.borderStrong,
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

  Color _factorColor(int score, CoolSemanticColors colors) {
    if (score >= 75) return colors.success;
    if (score >= 60) return colors.info;
    if (score >= 45) return colors.warning;
    return colors.danger;
  }
}

/// Score history line chart.
class ScoreHistoryChart extends StatelessWidget {
  const ScoreHistoryChart({required this.history, super.key});

  final List<CreditHistoryPoint> history;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final insets = context.coolInsets;
    final theme = Theme.of(context);
    final space = context.coolSpace;
    if (history.isEmpty) {
      return CoolCard(
        child: Padding(
          padding: insets.all(space.x5 - 2),
          child: Text(
            'History appears after multiple',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
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
      backgroundColor: colors.analyticsSurface,
      borderColor: colors.borderStrong,
      child: Padding(
        padding: insets.all(space.x5 - 2),
        child: Column(
          children: [
            SizedBox(
              height: 140,
              child: CustomPaint(
                size: const Size(double.infinity, 140),
                painter: _LineChartPainter(
                  values: values,
                  gridColor: colors.borderStrong,
                  accentColor: colors.accent,
                  surfaceColor: colors.cardSurfaceStrong,
                ),
              ),
            ),
            SizedBox(height: space.x2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: labels.map((label) {
                return Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.tertiaryText,
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
  _LineChartPainter({
    required this.values,
    required this.gridColor,
    required this.accentColor,
    required this.surfaceColor,
  });

  final List<double> values;
  final Color gridColor;
  final Color accentColor;
  final Color surfaceColor;

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
      ..color = gridColor
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
          accentColor.withValues(alpha: 0.15),
          accentColor.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = accentColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(linePath, linePaint);

    final dotPaint = Paint()..color = accentColor;
    final dotBgPaint = Paint()..color = surfaceColor;

    for (final point in points) {
      canvas.drawCircle(point, 5, dotBgPaint);
      canvas.drawCircle(point, 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.surfaceColor != surfaceColor;
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
