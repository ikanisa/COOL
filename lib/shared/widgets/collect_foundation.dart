import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_component_tokens.dart';
import '../../app/theme/collect_icons.dart';
import '../../app/theme/collect_motion.dart';
import '../../app/theme/collect_radius.dart';
import '../../app/theme/collect_shadows.dart';
import '../../app/theme/collect_spacing.dart';
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
    super.key,
  });

  final CollectionType type;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.textPrimary;
    final background = Color.alphaBlend(
      colors.actionColor.withValues(alpha: 0.10),
      colors.surfaceRaised,
    );
    return Semantics(
      label: '${type.label} collection',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: CollectRadius.pillBorder,
            border: Border.all(
              color: colors.actionColor.withValues(alpha: 0.18),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? CollectSpacing.x2 : CollectSpacing.x3,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = switch (emphasis) {
      CollectCardEmphasis.hero ||
      CollectCardEmphasis.glow => CollectRadius.cardLargeBorder,
      CollectCardEmphasis.compact => CollectRadius.mdBorder,
      _ => CollectRadius.cardBorder,
    };
    final background = switch (emphasis) {
      CollectCardEmphasis.flat =>
        isDark ? CollectColors.referenceContentDark : colors.surface,
      CollectCardEmphasis.outline =>
        isDark
            ? CollectColors.referencePaymentsPurpleDeep
            : colors.surfaceRaised,
      CollectCardEmphasis.tonal => Color.alphaBlend(
        (accentColor ?? colors.actionColor).withValues(
          alpha: isDark ? 0.18 : 0.08,
        ),
        isDark ? CollectColors.referenceAssetNavy : colors.surfaceRaised,
      ),
      CollectCardEmphasis.glow =>
        isDark ? CollectColors.referenceAssetNavy : colors.surfaceRaised,
      CollectCardEmphasis.compact =>
        isDark
            ? CollectColors.referencePaymentsPurpleDeep
            : colors.surfaceRaised,
      _ => isDark ? CollectColors.referencePaymentsPurple : colors.surfaceMuted,
    };
    final backgroundOpacity = switch (emphasis) {
      CollectCardEmphasis.hero => isDark ? 0.90 : 0.82,
      CollectCardEmphasis.glow => isDark ? 0.88 : 0.80,
      CollectCardEmphasis.tonal => isDark ? 0.86 : 0.78,
      CollectCardEmphasis.compact => isDark ? 0.84 : 0.76,
      CollectCardEmphasis.flat => isDark ? 0.82 : 0.70,
      CollectCardEmphasis.outline => isDark ? 0.82 : 0.74,
      CollectCardEmphasis.normal => isDark ? 0.84 : 0.78,
    };
    final border = switch (emphasis) {
      CollectCardEmphasis.flat => null,
      CollectCardEmphasis.glow => Border.all(
        color: (accentColor ?? colors.actionColor).withValues(
          alpha: isDark ? 0.34 : 0.24,
        ),
      ),
      CollectCardEmphasis.outline => Border.all(
        color: isDark
            ? colors.onImagePrimary.withValues(alpha: 0.14)
            : colors.border,
      ),
      CollectCardEmphasis.compact => Border.all(
        color: isDark
            ? colors.onImagePrimary.withValues(alpha: 0.12)
            : colors.border.withValues(alpha: 0.72),
      ),
      _ => Border.all(
        color: isDark
            ? colors.onImagePrimary.withValues(alpha: 0.12)
            : colors.border,
      ),
    };
    final shadows = switch (emphasis) {
      CollectCardEmphasis.flat ||
      CollectCardEmphasis.outline ||
      CollectCardEmphasis.compact => const <BoxShadow>[],
      CollectCardEmphasis.glow => [
        BoxShadow(
          color: (accentColor ?? colors.actionColor).withValues(
            alpha: isDark ? 0.20 : 0.13,
          ),
          blurRadius: isDark ? 34 : 28,
          offset: const Offset(0, 18),
        ),
      ],
      _ => CollectShadows.card(),
    };
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
