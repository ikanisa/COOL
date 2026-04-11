import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    required this.title,
    this.actionLabel,
    this.onAction,
    this.action,
    super.key,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) {
    final radii = context.coolRadii;
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final effectiveAction = onAction ?? action;
    return Semantics(
      header: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.primaryText,
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: effectiveAction,
              style: TextButton.styleFrom(
                minimumSize: const Size(52, CoolTapTargets.minimum),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(radii.md),
                ),
              ),
              child: Text(
                actionLabel!,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.accent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
