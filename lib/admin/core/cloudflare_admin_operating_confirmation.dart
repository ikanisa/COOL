part of 'cloudflare_admin_operating_pages.dart';

bool _journalUuid(Object? value) =>
    value is String &&
    RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    ).hasMatch(value);

bool _journalMoney(Object? value) =>
    value is int && value >= 0 && value <= 9007199254740991;

class _JournalPostingContext {
  const _JournalPostingContext(
    this.resource,
    this.entries,
    this.total,
    this.actor,
  );
  final Map<String, dynamic> resource;
  final List<Map<String, dynamic>> entries;
  final int total;
  final String actor;

  bool matches(
    CloudflareOperatingDetail? detail,
    String? target,
    Map<String, dynamic> body,
  ) =>
      detail != null &&
      detail.type == 'journals' &&
      detail.canManage &&
      detail.actorId == actor &&
      detail.id == target &&
      detail.id == resource['id'] &&
      detail.version == resource['version'] &&
      detail.version == body['expected_version'] &&
      detail.resource['group_id'] == resource['group_id'];
}

Future<_JournalPostingContext> _loadJournalPostingContext(
  CloudflareAdminRepository repository,
  CloudflareOperatingDetail? original,
  String? target,
  Map<String, dynamic> body,
) async {
  const invalid = FormatException(
    'The complete journal could not be verified.',
  );
  final actor = repository.session.user?.id;
  if (original == null ||
      original.type != 'journals' ||
      !original.canManage ||
      original.id != target ||
      original.actorId != actor ||
      original.version != body['expected_version'] ||
      !_journalUuid(original.resource['group_id'])) {
    throw invalid;
  }
  final fresh = await repository.operatingDetail(
    'journals',
    original.id,
    relation: 'entries',
    limit: 100,
    offset: 0,
  );
  final record = fresh.resource, page = fresh.relatedPages['entries'];
  final rows = fresh.related['entries'];
  if (!fresh.canManage ||
      fresh.actorId != actor ||
      repository.session.user?.id != actor ||
      fresh.id != original.id ||
      fresh.version != original.version ||
      record['group_id'] != original.resource['group_id'] ||
      record['status'] != 'draft' ||
      !_journalUuid(record['created_by_admin_id']) ||
      !_journalUuid(record['edited_by_admin_id']) ||
      record['created_by_admin_id'] == actor ||
      record['edited_by_admin_id'] == actor ||
      record['description'] is! String ||
      (record['description'] as String).trim().runes.length < 3 ||
      (record['description'] as String).runes.length > 1000 ||
      fresh.related.length != 1 ||
      fresh.relatedPages.length != 1 ||
      fresh.truncated ||
      page == null ||
      page.offset != 0 ||
      page.limit != 100 ||
      page.nextOffset != null ||
      page.total < 2 ||
      page.total > 100 ||
      rows == null ||
      rows.length != page.total) {
    throw invalid;
  }
  for (final key in ['allocation_id', 'transaction_id']) {
    if (record[key] != null && !_journalUuid(record[key])) throw invalid;
  }
  if ((record['allocation_id'] == null) != (record['transaction_id'] == null)) {
    throw invalid;
  }
  final ids = <String>{};
  var debits = BigInt.zero, credits = BigInt.zero;
  for (final (index, row) in rows.indexed) {
    if (!_journalUuid(row['id']) ||
        !ids.add(row['id'] as String) ||
        row['journal_id'] != original.id ||
        row['group_id'] != record['group_id'] ||
        !_journalUuid(row['account_id']) ||
        row['line_number'] != index + 1 ||
        !_journalMoney(row['debit_rwf']) ||
        !_journalMoney(row['credit_rwf']) ||
        ((row['debit_rwf'] == 0) == (row['credit_rwf'] == 0)) ||
        row['description'] is! String ||
        (row['description'] as String).runes.length > 500 ||
        row['account_code'] is! String ||
        (row['account_code'] as String).trim().isEmpty ||
        (row['account_code'] as String).runes.length > 40 ||
        row['account_name'] is! String ||
        (row['account_name'] as String).trim().runes.length < 2 ||
        (row['account_name'] as String).runes.length > 120) {
      throw invalid;
    }
    debits += BigInt.from(row['debit_rwf'] as int);
    credits += BigInt.from(row['credit_rwf'] as int);
  }
  if (debits != credits ||
      debits == BigInt.zero ||
      debits > BigInt.from(9007199254740991)) {
    throw invalid;
  }
  return _JournalPostingContext(
    Map<String, dynamic>.unmodifiable(record),
    List.unmodifiable(rows.map(Map<String, dynamic>.unmodifiable)),
    debits.toInt(),
    actor!,
  );
}

