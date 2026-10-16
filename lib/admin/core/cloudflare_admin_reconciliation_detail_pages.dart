part of 'cloudflare_admin_reconciliation_pages.dart';

class CloudflareReconciliationDetailPage extends ConsumerStatefulWidget {
  const CloudflareReconciliationDetailPage({
    required this.transactionId,
    this.backPath = '/admin/reconciliations',
    super.key,
  });
  final String transactionId, backPath;
  @override
  ConsumerState<CloudflareReconciliationDetailPage> createState() =>
      _DetailState();
}

class _DetailState extends ConsumerState<CloudflareReconciliationDetailPage> {
  final _memberSearch = TextEditingController(),
      _amount = TextEditingController(),
      _reason = TextEditingController(),
      _reviewReason = TextEditingController();
  String _search = '', _message = '';
  int _memberOffset = 0;
  final _relatedOffsets = <String, int>{};
  ReconciliationMember? _member, _reviewMember;
  ReconciliationProposal? _proposal;
  ReconciliationAttempt? _attempt;
  ReconciliationReceipt? _receipt;
  bool _confirmed = false,
      _reviewConfirmed = false,
      _busy = false,
      _unknown = false,
      _retryAllowed = false,
      _needsRefresh = false,
      _checkingMember = false,
      _restoreConfirmed = false;
  _DetailQuery get _detailQuery =>
      (id: widget.transactionId, relation: null, offset: 0);
  _MemberQuery get _memberQuery =>
      (id: widget.transactionId, search: _search, offset: _memberOffset);
  bool get _locked => _busy || _unknown || _needsRefresh;
  @override
  void initState() {
    super.initState();
    _restoreAttempt();
    _unknown = _attempt != null;
    if (_unknown) {
      _message =
          'Outcome unknown. Check the original request before continuing.';
    }
  }

  void _restoreAttempt() {
    try {
      _attempt =
          ref.read(
            cloudflareReconciliationAttemptsProvider,
          )[widget.transactionId] ??
          ref
              .read(cloudflareReconciliationApiProvider)
              .restorePending(widget.transactionId);
    } catch (error) {
      _attempt = null;
      _needsRefresh = true;
      _message = _error(error);
    }
  }

