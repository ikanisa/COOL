import 'package:flutter/material.dart';

import '../../../app/theme/collect_colors.dart';
import '../../../app/theme/collect_typography.dart';
import '../../../app/theme/collect_universal_tokens.dart';

class AdminPage extends StatelessWidget {
  const AdminPage({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.child,
    this.scrollController,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final Widget? child;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final tokens = context.collectUniversalTokens;
    return ListView(
      key: const Key('admin-page-scroll-view'),
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 2),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Operator actions retain their labels at phone widths and large
              // text sizes. This is the compact Business-pattern adaptation.
              final stackActions =
                  trailing != null &&
                  (constraints.maxWidth < 600 ||
                      MediaQuery.textScalerOf(context).scale(1) > 1.3);
              final heading = Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (leading != null) ...[
                    SizedBox.square(
                      dimension: tokens.touchTarget,
                      child: leading,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: CollectTypography.weightSemibold,
                                height: CollectTypography.leadingDisplay,
                              ),
                        ),
                        if (subtitle?.trim().isNotEmpty == true) ...[
                          const SizedBox(height: 5),
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
                    ),
                  ),
                  if (trailing != null && !stackActions) ...[
                    const SizedBox(width: 12),
                    trailing!,
                  ],
                ],
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  heading,
                  if (stackActions) ...[const SizedBox(height: 12), trailing!],
                ],
              );
            },
          ),
        ),
        if (child != null) ...[const SizedBox(height: 18), child!],
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
              fontWeight: CollectTypography.weightSemibold,
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
