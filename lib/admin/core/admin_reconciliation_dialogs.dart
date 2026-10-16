part of 'admin_runtime.dart';

class _ReconciliationStepUpDialog extends ConsumerStatefulWidget {
  const _ReconciliationStepUpDialog();
  @override
  ConsumerState<_ReconciliationStepUpDialog> createState() =>
      _ReconciliationStepUpDialogState();
}

class _ReconciliationStepUpDialogState
    extends ConsumerState<_ReconciliationStepUpDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_busy) return;
    final code = _code.text;
    final route = ModalRoute.of(context);
    _code.clear();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(adminReconciliationStepUpProvider)(code);
      if (mounted && route?.isCurrent == true) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _reconciliationError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      scrollable: true,
      title: const Text('Verify your authenticator'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter a current code from your existing verified authenticator to continue this reconciliation action.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            enabled: !_busy,
            autofocus: true,
            maxLength: 6,
            keyboardType: TextInputType.number,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Authenticator code'),
            onSubmitted: (_) => _verify(),
          ),
          if (_error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _verify,
          child: const Text('Verify and continue'),
        ),
      ],
    ),
  );
}

class _ReconciliationReasonDialog extends StatefulWidget {
  const _ReconciliationReasonDialog();
  @override
  State<_ReconciliationReasonDialog> createState() =>
      _ReconciliationReasonDialogState();
}

class _ReconciliationReasonDialogState
    extends State<_ReconciliationReasonDialog> {
  final _reason = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Approve independent evidence'),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _reason,
        autofocus: true,
        minLines: 2,
        maxLines: 4,
        maxLength: 500,
        decoration: const InputDecoration(
          labelText: 'Approval reason',
          helperText: 'Recorded in the immutable audit trail.',
        ),
        validator: (value) => (value?.trim().length ?? 0) < 10
            ? 'Use a reason of 10 to 500 characters.'
            : null,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _reason.text.trim());
          }
        },
        child: const Text('Approve evidence'),
      ),
    ],
  );
}

class _ReconciliationLineageDialog extends StatefulWidget {
  const _ReconciliationLineageDialog({required this.details});
  final Map<String, dynamic> details;
  @override
  State<_ReconciliationLineageDialog> createState() =>
      _ReconciliationLineageDialogState();
}

class _ReconciliationLineageDialogState
    extends State<_ReconciliationLineageDialog> {
  final _pages = <String, int>{};
  static const _pageSize = 10;
  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Evidence and audit trail'),
    content: SizedBox(
      width: 640,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final field in const {
            'id': 'Review',
            'payment_id': 'Payment',
            'source_reference': 'Independent source',
            'evidence_sha256': 'Evidence SHA-256',
            'occurred_at': 'Evidence time',
            'proposed_by': 'Proposed by',
            'proposed_at': 'Proposed at',
            'proposal_reason': 'Proposal reason',
            'approved_by': 'Approved by',
            'approved_at': 'Approved at',
            'approval_reason': 'Approval reason',
            'consumed_at': 'Finalized at',
            'payment_status': 'Current payment status',
            'collection_id': 'Group',
            'amount_rwf': 'Amount (RWF)',
            'currency': 'Currency',
            'transaction_id': 'Provider transaction',
            'provider_network': 'Provider network',
            'parsed_event_id': 'Parsed event',
            'raw_sms_id': 'SMS record',
            'payment_intent_id': 'Payment intent',
            'receiver_user_id': 'Receiver',
            'member_record_id': 'Member record',
          }.entries)
            if (widget.details[field.key] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SelectableText(
                  '${field.value}: ${widget.details[field.key]}',
                ),
              ),
          for (final section in const {
            'receiver_routes': 'Receiver routes',
            'journals': 'Ledger journals',
            'audit': 'Audit events',
          }.entries)
            _section(section.key, section.value),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
  Widget _section(String key, String title) {
    final rows = (widget.details[key] as List).cast<Map<Object?, Object?>>();
    final page = _pages[key] ?? 0;
    final start = page * _pageSize;
    final end = math.min(start + _pageSize, rows.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (rows.isEmpty) const Text('No records'),
        for (final row in rows.skip(start).take(_pageSize))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SelectableText(_lineageRow(key, row)),
          ),
        if (rows.isNotEmpty) Text('${start + 1}–$end of ${rows.length} $title'),
        if (rows.length > _pageSize)
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: page == 0
                    ? null
                    : () => setState(() => _pages[key] = page - 1),
                child: Text('Previous $title'),
              ),
              TextButton(
                onPressed: end >= rows.length
                    ? null
                    : () => setState(() => _pages[key] = page + 1),
                child: Text('Next $title'),
              ),
            ],
          ),
        const Divider(),
      ],
    );
  }

  String _lineageRow(String key, Map<Object?, Object?> row) {
    final keys = switch (key) {
      'receiver_routes' => ['id', 'network', 'is_active'],
      'journals' => ['id', 'entry_type', 'amount_rwf'],
      _ => ['id', 'action', 'actor_user_id', 'created_at'],
    };
    final lines = [
      for (final field in keys)
        if (row[field] != null) '${field.replaceAll('_', ' ')}: ${row[field]}',
    ];
    if (key == 'audit' && row['metadata'] is Map) {
      final metadata = row['metadata'] as Map;
      for (final field in [
        'review_id',
        'evidence_sha256',
        'source_reference',
        'occurred_at',
        'reason',
        'payment_fingerprint',
        'request_id',
      ]) {
        if (metadata[field] != null) {
          lines.add('${field.replaceAll('_', ' ')}: ${metadata[field]}');
        }
      }
    }
    return lines.join('\n');
  }
}

