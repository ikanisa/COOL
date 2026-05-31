import 'package:flutter/material.dart';

import 'collect_colors.dart';
import 'collect_radius.dart';
import 'collect_spacing.dart';

class CollectComponentTokens {
  const CollectComponentTokens._();

  static ButtonStyle filledButton(BuildContext context) {
    final colors = context.collectColors;
    return FilledButton.styleFrom(
      minimumSize: const Size(CollectSpacing.target, CollectSpacing.target),
      padding: const EdgeInsets.symmetric(
        horizontal: CollectSpacing.x5,
        vertical: CollectSpacing.x3,
      ),
      shape: RoundedRectangleBorder(borderRadius: CollectRadius.mdBorder),
      backgroundColor: colors.navy,
      foregroundColor: Colors.white,
      disabledBackgroundColor: colors.surfaceMuted,
      disabledForegroundColor: colors.textMuted,
      textStyle: Theme.of(context).textTheme.labelLarge,
    );
  }

  static ButtonStyle outlinedButton(BuildContext context) {
    final colors = context.collectColors;
    return OutlinedButton.styleFrom(
      minimumSize: const Size(CollectSpacing.target, CollectSpacing.target),
      padding: const EdgeInsets.symmetric(
        horizontal: CollectSpacing.x5,
        vertical: CollectSpacing.x3,
      ),
      shape: RoundedRectangleBorder(borderRadius: CollectRadius.mdBorder),
      foregroundColor: colors.textPrimary,
      side: BorderSide(color: colors.border),
      textStyle: Theme.of(context).textTheme.labelLarge,
    );
  }

  static InputDecoration inputDecoration({
    required BuildContext context,
    required String label,
    String? helper,
    String? prefix,
  }) {
    final colors = context.collectColors;
    final border = UnderlineInputBorder(
      borderSide: BorderSide(color: colors.textPrimary),
    );
    return InputDecoration(
      labelText: label,
      helperText: helper,
      prefixText: prefix,
      filled: false,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: colors.blue, width: 2),
      ),
    );
  }
}
