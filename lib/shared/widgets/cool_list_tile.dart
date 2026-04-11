import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';
import '../../core/theme/cool_icons.dart';
import 'cool_icon_box.dart';
import 'cool_skeleton.dart';

/// A universal row widget for icon-led list patterns.
class CoolListTile extends StatelessWidget {
  const CoolListTile({
    required this.title,
    this.leading,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.isDestructive = false,
    this.showChevron,
    this.dense = false,
    this.titleMaxLines = 1,
    this.subtitleMaxLines = 1,
    this.contentPadding,
    this.semanticsLabel,
    super.key,
  });

  final Widget? leading;

  final String title;

  final String? subtitle;

  final Widget? trailing;

  final VoidCallback? onTap;

  final bool isDestructive;

  final bool? showChevron;

  final bool dense;

  final int titleMaxLines;

  final int subtitleMaxLines;

  final EdgeInsets? contentPadding;

  final String? semanticsLabel;
  static Widget skeleton({bool hasSubtitle = true, bool dense = false}) {
    return _CoolListTileSkeleton(hasSubtitle: hasSubtitle, dense: dense);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    final titleColor = isDestructive ? colors.danger : colors.primaryText;
    final iconColor = isDestructive ? colors.danger : null;
    final verticalPad = dense ? CoolSpace.x2 : CoolSpace.x3;
    final effectiveShowChevron =
        showChevron ?? (onTap != null && trailing == null);

    final row = Padding(
      padding: contentPadding ?? EdgeInsets.symmetric(vertical: verticalPad),
      child: Row(
        children: [
          if (leading != null) ...[
            if (isDestructive && leading is CoolIconBox)
              CoolIconBox(
                icon: (leading! as CoolIconBox).icon,
                accent: colors.danger,
                size: (leading! as CoolIconBox).size,
                variant: (leading! as CoolIconBox).variant,
                iconWidget: (leading! as CoolIconBox).iconWidget,
              )
            else
              leading!,
            const SizedBox(width: CoolSpace.x4),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: titleMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: text.headline(
                    theme.textTheme.titleSmall,
                    fontWeight: FontWeight.w600,
                    color: titleColor,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: subtitleMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: text
                        .mobiLabel(color: colors.secondaryText)
                        .copyWith(fontWeight: FontWeight.w500),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: CoolSpace.x3),
            trailing!,
          ],
          if (effectiveShowChevron) ...[
            const SizedBox(width: CoolSpace.x2),
            Icon(
              CoolIcons.chevron,
              color: iconColor ?? colors.tertiaryText,
              size: 20,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return Semantics(
        label:
            semanticsLabel ?? '$title${subtitle != null ? '. $subtitle' : ''}',
        child: row,
      );
    }

    return Semantics(
      button: true,
      label: semanticsLabel ?? '$title${subtitle != null ? '. $subtitle' : ''}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CoolRadii.sm),
        child: row,
      ),
    );
  }
}

/// Skeleton loading state for [CoolListTile].
class _CoolListTileSkeleton extends StatelessWidget {
  const _CoolListTileSkeleton({this.hasSubtitle = true, this.dense = false});

  final bool hasSubtitle;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final verticalPad = dense ? CoolSpace.x2 : CoolSpace.x3;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPad),
      child: Row(
        children: [
          const CoolSkeleton(width: 44, height: 44, borderRadius: CoolRadii.md),
          const SizedBox(width: CoolSpace.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CoolSkeleton.line(width: 140),
                if (hasSubtitle) ...[
                  const SizedBox(height: CoolSpace.x2),
                  const CoolSkeleton.line(width: 100),
                ],
              ],
            ),
          ),
          const SizedBox(width: CoolSpace.x3),
          const CoolSkeleton.line(width: 60),
        ],
      ),
    );
  }
}
