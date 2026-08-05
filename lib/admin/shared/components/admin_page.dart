import 'package:flutter/material.dart';

import '../../../app/theme/collect_colors.dart';
import '../../../app/theme/collect_typography.dart';

class AdminPage extends StatelessWidget {
  const AdminPage({required this.title, this.subtitle, this.child, super.key});

  final String title;
  final String? subtitle;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceReadable,
              border: Border.all(color: colors.borderAccent),
              boxShadow: [
                BoxShadow(
                  color: colors.textPrimary.withValues(alpha: 0.18),
                  blurRadius: 30,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 560;
                  final titleBlock = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: CollectTypography.weightBold,
                              height: CollectTypography.leadingDisplay,
                            ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: colors.textSecondary,
                                height: CollectTypography.leadingSupporting,
                              ),
                        ),
                      ],
                    ],
                  );
                  final badge = DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.textPrimary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        'Audit safe',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: colors.surfaceReadable,
                              fontWeight: CollectTypography.weightBold,
                            ),
                      ),
                    ),
                  );
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [badge, const SizedBox(height: 14), titleBlock],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: titleBlock),
                      const SizedBox(width: 16),
                      badge,
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        if (child != null) ...[const SizedBox(height: 16), child!],
      ],
    );
  }
}

class AdminPageHeader extends StatelessWidget {
  const AdminPageHeader({required this.title, this.subtitle, super.key});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: CollectTypography.weightBold,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
