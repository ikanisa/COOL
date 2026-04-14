import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

export 'admin_workspace_kit_parts.dart';

/// Compact admin-specific interaction tones.
enum AdminTone { neutral, info, success, warning, danger, accent }

Color adminToneColor(BuildContext context, AdminTone tone) {
  final colors = context.coolSemanticColors;
  return switch (tone) {
    AdminTone.info => colors.info,
    AdminTone.success => colors.success,
    AdminTone.warning => colors.warning,
    AdminTone.danger => colors.danger,
    AdminTone.accent => colors.accent,
    AdminTone.neutral => colors.neutral,
  };
}

Color adminToneSurface(BuildContext context, AdminTone tone) {
  final color = adminToneColor(context, tone);
  return color.withValues(alpha: 0.10);
}

/// Low-noise panel surface used across admin shells.
class AdminPanelSurface extends StatelessWidget {
  const AdminPanelSurface({
    required this.child,
    this.padding = const EdgeInsets.all(CoolSpace.x5),
    this.backgroundColor,
    this.borderColor,
    this.radius = CoolRadii.lg,
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final decoration = BoxDecoration(
      color: backgroundColor ?? colors.elevatedBackground,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? colors.borderStrong.withValues(alpha: 0.7),
      ),
    );

    final content = DecoratedBox(
      decoration: decoration,
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) {
      return content;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: content,
      ),
    );
  }
}

class AdminStatusChip extends StatelessWidget {
  const AdminStatusChip({
    required this.label,
    this.tone = AdminTone.neutral,
    this.icon,
    this.trailing,
    super.key,
  });

  final String label;
  final AdminTone tone;
  final IconData? icon;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final color = adminToneColor(context, tone);
    final surface = adminToneSurface(context, tone);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(CoolRadii.pill),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: CoolSpace.x1),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: CoolSpace.x1),
            Text(
              trailing!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class AdminMetricItem {
  const AdminMetricItem({
    required this.label,
    required this.value,
    this.hint,
    this.icon,
    this.tone = AdminTone.neutral,
  });

  final String label;
  final String value;
  final String? hint;
  final IconData? icon;
  final AdminTone tone;
}

class AdminMetricStrip extends StatelessWidget {
  const AdminMetricStrip({
    required this.metrics,
    this.minColumnWidth = 180,
    super.key,
  });

  final List<AdminMetricItem> metrics;
  final double minColumnWidth;

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width ~/ minColumnWidth;
        final crossAxisCount = columns.clamp(1, 4);
        const spacing = CoolSpace.x3;
        final safeWidth = width.isFinite ? width : minColumnWidth;
        final itemWidth =
            (safeWidth - (spacing * (crossAxisCount - 1))) / crossAxisCount;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: itemWidth,
                child: _AdminMetricCard(metric: metric),
              ),
          ],
        );
      },
    );
  }
}

class _AdminMetricCard extends StatelessWidget {
  const _AdminMetricCard({required this.metric});

  final AdminMetricItem metric;

  @override
  Widget build(BuildContext context) {
    final color = adminToneColor(context, metric.tone);
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return AdminPanelSurface(
      backgroundColor: colors.cardSurface,
      padding: const EdgeInsets.all(CoolSpace.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (metric.icon != null) ...[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(CoolRadii.sm),
                  ),
                  alignment: Alignment.center,
                  child: Icon(metric.icon, size: 14, color: color),
                ),
                const SizedBox(width: CoolSpace.x2),
              ],
              Expanded(
                child: Text(
                  metric.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.secondaryText,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x4),
          Text(
            metric.value,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
          if (metric.hint != null) ...[
            const SizedBox(height: CoolSpace.x1),
            Text(
              metric.hint!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.tertiaryText,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class AdminPageHeader extends StatelessWidget {
  const AdminPageHeader({
    required this.title,
    this.subtitle,
    this.eyebrow,
    this.badges = const <Widget>[],
    this.actions = const <Widget>[],
    super.key,
  });

  final String title;
  final String? subtitle;
  final String? eyebrow;
  final List<Widget> badges;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return AdminPanelSurface(
      backgroundColor: colors.operationalSurface,
      padding: const EdgeInsets.all(CoolSpace.x6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 820;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null) ...[
                Text(
                  eyebrow!,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.secondaryText,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: CoolSpace.x2),
              ],
              if (stacked) ...[
                _HeaderCopy(title: title, subtitle: subtitle),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: CoolSpace.x4),
                  Wrap(
                    spacing: CoolSpace.x2,
                    runSpacing: CoolSpace.x2,
                    children: actions,
                  ),
                ],
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _HeaderCopy(title: title, subtitle: subtitle),
                    ),
                    if (actions.isNotEmpty) ...[
                      const SizedBox(width: CoolSpace.x4),
                      Wrap(
                        spacing: CoolSpace.x2,
                        runSpacing: CoolSpace.x2,
                        alignment: WrapAlignment.end,
                        children: actions,
                      ),
                    ],
                  ],
                ),
              if (badges.isNotEmpty) ...[
                const SizedBox(height: CoolSpace.x4),
                Wrap(
                  spacing: CoolSpace.x2,
                  runSpacing: CoolSpace.x2,
                  children: badges,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _HeaderCopy extends StatelessWidget {
  const _HeaderCopy({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: colors.primaryText,
            fontWeight: FontWeight.w800,
            height: 1.05,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: CoolSpace.x2),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

class AdminToolbar extends StatelessWidget {
  const AdminToolbar({
    this.search,
    this.filters = const <Widget>[],
    this.actions = const <Widget>[],
    super.key,
  });

  final Widget? search;
  final List<Widget> filters;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    if (search == null && filters.isEmpty && actions.isEmpty) {
      return const SizedBox.shrink();
    }

    final colors = context.coolSemanticColors;

    return AdminPanelSurface(
      backgroundColor: colors.cardSurface,
      padding: const EdgeInsets.all(CoolSpace.x4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 860;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (search != null || actions.isNotEmpty)
                if (stacked) ...[
                  // ignore: use_null_aware_elements
                  if (search != null) search!,
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: CoolSpace.x3),
                    Wrap(
                      spacing: CoolSpace.x2,
                      runSpacing: CoolSpace.x2,
                      children: actions,
                    ),
                  ],
                ] else
                  Row(
                    children: [
                      if (search != null) Expanded(child: search!),
                      if (search != null && actions.isNotEmpty)
                        const SizedBox(width: CoolSpace.x3),
                      if (actions.isNotEmpty)
                        Wrap(
                          spacing: CoolSpace.x2,
                          runSpacing: CoolSpace.x2,
                          children: actions,
                        ),
                    ],
                  ),
              if (filters.isNotEmpty) ...[
                if (search != null || actions.isNotEmpty)
                  const SizedBox(height: CoolSpace.x3),
                Wrap(
                  spacing: CoolSpace.x2,
                  runSpacing: CoolSpace.x2,
                  children: filters,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

