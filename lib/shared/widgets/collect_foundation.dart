import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_component_tokens.dart';
import '../../app/theme/collect_icons.dart';
import '../../app/theme/collect_motion.dart';
import '../../app/theme/collect_radius.dart';
import '../../app/theme/collect_spacing.dart';
import '../../app/theme/revolut_borrowed_tokens.dart';
import '../models/collect_models.dart';

class CollectButton extends StatelessWidget {
  const CollectButton({
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = CollectButtonVariant.primary,
    this.expand = false,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final CollectButtonVariant variant;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final style = switch (variant) {
      CollectButtonVariant.primary => CollectComponentTokens.filledButton(
        context,
      ),
      CollectButtonVariant.secondary => CollectComponentTokens.outlinedButton(
        context,
      ),
      CollectButtonVariant.subtle => TextButton.styleFrom(
        minimumSize: const Size(CollectSpacing.target, CollectSpacing.target),
        foregroundColor: colors.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: CollectRadius.mdBorder),
      ),
      CollectButtonVariant.danger => CollectComponentTokens.filledButton(
        context,
      ).copyWith(backgroundColor: WidgetStatePropertyAll(colors.danger)),
    };
    final child = icon == null
        ? Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)
        : Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon),
              CollectSpacing.gapW8,
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
    final button = switch (variant) {
      CollectButtonVariant.primary || CollectButtonVariant.danger =>
        FilledButton(onPressed: onPressed, style: style, child: child),
      CollectButtonVariant.secondary => OutlinedButton(
        onPressed: onPressed,
        style: style,
        child: child,
      ),
      CollectButtonVariant.subtle => TextButton(
        onPressed: onPressed,
        style: style,
        child: child,
      ),
    };
    if (!expand) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}

enum CollectButtonVariant { primary, secondary, subtle, danger }

IconData collectionTypeIcon(CollectionType type) {
  return switch (type) {
    CollectionType.ikimina => CollectIcons.savings,
    CollectionType.sport => CollectIcons.sport,
    CollectionType.church => CollectIcons.church,
    CollectionType.wedding => CollectIcons.wedding,
    CollectionType.other => CollectIcons.collections,
  };
}

class CollectionTypeBadge extends StatelessWidget {
  const CollectionTypeBadge({
    required this.type,
    this.compact = false,
    this.iconOnly = false,
    super.key,
  });

  final CollectionType type;
  final bool compact;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final accent = colors.actionColor;
    final foreground = colors.textPrimary;
    final background = RevolutBorrowedTokens.badgeBackground(colors, accent);
    return Semantics(
      label: '${type.label} collection',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: CollectRadius.pillBorder,
            border: Border.all(
              color: RevolutBorrowedTokens.badgeBorder(colors, accent),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: iconOnly
                  ? CollectSpacing.x2
                  : compact
                  ? CollectSpacing.x2
                  : CollectSpacing.x3,
              vertical: compact ? CollectSpacing.x1 : CollectSpacing.x2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  collectionTypeIcon(type),
                  size: compact ? 15 : 17,
                  color: foreground,
                ),
                if (!iconOnly) ...[
                  CollectSpacing.gapW8,
                  Text(
                    type.label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CollectCard extends StatelessWidget {
  const CollectCard({
    required this.child,
    this.onTap,
    this.padding = CollectSpacing.cardPadding,
    this.emphasis = CollectCardEmphasis.normal,
    this.backgroundGradient,
    this.accentColor,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final CollectCardEmphasis emphasis;
  final Gradient? backgroundGradient;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final brightness = Theme.of(context).brightness;
    final tokenEmphasis = emphasis.borrowedToken;
    final radius = RevolutBorrowedTokens.cardRadius(tokenEmphasis);
    final background = RevolutBorrowedTokens.cardBackground(
      colors,
      brightness,
      tokenEmphasis,
      accentColor,
    );
    final backgroundOpacity = RevolutBorrowedTokens.cardOpacity(
      brightness,
      tokenEmphasis,
    );
    final border = RevolutBorrowedTokens.cardBorder(
      colors,
      brightness,
      tokenEmphasis,
      accentColor,
    );
    final shadows = RevolutBorrowedTokens.cardShadows(
      colors,
      brightness,
      tokenEmphasis,
      accentColor,
    );
    final container = AnimatedContainer(
      duration: CollectMotion.duration(context, CollectMotion.fast),
      curve: CollectMotion.standard,
      decoration: BoxDecoration(
        color: backgroundGradient == null
            ? background.withValues(alpha: backgroundOpacity)
            : null,
        gradient: backgroundGradient,
        borderRadius: radius,
        border: border,
        boxShadow: shadows,
      ),
      child: Padding(padding: padding, child: child),
    );
    final decorated = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: container,
      ),
    );
    return Material(
      color: colors.transparent,
      borderRadius: radius,
      child: onTap == null
          ? decorated
          : InkWell(borderRadius: radius, onTap: onTap, child: decorated),
    );
  }
}

enum CollectCardEmphasis { flat, normal, hero, tonal, glow, outline, compact }

extension on CollectCardEmphasis {
  CollectBorrowedCardEmphasis get borrowedToken {
    return switch (this) {
      CollectCardEmphasis.flat => CollectBorrowedCardEmphasis.flat,
      CollectCardEmphasis.normal => CollectBorrowedCardEmphasis.normal,
      CollectCardEmphasis.hero => CollectBorrowedCardEmphasis.hero,
      CollectCardEmphasis.tonal => CollectBorrowedCardEmphasis.tonal,
      CollectCardEmphasis.glow => CollectBorrowedCardEmphasis.glow,
      CollectCardEmphasis.outline => CollectBorrowedCardEmphasis.outline,
      CollectCardEmphasis.compact => CollectBorrowedCardEmphasis.compact,
    };
  }
}
