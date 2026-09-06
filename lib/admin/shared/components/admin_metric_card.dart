import 'package:flutter/material.dart';

import '../../../app/theme/collect_colors.dart';
import '../../../app/theme/collect_typography.dart';
import '../../core/admin_models.dart';
import 'admin_status_chip.dart';

class AdminMetricCard extends StatelessWidget {
  const AdminMetricCard({required this.metric, super.key});

  final AdminMetric metric;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return SizedBox(
      width: 260,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceReadable,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.borderSoft),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceRaised,
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: Icon(
                        Icons.query_stats_outlined,
                        color: colors.textPrimary,
                        size: 18,
                      ),
                    ),
                  ),
                  const Spacer(),
                  AdminStatusChip(label: metric.status),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                metric.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: CollectTypography.weightBold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                metric.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: CollectTypography.weightBold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
