part of 'admin_runtime.dart';

String _exceptionTime(DateTime value) =>
    '${adminKigaliDate(value)} · ${adminKigaliTime(value)}:${value.second.toString().padLeft(2, '0')} · Africa/Kigali';
String _exceptionAge(DateTime first, DateTime now) {
  final elapsed = now.toUtc().difference(first);
  if (elapsed.inDays > 0) return '${elapsed.inDays}d since first observation';
  if (elapsed.inHours > 0) return '${elapsed.inHours}h since first observation';
  if (elapsed.inMinutes > 0) {
    return '${elapsed.inMinutes}m since first observation';
  }
  return '${math.max(0, elapsed.inSeconds)}s since first observation';
}

class AdminExceptionsPage extends ConsumerStatefulWidget {
  const AdminExceptionsPage({this.pageSize = 20, super.key});
  final int pageSize;
  @override
  ConsumerState<AdminExceptionsPage> createState() =>
      _AdminExceptionsPageState();
}

class _AdminExceptionsPageState extends ConsumerState<AdminExceptionsPage> {
  late AdminExceptionQuery _query = AdminExceptionQuery(limit: widget.pageSize);
  final _previous = <AdminExceptionQuery>[];
  Timer? _timer;
  Object? _scope;
  String? _ownerDigest, _message, _lookupRequestId;
  AdminExceptionCheckpoint? _checkpoint;
  AdminExceptionReceipt? _receipt;
  bool _busy = false, _saving = false, _storageFailed = false;

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

  void _refresh() {
    setState(() {
      _previous.clear();
      _query = AdminExceptionQuery(
        active: _query.active,
        source: _query.source,
        limit: widget.pageSize,
      );
    });
    ref.invalidate(adminExceptionInboxProvider(_query));
  }

