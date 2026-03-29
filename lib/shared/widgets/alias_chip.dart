import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/cool_foundations.dart';
import '../../core/theme/rs_colors.dart';

/// Displays a 6-digit fan alias in JetBrains Mono on a glass chip.
///
/// ROUGEBLACK design system component for anonymous identity display.
/// Uses the [CoolTextStyles.mono] helper for consistent monospace rendering.
///
/// ```dart
/// AliasChip(alias: '847291')
/// AliasChip(alias: '847291', showHash: true) // → #847291
/// ```
class AliasChip extends StatelessWidget {
  const AliasChip({
    required this.alias,
    this.showHash = false,
    this.size = AliasChipSize.md,
    this.onTap,
    this.copyOnLongPress = true,
    super.key,
  });

  /// The 6-digit numeric alias.
  final String alias;

  /// Whether to prefix with '#'.
  final bool showHash;

  /// Chip size preset.
  final AliasChipSize size;

  /// Optional tap callback.
  final VoidCallback? onTap;

  /// If true, long-press copies alias to clipboard with haptic feedback.
  final bool copyOnLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;

    final displayText = showHash ? '#$alias' : alias;

    final style = text.mono(
      TextStyle(
        fontSize: size.fontSize,
        fontWeight: FontWeight.w500,
      ),
      color: colors.primaryText,
      letterSpacing: 2.0,
    );

    return GestureDetector(
      onTap: onTap,
      onLongPress: copyOnLongPress ? () => _copyAlias(context) : null,
      child: Container(
        padding: size.padding,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: RsColors.glassOpacity),
          borderRadius: BorderRadius.circular(CoolRadii.pill),
          border: Border.all(
            color: Colors.white.withValues(alpha: RsColors.glassBorderOpacity),
            width: 1,
          ),
        ),
        child: Text(
          displayText,
          style: style,
          maxLines: 1,
        ),
      ),
    );
  }

  void _copyAlias(BuildContext context) {
    Clipboard.setData(ClipboardData(text: alias));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Alias #$alias copied'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Size presets for [AliasChip].
enum AliasChipSize {
  sm,
  md,
  lg;

  double get fontSize => switch (this) {
    AliasChipSize.sm => 12,
    AliasChipSize.md => 14,
    AliasChipSize.lg => 18,
  };

  EdgeInsets get padding => switch (this) {
    AliasChipSize.sm => const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    AliasChipSize.md => const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    AliasChipSize.lg => const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  };
}
