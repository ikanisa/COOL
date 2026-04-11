import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

/// Data class for an inline action chip.
class CoolActionItem {
  const CoolActionItem({
    required this.label,
    required this.onTap,
    this.icon,
    this.isPrimary = false,
    this.isDestructive = false,
    this.isLoading = false,
  });

  /// Short label (1–2 words).
  final String label;

  /// Tap handler.
  final VoidCallback? onTap;

  /// Optional leading icon.
  final IconData? icon;

  /// Whether this is the primary/emphasized action.
  final bool isPrimary;

  /// Whether this is a destructive action (renders in danger color).
  final bool isDestructive;

  /// Whether to show a loading indicator.
  final bool isLoading;
}

/// A horizontal row of compact action chips for contextual quick actions.
///
/// Replaces ad-hoc `Row` of buttons at the bottom of detail screens
/// and inline action strips.
///
/// ```dart
/// CoolActionRow(
///   actions: [
///     CoolActionItem(label: 'Contribute', icon: CoolIcons.contribute, isPrimary: true, onTap: ...),
///     CoolActionItem(label: 'Invite', icon: CoolIcons.invite, onTap: ...),
///     CoolActionItem(label: 'Share', icon: CoolIcons.share, onTap: ...),
///   ],
/// )
/// ```
class CoolActionRow extends StatelessWidget {
  const CoolActionRow({
    required this.actions,
    this.scrollable = true,
    this.spacing,
    this.padding,
    super.key,
  });

  /// List of actions to display.
  final List<CoolActionItem> actions;

  /// Whether the row scrolls horizontally (default: true).
  final bool scrollable;

  /// Spacing between action chips.
  final double? spacing;

  /// Outer padding.
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final resolvedSpacing = spacing ?? CoolSpace.x2;

    final chips = <Widget>[];
    for (int i = 0; i < actions.length; i++) {
      chips.add(_ActionChip(action: actions[i]));
      if (i < actions.length - 1) {
        chips.add(SizedBox(width: resolvedSpacing));
      }
    }

    final row = Row(
      mainAxisSize: scrollable ? MainAxisSize.min : MainAxisSize.max,
      children: chips,
    );

    if (scrollable) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding ?? EdgeInsets.zero,
        child: row,
      );
    }

    return Padding(padding: padding ?? EdgeInsets.zero, child: row);
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.action});

  final CoolActionItem action;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final isActive = action.isPrimary;
    final isDestructive = action.isDestructive;
    final enabled = action.onTap != null && !action.isLoading;

    final bg = isActive
        ? colors.chipSelectedBackground
        : isDestructive
            ? colors.danger.withValues(alpha: 0.10)
            : colors.chipBackground;
    final fg = isDestructive
        ? colors.danger
        : isActive
            ? colors.primaryText
            : colors.secondaryText;

    return Semantics(
      button: true,
      label: action.label,
      enabled: enabled,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? action.onTap : null,
          borderRadius: BorderRadius.circular(CoolRadii.pill),
          child: AnimatedContainer(
            duration: CoolMotion.quick,
            curve: CoolMotion.enterCurve,
            padding: const EdgeInsets.symmetric(
              horizontal: CoolSpace.x4,
              vertical: CoolSpace.x3,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(CoolRadii.pill),
              border: Border.all(
                color: isActive
                    ? colors.accent.withValues(alpha: 0.24)
                    : colors.border,
              ),
            ),
            child: action.isLoading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: fg,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (action.icon != null) ...[
                        Icon(action.icon, size: 16, color: fg),
                        const SizedBox(width: CoolSpace.x2),
                      ],
                      Text(
                        action.label,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight:
                              isActive ? FontWeight.w600 : FontWeight.w500,
                          color: fg,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