  void _filter({
    bool? active,
    AdminExceptionSource? source,
    bool changeSource = false,
  }) {
    setState(() {
      _previous.clear();
      _query = AdminExceptionQuery(
        active: active ?? _query.active,
        source: changeSource ? source : _query.source,
        limit: widget.pageSize,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(adminAuthSessionScopeProvider);
    final repository = ref.watch(adminRepositoryProvider);
    final identityState = ref.watch(adminIdentityProvider);
    final identity = _adminResolvedIdentity(identityState);
    final store = ref.watch(adminExceptionCheckpointStoreProvider);
    final scope = (session, repository, identity?.userId, store);
    if (_scope != scope) {
      _scope = scope;
      _previous.clear();
      _query = AdminExceptionQuery(limit: widget.pageSize);
      _checkpoint = null;
      _receipt = null;
      _lookupRequestId = null;
      _message = null;
      _storageFailed = false;
      _ownerDigest =
          identity != null &&
              session != null &&
              identity.userId == session.key.userId
          ? adminExceptionOwnerDigest(identity.userId)
          : null;
      if (_ownerDigest != null &&
          _exceptionCanRead(identity) &&
          store != null) {
        try {
          final saved = store.read(_ownerDigest!);
          if (saved != null) {
            _checkpoint = AdminExceptionCheckpoint.parse(saved, _ownerDigest!);
            _message =
                'A reviewed request was recovered from this tab. Check its original request ID before another action.';
          }
        } catch (_) {
          _storageFailed = true;
          _message =
              'The recovery checkpoint could not be read. Review actions are unavailable in this tab.';
        }
      }
    }
    if (identityState.isLoading) {
      return const AdminLoadingState(
        title: 'Checking exception access',
        message: 'Checking current Admin permissions.',
      );
    }
    if (!_exceptionCanRead(identity)) {
      return const AdminDeniedPage(
        requiredPermission:
            'payments.read, notifications.read and system_health.read',
      );
    }
    final read = ref.watch(adminExceptionInboxProvider(_query));
    final now = ref.watch(adminClockProvider)();
    final snapshot = read.isLoading ? null : read.asData?.value;
    final fresh = snapshot?.isFresh(now) == true;
    final canManage =
        fresh &&
        _exceptionCanManage(identity) &&
        _ownerDigest != null &&
        store != null &&
        !_storageFailed &&
        !_busy &&
        _checkpoint == null;
    final lookup = _lookupRequestId == null
        ? null
        : ref.watch(adminExceptionLookupProvider(_lookupRequestId!));
    return AdminPage(
      title: 'Exceptions',
      subtitle:
          'Recorded payment, receipt and SMS Gateway observations. Platform scope.',
      trailing: OutlinedButton.icon(
        onPressed: read.isLoading || _busy ? null : _refresh,
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh inbox'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _ExceptionNotice(
            title: 'Historical scan incomplete',
            message:
                'This inbox contains captured source changes and bounded source observations. An empty view does not establish that all operations are healthy. Refreshing the inbox rereads records; it does not rescan every source.',
          ),
          const SizedBox(height: 18),
          const AdminExceptionEscalationInbox(),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('exception-state-${_query.active}'),
                  initialValue: _query.active ? 'active' : 'cleared',
                  decoration: const InputDecoration(
                    labelText: 'Recorded source state',
                  ),
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'cleared', child: Text('Cleared')),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => _filter(active: value == 'active'),
                ),
              ),
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('exception-category-${_query.source}'),
                  initialValue: _query.source?.wire ?? 'all',
                  decoration: const InputDecoration(
                    labelText: 'Source category',
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All sources'),
                    ),
                    for (final source in AdminExceptionSource.values)
                      DropdownMenuItem(
                        value: source.wire,
                        child: Text(source.label),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => _filter(
                          changeSource: true,
                          source: value == 'all'
                              ? null
                              : AdminExceptionSource.parse(value),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_message != null) ...[
            _ExceptionNotice(
              title: _checkpoint != null
                  ? 'Original request requires review'
                  : 'Review update',
              message: _message!,
            ),
            const SizedBox(height: 16),
          ],
          if (_saving) ...[
            const LinearProgressIndicator(
              semanticsLabel: 'Recording reviewed exception action',
            ),
            const SizedBox(height: 16),
          ],
          if (_checkpoint != null) ...[
            Text(
              'Original request ID',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            SelectableText(_checkpoint!.intent.requestId),
            Text(
              '${_checkpoint!.intent.action.label} · revision ${_checkpoint!.intent.revision}',
            ),
            const Text(
              'Outcome is unconfirmed until a matching immutable receipt is read. No action will be replayed automatically.',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () {
                        setState(
                          () =>
                              _lookupRequestId = _checkpoint!.intent.requestId,
                        );
                        ref.invalidate(
                          adminExceptionLookupProvider(_lookupRequestId!),
                        );
                      },
                icon: const Icon(Icons.manage_search_outlined),
                label: const Text('Check original request'),
              ),
            ),
            if (lookup != null) _lookupView(lookup, now),
            const SizedBox(height: 20),
          ],
          if (_receipt != null) ...[
            _ExceptionReceiptView(receipt: _receipt!),
            const SizedBox(height: 18),
          ],
          if (_exceptionCanManage(identity) &&
              (store == null || _ownerDigest == null || _storageFailed)) ...[
            const _ExceptionNotice(
              title: 'Recovery storage unavailable',
              message:
                  'A current session and a verified same-tab recovery checkpoint are required before recording a review action.',
            ),
            const SizedBox(height: 16),
          ],
          if (read.isLoading)
            const AdminLoadingState(
              title: 'Loading exceptions',
              message: 'Reading retained source observations.',
            )
          else if (read.hasError)
            _ExceptionReadError(error: read.error!, onRefresh: _refresh)
          else if (!fresh)
            const _ExceptionNotice(
              title: 'Exception snapshot expired',
              message:
                  'Refresh the inbox before using its recorded source state or review controls. Read freshness does not renew source observations.',
            )
          else if (snapshot!.rows.isEmpty)
            const _ExceptionNotice(
              title: 'No recorded exceptions in this view',
              message:
                  'No matching rows were returned for these filters. A complete historical scan has not been verified.',
            )
          else ...[
            Text('Checked ${_exceptionTime(snapshot.checkedAt)}'),
            Text(
              '${snapshot.rows.length} rows in this page · source observations retain their own times',
            ),
            const SizedBox(height: 12),
            for (final row in snapshot.rows) ...[
              _ExceptionRowView(
                row: row,
                now: now,
                busy: _busy,
                onReview: canManage && row.active
                    ? (action) => _review(row, action)
                    : null,
              ),
              const SizedBox(height: 12),
            ],
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
                        : () => setState(() => _query = _previous.removeLast()),
                    child: const Text('Previous page'),
                  ),
                if (snapshot!.nextCursor != null)
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _previous.add(_query);
                            _query = AdminExceptionQuery(
                              active: _query.active,
                              source: _query.source,
                              limit: widget.pageSize,
                              beforeChangedAt: snapshot.nextCursor!.changedAt,
                              beforeId: snapshot.nextCursor!.id,
                            );
                          }),
                    child: const Text('Next page'),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _lookupView(AsyncValue<AdminExceptionLookup> read, DateTime now) {
    if (read.isLoading) {
      return const _ExceptionNotice(
        title: 'Checking original request',
        message: 'Reading actor-bound action evidence.',
      );
    }
    if (read.hasError) return _ExceptionReadError(error: read.error!);
    final result = read.asData!.value;
    if (!result.isFresh(now)) {
      return const _ExceptionNotice(
        title: 'Request lookup expired',
        message:
            'Check the original request again. Its outcome remains unconfirmed.',
      );
    }
    if (result.receipt == null) {
      return _ExceptionNotice(
        title: result.status == 'in_progress'
            ? 'Request still in progress'
            : 'No receipt visible for this request',
        message:
            'The outcome remains unconfirmed. Keep the original request ID and check it again; no mutation is replayed.',
      );
    }
    if (!result.receipt!.matches(_checkpoint!.intent)) {
      return const _ExceptionNotice(
        title: 'Request evidence does not match',
        message:
            'The returned receipt does not match the reviewed exception, revision and action. The original checkpoint is retained.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ExceptionReceiptView(receipt: result.receipt!),
        OutlinedButton(
          onPressed: () => _adopt(result.receipt!),
          child: const Text('Use recorded result and refresh'),
        ),
      ],
    );
  }

  void _adopt(AdminExceptionReceipt receipt) {
    if (_checkpoint == null ||
        !receipt.matches(_checkpoint!.intent) ||
        _ownerDigest == null) {
      return;
    }
    final state = ref.read(
      adminExceptionLookupProvider(_checkpoint!.intent.requestId),
    );
    if (state.isLoading ||
        state.hasError ||
        state.asData?.value.isFresh(ref.read(adminClockProvider)()) != true) {
      return;
    }
    try {
      ref.read(adminExceptionCheckpointStoreProvider)!.clear(_ownerDigest!);
    } catch (_) {
      setState(
        () => _message =
            'The recorded result is known, but the recovery checkpoint could not be cleared.',
      );
      return;
    }
    setState(() {
      _receipt = receipt;
      _checkpoint = null;
      _lookupRequestId = null;
      _message =
          'Review action recorded. Refreshing the source observation; acknowledgment does not clear it and escalation delivery is unverified.';
    });
    _refresh();
  }

  Future<void> _review(
    AdminExceptionRow row,
    AdminExceptionAction action,
  ) async {
    if (_busy ||
        _checkpoint != null ||
        !_exceptionCanManage(
          _adminResolvedIdentity(ref.read(adminIdentityProvider)),
        )) {
      return;
    }
    final scope = _AdminActionScope(ref);
    final requestId = const Uuid().v4();
    AdminExceptionIntent? intent;
    var submitted = false;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      intent = await _showAdminFormDialog<AdminExceptionIntent>(
        context: context,
        builder: (dialogContext) => _AdminSessionDialog(
          scope: scope,
          child: _ExceptionReviewDialog(
            row: row,
            action: action,
            requestId: requestId,
            onConfirm: (reason) => Navigator.pop(
              dialogContext,
              AdminExceptionIntent(
                requestId: requestId,
                exceptionId: row.id,
                revision: row.revision,
                action: action,
                reason: reason,
              ),
            ),
          ),
        ),
      );
      if (intent == null || !mounted || !scope.isCurrent) return;
      final actor = await scope.repository.currentIdentity();
      if (!mounted || !scope.isCurrent) return;
      if (actor?.userId != scope.actorId || !_exceptionCanManage(actor)) {
        throw const AdminExceptionDenied();
      }
      final current = ref.read(adminExceptionInboxProvider(_query));
      if (current.isLoading ||
          current.hasError ||
          current.asData?.value.isFresh(ref.read(adminClockProvider)()) !=
              true ||
          current.asData!.value.rows
                  .where(
                    (item) =>
                        item.id == row.id &&
                        item.revision == row.revision &&
                        item.active,
                  )
                  .length !=
              1 ||
          _ownerDigest == null ||
          _storageFailed) {
        throw const FormatException('Current reviewed source required.');
      }
      final store = ref.read(adminExceptionCheckpointStoreProvider);
      if (store == null) {
        throw const FormatException('Recovery store required.');
      }
      final checkpoint = AdminExceptionCheckpoint(_ownerDigest!, intent);
      try {
        store.write(_ownerDigest!, checkpoint.encode());
        final saved = store.read(_ownerDigest!);
        if (saved == null ||
            AdminExceptionCheckpoint.parse(saved, _ownerDigest!).encode() !=
                checkpoint.encode()) {
          throw const FormatException('Recovery checkpoint not acknowledged.');
        }
      } catch (_) {
        _storageFailed = true;
        rethrow;
      }
      if (!mounted || !scope.isCurrent) return;
      setState(() {
        _checkpoint = checkpoint;
        _saving = true;
      });
      submitted = true;
      final receipt = await scope.repository.exceptionAction(intent);
      if (!mounted || !scope.isCurrent) return;
      if (!receipt.matches(intent)) exceptionInvalid();
      store.clear(_ownerDigest!);
      setState(() {
        _checkpoint = null;
        _receipt = receipt;
        _message =
            'Review action recorded. Refreshing the observation; the source is not resolved and escalation delivery is unverified.';
      });
      _refresh();
    } catch (error) {
      if (!mounted || !scope.isCurrent) return;
      final definite =
          !submitted ||
          error is AdminExceptionDenied ||
          error is UnsupportedError ||
          error is CollectApiException &&
              {'42501', '22023', '55000'}.contains(error.code);
      if (definite && _ownerDigest != null && _checkpoint != null) {
        try {
          ref.read(adminExceptionCheckpointStoreProvider)?.clear(_ownerDigest!);
          _checkpoint = null;
        } catch (_) {
          _storageFailed = true;
        }
      }
      setState(
        () => _message = definite
            ? error is CollectApiException && error.code == '55000'
                  ? 'The source changed or cleared before review. Refresh the inbox and review its latest revision.'
                  : !submitted
                  ? 'Review was not submitted. Current authority, source revision and verified recovery storage are required.'
                  : 'Review action refused by the current service authority. Refresh and check current permissions.'
            : 'Review action outcome unconfirmed. The original request checkpoint is retained; check it before another action.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _saving = false;
        });
      }
    }
  }
}

