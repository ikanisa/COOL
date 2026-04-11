import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';
import 'cool_card.dart';

/// A 2×N grid of metric cards for admin summary surfaces.
///
/// Each metric is displayed as a [CoolCard] with label, value, and optional
/// icon + trend indicator. Designed for operational dashboards.
class AdminSummaryMetricGrid extends StatelessWidget {
  const AdminSummaryMetricGrid({
    required this.metrics,
    this.crossAxisCount = 2,
    this.childAspectRatio = 1.3,
    super.key,
  });

  /// List of metrics to display.
  final List<AdminMetric> metrics;

  /// Number of columns in the grid.
  final int crossAxisCount;

  /// Aspect ratio for each cell.
  final double childAspectRatio;

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) return const SizedBox.shrink();
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: crossAxisCount,
      childAspectRatio: childAspectRatio,
      crossAxisSpacing: CoolSpace.x3,
      mainAxisSpacing: CoolSpace.x3,
      children: metrics.map((m) => _MetricCell(metric: m)).toList(),
    );
  }
}

/// Data class for a single metric in [AdminSummaryMetricGrid].
class AdminMetric {
  const AdminMetric({
    required this.label,
    required this.value,
    this.icon,
    this.trend,
    this.trendIsPositive,
  });

  /// Metric label (e.g. "Active Users").
  final String label;

  /// Formatted value string (e.g. "1,234").
  final String value;

  /// Optional leading icon.
  final IconData? icon;

  /// Optional trend text (e.g. "+12%").
  final String? trend;

  /// Whether the trend is positive (green) or negative (red).
  final bool? trendIsPositive;
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.metric});

  final AdminMetric metric;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return CoolCard(
      useGradient: false,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (metric.icon != null) ...[
                Icon(metric.icon, size: 16, color: colors.secondaryText),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  metric.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w400,
                    color: colors.secondaryText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  metric.value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
              ),
              if (metric.trend != null)
                Text(
                  metric.trend!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: metric.trendIsPositive == true
                        ? colors.success
                        : metric.trendIsPositive == false
                        ? colors.danger
                        : colors.tertiaryText,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
