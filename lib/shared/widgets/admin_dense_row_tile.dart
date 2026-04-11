import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

/// Dense data row tile for admin list surfaces.
///
/// Renders an icon slot, title/subtitle, and trailing action in a compact
/// layout. Designed for admin management screens with many items.
class AdminDenseRowTile extends StatelessWidget {
  const AdminDenseRowTile({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.contentPadding,
    super.key,
  });

  /// Primary row title.
  final String title;

  /// Optional secondary text below the title.
  final String? subtitle;

  /// Optional leading widget (e.g. icon, avatar, or emoji).
  final Widget? leading;

  /// Optional trailing widget (e.g. action button, switch, or chip).
  final Widget? trailing;

  /// Tap handler for the entire row.
  final VoidCallback? onTap;

  /// Custom content padding.
  final EdgeInsets? contentPadding;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final resolvedPadding =
        contentPadding ??
        const EdgeInsets.symmetric(horizontal: 14, vertical: 10);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CoolRadii.sm),
        child: Padding(
          padding: resolvedPadding,
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w400,
                        color: colors.primaryText,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.secondaryText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}
