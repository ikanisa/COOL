part of 'admin_runtime.dart';

Future<void> _showAdminExceptionFollowUp(
  BuildContext context,
  _AdminActionScope scope,
  String exceptionId,
) async {
  if (!scope.isCurrent) return;
  await _showAdminFormDialog<void>(
    context: context,
    builder: (dialogContext) => _AdminSessionDialog(
      scope: scope,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AdminExceptionWorkflowCard(exceptionId: exceptionId),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Close follow-up'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final adminExceptionWorkflowProvider = FutureProvider.autoDispose
    .family<AdminExceptionWorkflow, String>((ref, id) async {
      final scope = ref.watch(adminAuthSessionScopeProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      if (scope == null ||
          identity?.userId != scope.key.userId ||
          !_exceptionCanRead(identity)) {
        throw const AdminExceptionDenied();
      }
      final raw = await repository.exceptionWorkflow(id);
      if (!current) throw const AdminSessionChanged();
      return AdminExceptionWorkflow.parse(raw, id);
    });

class AdminExceptionWorkflowCard extends ConsumerStatefulWidget {
  const AdminExceptionWorkflowCard({required this.exceptionId, super.key});
  final String exceptionId;
  @override
  ConsumerState<AdminExceptionWorkflowCard> createState() =>
      _ExceptionWorkflowCardState();
}

class _ExceptionWorkflowCardState
    extends ConsumerState<AdminExceptionWorkflowCard> {
  Object? _scope;
  String? _owner, _message;
  AdminExceptionWorkflowIntent? _pending;
  bool _busy = false, _storageFailed = false;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refresh() =>
      ref.invalidate(adminExceptionWorkflowProvider(widget.exceptionId));

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(adminAuthSessionScopeProvider);
    final identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider));
    final repository = ref.watch(adminRepositoryProvider);
    final store = ref.watch(adminExceptionCheckpointStoreProvider);
    final scope = (
      session,
      identity?.userId,
      repository,
      store,
      widget.exceptionId,
    );
    if (_scope != scope) {
      _scope = scope;
      _pending = null;
      _message = null;
      _storageFailed = false;
      _owner =
          session != null &&
              identity?.userId == session.key.userId &&
              _exceptionCanRead(identity)
          ? adminExceptionOwnerDigest(
              'workflow:${identity!.userId}:${widget.exceptionId}',
            )
          : null;
      if (_owner != null && store != null) {
        try {
          final saved = store.read(_owner!);
          if (saved != null) {
            _pending = AdminExceptionWorkflowIntent.decode(saved, _owner!);
            if (_pending!.exceptionId != widget.exceptionId) {
              exceptionInvalid();
            }
            _message =
                'A pending follow-up request was recovered. Check its outcome before another action.';
          }
        } catch (_) {
          _storageFailed = true;
        }
      }
    }
    if (_owner == null) {
      return const Text('Current exception access is required.');
    }
    final state = ref.watch(adminExceptionWorkflowProvider(widget.exceptionId));
    final now = ref.watch(adminClockProvider)();
    final workflow = state.isLoading ? null : state.asData?.value;
    final canAct =
        workflow?.isFresh(now) == true &&
        !_busy &&
        _pending == null &&
        !_storageFailed &&
        store != null &&
        _exceptionCanManage(identity);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Exception follow-up',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Escalations are delivered to the assigned operator’s Admin inbox. Delivery and opening are recorded separately.',
        ),
        const SizedBox(height: 12),
        if (state.isLoading)
          const Text('Checking assignment and deadline…')
        else if (state.hasError)
          const Text(
            'Follow-up could not be verified. Refresh and check current access.',
          )
        else if (workflow != null) ...[
          Text(
            'Follow-up: ${switch (workflow.status) {
              'unassigned' => 'Unassigned',
              'assigned' => 'Assigned',
              'source_cleared' => 'Source cleared · resolution available',
              _ => 'Resolved',
            }}',
          ),
          if (workflow.assigneeId != null)
            Text(
              workflow.assigneeId == identity!.userId
                  ? 'Assigned to you'
                  : 'Assigned to another approved operator',
            ),
          if (workflow.dueAt != null)
            Text(
              'Due ${_exceptionTime(workflow.dueAt!)}${workflow.overdue ? ' · overdue' : ''}',
            ),
          if (workflow.assigneeId != null && !workflow.recipientAvailable)
            const Text(
              'Assigned operator access is unavailable. Reassignment is required.',
            ),
          if (!workflow.isFresh(now))
            const Text(
              'Follow-up observation expired. Refresh before taking action.',
            ),
          for (final escalation in workflow.escalations) ...[
            const SizedBox(height: 8),
            Text(
              'Escalation · ${switch (escalation.state) {
                'queued' => 'Queued for Admin delivery',
                'delivered' => 'Delivered to Admin inbox',
                'recipient_unavailable' => 'Recipient access unavailable · waiting for retry',
                _ => 'Source changed · delivery cancelled',
              }}',
            ),
            if (escalation.deliveredAt != null)
              Text('Delivered ${_exceptionTime(escalation.deliveredAt!)}'),
            if (escalation.readAt != null)
              Text('Opened ${_exceptionTime(escalation.readAt!)}'),
          ],
        ],
        if (_storageFailed)
          const Text(
            'Recovery storage is unavailable. Follow-up actions are disabled.',
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(liveRegion: true, child: Text(_message!)),
          ),
        if (_pending != null) ...[
          const SizedBox(height: 8),
          SelectableText('Pending request: ${_pending!.requestId}'),
          OutlinedButton(
            onPressed: _busy ? null : _reconcile,
            child: const Text('Check follow-up request'),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh follow-up'),
            ),
            if (workflow?.sourceActive == true) ...[
              OutlinedButton(
                onPressed: canAct ? () => _act(workflow!, 'assign') : null,
                child: const Text('Assign to me · due in 1 hour'),
              ),
              OutlinedButton(
                onPressed:
                    canAct &&
                        workflow!.assigneeId != null &&
                        workflow.recipientAvailable
                    ? () => _act(workflow, 'escalate')
                    : null,
                child: const Text('Escalate to assigned operator'),
              ),
            ],
            if (workflow?.status == 'source_cleared')
              OutlinedButton(
                onPressed: canAct ? () => _act(workflow!, 'resolve') : null,
                child: const Text('Record source resolution'),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _act(AdminExceptionWorkflow workflow, String action) async {
    if (_busy || _pending != null || _storageFailed || _owner == null) return;
    final scope = _AdminActionScope(ref);
    final owner = _owner!;
    final store = ref.read(adminExceptionCheckpointStoreProvider);
    if (store == null) return;
    var submitted = false;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final actor = await scope.repository.currentIdentity();
      if (!mounted || !scope.isCurrent) return;
      if (actor?.userId != scope.actorId || !_exceptionCanManage(actor)) {
        throw const AdminExceptionDenied();
      }
      final now = ref.read(adminClockProvider)();
      if (!workflow.isFresh(now)) {
        exceptionInvalid();
      }
      final intent = AdminExceptionWorkflowIntent(
        requestId: const Uuid().v4(),
        exceptionId: workflow.exceptionId,
        sourceRevision: workflow.sourceRevision,
        workflowRevision: workflow.revision,
        action: action,
        expiresAt: now.add(const Duration(seconds: 90)),
        assigneeId: action == 'assign' ? actor!.userId : null,
        dueAt: action == 'assign' ? now.add(const Duration(hours: 1)) : null,
      );
      final encoded = intent.encode(owner);
      try {
        store.write(owner, encoded);
        if (store.read(owner) != encoded) {
          throw const FormatException(
            'Recovery storage did not acknowledge the request.',
          );
        }
        AdminExceptionWorkflowIntent.decode(encoded, owner);
      } catch (_) {
        _storageFailed = true;
        rethrow;
      }
      if (!mounted || !scope.isCurrent) return;
      setState(() => _pending = intent);
      submitted = true;
      final raw = await scope.repository.exceptionWorkflowAction(intent);
      if (!mounted || !scope.isCurrent) return;
      AdminExceptionWorkflowReceipt.parse(raw, intent);
      store.clear(owner);
      setState(() {
        _pending = null;
        _message = 'Follow-up action recorded.';
      });
      _refresh();
    } catch (_) {
      if (!mounted || !scope.isCurrent) return;
      setState(
        () => _message = submitted
            ? 'Outcome unconfirmed. Check the original request before another action.'
            : 'Follow-up was not submitted. Check current access, freshness and recovery storage.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reconcile() async {
    if (_busy || _pending == null || _owner == null) return;
    final scope = _AdminActionScope(ref);
    final intent = _pending!, owner = _owner!;
    setState(() => _busy = true);
    try {
      final raw = await scope.repository.exceptionWorkflowRequest(
        intent.requestId,
      );
      if (!mounted || !scope.isCurrent) return;
      final lookup = AdminExceptionWorkflowLookup.parse(raw, intent);
      final now = ref.read(adminClockProvider)();
      if (now.isBefore(lookup.checkedAt) || !now.isBefore(lookup.validUntil)) {
        exceptionInvalid();
      }
      if (lookup.status == 'recorded' ||
          lookup.canClearUnrecorded(intent, now)) {
        final store = ref.read(adminExceptionCheckpointStoreProvider);
        if (store == null) {
          exceptionInvalid();
        }
        store.clear(owner);
        setState(() {
          _pending = null;
          _message = lookup.status == 'recorded'
              ? 'The original follow-up action was recorded.'
              : 'The original request expired without being recorded. Refresh before a new action.';
        });
        _refresh();
      } else {
        setState(
          () => _message =
              'The request is pending or can still arrive. Its checkpoint is retained.',
        );
      }
    } catch (_) {
      if (mounted && scope.isCurrent) {
        setState(
          () => _message =
              'The request outcome could not be verified. Its checkpoint is retained.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

final adminExceptionEscalationInboxProvider =
    FutureProvider.autoDispose<AdminExceptionEscalationSnapshot>((ref) async {
      final scope = ref.watch(adminAuthSessionScopeProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      if (scope == null ||
          identity?.userId != scope.key.userId ||
          !_exceptionCanRead(identity)) {
        throw const AdminExceptionDenied();
      }
      final raw = await repository.exceptionEscalationInbox();
      if (!current) throw const AdminSessionChanged();
      return AdminExceptionEscalationSnapshot.parse(raw);
    });

class AdminExceptionEscalationInbox extends ConsumerStatefulWidget {
  const AdminExceptionEscalationInbox({super.key});
  @override
  ConsumerState<AdminExceptionEscalationInbox> createState() =>
      _EscalationInboxState();
}

class _EscalationInboxState
    extends ConsumerState<AdminExceptionEscalationInbox> {
  bool _expanded = false, _busy = false;
  String? _message;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _expanded) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider));
    final session = ref.watch(adminAuthSessionScopeProvider);
    if (session == null ||
        identity?.userId != session.key.userId ||
        !_exceptionCanRead(identity)) {
      return const SizedBox.shrink();
    }
    final state = _expanded
        ? ref.watch(adminExceptionEscalationInboxProvider)
        : null;
    final snapshot = state?.isLoading == false ? state?.asData?.value : null;
    final fresh = snapshot?.isFresh(ref.watch(adminClockProvider)()) == true;
    return Material(
      type: MaterialType.transparency,
      child: ExpansionTile(
        title: const Text('Your escalation inbox'),
        onExpansionChanged: (value) => setState(() => _expanded = value),
        children: [
          if (_expanded)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state!.isLoading)
                    const Text('Checking escalation deliveries…')
                  else if (state.hasError)
                    const Text(
                      'Escalation deliveries could not be verified. Refresh and check current access.',
                    )
                  else if (!fresh)
                    const Text(
                      'Escalation inbox observation expired. Refresh to continue.',
                    )
                  else if (snapshot!.rows.isEmpty)
                    const Text(
                      'No delivered escalations in the latest 20 records.',
                    )
                  else
                    for (final row in snapshot.rows) ...[
                      Text(
                        row.reasonCode == 'deadline_exceeded'
                            ? 'Follow-up deadline exceeded'
                            : 'Operator escalation',
                      ),
                      Text('Delivered ${_exceptionTime(row.deliveredAt)}'),
                      if (row.readAt != null)
                        Text('Opened ${_exceptionTime(row.readAt!)}'),
                      if (!row.sourceActive ||
                          row.sourceRevision != row.currentSourceRevision)
                        const Text(
                          'The source has changed since this escalation. Review its current follow-up.',
                        ),
                      OutlinedButton(
                        onPressed: _busy ? null : () => _open(row),
                        child: const Text('Open exception follow-up'),
                      ),
                      const SizedBox(height: 12),
                    ],
                  if (_message != null)
                    Semantics(liveRegion: true, child: Text(_message!)),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => ref.invalidate(
                            adminExceptionEscalationInboxProvider,
                          ),
                    child: const Text('Refresh escalation inbox'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _open(AdminExceptionInboxDelivery row) async {
    if (_busy) return;
    final scope = _AdminActionScope(ref);
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final snapshot = ref.read(adminExceptionEscalationInboxProvider);
      if (snapshot.isLoading ||
          snapshot.asData?.value.isFresh(ref.read(adminClockProvider)()) !=
              true) {
        exceptionInvalid();
      }
      final raw = await scope.repository.readExceptionEscalation(row.id);
      if (!mounted || !scope.isCurrent) return;
      final data = exceptionObject(raw, {
        'contract_version',
        'escalation_id',
        'read_at',
        'source_resolved',
      });
      if (data['contract_version'] is! int ||
          data['contract_version'] != 1 ||
          exceptionUuid(data['escalation_id']) != row.id ||
          data['source_resolved'] != false ||
          exceptionInstant(data['read_at']).isBefore(row.deliveredAt)) {
        exceptionInvalid();
      }
      ref.invalidate(adminExceptionEscalationInboxProvider);
      await _showAdminExceptionFollowUp(context, scope, row.exceptionId);
    } catch (_) {
      if (mounted && scope.isCurrent) {
        setState(
          () => _message =
              'Opening could not be recorded. Refresh the inbox to check its durable read acknowledgement.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
