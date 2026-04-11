import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

/// Compact admin-specific interaction tones.
enum AdminTone { neutral, info, success, warning, danger, accent }

Color _adminToneColor(BuildContext context, AdminTone tone) {
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

Color _adminToneSurface(BuildContext context, AdminTone tone) {
  final color = _adminToneColor(context, tone);
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
    final color = _adminToneColor(context, tone);
    final surface = _adminToneSurface(context, tone);
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
    final color = _adminToneColor(context, metric.tone);
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

class AdminSectionCard extends StatelessWidget {
  const AdminSectionCard({
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(CoolSpace.x5),
    super.key,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return AdminPanelSurface(
      backgroundColor: colors.cardSurface,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null || subtitle != null || trailing != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null)
                        Text(
                          title!,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: colors.primaryText,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      if (subtitle != null) ...[
                        const SizedBox(height: CoolSpace.x1),
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
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: CoolSpace.x3),
                  trailing!,
                ],
              ],
            ),
            const SizedBox(height: CoolSpace.x4),
          ],
          child,
        ],
      ),
    );
  }
}

class AdminDataTableCard extends StatelessWidget {
  const AdminDataTableCard({
    required this.columns,
    required this.rows,
    this.title,
    this.subtitle,
    this.trailing,
    this.footer,
    this.emptyLabel = 'No records',
    this.minWidth = 720,
    this.showCheckboxColumn = false,
    super.key,
  });

  final List<DataColumn> columns;
  final List<DataRow> rows;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? footer;
  final String emptyLabel;
  final double minWidth;
  final bool showCheckboxColumn;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    Widget content;
    if (rows.isEmpty) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: CoolSpace.x7),
        child: Center(
          child: Text(
            emptyLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.tertiaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    } else {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(CoolRadii.md),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth),
            child: Theme(
              data: theme.copyWith(
                dividerColor: colors.border,
                dataTableTheme: DataTableThemeData(
                  headingRowColor: WidgetStatePropertyAll(colors.inputSurface),
                  dataRowColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  headingTextStyle: theme.textTheme.labelLarge?.copyWith(
                    color: colors.secondaryText,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                  dataTextStyle: theme.textTheme.bodySmall?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                  horizontalMargin: CoolSpace.x3,
                  columnSpacing: CoolSpace.x4,
                  dataRowMinHeight: 64,
                  dataRowMaxHeight: 78,
                  dividerThickness: 0.6,
                ),
              ),
              child: DataTable(
                showCheckboxColumn: showCheckboxColumn,
                columns: columns,
                rows: rows,
                border: TableBorder(
                  horizontalInside: BorderSide(color: colors.border),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return AdminSectionCard(
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          content,
          if (footer != null) ...[
            const SizedBox(height: CoolSpace.x4),
            footer!,
          ],
        ],
      ),
    );
  }
}

class AdminRankItem {
  const AdminRankItem({required this.label, required this.value});

  final String label;
  final int value;
}

class AdminRankList extends StatelessWidget {
  const AdminRankList({
    required this.items,
    this.emptyLabel = 'No records',
    this.tone = AdminTone.info,
    super.key,
  });

  final List<AdminRankItem> items;
  final String emptyLabel;
  final AdminTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    if (items.isEmpty) {
      return Text(
        emptyLabel,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colors.tertiaryText,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    final total = items.fold<int>(0, (sum, item) => sum + item.value);
    final progressColor = _adminToneColor(context, tone);

    return Column(
      children: [
        for (var index = 0; index < items.length; index++) ...[
          _AdminRankRow(
            item: items[index],
            total: total,
            progressColor: progressColor,
          ),
          if (index < items.length - 1) const SizedBox(height: CoolSpace.x3),
        ],
      ],
    );
  }
}

class _AdminRankRow extends StatelessWidget {
  const _AdminRankRow({
    required this.item,
    required this.total,
    required this.progressColor,
  });

  final AdminRankItem item;
  final int total;
  final Color progressColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final ratio = total == 0 ? 0.0 : item.value / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                item.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${item.value}',
              style: theme.textTheme.titleSmall?.copyWith(
                color: colors.primaryText,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: CoolSpace.x2),
        ClipRRect(
          borderRadius: BorderRadius.circular(CoolRadii.pill),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: colors.inputSurface,
            valueColor: AlwaysStoppedAnimation<Color>(progressColor),
          ),
        ),
      ],
    );
  }
}

class AdminActivityTile extends StatelessWidget {
  const AdminActivityTile({
    required this.title,
    this.subtitle,
    this.meta,
    this.icon,
    this.tone = AdminTone.neutral,
    this.badges = const <Widget>[],
    this.onTap,
    this.expandedChild,
    this.expanded = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final String? meta;
  final IconData? icon;
  final AdminTone tone;
  final List<Widget> badges;
  final VoidCallback? onTap;
  final Widget? expandedChild;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final toneColor = _adminToneColor(context, tone);

    return AdminPanelSurface(
      backgroundColor: colors.inputSurface,
      padding: const EdgeInsets.all(CoolSpace.x4),
      onTap: onTap,
      radius: CoolRadii.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: toneColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(CoolRadii.sm),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 16, color: toneColor),
                ),
                const SizedBox(width: CoolSpace.x3),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: CoolSpace.x1),
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
                ),
              ),
              if (meta != null)
                Text(
                  meta!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.tertiaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          if (badges.isNotEmpty) ...[
            const SizedBox(height: CoolSpace.x3),
            Wrap(
              spacing: CoolSpace.x2,
              runSpacing: CoolSpace.x2,
              children: badges,
            ),
          ],
          if (expandedChild != null && expanded) ...[
            const SizedBox(height: CoolSpace.x4),
            expandedChild!,
          ],
        ],
      ),
    );
  }
}
