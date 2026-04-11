import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

/// Reusable section header for admin dashboard surfaces.
///
/// Renders a title + optional description message and optional trailing
/// action widget. Extracted from the common `_SectionHeader` pattern
/// duplicated across admin screens.
class AdminSectionHeader extends StatelessWidget {
  const AdminSectionHeader({
    required this.title,
    this.message,
    this.trailing,
    super.key,
  });

  /// Section title text.
  final String title;

  /// Optional descriptive message shown below the title.
  final String? message;

  /// Optional trailing action widget (e.g. an IconButton or TextButton).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: CoolSpace.x1),
                Text(
                  message!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w400,
                    color: colors.secondaryText,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}
