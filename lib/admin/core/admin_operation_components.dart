part of 'admin_runtime.dart';

class _AdminPremiumTable extends StatelessWidget {
  const _AdminPremiumTable({
    required this.minimumWidth,
    required this.columns,
    required this.rows,
  });

  final double minimumWidth;
  final List<DataColumn> columns;
  final List<DataRow> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceReadable,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.borderSoft),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Scrollbar(
              scrollbarOrientation: ScrollbarOrientation.bottom,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: math.max(minimumWidth, constraints.maxWidth),
                  ),
                  child: DataTable(
                    showCheckboxColumn: false,
                    headingRowColor: WidgetStatePropertyAll(
                      colors.surfaceRaised.withValues(alpha: 0.82),
                    ),
                    headingTextStyle: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(
                          color: colors.textSecondary,
                          fontWeight: CollectTypography.weightBold,
                        ),
                    dataTextStyle: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: CollectTypography.weightSemibold,
                        ),
                    dividerThickness: 0.7,
                    headingRowHeight: 48 + ((textScale - 1) * 20),
                    dataRowMinHeight: 64 + ((textScale - 1) * 36),
                    dataRowMaxHeight: 78 + ((textScale - 1) * 44),
                    horizontalMargin: 18,
                    columnSpacing: 20,
                    columns: columns,
                    rows: rows,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AdminColumnLabel extends StatelessWidget {
  const _AdminColumnLabel({required this.icon, required this.label})
    : brandIcon = null;

  const _AdminColumnLabel.brand({required this.brandIcon, required this.label})
    : icon = null;

  final IconData? icon;
  final FaIconData? brandIcon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (brandIcon != null)
              FaIcon(brandIcon!, size: 17, color: colors.textSecondary)
            else
              Icon(icon, size: 17, color: colors.textSecondary),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _AdminDateTimeValue extends StatelessWidget {
  const _AdminDateTimeValue(this.value, {this.dateOnly = false});

  final DateTime? value;
  final bool dateOnly;

  @override
  Widget build(BuildContext context) {
    final formatted = _adminDateTime(value, dateOnly: dateOnly);
    final separator = formatted.indexOf(' · ');
    if (dateOnly || separator < 0) return Text(formatted);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(formatted.substring(0, separator)),
        Text(
          formatted.substring(separator + 3),
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }
}

class _AdminOpenButton extends StatelessWidget {
  const _AdminOpenButton({required this.row, required this.onOpen, this.label});

  final AdminTableRowData row;
  final ValueChanged<AdminTableRowData>? onOpen;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: label ?? 'Open ${row.title}',
      onPressed: onOpen == null ? null : () => onOpen!(row),
      icon: const Icon(Icons.arrow_outward, size: 18),
    );
  }
}

class _AdminAccessLabel extends StatelessWidget {
  const _AdminAccessLabel({required this.row});

  final AdminTableRowData row;

  @override
  Widget build(BuildContext context) {
    final publicGroup = _isPublicGroup(row);
    return Tooltip(
      message: publicGroup
          ? 'Platform-sponsored public group'
          : 'Member-created private group',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            publicGroup ? Icons.public_outlined : Icons.lock_outline,
            size: 18,
          ),
          const SizedBox(width: 7),
          Text(publicGroup ? 'Public' : 'Private'),
        ],
      ),
    );
  }
}

class _AdminOperationsSummary extends StatelessWidget {
  const _AdminOperationsSummary({
    required this.semanticLabel,
    required this.items,
  });