class _ExceptionReviewDialog extends StatefulWidget {
  const _ExceptionReviewDialog({
    required this.row,
    required this.action,
    required this.requestId,
    required this.onConfirm,
  });
  final AdminExceptionRow row;
  final AdminExceptionAction action;
  final String requestId;
  final ValueChanged<AdminExceptionReviewReason> onConfirm;
  @override
  State<_ExceptionReviewDialog> createState() => _ExceptionReviewDialogState();
}

class _ExceptionReviewDialogState extends State<_ExceptionReviewDialog> {
  late AdminExceptionReviewReason _reason =
      widget.action == AdminExceptionAction.acknowledge
      ? AdminExceptionReviewReason.reviewStarted
      : AdminExceptionReviewReason.ownerReviewRequired;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.action.label),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.row.reasonLabel),
          Text('Recorded active observation · revision ${widget.row.revision}'),
          const SizedBox(height: 12),
          const Text(
            'This records human review only. It does not resolve the source, change finances or send a message. Escalation delivery is unverified.',
          ),
          const SizedBox(height: 12),
          Text('Exception ID', style: Theme.of(context).textTheme.labelLarge),
          SelectableText(widget.row.id),
          Text(
            'Original request ID',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          SelectableText(widget.requestId),
          const SizedBox(height: 12),
          DropdownButtonFormField<AdminExceptionReviewReason>(
            initialValue: _reason,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Review reason'),
            items: [
              for (final reason in AdminExceptionReviewReason.values)
                DropdownMenuItem(value: reason, child: Text(reason.label)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _reason = value);
            },
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
        onPressed: () => widget.onConfirm(_reason),
        child: Text(
          widget.action == AdminExceptionAction.acknowledge
              ? 'Record acknowledgment'
              : 'Record escalation request',
        ),
      ),
    ],
  );
}