class _JournalPostingTables extends StatelessWidget {
  const _JournalPostingTables(this.journal);
  final _JournalPostingContext journal;

  @override
  Widget build(BuildContext context) {
    final facts = {
      ...journal.resource,
      'entry_count': journal.entries.length,
      'debit_total_rwf': journal.total,
      'credit_total_rwf': journal.total,
      'current_actor_id': journal.actor,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminDataTable(
          tableLabel: 'Journal posting context',
          rows: [
            AdminTableRowData(
              id: '${facts['id']}',
              title: '',
              subtitle: '',
              status: '',
              amount: '',
              extra: facts,
            ),
          ],
          columns: [
            for (final key in [
              'id',
              'group_id',
              'description',
              'status',
              'version',
              'created_by_admin_id',
              'edited_by_admin_id',
              'current_actor_id',
              'allocation_id',
              'transaction_id',
              'entry_count',
              'debit_total_rwf',
              'credit_total_rwf',
            ])
              _operatingColumn(key),
          ],
        ),
        const SizedBox(height: 16),
        AdminDataTable(
          tableLabel: 'Journal entries to post',
          rows: [
            for (final row in journal.entries)
              AdminTableRowData(
                id: row['id'] as String,
                title: '',
                subtitle: '',
                status: '',
                amount: '',
                extra: row,
              ),
          ],
          columns: [
            for (final key in [
              'line_number',
              'account_code',
              'account_name',
              'account_id',
              'description',
              'debit_rwf',
              'credit_rwf',
            ])
              _operatingColumn(key),
          ],
        ),
      ],
    );
  }
}

Future<bool?> _reviewOperatingConfirmation({
  required BuildContext context,
  required CloudflareOperation operation,
  required Map<String, dynamic> body,
  required String Function(String?) accountLabel,
  required bool Function() canConfirm,
  _JournalPostingContext? journal,
  String? retryKey,
}) => showDialog<bool>(
  context: context,
  builder: (context) => Consumer(
    builder: (context, ref, _) {
      ref.watch(cloudflareAdminSessionProvider);
      return AlertDialog(
        title: Text(
          retryKey == null
              ? 'Review: ${_actionTitle(operation).toLowerCase()}'
              : 'Review identical request retry',
        ),
        content: SizedBox(
          width: 700,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_actionExplanation(operation)),
                if (retryKey != null)
                  SelectableText('Request reference: $retryKey'),
                const SizedBox(height: 16),
                if (journal != null) ...[
                  _JournalPostingTables(journal),
                  const SizedBox(height: 16),
                ],
                _OperatingConfirmationTables(
                  body: body,
                  accountLabel: accountLabel,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(retryKey == null ? 'Back to edit' : 'Back to review'),
          ),
          FilledButton(
            onPressed: canConfirm()
                ? () {
                    if (canConfirm()) Navigator.pop(context, true);
                  }
                : null,
            child: Text(
              retryKey != null
                  ? 'Confirm identical retry'
                  : operation == CloudflareOperation.postJournal
                  ? 'Confirm permanent posting'
                  : 'Confirm change',
            ),
          ),
        ],
      );
    },
  ),
);
