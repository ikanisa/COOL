part of 'cloudflare_admin_momo_page.dart';

class _SourceExceptions extends ConsumerStatefulWidget {
  const _SourceExceptions({super.key});
  @override
  ConsumerState<_SourceExceptions> createState() => _SourceExceptionsState();
}

class _SourceExceptionsState extends ConsumerState<_SourceExceptions> {
  String _state = 'needs_review';
  int _offset = 0;
  late Future<Map<String, dynamic>> _future;
  @override
  void initState() {
    super.initState();
    _fetch();
  }

  void _fetch() {
    _future = ref
        .read(momoAdminApiProvider)
        .read('sources?status=$_state&limit=25&offset=$_offset', 'sms.read');
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    expansionAnimationStyle: CollectMotion.animationStyle(context),
    initiallyExpanded: true,
    title: const Text('Source messages needing attention'),
    subtitle: const Text(
      'Unresolved sources are not validated payments. This separate source view does not use transaction filters or amount totals.',
    ),
    children: [
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: _state,
        decoration: const InputDecoration(labelText: 'Source state'),
        items: const [
          DropdownMenuItem(
            value: 'needs_review',
            child: Text('Extraction needs review'),
          ),
          DropdownMenuItem(
            value: 'source_unresolved',
            child: Text('Receiving source unresolved'),
          ),
          DropdownMenuItem(value: 'retry', child: Text('Processing retry')),
          DropdownMenuItem(
            value: 'completed',
            child: Text('Processed source messages'),
          ),
        ],
        onChanged: (value) => setState(() {
          _state = value!;
          _offset = 0;
          _fetch();
        }),
      ),
      FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _Note(_error(snapshot.error!), error: true);
          }
          if (!snapshot.hasData) return const LinearProgressIndicator();
          try {
            final data = snapshot.data!;
            if (data['rows'] is! List) _invalid();
            final total = exactJsonInteger(
              data['total'],
              field: 'Source count',
              minimum: 0,
            );
            final jobs = [
              for (final value in data['rows'] as List) _map(value),
            ];
            for (final job in jobs) {
              _identifier(job['raw_sms_id']);
              if (job['state'] != _state) _invalid();
              for (final field in ['binding_id', 'receiving_account_id']) {
                if (!job.containsKey(field)) _invalid();
                if (job[field] != null) _identifier(job[field]);
              }
            }
            return Column(
              children: [
                if (jobs.isEmpty)
                  const _Note('No source messages in this state.'),
                if (jobs.isNotEmpty)
                  AdminDataTable(
                    tableLabel: 'MoMo source messages',
                    rows: [
                      for (final (index, job) in jobs.indexed)
                        AdminTableRowData(
                          id: 'source:$index:${job['raw_sms_id']}',
                          title: job['state'] == 'source_unresolved'
                              ? 'Source message — receiving source unresolved'
                              : job['state'] == 'completed'
                              ? 'Source message — processing completed'
                              : 'Source message — extraction needs review',
                          subtitle: '',
                          status: '${job['state']}',
                          amount: '',
                          extra: job,
                        ),
                    ],
                    columns: [
                      AdminTableColumn(
                        label: 'Source message',
                        value: (row) => row.title,
                      ),
                      AdminTableColumn(
                        label: 'Status',
                        value: (row) => row.status,
                      ),
                      AdminTableColumn(
                        label: 'Received at',
                        value: (row) => '${row.extra['received_at']}',
                      ),
                      AdminTableColumn(
                        label: 'Processing issue',
                        value: (row) =>
                            '${row.extra['last_error'] ?? row.extra['state']}',
                      ),
                      AdminTableColumn(
                        label: 'SMS reference',
                        selectable: true,
                        value: (row) => '${row.extra['raw_sms_id']}',
                      ),
                    ],
                    onOpen: (row) async {
                      final job = row.extra;
                      await showDialog<void>(
                        context: context,
                        animationStyle: CollectMotion.animationStyle(context),
                        builder: (_) => _SourceDialog(
                          id: job['raw_sms_id'] as String,
                          job: Map.unmodifiable(job),
                        ),
                      );
                      if (mounted) setState(_fetch);
                    },
                  ),
                _Pager(
                  total: total,
                  offset: _offset,
                  limit: 25,
                  onPage: (offset) => setState(() {
                    _offset = offset;
                    _fetch();
                  }),
                ),
              ],
            );
          } catch (error) {
            return _Note(_error(error), error: true);
          }
        },
      ),
    ],
  );
}

