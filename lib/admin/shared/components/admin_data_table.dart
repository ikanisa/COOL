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
    super.key,
  });

  final List<AdminTableRowData> rows;
  final ValueChanged<AdminTableRowData>? onOpen;
  final Widget Function(AdminTableRowData row)? trailingBuilder;

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
                        const DataColumn(label: Text('Actions')),
                      const DataColumn(label: Text('Record')),
                      const DataColumn(label: Text('Status')),
                      const DataColumn(label: Text('Amount')),
                      const DataColumn(label: Text('Created')),
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
                            DataCell(
                              Text(row.amount.isEmpty ? '-' : row.amount),
                            ),
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
  });

  final List<AdminTableRowData> rows;
  final ValueChanged<AdminTableRowData>? onOpen;
  final Widget Function(AdminTableRowData row)? trailingBuilder;

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
  });

  final AdminTableRowData row;
  final ValueChanged<AdminTableRowData>? onOpen;
  final Widget? trailing;

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
                    label: 'Amount',
                    value: row.amount.isEmpty ? '-' : row.amount,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _CompactValue(
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
                    TextButton.icon(
                      onPressed: () => onOpen!(row),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Semantics(
                        label: 'Open ${row.title}',
                        hint: 'Opens this admin record.',
                        excludeSemantics: true,
                        child: const Text('Open record'),
                      ),
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
  const _CompactValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: CollectTypography.weightBold,
          ),
        ),
      ],
    );
  }
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
