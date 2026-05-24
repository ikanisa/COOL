import 'package:flutter/material.dart';

import '../../core/admin_models.dart';

class AdminMetricCard extends StatelessWidget {
  const AdminMetricCard({required this.metric, super.key});

  final AdminMetric metric;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 260,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(metric.label, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 10),
              Text(
                metric.value,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  metric.status,
                  style: TextStyle(color: colorScheme.onSecondaryContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