class _SourceDialog extends ConsumerStatefulWidget {
  const _SourceDialog({required this.id, this.job});
  final String id;
  final Map<String, dynamic>? job;
  @override
  ConsumerState<_SourceDialog> createState() => _SourceDialogState();
}

class _SourceDialogState extends ConsumerState<_SourceDialog> {
  late final Object _openingFence = ref
      .read(cloudflareAdminSessionProvider.notifier)
      .authorityFence;

  final _reason = TextEditingController();
  String? _body, _errorValue;
  Map<String, dynamic>? _candidate;
  bool _busy = false, _resolutionQueued = false, _reviewRecorded = false;
  bool get _unresolved => widget.job?['state'] == 'source_unresolved';
  bool get _canResolveSource =>
      !_resolutionQueued &&
      _unresolved &&
      widget.job?['raw_sms_id'] == widget.id &&
      widget.job!.containsKey('binding_id') &&
      widget.job!.containsKey('receiving_account_id') &&
      widget.job!['binding_id'] == null &&
      widget.job!['receiving_account_id'] == null;
  bool get _canReview =>
      !_reviewRecorded &&
      const {'needs_review', 'completed'}.contains(widget.job?['state']) &&
      widget.job?['receiving_account_id'] != null &&
      widget.job?['attempt_count'] is int &&
      RegExp(r'^[a-f0-9]{64}$').hasMatch('${widget.job?['body_sha256']}') &&
      !const {
        'accepted',
        'duplicate',
      }.contains(widget.job?['latest_attempt_outcome']);
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _reveal() async {
    setState(() {
      _busy = true;
      _errorValue = null;
    });
    try {
      final data = await ref
          .read(momoAdminApiProvider)
          .read(
            'sources/${widget.id}/content',
            'sms.reveal',
            reason: _reason.text.trim(),
          );
      if (data['raw_sms_id'] != widget.id || data['raw_body'] is! String) {
        _invalid();
      }
      if (widget.job?['body_sha256'] != null &&
          data['body_sha256'] != widget.job!['body_sha256']) {
        _invalid();
      }
      Map<String, dynamic>? candidate;
      final latest = data['latest_attempt'];
      if (latest is Map && latest['output_json'] is String) {
        try {
          candidate = _map(jsonDecode(latest['output_json'] as String));
        } catch (_) {
          // Invalid model output remains evidence; the correction starts blank.
        }
      }
      if (mounted) {
        setState(() {
          _body = data['raw_body'] as String;
          _candidate = candidate;
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

  @override
  Widget build(BuildContext context) {
    final permissions =
        ref.watch(cloudflareAdminSessionProvider).asData?.value?.permissions ??
        [];
    return _Scope(
      fence: _openingFence,
      child: AlertDialog(
        title: const Text('Source message'),
        content: SizedBox(
          width: 650,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'A source message is evidence, and does not by itself credit a contribution.',
                ),
                AdminRecordFactsTable(
                  semanticLabel: 'Source message facts',
                  fields: [
                    ('SMS reference', widget.id),
                    if (widget.job case final job?) ...[
                      ('Status', '${job['state']}'),
                      ('Received at', '${job['received_at']}'),
                      (
                        'Processing issue',
                        '${job['last_error'] ?? job['state']}',
                      ),
                      (
                        'Receiving account reference',
                        '${job['receiving_account_id'] ?? 'Unassigned'}',
                      ),
                      (
                        'Binding reference',
                        '${job['binding_id'] ?? 'Unassigned'}',
                      ),
                    ],
                  ],
                ),
                if (_resolutionQueued)
                  const _Note(
                    'Historical source queued for processing. Close this source view to refresh its state.',
                  ),
                if (_reviewRecorded)
                  const _Note(
                    'Review recorded. Close this view to refresh validation and source state.',
                  ),
                if (permissions.contains('sms.reveal')) ...[
                  TextField(
                    controller: _reason,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'Reason to review the original source',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                if (_errorValue != null) _Note(_errorValue!, error: true),
                if (permissions.contains('sms.reveal'))
                  TextButton.icon(
                    onPressed: _busy || _reason.text.trim().length < 8
                        ? null
                        : _reveal,
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Reveal original SMS'),
                  ),
                if (_body != null)
                  AdminRecordFactsTable(
                    semanticLabel: 'Revealed original SMS evidence',
                    fields: [('Original SMS', _body!)],
                  ),
                if (_canReview && permissions.contains('sms.extract'))
                  for (final kind in ['correct', 'non-payment'])
                    TextButton.icon(
                      icon: Icon(
                        kind == 'correct'
                            ? Icons.edit_note_rounded
                            : Icons.block_rounded,
                      ),
                      label: Text(
                        kind == 'correct'
                            ? 'Correct extraction'
                            : 'Classify non-payment',
                      ),
                      onPressed: _busy
                          ? null
                          : () async {
                              final recorded = await showDialog<bool>(
                                context: context,
                                animationStyle: CollectMotion.animationStyle(
                                  context,
                                ),
                                builder: (_) => _MomoReviewDialog(
                                  kind: kind,
                                  sourceId: widget.id,
                                  job: widget.job,
                                  candidate: _candidate,
                                ),
                              );
                              if (mounted && recorded == true) {
                                setState(() => _reviewRecorded = true);
                              }
                            },
                    ),
                if (_canResolveSource &&
                    permissions.contains('sms.extract') &&
                    permissions.contains('receivers.read'))
                  TextButton.icon(
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('Resolve historical source'),
                    onPressed: _busy
                        ? null
                        : () => showDialog<void>(
                            context: context,
                            animationStyle: CollectMotion.animationStyle(
                              context,
                            ),
                            builder: (_) => _HistoricalSourceDialog(
                              sourceId: widget.id,
                              onQueued: () {
                                if (mounted) {
                                  setState(() => _resolutionQueued = true);
                                }
                              },
                            ),
                          ),
                  ),
                if (permissions.contains('sms.extract') &&
                    !_unresolved &&
                    !_reviewRecorded)
                  TextButton.icon(
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('Request reparse'),
                    onPressed: _busy
                        ? null
                        : () => showDialog<void>(
                            context: context,
                            animationStyle: CollectMotion.animationStyle(
                              context,
                            ),
                            builder: (_) =>
                                _MomoActionDialog(sourceId: widget.id),
                          ),
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
        ],
      ),
    );
  }
}

const _extractionRawLabels = {
  'transaction_id_raw': 'Provider transaction ID',
  'original_transaction_id_raw': 'Original transaction ID',
  'transaction_datetime_raw': 'Provider date and time',
  'principal_amount_raw': 'Principal amount',
  'currency_raw': 'Currency',
  'payer_name_raw': 'Payer name',
  'payer_identifier_raw': 'Visible payer identifier',
  'payment_reference_raw': 'Payment reference',
  'fee_amount_raw': 'Fee',
  'wallet_balance_after_raw': 'Wallet balance observation',
};
const _extractionEvidenceLabels = {
  'incoming_success': 'Success or classification excerpt',
  'principal': 'Principal excerpt',
  'transaction_id': 'Transaction ID excerpt',
  'transaction_datetime': 'Date and time excerpt',
  'payer': 'Payer excerpt',
  'fee': 'Fee excerpt',
  'wallet_balance_after': 'Wallet balance excerpt',
};
const _reviewSchema = AdminPendingAttemptSchema(
  fields: {
    'expected_state',
    'expected_attempt_count',
    'expected_body_sha256',
    'extraction',
    'classification_evidence',
    'evidence_reference',
    'reason',
    'expected_version',
    'expected_conflicting_attempt_ids',
    'decision',
  },
  nestedFields: {
    'extraction': {
      'schema_version',
      'event_kind',
      'payment_outcome',
      'transaction_id_raw',
      'original_transaction_id_raw',
      'transaction_datetime_raw',
      'principal_amount_raw',
      'currency_raw',
      'payer_name_raw',
      'payer_identifier_raw',
      'payment_reference_raw',
      'fee_amount_raw',
      'wallet_balance_after_raw',
      'evidence',
      'issues',
    },
    'extraction.evidence': {
      'incoming_success',
      'principal',
      'transaction_id',
      'transaction_datetime',
      'payer',
      'fee',
      'wallet_balance_after',
    },
  },
);

class _MomoReviewDialog extends ConsumerStatefulWidget {
  const _MomoReviewDialog({
    required this.kind,
    this.sourceId,
    this.job,
    this.candidate,
    this.transaction,
    this.conflictingAttempts = const [],
  });
  final String kind;
  final String? sourceId;
  final Map<String, dynamic>? job, candidate;
  final MomoTransaction? transaction;
  final List<String> conflictingAttempts;
  @override
  ConsumerState<_MomoReviewDialog> createState() => _MomoReviewState();
}

class _MomoReviewState extends ConsumerState<_MomoReviewDialog> {
  late final Object _fence = ref
      .read(cloudflareAdminSessionProvider.notifier)
      .authorityFence;
  final _evidence = TextEditingController(),
      _reason = TextEditingController(),
      _classification = TextEditingController();
  final _raw = {
    for (final key in _extractionRawLabels.keys) key: TextEditingController(),
  };
  final _excerpts = {
    for (final key in _extractionEvidenceLabels.keys)
      key: TextEditingController(),
  };
  String? _kind, _outcome, _errorValue;
  AdminPendingAttemptCheckpoint? _pending;
  bool _busy = false, _recorded = false;
  bool get _conflict => widget.kind == 'conflict';
  bool get _nonPayment => widget.kind == 'non-payment';
  String get _resource => widget.transaction?.id ?? widget.sourceId!;
  String get _family => 'momo-review-${widget.kind}';
  String get _permission => _conflict ? 'payments.write' : 'sms.extract';

  void _validateOriginal(Map<String, dynamic> intent) {
    for (final key in ['evidence_reference', 'reason']) {
      final value = _text(intent[key]);
      if (value.trim().length < 8 || value.length > 500) _invalid();
    }
    if (_conflict) {
      exactJsonInteger(
        intent['expected_version'],
        field: 'Review version',
        minimum: 1,
      );
      final attempts = intent['expected_conflicting_attempt_ids'];
      if (intent['decision'] != 'retain_original' ||
          attempts is! List ||
          attempts.isEmpty ||
          attempts.length > 100 ||
          attempts.toSet().length != attempts.length) {
        _invalid();
      }
      for (final attempt in attempts) {
        _identifier(attempt);
      }
    } else {
      if (!const {
            'needs_review',
            'completed',
          }.contains(intent['expected_state']) ||
          !RegExp(
            r'^[a-f0-9]{64}$',
          ).hasMatch('${intent['expected_body_sha256']}')) {
        _invalid();
      }
      exactJsonInteger(
        intent['expected_attempt_count'],
        field: 'Reviewed attempts',
        minimum: 0,
      );
      final extraction = _map(intent['extraction']);
      if (extraction['schema_version'] != 'momo-extraction.v1' ||
          !const {
            'incoming_receipt',
            'reversal',
            'outgoing',
            'failed',
            'pending',
            'other',
            'unknown',
          }.contains(extraction['event_kind']) ||
          !const {
            'successful',
            'failed',
            'pending',
            'unknown',
          }.contains(extraction['payment_outcome'])) {
        _invalid();
      }
      final evidence = _map(extraction['evidence']);
      for (final entry in {
        for (final key in _extractionRawLabels.keys) key: extraction[key],
        for (final key in _extractionEvidenceLabels.keys) key: evidence[key],
      }.entries) {
        if (entry.value != null &&
            (entry.value is! String || (entry.value as String).length > 500)) {
          _invalid();
        }
      }
      if (!extraction.keys.toSet().containsAll(_extractionRawLabels.keys) ||
          !evidence.keys.toSet().containsAll(_extractionEvidenceLabels.keys) ||
          extraction['issues'] is! List) {
        _invalid();
      }
      if (_nonPayment &&
          (intent['classification_evidence'] is! String ||
              (intent['classification_evidence'] as String).isEmpty ||
              (intent['classification_evidence'] as String).length > 500)) {
        _invalid();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _fence;
    _pending = ref
        .read(adminPendingAttemptStoreProvider)
        .restore(family: _family, resourceId: _resource, schema: _reviewSchema);
    if (_pending != null) {
      try {
        _validateOriginal(_pending!.intent);
      } catch (error) {
        _errorValue = _error(error);
      }
    }
    if (!_conflict && !_nonPayment && widget.candidate != null) {
      final candidate = widget.candidate!;
      if (candidate['schema_version'] == 'momo-extraction.v1') {
        if (const {
          'incoming_receipt',
          'reversal',
          'outgoing',
          'failed',
          'pending',
          'other',
          'unknown',
        }.contains(candidate['event_kind'])) {
          _kind = candidate['event_kind'] as String;
        }
        if (const {
          'successful',
          'failed',
          'pending',
          'unknown',
        }.contains(candidate['payment_outcome'])) {
          _outcome = candidate['payment_outcome'] as String;
        }
        for (final key in _raw.keys) {
          final value = candidate[key];
          if (value is String && value.length <= 500) _raw[key]!.text = value;
        }
        final evidence = candidate['evidence'];
        if (evidence is Map) {
          for (final key in _excerpts.keys) {
            final value = evidence[key];
            if (value is String && value.length <= 500) {
              _excerpts[key]!.text = value;
            }
          }
        }
      }
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _evidence,
      _reason,
      _classification,
      ..._raw.values,
      ..._excerpts.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _value(TextEditingController controller) =>
      controller.text.isEmpty ? null : controller.text;
  Map<String, dynamic> _intent() => {
    'evidence_reference': _evidence.text.trim(),
    'reason': _reason.text.trim(),
    if (_conflict) ...{
      'expected_version': widget.transaction!.version,
      'expected_conflicting_attempt_ids': widget.conflictingAttempts,
      'decision': 'retain_original',
    } else ...{
      'expected_state': widget.job!['state'],
      'expected_attempt_count': widget.job!['attempt_count'],
      'expected_body_sha256': widget.job!['body_sha256'],
      if (_nonPayment) 'classification_evidence': _classification.text,
      'extraction': {
        'schema_version': 'momo-extraction.v1',
        'event_kind': _kind,
        'payment_outcome': _nonPayment
            ? (_kind == 'outgoing' ? 'successful' : _kind)
            : _outcome,
        for (final key in _raw.keys)
          key: _nonPayment ? null : _value(_raw[key]!),
        'evidence': {
          for (final key in _excerpts.keys)
            key: _nonPayment
                ? (key == 'incoming_success' ? _classification.text : null)
                : _value(_excerpts[key]!),
        },
        'issues': <String>[],
      },
    },
  };
  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _errorValue = null;
    });
    try {
      final api = ref.read(momoAdminApiProvider);
      api.require(_permission, fresh: true);
      api.require('sms.extract');
      api.require(_conflict ? 'payments.read' : 'sms.read');
      final store = ref.read(adminPendingAttemptStoreProvider);
      if (_pending == null) _validateOriginal(_intent());
      _pending ??= store.retain(
        family: _family,
        resourceId: _resource,
        requestKey: const Uuid().v4(),
        permission: _permission,
        intent: _intent(),
        schema: _reviewSchema,
      );
      final original = _pending!;
      _validateOriginal(original.intent);
      final path = _conflict
          ? 'transactions/$_resource/review-conflict'
          : 'sources/$_resource/${_nonPayment ? 'classify-non-payment' : 'correct-extraction'}';
      final result = await api.session.request(
        'momo/$path',
        authenticated: true,
        body: original.intent,
        idempotencyKey: original.requestKey,
      );
      api.require(_permission);
      api.require('sms.extract');
      api.require(_conflict ? 'payments.read' : 'sms.read');
      if (exactJsonInteger(
            result['financial_effects'],
            field: 'Review financial effects',
            minimum: 0,
          ) !=
          0) {
        _invalid();
      }
      if (_conflict) {
        if (result['transaction_id'] != _resource ||
            result['status'] != 'needs_allocation' ||
            result['version'] !=
                (original.intent['expected_version'] as int) + 1) {
          _invalid();
        }
      } else {
        if (result['raw_sms_id'] != _resource ||
            result['status'] != 'review_recorded') {
          _invalid();
        }
        _identifier(result['parse_attempt_id']);
      }
      store.clear(family: _family, resourceId: _resource);
      if (mounted) {
        setState(() {
          _recorded = true;
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
      if (mounted) setState(() => _errorValue = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _Scope(
    fence: _fence,
    child: AlertDialog(
      title: Text(
        _conflict
            ? 'Review conflicting evidence'
            : _nonPayment
            ? 'Classify non-payment'
            : 'Correct extracted facts',
      ),
      content: SizedBox(
        width: 700,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_recorded)
                const _Note(
                  'Review recorded. Refresh the record to see validation and allocation state. No contribution was credited.',
                )
              else ...[
                Text(
                  _conflict
                      ? 'Retain the original accepted facts and dismiss only the exact conflicting attempts reviewed here. Replacing accepted facts is unavailable. No financial operation is performed.'
                      : 'This records a new reviewed attempt. Normal source validation and deduplication still apply; accepted payment facts are not edited and no contribution is credited.',
                ),
                if (_conflict)
                  _Note(
                    '${adminFormatWholeAmount(widget.transaction!.amount)} RWF · ${widget.transaction!.values['provider_transaction_id']}\nPayer ${widget.transaction!.payer}\n${widget.conflictingAttempts.length} conflicting attempts. Original receiving account and payment facts stay fixed.',
                  ),
                if (_pending != null) ...[
                  const _Note(
                    'An original request is unresolved. Retry the identical review and request key.',
                  ),
                  SelectableText(
                    'Request ${_pending!.requestKey}\n${_pending!.intent}',
                  ),
                ] else ...[
                  if (!_conflict) ...[
                    const _Note(
                      'Copy exact source text for facts and excerpts. Leave absent facts blank; do not infer hidden digits or values. A retained candidate is only a starting point.',
                    ),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _kind,
                      decoration: const InputDecoration(
                        labelText: 'Message type',
                      ),
                      items: [
                        for (final kind
                            in (_nonPayment
                                ? ['outgoing', 'failed', 'pending']
                                : [
                                    'incoming_receipt',
                                    'reversal',
                                    'outgoing',
                                    'failed',
                                    'pending',
                                    'other',
                                    'unknown',
                                  ]))
                          DropdownMenuItem(
                            value: kind,
                            child: Text(kind.replaceAll('_', ' ')),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _kind = value),
                    ),
                    if (_nonPayment)
                      TextField(
                        controller: _classification,
                        maxLength: 500,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(labelText: 'Excerpt'),
                        onChanged: (_) => setState(() {}),
                      )
                    else ...[
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _outcome,
                        decoration: const InputDecoration(
                          labelText: 'Provider outcome',
                        ),
                        items: [
                          for (final outcome in [
                            'successful',
                            'failed',
                            'pending',
                            'unknown',
                          ])
                            DropdownMenuItem(
                              value: outcome,
                              child: Text(outcome),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _outcome = value),
                      ),
                      for (final entry in _extractionRawLabels.entries)
                        TextField(
                          controller: _raw[entry.key],
                          maxLength: 500,
                          enabled: !_busy,
                          decoration: InputDecoration(labelText: entry.value),
                        ),
                      ExpansionTile(
                        expansionAnimationStyle: CollectMotion.animationStyle(
                          context,
                        ),
                        title: const Text('Exact supporting excerpts'),
                        children: [
                          for (final entry in _extractionEvidenceLabels.entries)
                            TextField(
                              controller: _excerpts[entry.key],
                              maxLength: 500,
                              minLines: 1,
                              maxLines: 3,
                              enabled: !_busy,
                              decoration: InputDecoration(
                                labelText: entry.value,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                  const _Note(
                    'Reference retained review evidence and explain the decision. Both fields require at least 8 characters.',
                  ),
                  TextField(
                    controller: _evidence,
                    maxLength: 500,
                    enabled: !_busy,
                    decoration: const InputDecoration(labelText: 'Evidence'),
                    onChanged: (_) => setState(() {}),
                  ),
                  TextField(
                    controller: _reason,
                    maxLength: 500,
                    minLines: 2,
                    maxLines: 4,
                    enabled: !_busy,
                    decoration: const InputDecoration(labelText: 'Reason'),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ],
              if (_errorValue != null) _Note(_errorValue!, error: true),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, _recorded),
          child: const Text('Close'),
        ),
        if (!_recorded)
          FilledButton(
            onPressed:
                _busy ||
                    (_pending == null &&
                        (_evidence.text.trim().length < 8 ||
                            _reason.text.trim().length < 8 ||
                            (!_conflict &&
                                (_kind == null ||
                                    (_nonPayment
                                        ? _classification.text.isEmpty
                                        : _outcome == null)))))
                ? null
                : _submit,
            child: Text(
              _pending != null
                  ? 'Retry original request'
                  : _conflict
                  ? 'Retain original'
                  : 'Save review',
            ),
          ),
      ],
    ),
  );
}

const _sourceResolutionSchema = AdminPendingAttemptSchema(
  fields: {'receiving_account_id', 'evidence_reference', 'reason'},
);

class _HistoricalSourceDialog extends ConsumerStatefulWidget {
  const _HistoricalSourceDialog({
    required this.sourceId,
    required this.onQueued,
  });
  final String sourceId;
  final VoidCallback onQueued;
  @override
  ConsumerState<_HistoricalSourceDialog> createState() =>
      _HistoricalSourceState();
}

class _HistoricalSourceState extends ConsumerState<_HistoricalSourceDialog> {
  late final Object _openingFence = ref
      .read(cloudflareAdminSessionProvider.notifier)
      .authorityFence;
  final _evidence = TextEditingController(), _reason = TextEditingController();
  List<Map<String, dynamic>> _accounts = [];
  String? _account, _errorValue;
  AdminPendingAttemptCheckpoint? _pending;
  bool _loading = true, _busy = false, _resolved = false;
  static const _family = 'momo-source-resolve';

  void _validateIntent(Map<String, dynamic> intent) {
    if (intent.length != 3) _invalid();
    _identifier(intent['receiving_account_id']);
    for (final key in ['evidence_reference', 'reason']) {
      final value = _text(intent[key]);
      if (value.trim().length < 8 || value.length > 500) _invalid();
    }
  }

  @override
  void initState() {
    super.initState();
    _openingFence;
    try {
      final pending = ref
          .read(adminPendingAttemptStoreProvider)
          .restore(
            family: _family,
            resourceId: widget.sourceId,
            schema: _sourceResolutionSchema,
          );
      if (pending != null) {
        _validateIntent(pending.intent);
        if (pending.permission != 'sms.extract') _invalid();
        _pending = pending;
      }
    } catch (error) {
      _errorValue = _error(error);
    }
    Future.microtask(_loadAccounts);
  }

  @override
  void dispose() {
    _evidence.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    try {
      final api = ref.read(momoAdminApiProvider);
      api.require('sms.extract');
      final data = await api.read('accounts', 'receivers.read');
      api.require('sms.extract');
      if (data['rows'] is! List) _invalid();
      final rows = [for (final value in data['rows'] as List) _map(value)];
      for (final row in rows) {
        _identifier(row['id']);
        _text(row['recipient_name']);
        _text(row['public_code']);
        if (!const {'active', 'suspended'}.contains(row['status']) ||
            !const {'mtn_momo', 'airtel_money'}.contains(row['provider'])) {
          _invalid();
        }
      }
      if (rows.map((row) => row['id']).toSet().length != rows.length) {
        _invalid();
      }
      if (mounted) {
        setState(
          () => _accounts = rows
              .where((row) => row['status'] == 'active')
              .toList(),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _errorValue = _error(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _errorValue = null;
    });
    try {
      final api = ref.read(momoAdminApiProvider);
      api.require('sms.extract', fresh: true);
      api.require('receivers.read');
      final store = ref.read(adminPendingAttemptStoreProvider);
      if (_pending == null) {
        if (!_accounts.any((row) => row['id'] == _account)) _invalid();
        final intent = <String, dynamic>{
          'receiving_account_id': _account,
          'evidence_reference': _evidence.text.trim(),
          'reason': _reason.text.trim(),
        };
        _validateIntent(intent);
        _pending = store.retain(
          family: _family,
          resourceId: widget.sourceId,
          requestKey: const Uuid().v4(),
          permission: 'sms.extract',
          intent: intent,
          schema: _sourceResolutionSchema,
        );
      }
      final original = _pending!;
      _validateIntent(original.intent);
      final result = await api.session.request(
        'momo/sources/${widget.sourceId}/resolve',
        authenticated: true,
        body: original.intent,
        idempotencyKey: original.requestKey,
      );
      api.require('sms.extract');
      api.require('receivers.read');
      if (result['raw_sms_id'] != widget.sourceId ||
          result['receiving_account_id'] !=
              original.intent['receiving_account_id'] ||
          result['mode'] != 'historical' ||
          result['status'] != 'pending' ||
          exactJsonInteger(
                result['financial_effects'],
                field: 'Historical source financial effects',
                minimum: 0,
              ) !=
              0) {
        _invalid();
      }
      store.clear(family: _family, resourceId: widget.sourceId);
      if (mounted) {
        setState(() {
          _pending = null;
          _resolved = true;
        });
        widget.onQueued();
      }
    } catch (error) {
      if (error is CloudflareAdminRequestException &&
          !error.outcomeUnknown &&
          error.statusCode != null) {
        ref
            .read(adminPendingAttemptStoreProvider)
            .clear(family: _family, resourceId: widget.sourceId);
        _pending = null;
      }
      if (mounted) setState(() => _errorValue = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _Scope(
    fence: _openingFence,
    child: AlertDialog(
      title: const Text('Resolve historical source'),
      content: SizedBox(
        width: 650,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Identify the receiving account from retained historical evidence. This queues source processing and does not credit a contribution or rebind a live capture.',
              ),
              if (_resolved)
                const _Note(
                  'Historical source queued for processing. No contribution was credited.',
                )
              else if (_pending != null) ...[
                const _Note(
                  'The original request is unresolved. Retry its identical account, evidence and reason with the same request key.',
                ),
                SelectableText(
                  'Request ${_pending!.requestKey}\n${_pending!.intent}',
                ),
              ] else ...[
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _account,
                  decoration: const InputDecoration(
                    labelText: 'Account',
                    hintText: 'Select the account established by evidence',
                  ),
                  items: [
                    for (final account in _accounts)
                      DropdownMenuItem(
                        value: account['id'] as String,
                        child: Text(
                          '${account['recipient_name']} · ${account['public_code']} · ${account['provider'] == 'mtn_momo' ? 'MTN MoMo' : 'Airtel Money'}',
                        ),
                      ),
                  ],
                  selectedItemBuilder: (_) => [
                    for (final account in _accounts)
                      Text(account['public_code'] as String),
                  ],
                  onChanged: _busy || _loading
                      ? null
                      : (value) => setState(() => _account = value),
                ),
                for (final account in _accounts.where(
                  (account) => account['id'] == _account,
                ))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${account['provider'] == 'mtn_momo' ? 'MTN MoMo' : 'Airtel Money'} · ${account['recipient_name']}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (!_loading && _accounts.isEmpty)
                  const _Note('No active receiving accounts are available.'),
                const _Note(
                  'Evidence reference and reason must each contain at least 8 characters.',
                ),
                TextField(
                  controller: _evidence,
                  enabled: !_busy,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'Evidence'),
                  onChanged: (_) => setState(() {}),
                ),
                TextField(
                  controller: _reason,
                  enabled: !_busy,
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              if (_errorValue != null) _Note(_errorValue!, error: true),
              if (_busy || _loading) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (!_resolved)
          FilledButton(
            onPressed:
                _busy ||
                    (_pending == null &&
                        (_loading ||
                            _account == null ||
                            _evidence.text.trim().length < 8 ||
                            _reason.text.trim().length < 8))
                ? null
                : _submit,
            child: Text(
              _pending == null ? 'Queue source' : 'Retry original request',
            ),
          ),
      ],
    ),
  );
}
