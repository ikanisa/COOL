import 'package:flutter/material.dart';

import '../../../app/theme/collect_colors.dart';
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
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.textPrimary,
              Color.alphaBlend(
                colors.periwinklePaint.withValues(alpha: 0.24),
                colors.textPrimary,
              ),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: colors.surfaceReadable.withValues(alpha: 0.14),
          ),
          boxShadow: [
            BoxShadow(
              color: colors.textPrimary.withValues(alpha: 0.16),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
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
                      color: colors.surfaceReadable.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: Icon(
                        Icons.query_stats_outlined,
                        color: colors.surfaceReadable,
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
                  color: colors.surfaceReadable.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                metric.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: colors.surfaceReadable,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