  @override
  void didUpdateWidget(covariant CloudflareReconciliationDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transactionId == widget.transactionId) return;
    for (final controller in [_memberSearch, _amount, _reason, _reviewReason]) {
      controller.clear();
    }
    _search = '';
    _memberOffset = 0;
    _relatedOffsets.clear();
    _member = null;
    _proposal = null;
    _reviewMember = null;
    _receipt = null;
    _confirmed = false;
    _reviewConfirmed = false;
    _checkingMember = false;
    _busy = false;
    _retryAllowed = false;
    _restoreConfirmed = false;
    _needsRefresh = false;
    _restoreAttempt();
    _unknown = _attempt != null;
    _message = _unknown
        ? 'Outcome unknown. Check the original request before continuing.'
        : '';
  }

  @override
  void dispose() {
    for (final controller in [_memberSearch, _amount, _reason, _reviewReason]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(_detailProvider(_detailQuery));
    ref.invalidate(_membersProvider(_memberQuery));
    for (final entry in _relatedOffsets.entries) {
      ref.invalidate(
        _detailProvider((
          id: widget.transactionId,
          relation: entry.key,
          offset: entry.value,
        )),
      );
    }
    if (!_unknown && !_busy) {
      setState(() {
        _member = null;
        _proposal = null;
        _reviewMember = null;
        _confirmed = false;
        _reviewConfirmed = false;
        _needsRefresh = false;
        _relatedOffsets.clear();
      });
    }
  }

  void _prepare(ReconciliationAttempt Function() create) {
    try {
      _send(create());
    } catch (error) {
      setState(() {
        _message = _error(error);
        _needsRefresh = true;
      });
    }
  }

  Future<void> _send(ReconciliationAttempt attempt) async {
    if (_busy) return;
    setState(() {
      _attempt = attempt;
      _busy = true;
      _retryAllowed = false;
      _message = '';
      _receipt = null;
    });
    ref
        .read(cloudflareReconciliationAttemptsProvider.notifier)
        .update((pending) => {...pending, widget.transactionId: attempt});
    try {
      final receipt = await ref
          .read(cloudflareReconciliationApiProvider)
          .submit(attempt);
      if (!mounted || widget.transactionId != attempt.transactionId) return;
      _accepted(receipt);
    } catch (error) {
      if (!mounted || widget.transactionId != attempt.transactionId) return;
      setState(() {
        _busy = false;
        _unknown =
            error is CloudflareAdminRequestException &&
            (error.outcomeUnknown || error.code == 'request_pending');
        _needsRefresh = !_unknown;
        _message = _unknown
            ? 'Outcome unknown. Check the original request before continuing.'
            : _error(error);
        if (!_unknown) _attempt = null;
      });
      if (!_unknown) _forgetAttempt();
    }
  }

  void _accepted(ReconciliationReceipt receipt) {
    _forgetAttempt();
    setState(() {
      _receipt = receipt;
      _attempt = null;
      _busy = false;
      _unknown = false;
      _retryAllowed = false;
      _needsRefresh = false;
      _member = null;
      _proposal = null;
      _reviewMember = null;
      _confirmed = false;
      _reviewConfirmed = false;
      _message = receipt.status == 'pending'
          ? 'Proposal recorded. An independent administrator must review it.'
          : receipt.status == 'approved'
          ? 'Approval and allocation recorded. Settlement is not asserted.'
          : 'Rejection recorded. No allocation was created.';
    });
    ref.invalidate(_detailProvider(_detailQuery));
    ref.invalidate(_membersProvider(_memberQuery));
    refreshCloudflareAdminData(ref);
  }

  void _forgetAttempt() {
    ref
        .read(cloudflareReconciliationAttemptsProvider.notifier)
        .update((pending) => {...pending}..remove(widget.transactionId));
  }

  Future<void> _recover() async {
    final attempt = _attempt;
    if (attempt == null || _busy) return;
    setState(() {
      _busy = true;
      _retryAllowed = false;
      _restoreConfirmed = false;
    });
    try {
      final lookup = await ref
          .read(cloudflareReconciliationApiProvider)
          .lookup(attempt);
      if (!mounted || widget.transactionId != attempt.transactionId) return;
      if (lookup.receipt != null) {
        _accepted(lookup.receipt!);
      } else {
        setState(() {
          _busy = false;
          _retryAllowed = lookup.status == 'not_found';
          _message = lookup.status == 'not_found'
              ? 'The original request was not found. You may retry its unchanged content with the same key.'
              : 'The request is ${lookup.status}. Keep this request locked and check again.';
        });
      }
    } catch (error) {
      if (mounted && widget.transactionId == attempt.transactionId) {
        setState(() {
          _busy = false;
          _message = _error(error);
        });
      }
    }
  }

  Future<void> _reconfirmRecovery() async {
    final attempt = _attempt;
    if (attempt == null || !_restoreConfirmed || !_retryAllowed || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final api = ref.read(cloudflareReconciliationApiProvider);
      final detail = await api.detail(attempt.transactionId);
      ReconciliationMember? member;
      if (attempt.memberPublicId != null) {
        final members = await api.members(
          attempt.transactionId,
          search: attempt.memberPublicId!,
        );
        final matches = members.rows
            .where((row) => row.publicId == attempt.memberPublicId)
            .toList();
        if (matches.length == 1) member = matches.single;
      }
      ReconciliationProposal? proposal;
      if (attempt.proposalId != null) {
        var page = detail.related['proposals']!;
        for (var index = 0; index < 10; index++) {
          final matches = page.rows
              .where((row) => row['id'] == attempt.proposalId)
              .toList();
          if (matches.length == 1) {
            proposal = ReconciliationProposal.parse(matches.single);
            break;
          }
          if (page.nextOffset == null) break;
          page = (await api.detail(
            attempt.transactionId,
            relation: 'proposals',
            offset: page.nextOffset!,
          )).related['proposals']!;
        }
      }
      if (!mounted || widget.transactionId != attempt.transactionId) return;
      api.reconfirmRestored(
        attempt,
        detail.transaction,
        member: member,
        proposal: proposal,
        confirmationReviewed: _restoreConfirmed,
      );
      setState(() => _busy = false);
      await _send(attempt);
    } catch (error) {
      if (mounted && widget.transactionId == attempt.transactionId) {
        setState(() {
          _busy = false;
          _restoreConfirmed = false;
          _message = _error(error);
        });
      }
    }
  }

  Future<void> _selectProposal(ReconciliationProposal proposal) async {
    if (_locked) return;
    setState(() {
      _proposal = proposal;
      _reviewMember = null;
      _reviewConfirmed = false;
      _reviewReason.clear();
      _checkingMember = true;
    });
    try {
      final page = await ref
          .read(cloudflareReconciliationApiProvider)
          .members(
            widget.transactionId,
            search: '${proposal.values['public_id'] ?? ''}',
          );
      if (!mounted || _proposal?.id != proposal.id) return;
      final matches = page.rows
          .where(
            (member) =>
                member.id == proposal.values['member_user_id'] &&
                member.groupId == proposal.values['group_id'],
          )
          .toList();
      setState(() {
        _reviewMember = matches.length == 1 ? matches.single : null;
        _checkingMember = false;
      });
    } catch (error) {
      if (mounted && _proposal?.id == proposal.id) {
        setState(() {
          _checkingMember = false;
          _message = _error(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Reconciliation detail',
    subtitle:
        'Review recorded identities and evidence before proposing or approving an allocation.',
    leading: IconButton(
      tooltip: 'Back to reconciliations',
      onPressed: _busy || _unknown
          ? null
          : () => context.go(reconciliationReturnLocation(widget.backPath)),
      icon: const Icon(Icons.arrow_back),
    ),
    trailing: IconButton(
      tooltip: 'Refresh reconciliation',
      onPressed: _busy ? null : _refresh,
      icon: const Icon(Icons.refresh),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._outcomeWidgets(),
        if (!ref.watch(adminPendingAttemptStoreProvider).storageAvailable)
          _Message(
            ref.read(adminPendingAttemptStoreProvider).storageMessage,
            error: true,
          ),
        ref
            .watch(_detailProvider(_detailQuery))
            .when(
              loading: () =>
                  const AdminLoadingState(message: 'Loading reconciliation'),
              error: (error, _) => _Message(_error(error), error: true),
              data: _contents,
            ),
      ],
    ),
  );
  List<Widget> _outcomeWidgets() => [
    if (_message.isNotEmpty) _Message(_message, error: _receipt == null),
    if (_attempt != null && _unknown) ...[
      AdminDataTable(
        tableLabel: 'Original request',
        rows: [
          _row({
            'id': _attempt!.key,
            'key': _attempt!.key,
            'action': _attempt!.permission,
            'amount_rwf': _attempt!.body['amount_rwf'],
            'reason': _attempt!.body['reason'],
            'member_id': _attempt!.memberPublicId,
            'member_name':
                (_attempt!.body['expected_payment_identity']
                    as Map?)?['display_name'],
            'momo_number':
                (_attempt!.body['expected_payment_identity']
                    as Map?)?['momo_number'],
            'momo_code':
                (_attempt!.body['expected_payment_identity']
                    as Map?)?['momo_pay_code'],
            'outcome': _attempt!.body['outcome'],
            'proposal_id': _attempt!.proposalId,
            'transaction_version':
                _attempt!.body['expected_transaction_version'],
          }),
        ],
        columns: [
          _column('Request key', 'key'),
          _column('Action', 'action'),
          _column('Member ID', 'member_id', numeric: true),
          _column('Recorded name', 'member_name'),
          _column('MoMo number', 'momo_number', numeric: true),
          _column('MoMo code', 'momo_code', numeric: true),
          _column('Amount', 'amount_rwf', numeric: true, amount: true),
          _column('Reason', 'reason'),
          _column('Review outcome', 'outcome'),
          _column('Proposal', 'proposal_id'),
          _column('Transaction version', 'transaction_version', numeric: true),
        ],
      ),
      Wrap(
        spacing: 12,
        children: [
          OutlinedButton(
            onPressed: _busy ? null : _recover,
            child: const Text('Check original request'),
          ),
          if (_retryAllowed && !_attempt!.needsReconfirmation)
            FilledButton(
              onPressed: _busy ? null : () => _send(_attempt!),
              child: const Text('Retry original request'),
            ),
        ],
      ),
      if (_retryAllowed && _attempt!.needsReconfirmation) ...[
        Material(
          color: Colors.transparent,
          child: CheckboxListTile(
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'I reviewed the original confirmation and want to retry this same request',
            ),
            value: _restoreConfirmed,
            onChanged: _busy
                ? null
                : (value) => setState(() => _restoreConfirmed = value!),
          ),
        ),
        FilledButton(
          onPressed: _busy || !_restoreConfirmed ? null : _reconfirmRecovery,
          child: const Text('Reconfirm and retry original request'),
        ),
      ],
    ],
    if (_receipt != null)
      AdminDataTable(
        tableLabel: 'Confirmed operation receipt',
        rows: [_row(_receipt!.values)],
        columns: [
          _column('Request', 'request_id'),
          _column('Proposal', 'resource_id'),
          _column('Outcome', 'proposal_status', status: true),
          _column('Allocation', 'allocation_id'),
          _column('Version', 'version', numeric: true),
        ],
      ),
    if (_needsRefresh)
      OutlinedButton(
        onPressed: _refresh,
        child: const Text('Refresh changed record'),
      ),
  ];
  Widget _contents(ReconciliationDetail detail) {
    final transaction = detail.transaction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminDataTable(
          tableLabel: 'Transaction facts',
          rows: [_row(transaction.values)],
          columns: [
            ..._transactionColumns(
              sourceFacts: transaction.values.containsKey(
                'transaction_reference',
              ),
            ),
            _column('Transaction ID', 'id'),
            _column('Payee status', 'payee_status', status: true),
            _column('Group status', 'group_status', status: true),
            _column('Created', 'created_at', time: true),
          ],
        ),
        if (detail.canPropose &&
            transaction.remaining > 0 &&
            transaction.values['verification_status'] !=
                'rejection_recorded') ...[
          const SizedBox(height: 24),
          Text(
            'Propose a member allocation',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const _Message(
            'Select an existing member. The group comes from the transaction. A proposal does not verify a payment or create an allocation.',
          ),
          TextField(
            controller: _memberSearch,
            enabled: !_locked,
            decoration: const InputDecoration(
              labelText: 'Search member',
              hintText: 'Recorded name, 6-digit ID, MoMo number or code',
            ),
            onSubmitted: (value) {
              setState(() {
                _search = value.trim();
                _memberOffset = 0;
                _member = null;
                _confirmed = false;
              });
            },
          ),
          const SizedBox(height: 12),
          ref
              .watch(_membersProvider(_memberQuery))
              .when(
                loading: () => const AdminLoadingState(
                  message: 'Loading eligible members',
                ),
                error: (error, _) => _Message(_error(error), error: true),
                data: (page) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (page.total == 0)
                      const _Message(
                        'No eligible recorded member matches this search.',
                      )
                    else
                      AdminDataTable(
                        tableLabel: 'Eligible members',
                        rows: page.rows
                            .map((member) => _row(member.values))
                            .toList(),
                        columns: _memberColumns,
                        trailingBuilder: (row) {
                          final member = page.rows.singleWhere(
                            (member) =>
                                member.id == row.id &&
                                member.groupId == row.extra['group_id'],
                          );
                          return TextButton(
                            onPressed:
                                _locked ||
                                    !member.identity.eligible ||
                                    member.groupId != transaction.groupId
                                ? null
                                : () => setState(() {
                                    _member = member;
                                    _confirmed = false;
                                  }),
                            child: Text(
                              _member?.id == member.id
                                  ? 'Selected'
                                  : 'Select member',
                            ),
                          );
                        },
                      ),
                    _Paging(
                      total: page.total,
                      offset: page.offset,
                      count: page.rows.length,
                      next: page.nextOffset,
                      onPage: (offset) {
                        if (!_locked) setState(() => _memberOffset = offset);
                      },
                    ),
                  ],
                ),
              ),
          if (_member != null) ...[
            const SizedBox(height: 12),
            AdminDataTable(
              tableLabel: 'Selected member identity',
              rows: [_row(_member!.values)],
              columns: _memberColumns,
            ),
            Material(
              color: Colors.transparent,
              child: CheckboxListTile(
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'I confirm the recorded member name and MoMo number/code for this group',
                ),
                value: _confirmed,
                onChanged: _locked
                    ? null
                    : (value) => setState(() => _confirmed = value!),
              ),
            ),
            TextField(
              controller: _amount,
              enabled: !_locked,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Amount',
                helperText:
                    'Whole amount up to ${adminFormatWholeAmount(transaction.remaining)}',
              ),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _reason,
              enabled: !_locked,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Proposal reason',
                helperText: '8–1000 characters',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed:
                    !_locked &&
                        _confirmed &&
                        _amountValue != null &&
                        _amountValue! <= transaction.remaining &&
                        _validReason(_reason.text)
                    ? () => _prepare(
                        () => ref
                            .read(cloudflareReconciliationApiProvider)
                            .propose(
                              transaction,
                              _member!,
                              _amountValue!,
                              _reason.text,
                            ),
                      )
                    : null,
                child: const Text('Record proposal'),
              ),
            ),
          ],
        ],
        for (final kind in reconciliationRelations) ...[
          const SizedBox(height: 24),
          Text(_label(kind), style: Theme.of(context).textTheme.titleLarge),
          _related(detail, kind),
        ],
        if (_proposal != null) ..._review(detail),
      ],
    );
  }

  int? get _amountValue {
    final raw = _amount.text.trim();
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(raw)) return null;
    final value = int.tryParse(raw);
    return value != null && value <= 9007199254740991 ? value : null;
  }

  bool _validReason(String value) =>
      value.trim().length >= 8 &&
      value.length <= 1000 &&
      !RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]').hasMatch(value);
  Widget _related(ReconciliationDetail detail, String kind) {
    final offset = _relatedOffsets[kind] ?? 0;
    if (offset > 0) {
      return ref
          .watch(
            _detailProvider((
              id: widget.transactionId,
              relation: kind,
              offset: offset,
            )),
          )
          .when(
            loading: () =>
                const AdminLoadingState(message: 'Loading related records'),
            error: (error, _) => _Message(_error(error), error: true),
            data: (fresh) =>
                _relatedTable(fresh.related[kind]!, kind, detail.canReview),
          );
    }
    return _relatedTable(detail.related[kind]!, kind, detail.canReview);
  }

  Widget _relatedTable(
    ReconciliationPage<Map<String, dynamic>> page,
    String kind,
    bool canReview,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (page.total == 0)
        Text('No ${_label(kind).toLowerCase()} recorded.')
      else
        AdminDataTable(
          tableLabel: _label(kind),
          rows: page.rows.map((values) => _row(values)).toList(),
          columns: _relatedColumns(kind),
          trailingBuilder: kind == 'proposals' && canReview
              ? (row) {
                  final proposal = ReconciliationProposal.parse(row.extra);
                  final independent = proposal.independent(
                    ref
                            .read(cloudflareAdminSessionProvider)
                            .asData
                            ?.value
                            ?.id ??
                        '',
                  );
                  return TextButton(
                    onPressed: !_locked && independent
                        ? () => _selectProposal(proposal)
                        : null,
                    child: Text(independent ? 'Review' : 'Unavailable'),
                  );
                }
              : null,
        ),
      _Paging(
        total: page.total,
        offset: page.offset,
        count: page.rows.length,
        next: page.nextOffset,
        onPage: (offset) {
          if (!_locked) setState(() => _relatedOffsets[kind] = offset);
        },
      ),
    ],
  );
  List<Widget> _review(ReconciliationDetail detail) {
    final proposal = _proposal!,
        canApprove = proposal.currentFor(detail.transaction, _reviewMember);
    return [
      const SizedBox(height: 24),
      Text(
        'Independent proposal review',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      AdminDataTable(
        tableLabel: 'Proposed identity',
        rows: [
          _row({...proposal.values, ...proposal.identity.json}),
        ],
        columns: [
          _column('Member ID', 'public_id', numeric: true),
          _column('Recorded name', 'display_name'),
          _column('MoMo number', 'momo_number', numeric: true),
          _column('MoMo code', 'momo_pay_code', numeric: true),
          _column('Amount', 'amount_rwf', numeric: true, amount: true),
          _column('Proposal reason', 'reason'),
          _column('Proposed by', 'proposed_by_admin_id'),
        ],
      ),
      if (_checkingMember)
        const AdminLoadingState(message: 'Checking current member')
      else if (!canApprove)
        const _Message(
          'Approval unavailable: confirmation or the current member, group, payee or transaction identity differs. Refresh and resolve the changed evidence.',
          error: true,
        ),
      Material(
        color: Colors.transparent,
        child: CheckboxListTile(
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'I independently reviewed this proposal and its recorded payment evidence',
          ),
          value: _reviewConfirmed,
          onChanged: _locked
              ? null
              : (value) => setState(() => _reviewConfirmed = value!),
        ),
      ),
      TextField(
        controller: _reviewReason,
        enabled: !_locked,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: 'Review reason',
          helperText: '8–1000 characters',
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton(
            onPressed:
                !_locked &&
                    _reviewConfirmed &&
                    canApprove &&
                    _validReason(_reviewReason.text)
                ? () => _prepare(
                    () => ref
                        .read(cloudflareReconciliationApiProvider)
                        .review(
                          detail.transaction,
                          proposal,
                          'approved',
                          _reviewReason.text,
                          currentMember: _reviewMember,
                        ),
                  )
                : null,
            child: const Text('Approve allocation'),
          ),
          OutlinedButton(
            onPressed:
                !_locked &&
                    _reviewConfirmed &&
                    _validReason(_reviewReason.text) &&
                    proposal.independent(detail.actorId)
                ? () => _prepare(
                    () => ref
                        .read(cloudflareReconciliationApiProvider)
                        .review(
                          detail.transaction,
                          proposal,
                          'rejected',
                          _reviewReason.text,
                        ),
                  )
                : null,
            child: const Text('Reject proposal'),
          ),
        ],
      ),
    ];
  }
}

