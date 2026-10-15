import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/collect_colors.dart';
import '../../../app/theme/collect_radius.dart';
import '../../../app/theme/collect_typography.dart';
import '../../core/admin_display_formatters.dart';
import '../../core/admin_models.dart';
import 'admin_status_chip.dart';

/// A field has one column and one authoritative value. Custom schemas let
/// operating areas retain their own facts instead of combining them in a label.
class AdminTableColumn {
  const AdminTableColumn({
    required this.label,
    required this.value,
    this.numeric = false,
    this.icon,
    this.selectable = false,
    this.cellBuilder,
    this.sortKey,
  });

  final String label;
  final String Function(AdminTableRowData row) value;
  final bool numeric;
  final IconData? icon;
  final bool selectable;
  final Widget Function(AdminTableRowData row)? cellBuilder;

  /// An allowlisted server ordering field, never a page-local comparator.
  final String? sortKey;
}

class AdminDataTable extends StatefulWidget {
  const AdminDataTable({
    required this.rows,
    this.rpcName = '',
    this.onOpen,
    this.trailingBuilder,
    this.valueLabel = 'Amount',
    this.columns,
    this.tableLabel = 'Admin records',
    this.sortBy = '',
    this.onSortChanged,
    super.key,
  });

  final List<AdminTableRowData> rows;
  final String rpcName;
  final ValueChanged<AdminTableRowData>? onOpen;
  final Widget Function(AdminTableRowData row)? trailingBuilder;
  final String valueLabel;
  final List<AdminTableColumn>? columns;
  final String tableLabel;
  final String sortBy;
  final ValueChanged<String>? onSortChanged;

  @override
  State<AdminDataTable> createState() => _AdminDataTableState();
}

class _AdminDataTableState extends State<AdminDataTable> {
  final _search = TextEditingController();
  String _query = '', _filterColumn = '', _filterValue = '';
  int? _localSort;
  bool _localAscending = true;
  final _horizontal = ScrollController();
  final _focus = FocusNode(debugLabel: 'Admin table horizontal scrolling');

