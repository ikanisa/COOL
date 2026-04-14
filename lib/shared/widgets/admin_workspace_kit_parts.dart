import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';
import 'admin_workspace_kit.dart';

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
    final progressColor = adminToneColor(context, tone);

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
    final toneColor = adminToneColor(context, tone);

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
