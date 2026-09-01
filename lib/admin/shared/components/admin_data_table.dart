import 'package:flutter/material.dart';

import '../../../app/theme/collect_colors.dart';
import '../../../app/theme/collect_typography.dart';
import '../../core/admin_display_formatters.dart';
import '../../core/admin_models.dart';
import 'admin_status_chip.dart';

class AdminDataTable extends StatelessWidget {
  const AdminDataTable({
    required this.rows,
    this.rpcName = '',
    this.onOpen,
    this.trailingBuilder,
    this.valueLabel = 'Amount',
    super.key,
  });

  final List<AdminTableRowData> rows;
  final String rpcName;
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
              rpcName: rpcName,
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
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
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
                        if (onOpen != null)
                          const DataColumn(
                            label: _AdminDataColumnLabel(
                              icon: Icons.open_in_new_rounded,
                              label: 'Open',
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
                                    ? _RecordCell(row: row, rpcName: rpcName)
                                    : TextButton(
                                        onPressed: () => onOpen!(row),
                                        child: Semantics(
                                          label: 'Open ${row.title}',
                                          hint: 'Opens this admin record.',
                                          excludeSemantics: true,
                                          child: _RecordCell(
                                            row: row,
                                            rpcName: rpcName,
                                          ),
                                        ),
                                      ),
                              ),
                              DataCell(
                                _adminRowStatusVisible(rpcName, row.status)
                                    ? AdminStatusChip(label: row.status)
                                    : const SizedBox.shrink(),
                              ),
                              DataCell(
                                Text(
                                  _adminDisplayValue(
                                    row,
                                    valueLabel,
                                    rpcName: rpcName,
                                  ),
                                ),
                              ),
                              DataCell(Text(_date(row.createdAt))),
                              if (onOpen != null)
                                DataCell(
                                  IconButton.filledTonal(
                                    tooltip: 'Open ${row.title}',
                                    onPressed: () => onOpen!(row),
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
    required this.rpcName,
    required this.onOpen,
    required this.trailingBuilder,
    required this.valueLabel,
  });

  final List<AdminTableRowData> rows;
  final String rpcName;
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
            rpcName: rpcName,
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
    required this.rpcName,
    required this.onOpen,
    required this.trailing,
    required this.valueLabel,
  });

  final AdminTableRowData row;
  final String rpcName;
  final ValueChanged<AdminTableRowData>? onOpen;
  final Widget? trailing;
  final String valueLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final fields = _adminCompactFields(row, rpcName, valueLabel);
    return DecoratedBox(
      decoration: _tableDecoration(colors),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _RecordCell(row: row, rpcName: rpcName),
                ),
                if (_adminRowStatusVisible(rpcName, row.status)) ...[
                  const SizedBox(width: 8),
                  AdminStatusChip(label: row.status),
                ],
                if (trailing != null) ...[const SizedBox(width: 4), trailing!],
                if (onOpen != null) ...[
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    tooltip: 'Open ${row.title}',
                    onPressed: () => onOpen!(row),
                    icon: const Icon(Icons.arrow_outward, size: 18),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Divider(color: colors.borderSoft),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth < 420
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 16) / 2;
                return Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    for (final field in fields)
                      SizedBox(
                        width: width,
                        child: _CompactValue(
                          icon: field.icon,
                          label: field.label,
                          value: field.value,
                        ),
                      ),
                  ],
                );
              },
            ),
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

