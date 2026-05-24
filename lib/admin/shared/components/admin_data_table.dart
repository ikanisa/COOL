import 'package:flutter/material.dart';

import '../../core/admin_models.dart';

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
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
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
                  if (trailingBuilder != null) DataCell(trailingBuilder!(row)),
                  DataCell(
                    _RecordCell(row: row),
                    onTap: onOpen == null ? null : () => onOpen!(row),
                  ),
                  DataCell(Text(row.status)),
                  DataCell(Text(row.amount.isEmpty ? '-' : row.amount)),
                  DataCell(Text(_date(row.createdAt))),
                ],
              ),
          ],
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