class _ExceptionRowView extends ConsumerWidget {
  const _ExceptionRowView({
    required this.row,
    required this.now,
    required this.busy,
    required this.onReview,
  });
  final AdminExceptionRow row;
  final DateTime now;
  final bool busy;
  final ValueChanged<AdminExceptionAction>? onReview;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Material(
    type: MaterialType.transparency,
    child: Padding(
      key: ValueKey('exception-record-${row.id}'),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(row.reasonLabel, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AdminStatusChip(
                label: row.active ? 'Recorded active' : 'Recorded cleared',
                tone: row.active
                    ? CollectStatusTone.warning
                    : CollectStatusTone.info,
              ),
              AdminStatusChip(
                label: row.acknowledged
                    ? 'Acknowledged'
                    : 'Review not recorded',
                tone: CollectStatusTone.info,
              ),
              if (row.escalationRequested)
                const AdminStatusChip(
                  label: 'Escalation requested',
                  tone: CollectStatusTone.warning,
                ),
            ],
          ),
          const SizedBox(height: 10),
          _AdminSourceFactsListing(
            label: 'Exception record fields',
            facts: [
              ('Source', Text(row.source.label)),
              ('Revision', Text('${row.revision}')),
              (
                'Observation age',
                Text(_exceptionAge(row.firstObservedAt, now)),
              ),
              ('Last source change', Text(_exceptionTime(row.lastChangedAt))),
            ],
          ),
          if (row.escalationRequested)
            const Text('Escalation delivery has not been verified.'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (row.source.isReceiptDeferral)
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => _showAdminReceiptDeferralEvidence(
                          context,
                          _AdminActionScope(ref),
                          row,
                        ),
                  icon: const Icon(Icons.manage_search_outlined),
                  label: const Text('Review receipt work'),
                ),
              if (row.investigationPath != null)
                OutlinedButton.icon(
                  onPressed: () => context.go(row.investigationPath!),
                  icon: const Icon(Icons.open_in_new_outlined),
                  label: Text(row.investigationLabel),
                )
              else if (!row.source.isReceiptDeferral)
                const Text(
                  'A supported transaction investigation link is unavailable for this source.',
                ),
              AdminEntityAuditLink(
                kind: AdminAuditEntityKind.exception,
                id: row.id,
              ),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => _showAdminExceptionFollowUp(
                        context,
                        _AdminActionScope(ref),
                        row.id,
                      ),
                child: const Text('Manage follow-up'),
              ),
              if (row.active)
                OutlinedButton(
                  onPressed: onReview != null && !row.acknowledged && !busy
                      ? () => onReview!(AdminExceptionAction.acknowledge)
                      : null,
                  child: const Text('Acknowledge'),
                ),
              if (row.active)
                OutlinedButton(
                  onPressed:
                      onReview != null && !row.escalationRequested && !busy
                      ? () => onReview!(AdminExceptionAction.escalate)
                      : null,
                  child: const Text('Request escalation'),
                ),
            ],
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Observation evidence'),
            children: [
              _AdminSourceFactsListing(
                label: 'Observation evidence fields',
                facts: [
                  ('Exception ID', SelectableText(row.id)),
                  ('Source ID', SelectableText(row.sourceId)),
                  ('Reason code', Text(row.reasonCode)),
                  ('First observed', Text(_exceptionTime(row.firstObservedAt))),
                  (
                    'Redacted source predicate fingerprint',
                    SelectableText(row.sourceSha256),
                  ),
                ],
              ),
              const Text(
                'This fingerprint is not a receipt-body or destination hash.',
              ),
            ],
          ),
          const Divider(height: 24),
        ],
      ),
    ),
  );
}

