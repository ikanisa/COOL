part of 'cloudflare_admin_sms_pages.dart';

class _Paging extends StatelessWidget {
  const _Paging(this.page, this.onPage);
  final SmsReceiptPage<SmsReceiptSource> page;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          page.total == 0
              ? '0 records'
              : 'Showing ${page.offset + 1}–${page.offset + page.rows.length} of ${page.total}',
        ),
      ),
      IconButton(
        tooltip: 'Previous page',
        onPressed: page.offset > 0
            ? () => onPage((page.offset - page.limit).clamp(0, page.offset))
            : null,
        icon: const Icon(Icons.chevron_left),
      ),
      IconButton(
        tooltip: 'Next page',
        onPressed: page.nextOffset == null
            ? null
            : () => onPage(page.nextOffset!),
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
}

Widget _filter(
  String label,
  String current,
  Iterable<String> choices,
  ValueChanged<String> onChange,
) => SizedBox(
  width: 245,
  child: DropdownButtonFormField<String>(
    key: ValueKey('$label-$current'),
    initialValue: current,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      DropdownMenuItem(value: '', child: Text('All ${label.toLowerCase()}')),
      for (final value in choices)
        DropdownMenuItem(value: value, child: Text(_label(value))),
    ],
    onChanged: (value) => onChange(value!),
  ),
);

// The default operator list deliberately omits raw numbers and provenance hashes.
// Full evidence remains accessible through the authorized record-detail route.
List<AdminTableColumn> get _receiptListColumns => [
  _column('Received', 'received_at', time: true),
  _column('Source', 'source_kind', labelValue: true),
  AdminTableColumn(
    label: 'Payer / source',
    value: (row) {
      final payer = _value(row.extra['payer_name']);
      final source = _value(row.extra['display_name']);
      return payer != '—' ? payer : source;
    },
  ),
  _column('Masked contact', 'payer_masked_phone'),
  _column('Amount (RWF)', 'amount_rwf', numeric: true, amount: true),
  _column('Status', 'status', labelValue: true),
  _column('Extraction', 'extraction_status', labelValue: true),
  _column('Conflicts', 'conflicting_reference_count', numeric: true),
];

// Keep the full source schema: no evidential field is deleted by the redesign.
List<AdminTableColumn> get _receiptDetailColumns => [
  ..._sourceColumns,
  _column('User ID', 'user_id'),
  _column('Payee ID', 'payee_id'),
  _column('Profile ID', 'public_id', numeric: true),
  _column('Linked transaction', 'transaction_id'),
  _column('Source version', 'version', numeric: true),
  _column('Fact ID', 'source_fact_id'),
  _column('Parser', 'parser_version'),
  _column('Body SHA-256', 'source_body_sha256'),
  _column('Payload SHA-256', 'source_payload_sha256'),
  _column('Extracted', 'parsed_at', time: true),
  _column('Created', 'created_at', time: true),
];

const _receiptSummaryLabels = <String>{
  'Source', 'Amount', 'Received', 'Status', 'Evidence', 'Extraction',
};
const _receiptSupportingLabels = <String>{
  'Source name', 'Payer name', 'Source masked phone',
  'MoMo transaction', 'MoMo time', 'Network', 'Direction',
  'Duplicate references', 'Conflicting references', 'Payee MoMo code',
};

String _maskReceiptContact(String value) {
  if (value.isEmpty || value == '—') return '—';
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 4) return '••••';
  return '•••• ${digits.substring(digits.length - 4)}';
}

Widget _receiptFacts(SmsReceiptSource source) {
  final row = _row(source.values);
  final summary = <AdminRecordFact>[];
  final supporting = <AdminRecordFact>[];
  final technical = <AdminRecordFact>[];
  for (final column in _receiptDetailColumns) {
    // A received extraction may carry unmasked digits. A default detail view
    // must not become an implicit bypass of the reason-bound audited reveal.
    final sourceValue = column.value(row);
    final displayed = column.label == 'Payer phone' ||
            column.label == 'Payee MoMo number'
        ? _maskReceiptContact(sourceValue)
        : column.label == 'Amount' && sourceValue != '—'
            ? 'RWF $sourceValue'
            : sourceValue;
    final fact = AdminRecordFact(label: column.label, value: displayed);
    if (_receiptSummaryLabels.contains(column.label)) {
      summary.add(fact);
    } else if (_receiptSupportingLabels.contains(column.label)) {
      supporting.add(fact);
    } else {
      technical.add(fact);
    }
  }
  return AdminRecordFactsPanel(
    title: 'Source evidence',
    summary: summary,
    supporting: supporting,
    technical: technical,
  );
}

/// Presentation helpers: kept outside the primary receipts runtime file so
/// core list, detail, authentication and audit flows remain easy to review.
extension _SmsReceiptsUi on _ReceiptsState {
  bool get _hasFilters => _applied.isNotEmpty || _source.isNotEmpty ||
      _status.isNotEmpty || _extraction.isNotEmpty || _duplicates.isNotEmpty;
  void _clearFilters() {
    _search.clear();
    _change(() {
      _applied = '';
      _source = '';
      _status = '';
      _extraction = '';
      _duplicates = '';
    });
  }

  Widget _searchField() => ValueListenableBuilder<TextEditingValue>(
    valueListenable: _search,
    builder: (context, value, _) => TextField(
      controller: _search,
      maxLength: 200,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        labelText: 'Search all SMS receipts',
        hintText: 'Payer, source or MoMo reference',
        counterText: '',
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value.text.isNotEmpty)
              IconButton(
                key: const Key('sms-receipt-clear-search'),
                tooltip: 'Clear receipt search',
                onPressed: () {
                  _search.clear();
                  _change(() => _applied = '');
                },
                icon: const Icon(Icons.close_rounded),
              ),
            IconButton(
              key: const Key('sms-receipt-apply-search'),
              tooltip: 'Apply receipt search to all records',
              onPressed: () =>
                  _change(() => _applied = _search.text.trim()),
              icon: const Icon(Icons.search_rounded),
            ),
          ],
        ),
      ),
      onSubmitted: (value) => _change(() => _applied = value.trim()),
    ),
  );

  Widget _mobileReceiptCard(SmsReceiptSource source) {
    final row = _row(source.values);
    final values = source.values;
    final amountValue = adminFormatWholeAmount(values['amount_rwf']);
    final amount = amountValue == '—'
        ? 'Amount not established'
        : 'RWF $amountValue';
    final payer = _value(values['payer_name']);
    final sourceName = payer != '—' ? payer : _value(values['display_name']);
    final contact = _value(values['payer_masked_phone']);
    final status = _label(values['status']);
    final shortId = source.id.length > 8
        ? source.id.substring(0, 8)
        : source.id;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Open ${_label(source.kind)} receipt $shortId',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colors.outlineVariant),
          ),
          child: InkWell(
            key: ValueKey('sms-receipt-${source.id}'),
            borderRadius: BorderRadius.circular(16),
            onTap: () => _open(row),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_label(source.kind)} · $shortId',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, size: 28),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(sourceName),
                  if (contact != '—')
                    Text(
                      contact,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        amount,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(status, style: Theme.of(context).textTheme.labelLarge),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _time(values['received_at']),
                    style: Theme.of(context).textTheme.bodySmall,
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