class _ReconciliationEvidenceDialog extends StatefulWidget {
  const _ReconciliationEvidenceDialog({required this.paymentId});
  final String paymentId;
  @override
  State<_ReconciliationEvidenceDialog> createState() =>
      _ReconciliationEvidenceDialogState();
}

class _ReconciliationEvidenceDialogState
    extends State<_ReconciliationEvidenceDialog> {
  final _form = GlobalKey<FormState>();
  final _hash = TextEditingController();
  final _reference = TextEditingController();
  final _time = TextEditingController();
  final _reason = TextEditingController();
  @override
  void dispose() {
    for (final controller in [_hash, _reference, _time, _reason]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Propose independent evidence'),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _hash,
            maxLength: 64,
            decoration: const InputDecoration(
              labelText: 'Evidence SHA-256',
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
            validator: (value) =>
                RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(value?.trim() ?? '')
                ? null
                : 'Enter the verified 64-character evidence hash.',
          ),
          TextFormField(
            controller: _reference,
            maxLength: 128,
            decoration: const InputDecoration(
              labelText: 'Source reference',
              helperText: 'Provider or statement',
              helperMaxLines: 2,
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
            validator: (value) => (value?.trim().length ?? 0) >= 3
                ? null
                : 'Enter the independent source reference.',
          ),
          TextFormField(
            controller: _time,
            decoration: const InputDecoration(
              labelText: 'Evidence time in UTC',
              helperText: 'Example: 2026-09-29T10:00:00Z',
              helperMaxLines: 2,
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
            validator: (value) =>
                _reconciliationUtc(value?.trim() ?? '') == null
                ? 'Use a valid UTC timestamp ending in Z.'
                : null,
          ),
          TextFormField(
            controller: _reason,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Review reason',
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
            validator: (value) => (value?.trim().length ?? 0) >= 10
                ? null
                : 'Explain the evidence in at least 10 characters.',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          Navigator.pop(context, <String, dynamic>{
            'p_payment_id': widget.paymentId,
            'p_evidence_sha256': _hash.text.trim().toLowerCase(),
            'p_source_reference': _reference.text.trim(),
            'p_occurred_at': _reconciliationUtc(
              _time.text.trim(),
            )!.toIso8601String(),
            'p_reason': _reason.text.trim(),
          });
        },
        child: const Text('Record evidence'),
      ),
    ],
  );
}

DateTime? _reconciliationUtc(String raw) {
  if (!RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$',
  ).hasMatch(raw)) {
    return null;
  }
  return _reconciliationTimestamp(raw);
}
