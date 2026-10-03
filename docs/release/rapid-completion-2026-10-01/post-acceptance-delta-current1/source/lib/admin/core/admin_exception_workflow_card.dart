part of 'admin_runtime.dart';

Future<void> _showAdminExceptionFollowUp(
  BuildContext context,
  _AdminActionScope scope,
  String exceptionId,
) async {
  if (!scope.isCurrent) return;
  final router = GoRouter.maybeOf(context);
  final openHistory = await _showAdminFormDialog<bool>(
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
                  AdminExceptionWorkflowCard(
                    exceptionId: exceptionId,
                    showHistory: router != null,
                    onOpenHistory: () {
                      if (!scope.isCurrent ||
                          ModalRoute.of(dialogContext)?.isCurrent != true) {
                        return;
                      }
                      Navigator.pop(dialogContext, true);
                    },
                  ),
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
  if (openHistory == true &&
      router != null &&
      context.mounted &&
      scope.isCurrent &&
      adminEntityAuditCanRead(
        _adminResolvedIdentity(scope.ref.read(adminIdentityProvider)),
        AdminAuditEntityKind.exception,
      )) {
    router.push(
      adminEntityAuditPath(AdminAuditEntityKind.exception, exceptionId),
    );
  }
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
  const AdminExceptionWorkflowCard({
    required this.exceptionId,
    this.showHistory = true,
    this.onOpenHistory,
    super.key,
  });
  final String exceptionId;
  final bool showHistory;
  final VoidCallback? onOpenHistory;
  @override
  ConsumerState<AdminExceptionWorkflowCard> createState() =>
      _ExceptionWorkflowCardState();
}

class _ExceptionWorkflowCardState
    extends ConsumerState<AdminExceptionWorkflowCard> {
  Object? _scope;
  String? _owner, _message;
  AdminExceptionWorkflowIntent? _pending;
  AdminExceptionFollowupBookmark? _followup;
  AdminExceptionFollowupQuarantine? _quarantine;
  _AdminExceptionAssignmentSelection? _assignmentDraft;
  AdminExceptionWorkflowRecovery? _recovery;
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
      ref.watch(_adminIdentityRevisionProvider),
      repository,
      store,
      widget.exceptionId,
    );
    if (_scope != scope) {
      _scope = scope;
      _pending = null;
      _followup = null;
      _quarantine = null;
      _assignmentDraft = null;
      _recovery = null;
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
            Object? decoded;
            try {
              decoded = jsonDecode(saved);
            } catch (_) {
              // Unknown bytes remain blocked after privacy sanitization.
            }
            final request = decoded is Map ? decoded['request'] : null;
            final legacyRecovery =
                decoded is Map &&
                !decoded.containsKey('request_fingerprint') &&
                !decoded.containsKey('original_reference') &&
                !decoded.containsKey('original_request_id') &&
                ((decoded['version'] == 3 &&
                        decoded.containsKey('blocked_reference') &&
                        !decoded.containsKey('request')) ||
                    ({1, 2}.contains(decoded['version']) &&
                        request is Map &&
                        !request.containsKey('request_fingerprint') &&
                        request.containsKey('p_assignee_id') &&
                        request.containsKey('p_due_at') &&
                        request.containsKey('p_reason_code')));
            try {
              if (decoded is Map && decoded['version'] == 4) {
                _quarantine = AdminExceptionFollowupQuarantine.parse(
                  saved,
                  _owner!,
                  identity!.userId,
                  widget.exceptionId,
                );
                _storageFailed = true;
              } else if (decoded is Map &&
                  decoded['version'] == 3 &&
                  !decoded.containsKey('blocked_reference')) {
                _followup = AdminExceptionFollowupBookmark.decode(
                  saved,
                  _owner!,
                  identity!.userId,
                  widget.exceptionId,
                );
              } else if (legacyRecovery) {
                if (decoded.containsKey('blocked_reference')) {
                  _recovery = AdminExceptionWorkflowRecovery.parse(
                    saved,
                    _owner!,
                    identity!.userId,
                    widget.exceptionId,
                  );
                  _storageFailed = true;
                } else {
                  _pending = AdminExceptionWorkflowIntent.decode(
                    saved,
                    _owner!,
                    identity!.userId,
                  );
                  if (_pending!.exceptionId != widget.exceptionId) {
                    exceptionInvalid();
                  }
                }
              } else {
                exceptionInvalid();
              }
              _message = _quarantine != null || _recovery != null
                  ? 'Original request outcome is unverified. Follow-up actions remain disabled.'
                  : 'A pending follow-up request was recovered. Check its outcome before another action.';
            } catch (_) {
              _pending = null;
              _followup = null;
              _storageFailed = true;
              final sanitized = legacyRecovery
                  ? (_recovery = AdminExceptionWorkflowRecovery.scrub(
                      saved,
                      _owner!,
                      identity!.userId,
                      widget.exceptionId,
                    )).encode()
                  : (_quarantine = AdminExceptionFollowupQuarantine.scrub(
                      saved,
                      _owner!,
                      identity!.userId,
                      widget.exceptionId,
                    )).encode();
              try {
                store.write(_owner!, sanitized);
                if (store.read(_owner!) != sanitized) exceptionInvalid();
              } catch (_) {
                // Remove rejected private bytes, then retain a sanitized block.
                // Failed persistence never permits an action in this tab.
                store.clear(_owner!);
                if (store.read(_owner!) != null) exceptionInvalid();
                store.write(_owner!, sanitized);
                if (store.read(_owner!) != sanitized) exceptionInvalid();
              }
              _message =
                  'Untrusted recovery data was removed. Follow-up actions remain disabled until the original recorded outcome is verified.';
            }
          }
        } catch (_) {
          _storageFailed = true;
          _recovery = null;
          _quarantine = null;
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
        _followup == null &&
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
        if (_storageFailed && _recovery == null && _quarantine == null)
          const Text(
            'Recovery storage is unavailable. Follow-up actions are disabled.',
          ),
        if (_recovery != null)
          const Text(
            'Original request outcome is unverified. Follow-up actions are disabled.',
          ),
        if (_recovery?.requestId != null) ...[
          const SizedBox(height: 8),
          SelectableText('Original request: ${_recovery!.requestId}'),
          OutlinedButton(
            onPressed: _busy ? null : _reconcileRecovery,
            child: const Text('Check original follow-up request'),
          ),
        ],
        if (_quarantine != null) ...[
          const Text(
            'Original assignment proof is unverified. Follow-up actions are disabled.',
          ),
          if (_quarantine!.requestId != null)
            SelectableText(
              'Original assignment request: ${_quarantine!.requestId}',
            ),
          if (_quarantine!.reference != null)
            OutlinedButton(
              onPressed: !_busy && _exceptionFollowupCanRead(identity)
                  ? _reconcileQuarantinedAssignment
                  : null,
              child: const Text('Check original assignment proof'),
            )
          else
            const Text(
              'The original assignment fingerprint is unavailable. Keep this request for authorized investigation.',
            ),
        ],
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(liveRegion: true, child: Text(_message!)),
          ),
        if (_assignmentDraft != null && _followup == null)
          Text(
            'Selected ${_assignmentDraft!.displayLabel}, due ${_exceptionTime(_assignmentDraft!.dueAt)}. Review before submitting.',
          ),
        if (_pending != null) ...[
          const SizedBox(height: 8),
          SelectableText('Pending request: ${_pending!.requestId}'),
          OutlinedButton(
            onPressed: _busy ? null : _reconcile,
            child: const Text('Check follow-up request'),
          ),
        ],
        if (_followup != null) ...[
          const SizedBox(height: 8),
          SelectableText(
            'Pending assignment request: ${_followup!.reference.requestId}',
          ),
          const Text(
            'Check the original request before making another follow-up change.',
          ),
          OutlinedButton(
            onPressed: !_busy && _exceptionFollowupCanRead(identity)
                ? _reconcileAssignment
                : null,
            child: const Text('Check assignment request'),
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
              FilledButton(
                onPressed: canAct && _exceptionFollowupCanManage(identity)
                    ? () => _assignOperator(workflow!)
                    : null,
                child: const Text('Choose operator and deadline'),
              ),
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
        if (widget.showHistory) ...[
          const SizedBox(height: 12),
          AdminEntityAuditLink(
            kind: AdminAuditEntityKind.exception,
            id: widget.exceptionId,
            onOpenHistory: widget.onOpenHistory,
          ),
        ],
      ],
    );
  }

  Future<void> _act(AdminExceptionWorkflow workflow, String action) async {
    if (_busy ||
        _pending != null ||
        _followup != null ||
        _storageFailed ||
        _owner == null) {
      return;
    }
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
      final encoded = intent.encode(owner, actor!.userId);
      try {
        if (store.read(owner) != null) {
          throw const FormatException('An original follow-up is retained.');
        }
        store.write(owner, encoded);
        if (store.read(owner) != encoded) {
          throw const FormatException(
            'Recovery storage did not acknowledge the request.',
          );
        }
        AdminExceptionWorkflowIntent.decode(encoded, owner, actor.userId);
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

  Future<void> _assignOperator(AdminExceptionWorkflow workflow) async {
    if (_busy ||
        _pending != null ||
        _followup != null ||
        _storageFailed ||
        _owner == null) {
      return;
    }
    if (!_exceptionFollowupCanManage(
      _adminResolvedIdentity(ref.read(adminIdentityProvider)),
    )) {
      return;
    }
    final scope = _AdminActionScope(ref);
    final owner = _owner!;
    final store = ref.read(adminExceptionCheckpointStoreProvider);
    if (store == null || scope.session == null) return;
    var submitted = false;
    var conflict = false;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final selection = await _showExceptionAssignmentDialog(
        context,
        scope,
        initial: _assignmentDraft,
      );
      if (!mounted || !scope.isCurrent || selection == null) return;
      setState(() => _assignmentDraft = selection);
      final actor = await scope.repository.currentIdentity().timeout(
        const Duration(seconds: 15),
      );
      if (!mounted || !scope.isCurrent) return;
      if (actor?.userId != scope.actorId ||
          !_exceptionFollowupCanManage(actor)) {
        throw const AdminExceptionDenied();
      }
      final currentRaw = await scope.repository
          .exceptionWorkflow(workflow.exceptionId)
          .timeout(const Duration(seconds: 15));
      if (!mounted || !scope.isCurrent) return;
      final current = AdminExceptionWorkflow.parse(
        currentRaw,
        workflow.exceptionId,
      );
      final now = ref.read(adminClockProvider)();
      if (!current.sourceActive ||
          current.sourceRevision != workflow.sourceRevision ||
          current.revision != workflow.revision) {
        conflict = true;
        _refresh();
        exceptionInvalid();
      }
      if (!current.isFresh(now) ||
          !selection.isFresh(now) ||
          !selection.dueAt.isAfter(now) ||
          selection.dueAt.isAfter(now.add(const Duration(days: 30)))) {
        exceptionInvalid();
      }
      final intent = AdminExceptionWorkflowIntent(
        requestId: const Uuid().v4(),
        exceptionId: workflow.exceptionId,
        sourceRevision: workflow.sourceRevision,
        workflowRevision: workflow.revision,
        action: 'assign',
        assigneeId: selection.operatorId,
        dueAt: selection.dueAt,
        expiresAt: now.add(const Duration(seconds: 90)),
      );
      final original = AdminExceptionFollowupBookmark.fromIntent(
        intent,
        owner,
        actor!.userId,
      );
      final encoded = original.encode();
      try {
        if (store.read(owner) != null) {
          throw const FormatException('An original follow-up is retained.');
        }
        store.write(owner, encoded);
        if (store.read(owner) != encoded) exceptionInvalid();
        AdminExceptionFollowupBookmark.decode(
          encoded,
          owner,
          actor.userId,
          widget.exceptionId,
        );
      } catch (_) {
        _storageFailed = true;
        rethrow;
      }
      if (!mounted || !scope.isCurrent) return;
      setState(() => _followup = original);
      submitted = true;
      final raw = await scope.repository
          .exceptionFollowupAction(intent)
          .timeout(const Duration(seconds: 15));
      if (!mounted || !scope.isCurrent) return;
      original.receipt(raw);
      if (store.read(owner) != encoded) exceptionInvalid();
      store.clear(owner);
      if (store.read(owner) != null) exceptionInvalid();
      setState(() {
        _followup = null;
        _assignmentDraft = null;
        _message =
            'Assignment recorded for ${selection.displayLabel}, due ${_exceptionTime(selection.dueAt)}.';
      });
      _refresh();
    } catch (_) {
      if (!mounted || !scope.isCurrent) return;
      setState(
        () => _message = submitted
            ? 'Assignment outcome unconfirmed. Check the original request before another action.'
            : conflict
            ? 'Follow-up changed during review. Your operator and deadline are kept for review. Check the refreshed follow-up before submitting.'
            : 'Assignment was not submitted. Your selection is kept for review. Check current access, freshness and recovery storage.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reconcileAssignment() async {
    if (_busy || _followup == null || _owner == null) return;
    if (!_exceptionFollowupCanRead(
      _adminResolvedIdentity(ref.read(adminIdentityProvider)),
    )) {
      return;
    }
    final scope = _AdminActionScope(ref);
    final original = _followup!, owner = _owner!;
    setState(() => _busy = true);
    try {
      final raw = await scope.repository
          .exceptionFollowupRequest(original.reference)
          .timeout(const Duration(seconds: 15));
      if (!mounted || !scope.isCurrent) return;
      final lookup = original.lookup(raw);
      final now = ref.read(adminClockProvider)();
      if (!lookup.isFresh(now)) exceptionInvalid();
      if (lookup.status == 'recorded' || lookup.provesExpiredAbsence(now)) {
        final store = ref.read(adminExceptionCheckpointStoreProvider);
        if (store == null || store.read(owner) != original.encode()) {
          exceptionInvalid();
        }
        store.clear(owner);
        if (store.read(owner) != null) exceptionInvalid();
        setState(() {
          _followup = null;
          _message = lookup.status == 'recorded'
              ? 'The original assignment request was recorded.'
              : 'The original assignment expired without being recorded. Refresh before a new action.';
        });
        _refresh();
      } else {
        setState(
          () => _message =
              'The original request may still arrive. Its reference is retained.',
        );
      }
    } catch (_) {
      if (mounted && scope.isCurrent) {
        setState(
          () => _message =
              'The original assignment outcome could not be verified. Its reference is retained.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reconcileQuarantinedAssignment() async {
    if (_busy || _quarantine?.reference == null || _owner == null) return;
    if (!_exceptionFollowupCanRead(
      _adminResolvedIdentity(ref.read(adminIdentityProvider)),
    )) {
      return;
    }
    final scope = _AdminActionScope(ref);
    final original = _quarantine!, owner = _owner!;
    setState(() => _busy = true);
    try {
      final raw = await scope.repository
          .exceptionFollowupRequest(original.reference!)
          .timeout(const Duration(seconds: 15));
      if (!mounted || !scope.isCurrent) return;
      final lookup = AdminExceptionFollowupLookup.parse(
        raw,
        original.reference!,
      );
      if (!lookup.isFresh(ref.read(adminClockProvider)())) exceptionInvalid();
      if (lookup.status != 'recorded') {
        setState(
          () => _message =
              'The original recorded assignment proof is unavailable. Its reference is retained and further actions remain disabled.',
        );
        return;
      }
      final store = ref.read(adminExceptionCheckpointStoreProvider);
      if (store == null || store.read(owner) != original.encode()) {
        exceptionInvalid();
      }
      store.clear(owner);
      if (store.read(owner) != null) exceptionInvalid();
      setState(() {
        _quarantine = null;
        _storageFailed = false;
        _message = 'The original assignment was verified as recorded.';
      });
      _refresh();
    } catch (_) {
      if (mounted && scope.isCurrent) {
        setState(
          () => _message =
              'The original recorded assignment proof could not be verified. Further actions remain disabled.',
        );
      }
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

  Future<void> _reconcileRecovery() async {
    if (_busy || _recovery?.requestId == null || _owner == null) return;
    final scope = _AdminActionScope(ref);
    final recovery = _recovery!, owner = _owner!;
    setState(() => _busy = true);
    try {
      final raw = await scope.repository.exceptionWorkflowRequest(
        recovery.requestId!,
      );
      if (!mounted || !scope.isCurrent) return;
      final lookup = recovery.lookup(raw);
      final now = ref.read(adminClockProvider)();
      if (now.isBefore(lookup.checkedAt) || !now.isBefore(lookup.validUntil)) {
        exceptionInvalid();
      }
      if (lookup.status != 'recorded') {
        setState(
          () => _message =
              'The original recorded outcome is unavailable. Its reference is retained and further actions remain disabled.',
        );
        return;
      }
      final store = ref.read(adminExceptionCheckpointStoreProvider);
      if (store == null || store.read(owner) != recovery.encode()) {
        exceptionInvalid();
      }
      store.clear(owner);
      if (store.read(owner) != null) exceptionInvalid();
      setState(() {
        _recovery = null;
        _storageFailed = false;
        _message = 'The original follow-up action was verified as recorded.';
      });
      _refresh();
    } catch (_) {
      if (mounted && scope.isCurrent) {
        setState(
          () => _message =
              'The original recorded outcome could not be verified. Further actions remain disabled.',
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
  Object? _scope;
  AdminExceptionEscalationInboxQuery _query =
      const AdminExceptionEscalationInboxQuery();
  final _previous = <AdminExceptionEscalationInboxQuery>[];
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

  void _refreshInbox() {
    setState(() {
      _previous.clear();
      _query = const AdminExceptionEscalationInboxQuery();
      _message = null;
    });
    ref.invalidate(adminExceptionEscalationInboxPageProvider(_query));
  }

  @override
  Widget build(BuildContext context) {
    final identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider));
    final session = ref.watch(adminAuthSessionScopeProvider);
    final scope = (
      session,
      identity?.userId,
      ref.watch(_adminIdentityRevisionProvider),
      ref.watch(adminRepositoryProvider),
    );
    if (_scope != scope) {
      _scope = scope;
      _previous.clear();
      _query = const AdminExceptionEscalationInboxQuery();
      _message = null;
    }
    if (session == null ||
        identity?.userId != session.key.userId ||
        !_exceptionFollowupCanRead(identity)) {
      return const SizedBox.shrink();
    }
    final state = _expanded
        ? ref.watch(adminExceptionEscalationInboxPageProvider(_query))
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
                      'No delivered escalations in this history window.',
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
                        key: ValueKey('exception-followup-${row.id}'),
                        onPressed: _busy ? null : () => _open(row),
                        child: const Text('Open exception follow-up'),
                      ),
                      AdminEntityAuditLink(
                        kind: AdminAuditEntityKind.exception,
                        id: row.exceptionId,
                      ),
                      const SizedBox(height: 12),
                    ],
                  if (fresh)
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        if (_previous.isNotEmpty)
                          OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => setState(
                                    () => _query = _previous.removeLast(),
                                  ),
                            child: const Text('Newer escalations'),
                          ),
                        if (snapshot!.nextCursor case final cursor?)
                          OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    _previous.add(_query);
                                    _query = AdminExceptionEscalationInboxQuery(
                                      limit: _query.limit,
                                      before: cursor,
                                    );
                                  }),
                            child: const Text('Older escalations'),
                          ),
                      ],
                    ),
                  if (_message != null)
                    Semantics(liveRegion: true, child: Text(_message!)),
                  OutlinedButton(
                    onPressed: _busy ? null : _refreshInbox,
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
    final query = _query;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final state = ref.read(adminExceptionEscalationInboxPageProvider(query));
      final snapshot = state.isLoading ? null : state.asData?.value;
      if (snapshot?.isFresh(ref.read(adminClockProvider)()) != true ||
          snapshot!.rows.every((item) => item.id != row.id)) {
        exceptionInvalid();
      }
      final raw = await scope.repository
          .readExceptionEscalationCurrent(row.id)
          .timeout(const Duration(seconds: 15));
      if (!mounted || !scope.isCurrent || query != _query) return;
      AdminExceptionEscalationReadReceipt.parse(
        raw,
        escalationId: row.id,
        deliveredAt: row.deliveredAt,
      );
      ref.invalidate(adminExceptionEscalationInboxPageProvider(query));
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
