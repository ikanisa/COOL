import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/cool_icons.dart';
import '../../../core/theme/theme_preference.dart';
import '../../../shared/widgets/cool_card.dart';

part 'profile_settings_widgets_extras.dart';
part 'profile_settings_widgets_appearance.dart';

/// A titled settings section containing a list of [ProfileSettingsRow]s.
class ProfileSettingsSection extends StatelessWidget {
  const ProfileSettingsSection({
    required this.title,
    required this.rows,
    this.useCard = true,
    super.key,
  });

  final String title;
  final List<ProfileSettingsRow> rows;
  final bool useCard;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 12),
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: colors.secondaryText,
              ),
            ),
          ),
        ),
        if (useCard)
          CoolCard(
            backgroundColor: colors.cardSurfaceStrong,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  rows[i],
                  if (i < rows.length - 1) const SizedBox(height: CoolSpace.x2),
                ],
              ],
            ),
          )
        else
          Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                rows[i],
                if (i < rows.length - 1) const SizedBox(height: CoolSpace.x2),
              ],
            ],
          ),
      ],
    );
  }
}

class ProfileFactItem {
  const ProfileFactItem({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;
}

/// Compact summary card for passive account facts.
class ProfileFactsCard extends StatelessWidget {
  const ProfileFactsCard({required this.items, super.key});

  final List<ProfileFactItem> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return CoolCard(
      backgroundColor: colors.cardSurface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 560) {
            return Column(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  _ProfileFactTile(item: items[index]),
                  if (index < items.length - 1)
                    const SizedBox(height: CoolSpace.x4),
                ],
              ],
            );
          }

          return Row(
            children: [
              for (var index = 0; index < items.length; index++) ...[
                Expanded(child: _ProfileFactTile(item: items[index])),
                if (index < items.length - 1) const SizedBox(width: 20),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ProfileFactTile extends StatelessWidget {
  const _ProfileFactTile({required this.item});

  final ProfileFactItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Semantics(
      label: '${item.label}: ${item.value}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.tertiaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.value,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: item.valueColor ?? colors.primaryText,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Single row inside a [ProfileSettingsSection].
class ProfileSettingsRow extends StatelessWidget {
  const ProfileSettingsRow({
    required this.icon,
    required this.label,
    this.value,
    this.valueColor,
    this.labelColor,
    this.iconColor,
    this.onTap,
    this.trailing,
    this.showArrow = true,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? value;
  final Color? valueColor;
  final Color? labelColor;
  final Color? iconColor;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final resolvedLabelColor = labelColor ?? colors.primaryText;
    final resolvedValueColor = valueColor ?? colors.secondaryText;
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final shouldStackValue =
            trailing == null && value != null && constraints.maxWidth < 390;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            crossAxisAlignment: shouldStackValue
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.operationalSurface,
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                  boxShadow: CoolShadows.floating(
                    Theme.of(context).brightness,
                    strength: 0.18,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 22,
                  color: iconColor ?? resolvedLabelColor.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: shouldStackValue
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: resolvedLabelColor,
                                ),
                          ),
                          const SizedBox(height: CoolSpace.x1),
                          Text(
                            value!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: resolvedValueColor,
                                  height: 1.4,
                                ),
                          ),
                        ],
                      )
                    : Text(
                        label,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: resolvedLabelColor,
                        ),
                      ),
              ),
              if (trailing != null)
                trailing!
              else if (!shouldStackValue && value != null) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    value!,
                    maxLines: 2,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: resolvedValueColor,
                    ),
                  ),
                ),
              ],
              if (onTap != null && showArrow) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: EdgeInsets.only(top: shouldStackValue ? 4 : 0),
                  child: Icon(
                    CoolIcons.chevron,
                    size: 22,
                    color: colors.tertiaryText,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );

    final semanticsLabel = value == null ? label : '$label: $value';
    if (onTap == null) {
      return Semantics(label: semanticsLabel, child: content);
    }

    return Semantics(
      button: true,
      label: semanticsLabel,
      hint: context.l10n.profileOpenLabel(label),
      child: InkWell(
        onTap: onTap,
        splashColor: colors.accent.withValues(alpha: 0.08),
        highlightColor: Colors.transparent,
        child: content,
      ),
    );
  }
}
