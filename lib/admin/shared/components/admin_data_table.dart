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
    this.allowNaturalHeight = false,
    this.cellBuilder,
    this.sortKey,
    this.compare,
  });

  final String label;
  final String Function(AdminTableRowData row) value;
  final bool numeric;
  final IconData? icon;
  final bool selectable;

  /// Opt in only when the cell builder supplies bounded-width multiline facts.
  /// Other tables retain their ordinary row bounds.
  final bool allowNaturalHeight;
  final Widget Function(AdminTableRowData row)? cellBuilder;

  /// An allowlisted server ordering field, never a page-local comparator.
  final String? sortKey;

  /// Compares authoritative row values for loaded-row sorting only.
  /// Server-ordered tables retain their supplied order and never call this.
  final Comparator<AdminTableRowData>? compare;
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
  bool _showColumnFilters = false;
  bool _scrollFocused = false;
  final _horizontal = ScrollController();
  final _focus = FocusNode(debugLabel: 'Admin table horizontal scrolling');

  @override
  void initState() {
    super.initState();
    _focus.addListener(_updateScrollFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_updateScrollFocus);
    _search.dispose();
    _horizontal.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _updateScrollFocus() {
    if (!mounted || _scrollFocused == _focus.hasPrimaryFocus) return;
    setState(() => _scrollFocused = _focus.hasPrimaryFocus);
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
          compare:
              widget.valueLabel == 'Amount' ||
                  widget.valueLabel == 'Debit = credit'
              ? (a, b) => _compareAdminAmounts(
                  _adminDisplayValue(
                    a,
                    widget.valueLabel,
                    rpcName: widget.rpcName,
                  ),
                  _adminDisplayValue(
                    b,
                    widget.valueLabel,
                    rpcName: widget.rpcName,
                  ),
                )
              : null,
        ),
        AdminTableColumn(
          label: 'Created',
          icon: Icons.calendar_today_outlined,
          value: (row) => _date(row.createdAt),
          compare: (a, b) => switch ((a.createdAt, b.createdAt)) {
            (null, null) => 0,
            (null, _) => -1,
            (_, null) => 1,
            (final left?, final right?) => left.compareTo(right),
          },
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final columns = _columns;
    final localTools = widget.onSortChanged == null && widget.rows.length > 1;
    final visibleRows = _visibleRows(columns, localTools);
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
        label:
            '${widget.tableLabel} table, ${visibleRows.length} of ${widget.rows.length} loaded rows visible',
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
                        colors.surfaceReadable,
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
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                      dividerThickness: 0.5,
                      border: TableBorder(
                        horizontalInside: BorderSide(
                          color: colors.border.withValues(alpha: 0.55),
                          width: 0.5,
                        ),
                      ),
                      headingRowHeight: 48 + ((textScale - 1) * 24),
                      dataRowMinHeight: 56 + extraHeight,
                      dataRowMaxHeight:
                          columns.any((column) => column.allowNaturalHeight)
                          ? double.infinity
                          : 64 + extraHeight,
                      horizontalMargin: 16,
                      columnSpacing: 20,
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
                            label: Text(column.label),
                          ),
                        if (widget.onOpen != null)
                          const DataColumn(label: Text('Open')),
                      ],
                      rows: [
                        for (final row in visibleRows)
                          DataRow(
                            cells: [
                              if (widget.trailingBuilder != null)
                                DataCell(widget.trailingBuilder!(row)),
                              for (final column in columns)
                                DataCell(
                                  widget.onOpen != null &&
                                          column.cellBuilder == null &&
                                          !column.selectable
                                      ? GestureDetector(
                                          behavior: HitTestBehavior.translucent,
                                          excludeFromSemantics: true,
                                          onTap: () => widget.onOpen!(row),
                                          child: _cell(column, row),
                                        )
                                      : _cell(column, row),
                                ),
                              if (widget.onOpen != null)
                                DataCell(
                                  IconButton(
                                    tooltip: 'Open ${row.title}',
                                    onPressed: () => widget.onOpen!(row),
                                    icon: const Icon(
                                      Icons.arrow_outward_rounded,
                                      size: 26,
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
    // Paint above opaque heading cells without changing the table's layout.
    final framedTable = DecoratedBox(
      key: const Key('admin-table-scroll-focus-ring'),
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: CollectRadius.cardBorder,
        border: _scrollFocused
            ? Border.all(color: colors.focusRing, width: 2)
            : null,
      ),
      child: table,
    );
    if (!localTools) return framedTable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: (constraints.maxWidth - 56).clamp(0.0, 320.0),
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    labelText: 'Search loaded rows',
                    hintText: 'Words or "exact phrase"',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 26),
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
              IconButton(
                tooltip: 'Filter loaded rows',
                constraints: const BoxConstraints.tightFor(
                  width: kMinInteractiveDimension,
                  height: kMinInteractiveDimension,
                ),
                isSelected: _showColumnFilters || _filterValue.isNotEmpty,
                onPressed: () =>
                    setState(() => _showColumnFilters = !_showColumnFilters),
                icon: const Icon(Icons.filter_alt_outlined, size: 28),
                selectedIcon: const Icon(Icons.filter_alt_rounded, size: 28),
              ),
            ],
          ),
        ),
        if (_showColumnFilters) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  initialValue: _filterColumn,
                  decoration: const InputDecoration(labelText: 'Filter column'),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('All columns'),
                    ),
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
                child: TextFormField(
                  initialValue: _filterValue,
                  decoration: const InputDecoration(
                    labelText: 'Contains value',
                  ),
                  onChanged: (value) => setState(() => _filterValue = value),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        framedTable,
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '${visibleRows.length} of ${widget.rows.length} loaded rows',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ),
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
        final result =
            column.compare?.call(a, b) ??
            (x != null && y != null
                ? x.compareTo(y)
                : left.toLowerCase().compareTo(right.toLowerCase()));
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

int _compareAdminAmounts(String left, String right) {
  BigInt? parse(String value) {
    final match = RegExp(
      r'^(?:RWF\s+)?(-?(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+))(?:\s*=)?$',
    ).firstMatch(value.trim());
    return match == null
        ? null
        : BigInt.tryParse(match[1]!.replaceAll(',', ''));
  }

  final a = parse(left), b = parse(right);
  // Unavailable or contextual values remain distinct from a financial zero.
  if (a == null && b == null) {
    return left.toLowerCase().compareTo(right.toLowerCase());
  }
  if (a == null) return -1;
  if (b == null) return 1;
  return a.compareTo(b);
}

BoxDecoration _tableDecoration(CollectColors colors) {
  return BoxDecoration(
    color: colors.surfaceReadable,
    borderRadius: CollectRadius.cardBorder,
    border: Border.all(color: colors.border.withValues(alpha: 0.55)),
  );
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