/// Plain field listing for retained source observations and their evidence.
class _AdminSourceFactsListing extends StatelessWidget {
  const _AdminSourceFactsListing({required this.label, required this.facts});
  final String label;
  final List<(String, Widget)> facts;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: label,
    child: Table(
      columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(3)},
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      border: TableBorder(
        horizontalInside: BorderSide(color: context.collectColors.border),
      ),
      children: [
        for (final fact in facts)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 12, 10),
                child: Text(
                  fact.$1,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: fact.$2,
              ),
            ],
          ),
      ],
    ),
  );
}

class _ExceptionReceiptView extends StatelessWidget {
  const _ExceptionReceiptView({required this.receipt});
  final AdminExceptionReceipt receipt;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Immutable review receipt',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      Text('${receipt.action.label} · revision ${receipt.revision}'),
      const Text('Original request ID'),
      SelectableText(receipt.requestId),
      const Text('Exception ID'),
      SelectableText(receipt.exceptionId),
      Text('Recorded ${_exceptionTime(receipt.recordedAt)}'),
      const Text(
        'Source resolution, financial changes, sending and escalation delivery are not attested by this receipt.',
      ),
    ],
  );
}

class _ExceptionNotice extends StatelessWidget {
  const _ExceptionNotice({required this.title, required this.message});
  final String title, message;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        liveRegion: true,
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      const SizedBox(height: 6),
      Text(message),
    ],
  );
}

class _ExceptionReadError extends StatelessWidget {
  const _ExceptionReadError({required this.error, this.onRefresh});
  final Object error;
  final VoidCallback? onRefresh;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _ExceptionNotice(
        title: error is AdminExceptionDenied
            ? 'Exception access denied'
            : error is AdminExceptionAuthorityBusy
            ? 'Current authority busy'
            : error is UnsupportedError
            ? 'Exception service unavailable'
            : error is AdminSessionChanged
            ? 'Admin session changed'
            : 'Exception read failed',
        message: error is AdminExceptionAuthorityBusy
            ? 'No request outcome was disclosed. Keep the original request ID and check it again manually.'
            : 'Current approved access and valid service evidence are required. No outcome or complete scan is inferred.',
      ),
      if (onRefresh != null)
        TextButton(onPressed: onRefresh, child: const Text('Refresh inbox')),
    ],
  );
}
