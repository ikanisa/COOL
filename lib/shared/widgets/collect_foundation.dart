import 'package:flutter/material.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_component_tokens.dart';
import '../../app/theme/collect_icons.dart';
import '../../app/theme/collect_motion.dart';
import '../../app/theme/collect_radius.dart';
import '../../app/theme/collect_spacing.dart';
import '../../app/theme/collect_runtime_tokens.dart';
import '../../app/theme/collect_typography.dart';
import '../models/collect_models.dart';
import '../utils/collect_haptics.dart';

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
    final usesAccessibilityText =
        MediaQuery.textScalerOf(context).scale(1) >= 1.3;
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
      CollectButtonVariant.danger => CollectComponentTokens.dangerButton(
        context,
      ),
    };
    final child = icon == null
        ? usesAccessibilityText
              ? Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                )
              : Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)
        : Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon),
              CollectSpacing.gapW8,
              Flexible(
                child: usesAccessibilityText
                    ? Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      )
                    : Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          );
    void handlePressed() {
      if (variant == CollectButtonVariant.danger) {
        CollectHaptics.warning();
      } else if (variant == CollectButtonVariant.primary) {
        CollectHaptics.lightImpact();
      } else {
        CollectHaptics.selection();
      }
      onPressed?.call();
    }

    final button = switch (variant) {
      CollectButtonVariant.primary ||
      CollectButtonVariant.danger => FilledButton(
        onPressed: onPressed == null ? null : handlePressed,
        style: style,
        child: child,
      ),
      CollectButtonVariant.secondary => OutlinedButton(
        onPressed: onPressed == null ? null : handlePressed,
        style: style,
        child: child,
      ),
      CollectButtonVariant.subtle => TextButton(
        onPressed: onPressed == null ? null : handlePressed,
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
    final background = CollectRuntimeTokens.badgeBackground(colors, accent);
    return Semantics(
      label: '${type.label} collection',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: CollectRadius.pillBorder,
            border: Border.all(
              color: CollectRuntimeTokens.badgeBorder(colors, accent),
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
                      fontWeight: CollectTypography.weightBold,
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

class CollectionTypeIconSelector extends StatelessWidget {
  const CollectionTypeIconSelector({
    required this.selected,
    required this.onChanged,
    this.options,
    super.key,
  });

  final CollectionType selected;
  final ValueChanged<CollectionType> onChanged;
  final List<CollectionTypeCatalogItem>? options;

  @override
  Widget build(BuildContext context) {
    final catalogOptions = options?.isNotEmpty == true
        ? options!
        : CollectionTypeCatalogConfig.defaults.types;
    return Wrap(
      spacing: CollectSpacing.x3,
      runSpacing: CollectSpacing.x3,
      children: [
        for (final option in catalogOptions)
          _CollectionTypeIconChoice(
            option: option,
            selected: selected == option.type,
            onTap: () => onChanged(option.type),
          ),
      ],
    );
  }
}

class _CollectionTypeIconChoice extends StatelessWidget {
  const _CollectionTypeIconChoice({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final CollectionTypeCatalogItem option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final type = option.type;
    final colors = context.collectColors;
    final foreground = selected ? colors.onAccent : colors.textSecondary;
    final border = selected ? colors.actionColor : colors.panelBorder;
    final fill = selected ? colors.actionColor : colors.controlSurface;
    return Tooltip(
      message: option.label,
      child: Semantics(
        button: true,
        selected: selected,
        label: '${option.label} collection type',
        child: ExcludeSemantics(
          child: InkWell(
            onTap: onTap,
            borderRadius: CollectRadius.controlBorder,
            child: AnimatedContainer(
              duration: CollectMotion.duration(context, CollectMotion.fast),
              curve: CollectMotion.standard,
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: CollectRadius.controlBorder,
                border: Border.all(color: border, width: selected ? 0 : 1),
              ),
              child: Icon(
                collectionTypeIcon(type),
                color: foreground,
                size: 23,
              ),
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
    this.accentColor,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final CollectCardEmphasis emphasis;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final brightness = Theme.of(context).brightness;
    final tokenEmphasis = emphasis.runtimeToken;
    final radius = CollectRuntimeTokens.cardRadius(tokenEmphasis);
    final background = CollectRuntimeTokens.cardBackground(
      colors,
      brightness,
      tokenEmphasis,
      accentColor,
    );
    final backgroundOpacity = CollectRuntimeTokens.cardOpacity(
      brightness,
      tokenEmphasis,
    );
    final border = CollectRuntimeTokens.cardBorder(
      colors,
      brightness,
      tokenEmphasis,
      accentColor,
    );
    final shadows = CollectRuntimeTokens.cardShadows(
      colors,
      brightness,
      tokenEmphasis,
      accentColor,
    );
    final container = AnimatedContainer(
      duration: CollectMotion.duration(context, CollectMotion.fast),
      curve: CollectMotion.standard,
      decoration: BoxDecoration(
        color: background.withValues(alpha: backgroundOpacity),
        borderRadius: radius,
        border: border,
        boxShadow: shadows,
      ),
      child: Padding(padding: padding, child: child),
    );
    final decorated = ClipRRect(borderRadius: radius, child: container);
    return Material(
      color: colors.transparent,
      borderRadius: radius,
      child: onTap == null
          ? decorated
          : InkWell(borderRadius: radius, onTap: onTap, child: decorated),
    );
  }
}

/// A flat card whose read-only rows are built only near the viewport.
///
/// Use in ScreenScaffold.sliver, not inside a Column or shrink-wrapped list.
/// The list retains the normal card's spacing, surface and corner radius.
class CollectSliverCardList extends StatelessWidget {
  const CollectSliverCardList({
    required this.itemCount,
    required this.itemBuilder,
    this.separatorBuilder,
    this.topSpacing = 0,
    super.key,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final IndexedWidgetBuilder? separatorBuilder;
  final double topSpacing;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final brightness = Theme.of(context).brightness;
    const emphasis = CollectRuntimeCardEmphasis.flat;
    return SliverPadding(
      padding: EdgeInsets.only(top: topSpacing),
      sliver: DecoratedSliver(
        decoration: BoxDecoration(
          color:
              CollectRuntimeTokens.cardBackground(
                colors,
                brightness,
                emphasis,
                null,
              ).withValues(
                alpha: CollectRuntimeTokens.cardOpacity(brightness, emphasis),
              ),
          borderRadius: CollectRuntimeTokens.cardRadius(emphasis),
        ),
        sliver: SliverPadding(
          padding: CollectSpacing.cardPadding,
          sliver: SliverList.builder(
            itemCount: itemCount,
            addAutomaticKeepAlives: false,
            itemBuilder: (context, index) {
              final item = itemBuilder(context, index);
              return Material(
                key: item.key,
                type: MaterialType.transparency,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    item,
                    if (separatorBuilder != null && index < itemCount - 1)
                      separatorBuilder!(context, index),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

enum CollectCardEmphasis { flat, normal, hero, tonal, glow, outline, compact }

extension on CollectCardEmphasis {
  CollectRuntimeCardEmphasis get runtimeToken {
    return switch (this) {
      CollectCardEmphasis.flat => CollectRuntimeCardEmphasis.flat,
      CollectCardEmphasis.normal => CollectRuntimeCardEmphasis.normal,
      CollectCardEmphasis.hero => CollectRuntimeCardEmphasis.hero,
      CollectCardEmphasis.tonal => CollectRuntimeCardEmphasis.tonal,
      CollectCardEmphasis.glow => CollectRuntimeCardEmphasis.glow,
      CollectCardEmphasis.outline => CollectRuntimeCardEmphasis.outline,
      CollectCardEmphasis.compact => CollectRuntimeCardEmphasis.compact,
    };
  }
}