class _AdminCompactFieldData {
  const _AdminCompactFieldData(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;
}

List<_AdminCompactFieldData> _adminCompactFields(
  AdminTableRowData row,
  String rpcName,
  String valueLabel,
) {
  String extra(String key, {String fallback = ''}) {
    final value = '${row.extra[key] ?? ''}'.trim();
    return value.isEmpty || value == 'null' ? fallback : value;
  }

  return switch (rpcName) {
    'admin_list_audit_logs' => [
      _AdminCompactFieldData(
        Icons.person_outline,
        'Actor',
        extra('actor', fallback: 'System'),
      ),
      _AdminCompactFieldData(
        Icons.schedule_outlined,
        'Recorded',
        _date(row.createdAt),
      ),
    ],
    'admin_list_settings' => [
      _AdminCompactFieldData(
        Icons.tune_outlined,
        'Current value',
        extra('current_value', fallback: row.subtitle),
      ),
      _AdminCompactFieldData(
        Icons.public_outlined,
        'Scope',
        extra('scope', fallback: 'Operations'),
      ),
    ],
    'admin_list_feature_flags' => [
      _AdminCompactFieldData(
        Icons.public_outlined,
        'Scope',
        extra('scope', fallback: row.subtitle),
      ),
      _AdminCompactFieldData(
        Icons.schedule_outlined,
        'Updated',
        _date(row.createdAt),
      ),
    ],
    'admin_list_admin_users' => [
      _AdminCompactFieldData(
        Icons.schedule_outlined,
        'Created',
        _date(row.createdAt),
      ),
    ],
    _ => [
      _AdminCompactFieldData(
        _adminValueIcon(valueLabel),
        valueLabel,
        _adminDisplayValue(row, valueLabel, rpcName: rpcName),
      ),
      _AdminCompactFieldData(
        Icons.calendar_today_outlined,
        'Created',
        _date(row.createdAt),
      ),
    ],
  };
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
      ? _adminFormatCurrency(row.amount)
      : row.amount;
}

String _adminFormatCurrency(String value) {
  final match = RegExp(
    r'^(RWF|EUR)\s+([0-9,]+(?:\.[0-9]+)?)(\s*=)?$',
  ).firstMatch(value.trim());
  if (match == null) return value;

  final currency = match.group(1)!;
  final rawAmount = match.group(2)!.replaceAll(',', '');
  final parsed = double.tryParse(rawAmount);
  if (parsed == null) return value;

  final fixed = currency == 'EUR'
      ? parsed.toStringAsFixed(2)
      : parsed.round().toString();
  final parts = fixed.split('.');
  final digits = parts.first;
  final grouped = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) grouped.write(',');
    grouped.write(digits[index]);
  }
  final fraction = parts.length == 2 ? '.${parts.last}' : '';
  return '$currency $grouped$fraction';
}

class _RecordCell extends StatelessWidget {
  const _RecordCell({required this.row, required this.rpcName});

  final AdminTableRowData row;
  final String rpcName;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _adminRecordTitle(row, rpcName),
            overflow: TextOverflow.ellipsis,
          ),
          if (_adminRecordSubtitle(row, rpcName).isNotEmpty)
            Text(
              _adminRecordSubtitle(row, rpcName),
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

String _date(DateTime? value) {
  if (value == null) return '—';
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${value.day} ${months[value.month - 1]} ${value.year}';
}

String _adminRecordTitle(AdminTableRowData row, String rpcName) {
  final reference = '${row.extra['reference'] ?? ''}'.trim();
  if ((rpcName == 'admin_list_collect_reconciliations' ||
          rpcName == 'admin_list_collect_ledgers') &&
      reference.isNotEmpty) {
    return adminCompactTransactionReference(reference);
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
    case 'admin_list_settings':
      return '';
    case 'admin_list_collect_payees':
      final parts = row.subtitle.split(' • ');
      if (parts.length >= 3) return '${parts.first} • ${parts[2]}';
      return adminCompactTransactionReference(row.subtitle);
    case 'admin_list_admin_users':
      return adminCompactTransactionReference(
        row.subtitle.replaceAll('_', ' '),
      );
    case 'admin_list_notifications':
      return row.subtitle.split(' • ').first;
    case 'admin_list_audit_logs':
      return adminCompactTransactionReference(row.extra['target']);
    default:
      return adminCompactTransactionReference(row.subtitle);
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