List<AdminTableColumn> _relatedColumns(String kind) => switch (kind) {
  'evidence' => [
    _column('Kind', 'kind', status: true),
    _column('Reference', 'reference'),
    _column('SHA-256', 'sha256'),
    _column('Recorded by', 'recorded_by_admin_id'),
    _column('Recorded', 'created_at', time: true),
  ],
  'verification_reviews' => [
    _column('Outcome', 'outcome', status: true),
    _column('Reason', 'reason'),
    _column('Evidence', 'evidence_id'),
    _column('Reviewer', 'reviewed_by_admin_id'),
    _column('Transaction version', 'transaction_version', numeric: true),
    _column('Reviewed', 'reviewed_at', time: true),
  ],
  'allocations' => [
    _column('Member ID', 'public_id', numeric: true),
    _column('Member name', 'display_name'),
    _column('Amount', 'amount_rwf', numeric: true, amount: true),
    _column('Created by', 'created_by_admin_id'),
    _column('Created', 'created_at', time: true),
    _column('Allocation', 'id'),
  ],
  'proposals' => [
    _column('Member ID', 'public_id', numeric: true),
    _column('Current name', 'current_display_name'),
    _column('Amount', 'amount_rwf', numeric: true, amount: true),
    _column('Status', 'status', status: true),
    _column('Reason', 'reason'),
    _column('Proposed by', 'proposed_by_admin_id'),
    _column('Created', 'created_at', time: true),
    _column('Reviewer', 'reviewed_by_admin_id'),
    _column('Review reason', 'review_reason'),
    _column('Reviewed', 'reviewed_at', time: true),
  ],
  'journals' => [
    _column('Description', 'description'),
    _column('Status', 'status', status: true),
    _column('Version', 'version', numeric: true),
    _column('Created by', 'created_by_admin_id'),
    _column('Posted by', 'posted_by_admin_id'),
    _column('Allocation', 'allocation_id'),
    _column('Created', 'created_at', time: true),
  ],
  _ => throw const FormatException('Unsupported related table.'),
};
