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

class _AdminPrimaryCell extends StatelessWidget {
  const _AdminPrimaryCell({
    required this.title,
    required this.subtitle,
    this.maxWidth = 170,
    this.subtitleIcon,
  });

  final String title;
  final String subtitle;
  final double maxWidth;
  final IconData? subtitleIcon;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: CollectTypography.weightBold,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 3),
            if (subtitleIcon != null)
              Tooltip(
                message: subtitle,
                excludeFromSemantics: true,
                child: Semantics(
                  label: subtitle,
                  excludeSemantics: true,
                  child: Icon(
                    subtitleIcon,
                    size: 16,
                    color: colors.textSecondary,
                  ),
                ),
              )
            else
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: colors.textSecondary),
              ),
          ],
        ],
      ),
    );
  }
}

class _AdminSingleValue extends StatelessWidget {
  const _AdminSingleValue(
    this.value, {
    this.maxWidth = 150,
    this.alignEnd = false,
  });

  final String value;
  final double maxWidth;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Text(
        value.isEmpty ? '—' : value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
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

class _AdminRailLabel extends StatelessWidget {
  const _AdminRailLabel({required this.rail});
  final String rail;

  @override
  Widget build(BuildContext context) => const Tooltip(
    message: 'Rwanda MoMo USSD receipt',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.sms_outlined, size: 18),
        SizedBox(width: 7),
        Text('MoMo'),
      ],
    ),
  );
}

class _AdminRailIcon extends StatelessWidget {
  const _AdminRailIcon({required this.rail});
  final String rail;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.collectColors.success.withValues(alpha: 0.14),
      shape: BoxShape.circle,
    ),
    child: SizedBox.square(
      dimension: 34,
      child: Icon(
        Icons.sms_outlined,
        size: 18,
        color: context.collectColors.successForeground,
      ),
    ),
  );
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

class _AdminGroupRouteLabel extends StatelessWidget {
  const _AdminGroupRouteLabel({required this.row});

  final AdminTableRowData row;

  @override
  Widget build(BuildContext context) {
    final ready = _hasGroupPaymentRoute(row);
    return Tooltip(
      message: ready
          ? 'Rwanda MoMo USSD contribution route'
          : 'No active contribution route',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ready ? Icons.dialpad_outlined : Icons.warning_amber_outlined,
            size: 18,
          ),
          const SizedBox(width: 7),
          Text(ready ? 'MoMo USSD' : 'Missing'),
        ],
      ),
    );
  }
}

class _AdminCountryLabel extends StatelessWidget {
  const _AdminCountryLabel({required this.countryCode});
  final String countryCode;

  @override
  Widget build(BuildContext context) => const Tooltip(
    message: 'Rwanda member',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.phone_android_outlined, size: 18),
        SizedBox(width: 7),
        Text('RW'),
      ],
    ),
  );
}

class _AdminMemberPaymentLabel extends StatelessWidget {
  const _AdminMemberPaymentLabel({required this.row});
  final AdminTableRowData row;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Masked Rwanda MoMo profile',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.phone_android_outlined, size: 18),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            _memberPaymentLabel(row),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

class _AdminOperationsSummary extends StatelessWidget {
  const _AdminOperationsSummary({
    required this.semanticLabel,
    required this.items,
  });

  final String semanticLabel;
  final List<_AdminOperationsSummaryItem> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      container: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceReadable.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.borderSoft),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Wrap(spacing: 10, runSpacing: 8, children: items),
          ),
        ),
      ),
    );
  }
}

class _AdminOperationsSummaryItem extends StatelessWidget {
  const _AdminOperationsSummaryItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        label: '$label: $value',
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceRaised.withValues(alpha: 0.66),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: colors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: CollectTypography.weightBold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminOperationsCardList extends StatelessWidget {
  const _AdminOperationsCardList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('admin-compact-record-list'),
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index != children.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _AdminOperationsCard extends StatelessWidget {
  const _AdminOperationsCard({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.fields,
    required this.onOpen,
    required this.openLabel,
    this.subtitleIcon,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final String status;
  final List<_AdminOperationsFieldData> fields;
  final VoidCallback? onOpen;
  final String openLabel;
  final IconData? subtitleIcon;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceReadable,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.borderSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Tooltip(
                  message: title,
                  child: SizedBox.square(
                    dimension: 38,
                    child: Center(child: leading),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AdminPrimaryCell(
                    title: title,
                    subtitle: subtitle,
                    subtitleIcon: subtitleIcon,
                    maxWidth: double.infinity,
                  ),
                ),
                const SizedBox(width: 8),
                if (status.isNotEmpty) AdminStatusChip(label: status),
                if (onOpen != null) ...[
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    tooltip: openLabel,
                    onPressed: onOpen,
                    icon: const Icon(Icons.arrow_outward, size: 18),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: colors.borderSoft),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth < 420
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final field in fields)
                      SizedBox(
                        width: width,
                        child: _AdminOperationsField(data: field),
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

class _AdminOperationsFieldData {
  const _AdminOperationsFieldData(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;
}

class _AdminOperationsField extends StatelessWidget {
  const _AdminOperationsField({required this.data});

  final _AdminOperationsFieldData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final value = data.value.isEmpty ? '—' : data.value;
    return Tooltip(
      message: data.label,
      excludeFromSemantics: true,
      child: Semantics(
        label: '${data.label}: $value',
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(data.icon, size: 17, color: colors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.label,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: CollectTypography.weightBold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _rail(AdminTableRowData row) =>
    _extraText(row, 'rail', fallback: 'rw_momo');

String _transactionReference(AdminTableRowData row) =>
    adminCompactTransactionReference(
      _extraText(row, 'reference', fallback: row.title),
    );

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
  final amount = row.amount.trim();
  if (amount.isEmpty) return '—';
  if (RegExp(r'^-?[0-9]+$').hasMatch(amount)) {
    return adminFormatRwfAmount('RWF $amount');
  }
  return adminFormatRwfAmount(amount);
}

String _transactionSource(AdminTableRowData row) =>
    _extraText(row, 'source_label', fallback: 'MoMo receipt SMS');

bool _isPublicGroup(AdminTableRowData row) =>
    row.status == 'public_approved' ||
    _extraBool(row, 'is_platform_sponsored') ||
    _extraText(row, 'visibility') == 'public';

bool _isArchivedGroup(AdminTableRowData row) => row.status == 'archived';

bool _hasGroupPaymentRoute(AdminTableRowData row) =>
    _extraText(row, 'receiver_label').isNotEmpty ||
    _extraText(row, 'momo_code').isNotEmpty ||
    _extraText(row, 'momo_identifier').isNotEmpty;

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

String _maskedReceiver(AdminTableRowData row) {
  final value = _extraText(
    row,
    'momo_identifier',
    fallback: _extraText(row, 'momo_code'),
  );
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length <= 6) return value;
  return '${digits.substring(0, 2)}••••••${digits.substring(digits.length - 2)}';
}

String _country(AdminTableRowData row) =>
    _extraText(row, 'country_code', fallback: 'RW').toUpperCase();

String _memberPaymentLabel(AdminTableRowData row) => _extraText(
  row,
  'momo_masked',
  fallback: _extraText(row, 'momo_provider', fallback: 'MoMo not set'),
);

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