  @override
  void dispose() {
    _search.dispose();
    _horizontal.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scroll(double delta) {
    if (!_horizontal.hasClients) return;
    _horizontal.jumpTo(
      (_horizontal.offset + delta).clamp(
        _horizontal.position.minScrollExtent,
        _horizontal.position.maxScrollExtent,
      ),
    );
  }

  List<AdminTableColumn> get _columns =>
      widget.columns ??
      [
        AdminTableColumn(
          label: 'Record',
          icon: Icons.folder_open_outlined,
          value: (row) => _adminRecordTitle(row, widget.rpcName),
          cellBuilder: (row) => widget.onOpen == null
              ? Text(_adminRecordTitle(row, widget.rpcName), softWrap: false)
              : TextButton(
                  onPressed: () => widget.onOpen!(row),
                  child: Semantics(
                    label: 'Open ${row.title}',
                    hint: 'Opens this admin record.',
                    excludeSemantics: true,
                    child: Text(
                      _adminRecordTitle(row, widget.rpcName),
                      softWrap: false,
                    ),
                  ),
                ),
        ),
        if (widget.rows.any(
          (row) => _adminRecordSubtitle(row, widget.rpcName).isNotEmpty,
        ))
          AdminTableColumn(
            label: _adminSubtitleLabel(widget.rpcName),
            icon: Icons.subject_outlined,
            value: (row) => _adminRecordSubtitle(row, widget.rpcName),
          ),
        AdminTableColumn(
          label: 'Status',
          icon: Icons.verified_outlined,
          value: (row) => row.status,
          cellBuilder: (row) =>
              _adminRowStatusVisible(widget.rpcName, row.status)
              ? AdminStatusChip(label: row.status)
              : const SizedBox.shrink(),
        ),
        AdminTableColumn(
          label: _adminValueLabel(widget.rpcName, widget.valueLabel),
          icon: _adminValueIcon(widget.valueLabel),
          numeric:
              widget.valueLabel == 'Amount' ||
              widget.valueLabel == 'Debit = credit',
          value: (row) => _adminDisplayValue(
            row,
            widget.valueLabel,
            rpcName: widget.rpcName,
          ),
        ),
        AdminTableColumn(
          label: 'Created',
          icon: Icons.calendar_today_outlined,
          value: (row) => _date(row.createdAt),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final columns = _columns;
    final localTools = widget.onSortChanged == null && widget.rows.length > 1;
    final ascending = widget.sortBy.endsWith('_asc');
    final sortKey = widget.sortBy.replaceFirst(RegExp(r'_(?:asc|desc)$'), '');
    final sortedColumn = columns.indexWhere(
      (column) => column.sortKey != null && column.sortKey == sortKey,
    );
    final fontSize = Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14.0;
    final textScale =
        (MediaQuery.textScalerOf(context).scale(fontSize) / fontSize).clamp(
          1.0,
          2.0,
        );
    final extraHeight = (textScale - 1) * 40;
    final table = Focus(
      focusNode: _focus,
      onKeyEvent: (_, event) {
        // Let selectable facts retain their native caret/selection shortcuts.
        if (event is! KeyDownEvent || !_focus.hasPrimaryFocus) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _scroll(-180);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _scroll(180);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: '${widget.tableLabel} table, ${widget.rows.length} rows',
        hint:
            'Scroll horizontally to see all columns. Use left and right arrows when focused.',
        onScrollLeft: () => _scroll(-180),
        onScrollRight: () => _scroll(180),
        child: LayoutBuilder(
          builder: (context, constraints) => DecoratedBox(
            decoration: _tableDecoration(colors),
            child: ClipRRect(
              borderRadius: CollectRadius.cardBorder,
              child: Scrollbar(
                controller: _horizontal,
                thumbVisibility: true,
                interactive: true,
                scrollbarOrientation: ScrollbarOrientation.bottom,
                child: SingleChildScrollView(
                  controller: _horizontal,
                  primary: false,
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: DataTable(
                      showCheckboxColumn: false,
                      sortColumnIndex: localTools && _localSort != null
                          ? _localSort! +
                                (widget.trailingBuilder == null ? 0 : 1)
                          : sortedColumn < 0
                          ? null
                          : sortedColumn +
                                (widget.trailingBuilder == null ? 0 : 1),
                      sortAscending: localTools ? _localAscending : ascending,
                      headingRowColor: WidgetStatePropertyAll(
                        colors.surfaceRaised.withValues(alpha: 0.72),
                      ),
                      headingTextStyle: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(
                            color: colors.textSecondary,
                            fontWeight: CollectTypography.weightMedium,
                          ),
                      dataTextStyle: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: CollectTypography.weightRegular,
                          ),
                      dividerThickness: 0.8,
                      headingRowHeight: 44 + ((textScale - 1) * 24),
                      dataRowMinHeight: 50 + extraHeight,
                      dataRowMaxHeight: 62 + extraHeight,
                      columnSpacing: 24,
                      columns: [
                        if (widget.trailingBuilder != null)
                          const DataColumn(label: Text('Actions')),
                        for (final (columnIndex, column) in columns.indexed)
                          DataColumn(
                            numeric: column.numeric,
                            onSort: localTools
                                ? (_, direction) => setState(() {
                                    _localSort = columnIndex;
                                    _localAscending = direction;
                                  })
                                : column.sortKey == null ||
                                      widget.onSortChanged == null
                                ? null
                                : (_, ascending) => widget.onSortChanged!(
                                    '${column.sortKey}_${ascending ? 'asc' : 'desc'}',
                                  ),
                            label: column.icon == null
                                ? Text(column.label)
                                : _AdminDataColumnLabel(
                                    icon: column.icon!,
                                    label: column.label,
                                  ),
                          ),
                        if (widget.onOpen != null)
                          const DataColumn(label: Text('Open')),
                      ],
                      rows: [
                        for (final row in _visibleRows(columns, localTools))
                          DataRow(
                            onSelectChanged: widget.onOpen == null
                                ? null
                                : (_) => widget.onOpen!(row),
                            cells: [
                              if (widget.trailingBuilder != null)
                                DataCell(widget.trailingBuilder!(row)),
                              for (final column in columns)
                                DataCell(_cell(column, row)),
                              if (widget.onOpen != null)
                                DataCell(
                                  IconButton.filledTonal(
                                    tooltip: 'Open ${row.title}',
                                    onPressed: () => widget.onOpen!(row),
                                    icon: const Icon(
                                      Icons.arrow_outward_rounded,
                                      size: 18,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (!localTools) return table;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  labelText: 'Search loaded rows',
                  hintText: 'Words or "exact phrase"',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear table search',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                initialValue: _filterColumn,
                decoration: const InputDecoration(labelText: 'Filter column'),
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: '', child: Text('All columns')),
                  for (final column in columns)
                    DropdownMenuItem(
                      value: column.label,
                      child: Text(column.label),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _filterColumn = value ?? ''),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                decoration: const InputDecoration(labelText: 'Contains value'),
                onChanged: (value) => setState(() => _filterValue = value),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '${_visibleRows(columns, true).length} of ${widget.rows.length} loaded rows · Search, filter and header sorting apply to this page.',
          ),
        ),
        table,
      ],
    );
  }

  List<AdminTableRowData> _visibleRows(
    List<AdminTableColumn> columns,
    bool local,
  ) {
    if (!local) return widget.rows;
    String normalize(String value) =>
        value.toLowerCase().replaceAll(RegExp(r'[+()\s-]'), '');
    final terms = RegExp(
      r'"([^"]+)"|(\S+)',
    ).allMatches(_query.toLowerCase()).map((m) => m[1] ?? m[2]!).toList();
    final rows = widget.rows.where((row) {
      final values = columns.map((c) => c.value(row).toLowerCase()).toList();
      if (!terms.every(
        (term) => values.any(
          (value) =>
              value.contains(term) ||
              RegExp(r'^[+()0-9\s-]+$').hasMatch(term) &&
                  normalize(value).contains(normalize(term)),
        ),
      )) {
        return false;
      }
      final filtered = columns.where(
        (c) => _filterColumn.isEmpty || c.label == _filterColumn,
      );
      return _filterValue.isEmpty ||
          filtered.any(
            (c) =>
                c.value(row).toLowerCase().contains(_filterValue.toLowerCase()),
          );
    }).toList();
    if (_localSort != null && _localSort! < columns.length) {
      final column = columns[_localSort!];
      rows.sort((a, b) {
        final left = column.value(a), right = column.value(b);
        final x = column.numeric
            ? BigInt.tryParse(left.replaceAll(',', ''))
            : null;
        final y = column.numeric
            ? BigInt.tryParse(right.replaceAll(',', ''))
            : null;
        final result = x != null && y != null
            ? x.compareTo(y)
            : left.toLowerCase().compareTo(right.toLowerCase());
        return result == 0
            ? a.id.compareTo(b.id)
            : _localAscending
            ? result
            : -result;
      });
    }
    return rows;
  }

  Widget _cell(AdminTableColumn column, AdminTableRowData row) {
    if (column.cellBuilder != null) return column.cellBuilder!(row);
    final raw = column.value(row);
    final value = raw.isEmpty ? '—' : raw;
    if (!column.selectable) return Text(value, softWrap: false);
    // SelectableText's web edit control must not replace the readable fact with
    // an empty disabled textbox. Expose the actual labelled value explicitly.
    return Semantics(
      label: '${column.label}: $value',
      excludeSemantics: true,
      child: SelectableText(value, maxLines: 1),
    );
  }
}

BoxDecoration _tableDecoration(CollectColors colors) {
  return BoxDecoration(
    color: colors.surfaceReadable,
    borderRadius: CollectRadius.cardBorder,
    border: Border.all(color: colors.border),
  );
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
      ),
    );
  }
}

IconData _adminValueIcon(String label) => switch (label.toLowerCase()) {
  'members' => Icons.groups_outlined,
  'deliveries' => Icons.notifications_active_outlined,
  'roles' => Icons.admin_panel_settings_outlined,
  'access' => Icons.admin_panel_settings_outlined,
  'detail' => Icons.info_outline,
  _ => Icons.payments_outlined,
};

String _adminDisplayValue(
  AdminTableRowData row,
  String label, {
  String rpcName = '',
}) {
  final contextual = switch (rpcName) {
    'admin_list_audit_logs' => '${row.extra['actor'] ?? ''}'.trim(),
    'admin_list_settings' => '${row.extra['current_value'] ?? ''}'.trim(),
    'admin_list_feature_flags' => '${row.extra['scope'] ?? ''}'.trim(),
    _ => '',
  };
  if (contextual.isNotEmpty) return contextual;
  if (label == 'Payment route' && row.extra['rail'] == 'rw_momo') {
    return 'RW · MoMo';
  }
  if (row.amount.isEmpty) return '—';
  return label == 'Amount' || label == 'Debit = credit'
      ? adminFormatRwfAmount(row.amount)
      : row.amount;
}

String _date(DateTime? value) {
  return adminKigaliDateTime(value);
}

String _adminRecordTitle(AdminTableRowData row, String rpcName) {
  final reference = '${row.extra['reference'] ?? ''}'.trim();
  if ((rpcName == 'admin_list_collect_reconciliations' ||
          rpcName == 'admin_list_collect_ledgers') &&
      reference.isNotEmpty) {
    return reference;
  }
  if (rpcName == 'admin_list_audit_logs' ||
      rpcName == 'admin_list_settings' ||
      rpcName == 'admin_list_feature_flags') {
    return _adminHumanizeRecordKey(row.title);
  }
  return row.title;
}

String _adminHumanizeRecordKey(String value) {
  final words = value.trim().replaceAll(RegExp(r'[._-]+'), ' ').trim();
  if (words.isEmpty) return '';
  return '${words[0].toUpperCase()}${words.substring(1)}';
}

String _adminRecordSubtitle(AdminTableRowData row, String rpcName) {
  switch (rpcName) {
    case 'admin_list_collect_reconciliations':
    case 'admin_list_collect_ledgers':
    case 'admin_list_feature_flags':
      return '';
    case 'admin_list_settings':
      return '${row.extra['scope'] ?? ''}'.trim();
    case 'admin_list_collect_payees':
      final parts = row.subtitle.split(' • ');
      if (parts.length >= 3) return '${parts.first} • ${parts[2]}';
      return row.subtitle;
    case 'admin_list_admin_users':
      return row.subtitle.replaceAll('_', ' ');
    case 'admin_list_notifications':
      return row.subtitle.split(' • ').first;
    case 'admin_list_audit_logs':
      return '${row.extra['target'] ?? ''}'.trim();
    default:
      return row.subtitle;
  }
}

bool _adminRowStatusVisible(String rpcName, String status) {
  return switch (rpcName) {
    'admin_list_members' || 'admin_list_non_member_users' => status == 'admin',
    'admin_list_collect_ledgers' => status != 'balanced',
    'admin_list_notifications' => status != 'sent',
    'admin_list_audit_logs' ||
    'admin_list_settings' ||
    'admin_list_feature_flags' => false,
    'admin_list_admin_users' => status == 'revoked',
    _ => true,
  };
}

String _adminSubtitleLabel(String rpcName) => switch (rpcName) {
  'admin_list_audit_logs' => 'Target',
  'admin_list_settings' => 'Scope',
  'admin_list_admin_users' => 'Roles',
  'admin_list_notifications' => 'Recipient',
  _ => 'Description',
};

String _adminValueLabel(String rpcName, String fallback) => switch (rpcName) {
  'admin_list_audit_logs' => 'Actor',
  'admin_list_settings' => 'Current value',
  'admin_list_feature_flags' => 'Scope',
  _ => fallback,
};
