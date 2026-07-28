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
      label: 'Admin records table, ${rows.length} rows',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceReadable.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.borderAccent),
          boxShadow: [
            BoxShadow(
              color: colors.textPrimary.withValues(alpha: 0.14),
              blurRadius: 28,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Scrollbar(
            scrollbarOrientation: ScrollbarOrientation.bottom,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(
                  colors.textPrimary.withValues(alpha: 0.94),
                ),
                headingTextStyle: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(
                      color: colors.surfaceReadable,
                      fontWeight: CollectTypography.weightBold,
                    ),
                dataTextStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: CollectTypography.weightBold,
                ),
                headingRowHeight: 46 + ((textScale - 1) * 24),
                dataRowMinHeight: 52 + extraHeight,
                dataRowMaxHeight: 64 + extraHeight,
                columnSpacing: 28,
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
                          Semantics(
                            button: onOpen != null,
                            label: onOpen == null
                                ? row.title
                                : 'Open ${row.title}',
                            child: ExcludeSemantics(
                              child: _RecordCell(row: row),
                            ),
                          ),
                          onTap: onOpen == null ? null : () => onOpen!(row),
                        ),
                        DataCell(AdminStatusChip(label: row.status)),
                        DataCell(Text(row.amount.isEmpty ? '-' : row.amount)),
                        DataCell(Text(_date(row.createdAt))),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
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
