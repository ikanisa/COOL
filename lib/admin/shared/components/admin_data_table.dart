import 'package:flutter/material.dart';

import '../../../app/theme/collect_colors.dart';
import '../../../app/theme/collect_typography.dart';
import '../../core/admin_models.dart';
import 'admin_status_chip.dart';

class AdminDataTable extends StatelessWidget {
  const AdminDataTable({
    required this.rows,
    this.onOpen,
    this.trailingBuilder,
    this.valueLabel = 'Amount',
    super.key,
  });

  final List<AdminTableRowData> rows;
  final ValueChanged<AdminTableRowData>? onOpen;
  final Widget Function(AdminTableRowData row)? trailingBuilder;
  final String valueLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final extraHeight = (textScale - 1) * 40;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Admin records table, ${rows.length} rows',
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 700) {
            return _AdminCompactRecordList(
              rows: rows,
              onOpen: onOpen,
              trailingBuilder: trailingBuilder,
              valueLabel: valueLabel,
            );
          }
          return DecoratedBox(
            decoration: _tableDecoration(colors),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Scrollbar(
                scrollbarOrientation: ScrollbarOrientation.bottom,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStatePropertyAll(
                      colors.surfaceRaised.withValues(alpha: 0.72),
                    ),
                    headingTextStyle: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(
                          color: colors.textSecondary,
                          fontWeight: CollectTypography.weightBold,
                        ),
                    dataTextStyle: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: CollectTypography.weightBold,
                        ),
                    dividerThickness: 0.8,
                    headingRowHeight: 44 + ((textScale - 1) * 24),
                    dataRowMinHeight: 50 + extraHeight,
                    dataRowMaxHeight: 62 + extraHeight,
                    columnSpacing: 24,
                    columns: [
                      if (trailingBuilder != null)
                        const DataColumn(
                          label: _AdminDataColumnLabel(
                            icon: Icons.tune_outlined,
                            label: 'Actions',
                          ),
                        ),
                      const DataColumn(
                        label: _AdminDataColumnLabel(
                          icon: Icons.folder_open_outlined,
                          label: 'Record',
                        ),
                      ),
                      const DataColumn(
                        label: _AdminDataColumnLabel(
                          icon: Icons.verified_outlined,
                          label: 'Status',
                        ),
                      ),
                      DataColumn(
                        label: _AdminDataColumnLabel(
                          icon: _adminValueIcon(valueLabel),
                          label: valueLabel,
                        ),
                      ),
                      const DataColumn(
                        label: _AdminDataColumnLabel(
                          icon: Icons.calendar_today_outlined,
                          label: 'Created',
                        ),
                      ),
                    ],
                    rows: [
                      for (final row in rows)
                        DataRow(
                          cells: [
                            if (trailingBuilder != null)
                              DataCell(trailingBuilder!(row)),
                            DataCell(
                              onOpen == null
                                  ? _RecordCell(row: row)
                                  : TextButton(
                                      onPressed: () => onOpen!(row),
                                      child: Semantics(
                                        label: 'Open ${row.title}',
                                        hint: 'Opens this admin record.',
                                        excludeSemantics: true,
                                        child: _RecordCell(row: row),
                                      ),
                                    ),
                            ),
                            DataCell(AdminStatusChip(label: row.status)),
                            DataCell(Text(_adminDisplayValue(row, valueLabel))),
                            DataCell(Text(_date(row.createdAt))),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

BoxDecoration _tableDecoration(CollectColors colors) {
  return BoxDecoration(
    color: colors.surfaceReadable,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: colors.borderSoft),
    boxShadow: [
      BoxShadow(
        color: CollectColors.publicBlack.withValues(alpha: 0.07),
        blurRadius: 16,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

class _AdminCompactRecordList extends StatelessWidget {
  const _AdminCompactRecordList({
    required this.rows,
    required this.onOpen,
    required this.trailingBuilder,
    required this.valueLabel,
  });

  final List<AdminTableRowData> rows;
  final ValueChanged<AdminTableRowData>? onOpen;
  final Widget Function(AdminTableRowData row)? trailingBuilder;
  final String valueLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('admin-compact-record-list'),
      children: [
        for (var index = 0; index < rows.length; index++) ...[
          _AdminCompactRecordCard(
            row: rows[index],
            onOpen: onOpen,
            trailing: trailingBuilder?.call(rows[index]),
            valueLabel: valueLabel,
          ),
          if (index != rows.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _AdminCompactRecordCard extends StatelessWidget {
  const _AdminCompactRecordCard({
    required this.row,
    required this.onOpen,
    required this.trailing,
    required this.valueLabel,
  });

  final AdminTableRowData row;
  final ValueChanged<AdminTableRowData>? onOpen;
  final Widget? trailing;
  final String valueLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: _tableDecoration(colors),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RecordCell(row: row),
            const SizedBox(height: 10),
            AdminStatusChip(label: row.status),
            const SizedBox(height: 14),
            Divider(color: colors.borderSoft),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _CompactValue(
                    icon: _adminValueIcon(valueLabel),
                    label: valueLabel,
                    value: _adminDisplayValue(row, valueLabel),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _CompactValue(
                    icon: Icons.calendar_today_outlined,
                    label: 'Created',
                    value: _date(row.createdAt),
                  ),
                ),
              ],
            ),
            if (trailing != null || onOpen != null) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ?trailing,
                  if (onOpen != null)
                    IconButton.filledTonal(
                      tooltip: 'Open ${row.title}',
                      onPressed: () => onOpen!(row),
                      icon: const Icon(Icons.open_in_new, size: 18),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CompactValue extends StatelessWidget {
  const _CompactValue({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        label: '$label: $value',
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: CollectTypography.weightBold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminDataColumnLabel extends StatelessWidget {
  const _AdminDataColumnLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        label: label,
        excludeSemantics: true,
        child: Icon(icon, size: 18),
      ),
    );
  }
}

IconData _adminValueIcon(String label) => switch (label.toLowerCase()) {
  'members' => Icons.groups_outlined,
  'deliveries' => Icons.notifications_active_outlined,
  'roles' => Icons.admin_panel_settings_outlined,
  'detail' => Icons.info_outline,
  _ => Icons.payments_outlined,
};

String _adminDisplayValue(AdminTableRowData row, String label) {
  if (label == 'Payment route' && row.extra['rail'] == 'rw_momo') {
    return 'RW · MoMo';
  }
  return row.amount.isEmpty ? '—' : row.amount;
}

class _RecordCell extends StatelessWidget {
  const _RecordCell({required this.row});

  final AdminTableRowData row;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(row.title, overflow: TextOverflow.ellipsis),
          if (row.subtitle.isNotEmpty)
            Text(
              row.subtitle,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

String _date(DateTime? value) {
  if (value == null) return '-';
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
