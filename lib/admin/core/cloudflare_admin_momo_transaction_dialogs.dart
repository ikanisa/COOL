part of 'cloudflare_admin_momo_page.dart';

class _TransactionDialog extends ConsumerStatefulWidget {
  const _TransactionDialog({required this.id});
  final String id;
  @override
  ConsumerState<_TransactionDialog> createState() => _TransactionDialogState();
}

class _TransactionDialogState extends ConsumerState<_TransactionDialog> {
  late final Object _openingFence = ref
      .read(cloudflareAdminSessionProvider.notifier)
      .authorityFence;

  Map<String, dynamic>? _detail;
  Object? _errorValue;
  @override
  void initState() {
    super.initState();
    _openingFence;
    Future.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final data = await ref
          .read(momoAdminApiProvider)
          .read('transactions/${widget.id}', 'payments.read');
      final transaction = MomoTransaction.parse(_map(data['transaction']));
      if (transaction.id != widget.id || data['sources'] is! List) {
        _invalid();
      }
      for (final source in data['sources'] as List) {
        _identifier(_map(source)['raw_sms_id']);
      }
      if (data['conflicting_attempt_ids'] != null) {
        final attempts = data['conflicting_attempt_ids'];
        if (attempts is! List || attempts.length > 101) _invalid();
        for (final attempt in attempts) {
          _identifier(attempt);
        }
        if (attempts.toSet().length != attempts.length) _invalid();
      }
      if (mounted) {
        setState(() {
          _detail = data;
          _errorValue = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errorValue = error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final transaction = _detail == null
        ? null
        : MomoTransaction.parse(_map(_detail!['transaction']));
    final user = ref.watch(cloudflareAdminSessionProvider).asData?.value;
    return _Scope(
      fence: _openingFence,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Payment details',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close payment details',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                if (_errorValue != null)
                  _Note(_error(_errorValue!), error: true),
                if (transaction == null)
                  const LinearProgressIndicator()
                else ...[
                  AdminRecordFactsTable(
                    semanticLabel: 'MoMo payment facts',
                    fields: [
                      (
                        'Amount · RWF',
                        adminFormatWholeAmount(transaction.amount),
                      ),
                      ('Status', transaction.label),
                      (
                        'MoMo TX ID',
                        '${transaction.values['provider_transaction_id']}',
                      ),
                      (
                        'Receiving account',
                        '${transaction.values['recipient_name']}',
                      ),
                      ('MoMo code', '${transaction.values['public_code']}'),
                      (
                        'Payer name',
                        '${transaction.values['payer_name'] ?? 'Unknown payer'}',
                      ),
                      (
                        'Payer last 3',
                        '${transaction.values['payer_last3'] ?? '—'}',
                      ),
                      (
                        'Beneficiary',
                        '${transaction.values['member_name'] ?? 'Unassigned'}',
                      ),
                      (
                        'Group',
                        '${transaction.values['group_name'] ?? 'Unassigned'}',
                      ),
                      (
                        'Transaction time · Kigali',
                        transaction.transactionTime,
                      ),
                    ],
                  ),
                  if (transaction.hasConflict)
                    const _Note(
                      'Needs review · Conflicting payment evidence requires resolution. The recorded financial status is preserved.',
                      error: true,
                    ),
                  if (transaction.hasConflict &&
                      transaction.paymentId == null &&
                      user?.permissions.contains('payments.write') == true &&
                      user?.permissions.contains('sms.extract') == true &&
                      (_detail!['conflicting_attempt_ids'] as List?)
                              ?.isNotEmpty ==
                          true &&
                      (_detail!['conflicting_attempt_ids'] as List).length <=
                          100)
                    TextButton.icon(
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Review conflict'),
                      onPressed: () async {
                        await showDialog<void>(
                          context: context,
                          animationStyle: CollectMotion.animationStyle(context),
                          builder: (_) => _MomoReviewDialog(
                            kind: 'conflict',
                            transaction: transaction,
                            conflictingAttempts: List<String>.from(
                              _detail!['conflicting_attempt_ids'] as List,
                            ),
                          ),
                        );
                        if (mounted) _load();
                      },
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: 'Copy MoMo TX ID',
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: () => Clipboard.setData(
                        ClipboardData(
                          text:
                              transaction.values['provider_transaction_id']
                                  as String,
                        ),
                      ),
                    ),
                  ),
                  if (transaction.status == 'needs_allocation' &&
                      user?.permissions.contains('payments.write') == true &&
                      user?.permissions.contains('users.read') == true &&
                      user?.permissions.contains('collections.read') == true)
                    FilledButton.icon(
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('Assign for independent review'),
                      onPressed: () async {
                        await showDialog<void>(
                          context: context,
                          animationStyle: CollectMotion.animationStyle(context),
                          builder: (_) =>
                              _MomoActionDialog(transaction: transaction),
                        );
                        if (mounted) _load();
                      },
                    ),
                  if (transaction.paymentId != null &&
                      user?.permissions.contains('reconciliations.read') ==
                          true)
                    TextButton.icon(
                      icon: const Icon(Icons.rule_rounded),
                      label: const Text('Open financial review'),
                      onPressed: () {
                        Navigator.pop(context);
                        context.go(
                          '/admin/reconciliations/${transaction.paymentId}',
                        );
                      },
                    ),
                  ExpansionTile(
                    title: const Text('Source and processing history'),
                    subtitle: const Text(
                      'MoMo notification captured by the enrolled gateway. Parsing does not confirm provider API settlement.',
                    ),
                    expansionAnimationStyle: CollectMotion.animationStyle(
                      context,
                    ),
                    children: [
                      AdminDataTable(
                        tableLabel: 'Payment source and processing history',
                        rows: [
                          for (final (index, source)
                              in (_detail!['sources'] as List).indexed)
                            AdminTableRowData(
                              id: '${widget.id}:$index',
                              title: '${_map(source)['raw_sms_id']}',
                              subtitle: '',
                              status: '',
                              amount: '',
                              extra: _map(source),
                            ),
                        ],
                        columns: [
                          AdminTableColumn(
                            label: 'Source reference',
                            selectable: true,
                            value: (row) => row.title,
                          ),
                          AdminTableColumn(
                            label: 'Relationship',
                            value: (row) => '${row.extra['relation']}',
                          ),
                          AdminTableColumn(
                            label: 'Outcome',
                            value: (row) => '${row.extra['outcome']}',
                          ),
                          AdminTableColumn(
                            label: 'Parser',
                            value: (row) => '${row.extra['parser_version']}',
                          ),
                          AdminTableColumn(
                            label: 'Recorded at',
                            value: (row) => '${row.extra['created_at']}',
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (user?.permissions.contains('sms.reveal') == true)
                    ExpansionTile(
                      expansionAnimationStyle: CollectMotion.animationStyle(
                        context,
                      ),
                      title: const Text('Original SMS'),
                      children: [
                        for (final source in _detail!['sources'] as List)
                          TextButton.icon(
                            icon: const Icon(Icons.message_outlined),
                            label: const Text('Review original source'),
                            onPressed: () => showDialog<void>(
                              context: context,
                              animationStyle: CollectMotion.animationStyle(
                                context,
                              ),
                              builder: (_) => _SourceDialog(
                                id: _map(source)['raw_sms_id'] as String,
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberChecksDialog extends ConsumerStatefulWidget {
  const _MemberChecksDialog({required this.onSearch});
  final ValueChanged<String> onSearch;
  @override
  ConsumerState<_MemberChecksDialog> createState() => _MemberChecksState();
}

class _MemberChecksState extends ConsumerState<_MemberChecksDialog> {
  late final Object _fence = ref
      .read(cloudflareAdminSessionProvider.notifier)
      .authorityFence;
  List<Map<String, dynamic>> _rows = [];
  int _offset = 0, _total = 0;
  bool _loading = true;
  String? _errorValue;
  @override
  void initState() {
    super.initState();
    _fence;
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorValue = null;
      });
    }
    try {
      final api = ref.read(momoAdminApiProvider);
      api.require('users.read');
      api.require('collections.read');
      final data = await api.read(
        'transactions/payment-checks?limit=25&offset=$_offset',
        'payments.read',
      );
      api.require('users.read');
      api.require('collections.read');
      if (data['contract_version'] != 1 ||
          data['rows'] is! List ||
          data['offset'] != _offset ||
          data['limit'] != 25) {
        _invalid();
      }
      final total = exactJsonInteger(
        data['total'],
        field: 'Member check count',
        minimum: 0,
      );
      final rows = [for (final value in data['rows'] as List) _map(value)];
      if (rows.length != (total - _offset).clamp(0, 25) ||
          data['next_offset'] !=
              (_offset + rows.length < total ? _offset + rows.length : null) ||
          rows.map((row) => row['id']).toSet().length != rows.length) {
        _invalid();
      }
      for (final row in rows) {
        for (final key in ['id', 'member_id', 'group_id', 'intent_id']) {
          _identifier(row[key]);
        }
        for (final key in ['member_public_id', 'member_name', 'group_name']) {
          _text(row[key]);
        }
        exactJsonInteger(
          row['expected_amount_minor'],
          field: 'Requested contribution amount',
          minimum: 1,
        );
        exactJsonTimestamp(
          row['requested_at'],
          field: 'Member check requested time',
        );
        for (final key in ['provider_reference', 'evidence_note']) {
          if (row[key] != null &&
              (row[key] is! String ||
                  (row[key] as String).length >
                      (key == 'provider_reference' ? 160 : 2000))) {
            _invalid();
          }
        }
        if (row['currency'] != 'RWF' ||
            row['request_status'] != 'received' ||
            row['source'] != 'member_request' ||
            row['provider_reference_verified'] != false ||
            row['financial_effects'] != 0) {
          _invalid();
        }
      }
      if (mounted) {
        setState(() {
          _rows = rows;
          _total = total;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _errorValue = _error(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => _Scope(
    fence: _fence,
    child: AlertDialog(
      title: const Text('Member payment checks'),
      content: SizedBox(
        width: 700,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Member-supplied requests. References and notes are unverified; they do not establish a received payment or credit.',
              ),
              if (_loading) const LinearProgressIndicator(),
              if (_errorValue != null) _Note(_errorValue!, error: true),
              if (!_loading && _errorValue == null && _rows.isEmpty)
                const _Note('No member payment checks.'),
              if (_rows.isNotEmpty)
                AdminDataTable(
                  tableLabel: 'Member payment checks',
                  rows: [
                    for (final row in _rows)
                      AdminTableRowData(
                        id: '${row['id']}',
                        title: '${row['member_name']}',
                        subtitle: '',
                        status: 'Request received',
                        amount: '',
                        extra: row,
                      ),
                  ],
                  columns: [
                    AdminTableColumn(
                      label: 'Member',
                      value: (row) => row.title,
                    ),
                    AdminTableColumn(
                      label: 'Member ID',
                      value: (row) => '${row.extra['member_public_id']}',
                    ),
                    AdminTableColumn(
                      label: 'Group',
                      value: (row) => '${row.extra['group_name']}',
                    ),
                    AdminTableColumn(
                      label: 'Expected amount · RWF',
                      numeric: true,
                      value: (row) => adminFormatWholeAmount(
                        row.extra['expected_amount_minor'] as int,
                      ),
                    ),
                    AdminTableColumn(
                      label: 'Requested · Kigali',
                      value: (row) => adminKigaliDateTime(
                        DateTime.parse(row.extra['requested_at'] as String),
                      ),
                    ),
                    AdminTableColumn(
                      label: 'Status',
                      value: (row) => row.status,
                    ),
                    AdminTableColumn(
                      label: 'Unverified reference',
                      selectable: true,
                      value: (row) =>
                          '${row.extra['provider_reference'] ?? '—'}',
                    ),
                    AdminTableColumn(
                      label: 'Member note',
                      selectable: true,
                      value: (row) => '${row.extra['evidence_note'] ?? '—'}',
                    ),
                    AdminTableColumn(
                      label: 'Request ID',
                      selectable: true,
                      value: (row) => row.id,
                    ),
                    AdminTableColumn(
                      label: 'Search',
                      value: (_) => 'Search reference',
                      cellBuilder: (row) => TextButton.icon(
                        onPressed: row.extra['provider_reference'] == null
                            ? null
                            : () => widget.onSearch(
                                row.extra['provider_reference'] as String,
                              ),
                        icon: const Icon(Icons.search_rounded),
                        label: const Text('Search reference'),
                      ),
                    ),
                  ],
                ),
              if (!_loading)
                _Pager(
                  total: _total,
                  offset: _offset,
                  limit: 25,
                  onPage: (offset) {
                    setState(() {
                      _offset = offset;
                      _rows = [];
                    });
                    _load();
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        TextButton(
          onPressed: _loading ? null : _load,
          child: const Text('Refresh'),
        ),
      ],
    ),
  );
}

const _actionSchema = AdminPendingAttemptSchema(
  fields: {'reason', 'group_id', 'member_id', 'expected_version'},
);

class _MomoActionDialog extends ConsumerStatefulWidget {
  const _MomoActionDialog({this.transaction, this.sourceId});
  final MomoTransaction? transaction;
  final String? sourceId;
  @override
  ConsumerState<_MomoActionDialog> createState() => _MomoActionState();
}

class _MomoActionState extends ConsumerState<_MomoActionDialog> {
  late final Object _openingFence = ref
      .read(cloudflareAdminSessionProvider.notifier)
      .authorityFence;

  final _reason = TextEditingController(), _search = TextEditingController();
  List<Map<String, dynamic>> _candidates = [];
  Map<String, dynamic>? _selected, _result;
  AdminPendingAttemptCheckpoint? _pending;
  String? _errorValue;
  bool _busy = false;
  int _candidateOffset = 0, _candidateTotal = 0;
  String get _resource => widget.transaction?.id ?? widget.sourceId!;
  String get _family =>
      widget.transaction == null ? 'momo-reparse' : 'momo-assign';
  String get _permission =>
      widget.transaction == null ? 'sms.extract' : 'payments.write';
  @override
  void initState() {
    super.initState();
    _openingFence;
    _pending = ref
        .read(adminPendingAttemptStoreProvider)
        .restore(family: _family, resourceId: _resource, schema: _actionSchema);
    if (_pending != null) _reason.text = _pending!.intent['reason'] as String;
  }

  @override
  void dispose() {
    _reason.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    setState(() {
      _busy = true;
      _errorValue = null;
      _selected = null;
    });
    try {
      final query = Uri(
        queryParameters: {
          'search': _search.text.trim(),
          'limit': '25',
          'offset': '$_candidateOffset',
        },
      ).query;
      final data = await ref
          .read(momoAdminApiProvider)
          .read('transactions/$_resource/candidates?$query', 'payments.read');
      if (data['rows'] is! List ||
          data['offset'] != _candidateOffset ||
          data['limit'] != 25) {
        _invalid();
      }
      final rows = [for (final value in data['rows'] as List) _map(value)];
      for (final row in rows) {
        _identifier(row['group_id']);
        _identifier(row['member_id']);
        _text(row['group_name']);
        _text(row['member_name']);
        _text(row['member_public_id']);
      }
      final total = exactJsonInteger(
        data['total'],
        field: 'Eligible destinations',
        minimum: 0,
      );
      if (mounted) {
        setState(() {
          _candidates = rows;
          _candidateTotal = total;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errorValue = _error(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _errorValue = null;
    });
    try {
      final api = ref.read(momoAdminApiProvider);
      api.require(_permission, fresh: true);
      final store = ref.read(adminPendingAttemptStoreProvider);
      _pending ??= store.retain(
        family: _family,
        resourceId: _resource,
        requestKey: const Uuid().v4(),
        permission: _permission,
        schema: _actionSchema,
        intent: {
          'reason': _reason.text.trim(),
          if (widget.transaction != null) ...{
            'group_id': _selected!['group_id'],
            'member_id': _selected!['member_id'],
            'expected_version': widget.transaction!.version,
          },
        },
      );
      final path = widget.transaction == null
          ? 'sources/$_resource/reparse'
          : 'transactions/$_resource/assign';
      final result = await api.session.request(
        'momo/$path',
        body: _pending!.intent,
        authenticated: true,
        idempotencyKey: _pending!.requestKey,
      );
      api.require(_permission);
      if (widget.transaction != null) {
        _identifier(result['payment_id']);
        if (result['transaction_id'] != _resource ||
            !{
              'awaiting_review',
              'linked_existing',
            }.contains(result['status'])) {
          _invalid();
        }
      } else if (result['raw_sms_id'] != _resource ||
          result['status'] != 'pending') {
        _invalid();
      }
      store.clear(family: _family, resourceId: _resource);
      if (mounted) {
        setState(() {
          _result = result;
          _pending = null;
        });
      }
    } catch (error) {
      if (error is CloudflareAdminRequestException &&
          !error.outcomeUnknown &&
          error.statusCode != null) {
        ref
            .read(adminPendingAttemptStoreProvider)
            .clear(family: _family, resourceId: _resource);
        _pending = null;
      }
      if (mounted) {
        setState(() => _errorValue = _error(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => _Scope(
    fence: _openingFence,
    child: AlertDialog(
      title: Text(
        widget.transaction == null
            ? 'Reparse source message'
            : 'Assign beneficiary for review',
      ),
      content: SizedBox(
        width: 700,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_result != null)
                _Note(
                  widget.transaction == null
                      ? 'Source queued for extraction. It must pass validation before a payment can be accepted.'
                      : 'Request recorded. Financial posting still follows the existing independent review process.',
                )
              else ...[
                if (widget.transaction != null)
                  _Note(
                    '${adminFormatWholeAmount(widget.transaction!.amount)} RWF · Payer ${widget.transaction!.payer}\nThe receiving account remains fixed. Assignment prepares financial review and does not credit a balance.',
                  ),
                if (_pending != null) ...[
                  const _Note(
                    'An original request is unresolved. Review and retry its identical request; no new request will be created.',
                  ),
                  SelectableText(
                    'Request ${_pending!.requestKey}\n${_pending!.intent}',
                  ),
                ] else if (widget.transaction != null) ...[
                  TextField(
                    controller: _search,
                    maxLength: 200,
                    decoration: InputDecoration(
                      labelText: 'Find eligible group and beneficiary',
                      suffixIcon: IconButton(
                        tooltip: 'Search eligible destinations',
                        onPressed: _busy
                            ? null
                            : () {
                                _candidateOffset = 0;
                                _find();
                              },
                        icon: const Icon(Icons.search_rounded),
                      ),
                    ),
                    onSubmitted: (_) {
                      _candidateOffset = 0;
                      _find();
                    },
                  ),
                  for (final candidate in _candidates)
                    ListTile(
                      selected: _selected == candidate,
                      leading: Icon(
                        _selected == candidate
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      title: Text(
                        '${candidate['member_name']} · ${candidate['member_public_id']}',
                      ),
                      subtitle: Text(
                        '${candidate['group_name']} · Active membership; receiving account matches',
                      ),
                      onTap: _busy
                          ? null
                          : () => setState(() => _selected = candidate),
                    ),
                  if (_candidates.isEmpty)
                    const _Note(
                      'Search to load eligible destinations. No beneficiary or group is selected automatically.',
                    ),
                  if (_candidateTotal > 25)
                    _Pager(
                      total: _candidateTotal,
                      offset: _candidateOffset,
                      limit: 25,
                      onPage: (offset) {
                        _candidateOffset = offset;
                        _find();
                      },
                    ),
                ],
                TextField(
                  controller: _reason,
                  enabled: !_busy && _pending == null,
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Evidence and reason',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              if (_errorValue != null) _Note(_errorValue!, error: true),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (_result?['payment_id'] != null)
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
              context.go('/admin/reconciliations/${_result!['payment_id']}');
            },
            child: const Text('Open financial review'),
          ),
        if (_result == null)
          FilledButton(
            onPressed:
                _busy ||
                    _reason.text.trim().length < 8 ||
                    (widget.transaction != null &&
                        _selected == null &&
                        _pending == null)
                ? null
                : _submit,
            child: Text(
              _pending != null
                  ? 'Retry original request'
                  : widget.transaction == null
                  ? 'Request reparse'
                  : 'Assign for review',
            ),
          ),
      ],
    ),
  );
}
