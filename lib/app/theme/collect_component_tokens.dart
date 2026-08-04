import 'package:flutter/material.dart';

import 'collect_colors.dart';
import 'collect_radius.dart';
import 'collect_spacing.dart';
import 'collect_runtime_tokens.dart';
import 'collect_universal_tokens.dart';

class CollectComponentTokens {
  const CollectComponentTokens._();

  static ButtonStyle filledButton(BuildContext context) {
    final colors = context.collectColors;
    final tokens = context.collectUniversalTokens;
    return FilledButton.styleFrom(
      minimumSize: Size(tokens.touchTarget, tokens.touchTarget),
      padding: const EdgeInsets.symmetric(
        horizontal: CollectSpacing.x5,
        vertical: CollectSpacing.x3,
      ),
      shape: RoundedRectangleBorder(borderRadius: CollectRadius.controlBorder),
      backgroundColor: tokens.actionPrimary,
      foregroundColor: colors.onAccent,
      disabledBackgroundColor: colors.neutralContainer,
      disabledForegroundColor: colors.textMuted,
      textStyle: Theme.of(context).textTheme.labelLarge,
    );
  }

  static ButtonStyle dangerButton(BuildContext context) {
    final colors = context.collectColors;
    return filledButton(context).copyWith(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return colors.neutralContainer;
        }
        if (states.contains(WidgetState.pressed)) {
          return Color.alphaBlend(
            colors.textPrimary.withValues(alpha: 0.12),
            colors.danger,
          );
        }
        return colors.danger;
      }),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? colors.textMuted
            : colors.surfaceReadable,
      ),
    );
  }

  static ButtonStyle outlinedButton(BuildContext context) {
    final colors = context.collectColors;
    final tokens = context.collectUniversalTokens;
    return OutlinedButton.styleFrom(
      minimumSize: Size(tokens.touchTarget, tokens.touchTarget),
      padding: const EdgeInsets.symmetric(
        horizontal: CollectSpacing.x5,
        vertical: CollectSpacing.x3,
      ),
      shape: RoundedRectangleBorder(borderRadius: CollectRadius.controlBorder),
      foregroundColor: colors.textPrimary,
      side: BorderSide(color: CollectRuntimeTokens.controlBorder(colors)),
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
    final tokens = context.collectUniversalTokens;
    final border = UnderlineInputBorder(
      borderSide: BorderSide(color: CollectRuntimeTokens.inputBorder(colors)),
    );
    return InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 1,
      prefixText: prefix,
      filled: false,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(
          color: tokens.focusRing,
          width: tokens.focusRingWidth,
        ),
      ),
    );
  }
}