  final String semanticLabel;
  final List<_AdminOperationsSummaryItem> items;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: semanticLabel,
    child: ExcludeSemantics(
      child: AdminDataSection(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: [
              TableRow(
                children: [
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 24, 4),
                      child: _AdminColumnLabel(
                        icon: item.icon,
                        label: item.label,
                      ),
                    ),
                ],
              ),
              TableRow(
                children: [
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 24, 8),
                      child: Text(item.value, softWrap: false),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AdminOperationsSummaryItem {
  const _AdminOperationsSummaryItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;
}

String _rail(AdminTableRowData row) =>
    _extraText(row, 'rail', fallback: 'rw_momo');

String _transactionReference(AdminTableRowData row) {
  final identifier = _extraText(row, 'collect_transaction_id');
  return RegExp(r'^[0-9]{15}$').hasMatch(identifier) ? identifier : '';
}

String _momoSender(AdminTableRowData row) {
  final masked = _extraText(row, 'sender_masked').trim();
  if (masked.isEmpty) return '—';
  return masked
      .replaceFirst(
        RegExp(r'^(payer|momo|phone)\s*[·•:\-]*\s*', caseSensitive: false),
        '',
      )
      .trim();
}

String _transactionDisplayAmount(AdminTableRowData row) {
  final amount = row.amount.trim().replaceFirst(RegExp(r'^RWF\s+'), '');
  if (!RegExp(
    r'^-?(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.[0-9]{1,2})?$',
  ).hasMatch(amount)) {
    return '';
  }
  return adminFormatRwfAmount('RWF $amount').replaceFirst('RWF ', '');
}

String _transactionAllocationDisplay(AdminTableRowData row) =>
    AdminTransactionLifecycle.parse(row.extra['lifecycle'])?.allocation ==
        'allocated'
    ? 'Allocated'
    : 'Unallocated';

bool _isPublicGroup(AdminTableRowData row) =>
    row.status == 'public_approved' ||
    _extraBool(row, 'is_platform_sponsored') ||
    _extraText(row, 'visibility') == 'public';

bool _isArchivedGroup(AdminTableRowData row) => row.status == 'archived';

String _groupPurpose(AdminTableRowData row) => _extraText(
  row,
  'purpose_label',
  fallback: _extraText(row, 'collection_type', fallback: row.subtitle),
);

IconData _groupPurposeIcon(AdminTableRowData row) {
  final type = _extraText(row, 'collection_type').toLowerCase();
  final purpose = _groupPurpose(row).toLowerCase();
  if (type.contains('sport') || purpose.contains('club')) {
    return Icons.sports_soccer_outlined;
  }
  if (purpose.contains('saving') || type.contains('ikimina')) {
    return Icons.savings_outlined;
  }
  return Icons.groups_2_outlined;
}

int? _groupMemberCount(AdminTableRowData row) {
  final explicit = _extraInt(row, 'active_members');
  if (row.extra.containsKey('active_members')) return explicit;
  // Legacy responses carried only the member-count display string. Never
  // treat another amount or an absent measurement as a zero member count.
  final match = RegExp(r'^([0-9]+) members?$').firstMatch(row.amount.trim());
  if (match == null) return null;
  try {
    return exactJsonInteger(
      match[1],
      field: 'active_members',
      minimum: 0,
      allowDigitString: true,
    );
  } on FormatException {
    return null;
  }
}

String _country(AdminTableRowData row) =>
    _extraText(row, 'country_code', fallback: 'RW').toUpperCase();

String _extraText(AdminTableRowData row, String key, {String fallback = ''}) {
  final value = row.extra[key];
  if (value == null) return fallback;
  final text = '$value'.trim();
  return text.isEmpty || text == 'null' ? fallback : text;
}

int? _extraInt(AdminTableRowData row, String key) {
  final value = row.extra[key];
  if (value == null) return null;
  try {
    return exactJsonInteger(
      value is String ? value.trim() : value,
      field: key,
      minimum: 0,
      allowDigitString: true,
    );
  } on FormatException {
    return null;
  }
}

bool _extraBool(AdminTableRowData row, String key) {
  final value = row.extra[key];
  return value == true || '$value'.toLowerCase() == 'true';
}

DateTime? _extraDate(AdminTableRowData row, String key) {
  final value = row.extra[key];
  if (value == null) return null;
  try {
    return exactJsonTimestamp(value, field: key);
  } on FormatException {
    return null;
  }
}

String _adminDateTime(DateTime? value, {bool dateOnly = false}) {
  return dateOnly ? adminKigaliDate(value) : adminKigaliDateTime(value);
}

String _transactionWalletBalance(AdminTableRowData row) {
  final value = row.extra['wallet_balance_rwf'];
  if (value == null ||
      value is num && (value.abs() > maxExactJsonInteger || !value.isFinite)) {
    return '';
  }
  final raw = '$value';
  if (!RegExp(r'^[0-9]+(?:\.[0-9]{1,2})?$').hasMatch(raw)) return '';
  return adminFormatRwfAmount('RWF $raw').replaceFirst(RegExp(r'^RWF\s*'), '');
}
