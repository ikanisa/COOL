part of 'admin_runtime.dart';

String _cancelTime(DateTime value) =>
    '${adminKigaliDate(value)} · ${adminKigaliTime(value)}:${value.second.toString().padLeft(2, '0')} · Africa/Kigali';

class AdminReceiptCancelCard extends ConsumerStatefulWidget {
  const AdminReceiptCancelCard({
    required this.outboxId,
    this.onRecorded,
    super.key,
  });
  final String outboxId;
  final VoidCallback? onRecorded;
  @override
  ConsumerState<AdminReceiptCancelCard> createState() =>
      _ReceiptCancelCardState();
}

class _ReceiptCancelCardState extends ConsumerState<AdminReceiptCancelCard> {
  Timer? _timer;
  Object? _scope;
  String? _ownerDigest, _message, _lookupId;
  bool _busy = false, _saving = false, _storageFailed = false;
  AdminReceiptCancelCheckpoint? _checkpoint;
  AdminReceiptCancelReceipt? _receipt;
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
    ref.invalidate(adminReceiptCancelInspectionProvider(widget.outboxId));
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(adminAuthSessionScopeProvider),
        repository = ref.watch(adminRepositoryProvider);
    final identityState = ref.watch(adminIdentityProvider),
        identity = _adminResolvedIdentity(identityState);
    final store = ref.watch(adminReceiptCancelCheckpointStoreProvider);
    final scope = (
      session,
      repository,
      identity?.userId,
      store,
      widget.outboxId,
    );
    if (_scope != scope) {
      _scope = scope;
      _checkpoint = null;
      _receipt = null;
      _lookupId = null;
      _message = null;
      _storageFailed = false;
      _busy = false;
      _saving = false;
      _ownerDigest =
          identity != null &&
              session != null &&
              session.key.userId == identity.userId
          ? adminReceiptCancelOwnerDigest(identity.userId)
          : null;
      if (_ownerDigest != null &&
          store != null &&
          _receiptCancelCanRead(identity)) {
        try {
          final saved = store.read(_ownerDigest!);
          if (saved != null) {
            _checkpoint = AdminReceiptCancelCheckpoint.parse(
              saved,
              _ownerDigest!,
            );
            _message =
                'An original cancellation request was recovered from this tab. Check that request before another cancellation.';
          }
        } catch (_) {
          _storageFailed = true;
          _message =
              'Recovery storage could not be read. Cancellation is unavailable in this tab.';
        }
      }
    }
    if (identityState.isLoading) {
      return const _CancelNotice(
        'Checking cancellation access',
        'Checking current operator role and permissions.',
      );
    }
    if (!_receiptCancelCanRead(identity)) {
      return const _CancelNotice(
        'Cancellation access required',
        'Current platform-owner access, payments.read, notifications.read and system_health.read are required. The server also verifies current email approval and session.',
      );
    }
    final read = ref.watch(
      adminReceiptCancelInspectionProvider(widget.outboxId),
    );
    final now = ref.watch(adminClockProvider)();
    final inspection = read.isLoading ? null : read.asData?.value;
    final fresh = inspection?.isFresh(now) == true;
    final canCancel =
        fresh &&
        inspection!.canCancel &&
        _receiptCancelCanManage(identity) &&
        _ownerDigest != null &&
        store != null &&
        !_storageFailed &&
        !_busy &&
        _checkpoint == null;
    final lookup = _lookupId == null
        ? null
        : ref.watch(adminReceiptCancelLookupProvider(_lookupId!));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Cancel an unstarted receipt',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Only a queued receipt with no recorded claim or transport history can qualify. This stops the primary receipt; it does not reverse a payment, send a message or verify carrier delivery.',
            ),
            const SizedBox(height: 12),
            read.when(
              skipLoadingOnRefresh: false,
              loading: () => const _CancelNotice(
                'Inspecting receipt',
                'Reading current server eligibility and revision.',
              ),
              error: (error, _) => _cancelError(error),
              data: (data) => !fresh
                  ? const _CancelNotice(
                      'Cancellation inspection expired',
                      'Refresh eligibility. Older source state and revision are hidden.',
                    )
                  : !data.available
                  ? const _CancelNotice(
                      'Cancellation unavailable',
                      'The source is missing or does not establish supported Rwanda receipt scope. No state or revision is inferred.',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AdminStatusChip(
                          label: data.canCancel
                              ? 'Eligible for cancellation'
                              : 'Cancellation blocked',
                          tone: data.canCancel
                              ? CollectStatusTone.info
                              : CollectStatusTone.warning,
                        ),
                        const SizedBox(height: 8),
                        Text(data.eligibility!.label),
                        Text(
                          'Recorded state: ${data.state} · revision ${data.revision}',
                        ),
                        Text('Reason code: ${data.eligibility!.wire}'),
                        Text('Checked ${_cancelTime(data.checkedAt)}'),
                        Text(
                          'Inspection expires ${_cancelTime(data.validUntil)}',
                        ),
                        const Text(
                          'Rwanda receipt scope · Inspection freshness does not attest carrier behavior outside the recorded workflow.',
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: read.isLoading || _busy ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh eligibility'),
                ),
                if (_receiptCancelCanManage(identity))
                  FilledButton(
                    onPressed: canCancel ? () => _review(inspection) : null,
                    child: const Text('Review cancellation'),
                  ),
              ],
            ),
            if (!_receiptCancelCanManage(identity))
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'notifications.manage is also required to submit cancellation.',
                ),
              ),
            if (_receiptCancelCanManage(identity) &&
                (_ownerDigest == null || store == null || _storageFailed))
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'A current session and verified same-tab recovery storage are required before submission.',
                ),
              ),
            if (_saving) ...[
              const SizedBox(height: 12),
              Semantics(
                label: 'Recording receipt cancellation',
                child: const LinearProgressIndicator(),
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              Semantics(liveRegion: true, child: Text(_message!)),
            ],
            if (_receipt != null) ...[
              const SizedBox(height: 12),
              _CancelReceiptView(receipt: _receipt!),
            ],
            if (_checkpoint != null) ...[
              const SizedBox(height: 16),
              Semantics(
                header: true,
                child: Text(
                  'Original cancellation request',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const Text(
                'The original outcome remains protected. A not-recorded result at any age cannot prove that a delayed request will never execute. No replacement request or replay is available.',
              ),
              const SizedBox(height: 8),
              SelectableText('Request ID: ${_checkpoint!.intent.requestId}'),
              SelectableText('Receipt ID: ${_checkpoint!.intent.outboxId}'),
              Text(
                'Reviewed revision ${_checkpoint!.intent.revision} · ${_checkpoint!.intent.reason.label}',
              ),
              if (_checkpoint!.intent.outboxId != widget.outboxId)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => context.go(
                      '/admin/sms-receipts/${_checkpoint!.intent.outboxId}',
                    ),
                    child: const Text('Open original receipt'),
                  ),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _busy || lookup?.isLoading == true
                      ? null
                      : () {
                          setState(
                            () => _lookupId = _checkpoint!.intent.requestId,
                          );
                          ref.invalidate(
                            adminReceiptCancelLookupProvider(_lookupId!),
                          );
                        },
                  icon: const Icon(Icons.manage_search_outlined),
                  label: const Text('Check original request'),
                ),
              ),
              if (lookup != null) ...[
                const SizedBox(height: 12),
                lookup.when(
                  skipLoadingOnRefresh: false,
                  loading: () => const _CancelNotice(
                    'Checking original request',
                    'Reading current actor-bound operation evidence without resubmission.',
                  ),
                  error: (error, _) => _cancelError(error),
                  data: (data) => !data.isFresh(now)
                      ? const _CancelNotice(
                          'Cancellation lookup expired',
                          'Check the original request again. Its recovery reference is retained.',
                        )
                      : data.receipt == null
                      ? _CancelNotice(
                          data.status == 'in_progress'
                              ? 'Original request in progress'
                              : 'Original request not recorded at this check',
                          'This result does not establish a final failure. The original request is retained; no replay or new request is permitted.',
                        )
                      : !data.receipt!.matches(_checkpoint!.intent)
                      ? const _CancelNotice(
                          'Cancellation receipt mismatch',
                          'The recorded evidence does not match the original receipt, revision and reason. The reference is retained.',
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _CancelReceiptView(receipt: data.receipt!),
                            Text(
                              'Lookup checked ${_cancelTime(data.checkedAt)}',
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: () => _adopt(data),
                                child: const Text(
                                  'Use confirmed cancellation and refresh',
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  void _clear(
    AdminReceiptCancelCheckpointStore store,
    AdminReceiptCancelCheckpoint checkpoint,
  ) {
    final saved = store.read(checkpoint.ownerDigest);
    if (saved != null &&
        AdminReceiptCancelCheckpoint.parse(
              saved,
              checkpoint.ownerDigest,
            ).encode() !=
            checkpoint.encode()) {
      throw const FormatException('Recovery reference changed.');
    }
    store.clear(checkpoint.ownerDigest);
    if (store.read(checkpoint.ownerDigest) != null) {
      throw const FormatException('Recovery reference remains stored.');
    }
  }

  void _adopt(AdminReceiptCancelLookup lookup) {
    final checkpoint = _checkpoint,
        session = ref.read(adminAuthSessionScopeProvider),
        identity = _adminResolvedIdentity(ref.read(adminIdentityProvider));
    final current = _lookupId == null
        ? null
        : ref.read(adminReceiptCancelLookupProvider(_lookupId!));
    if (checkpoint == null ||
        lookup.receipt?.matches(checkpoint.intent) != true ||
        !lookup.isFresh(ref.read(adminClockProvider)()) ||
        current?.isLoading == true ||
        current?.hasError == true ||
        current?.asData?.value != lookup ||
        session == null ||
        session.key.userId != identity?.userId ||
        !_receiptCancelCanRead(identity) ||
        _ownerDigest != checkpoint.ownerDigest) {
      return;
    }
    try {
      _clear(ref.read(adminReceiptCancelCheckpointStoreProvider)!, checkpoint);
    } catch (_) {
      setState(
        () => _message =
            'Cancellation is confirmed, but the recovery reference could not be cleared. The original request is retained.',
      );
      return;
    }
    setState(() {
      _receipt = lookup.receipt;
      _checkpoint = null;
      _lookupId = null;
      _message =
          'Cancellation recorded. The primary receipt is retained; payment and delivery evidence are separate.';
    });
    _refresh();
    widget.onRecorded?.call();
  }

  Future<void> _review(AdminReceiptCancelInspection inspection) async {
    if (_busy ||
        _checkpoint != null ||
        _ownerDigest == null ||
        !_receiptCancelCanManage(
          _adminResolvedIdentity(ref.read(adminIdentityProvider)),
        )) {
      return;
    }
    final scope = _AdminActionScope(ref),
        store = ref.read(adminReceiptCancelCheckpointStoreProvider),
        owner = _ownerDigest!,
        operationScope = _scope;
    if (store == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    AdminReceiptCancelIntent? intent;
    AdminReceiptCancelReceipt? observed;
    var submitted = false;
    try {
      final requestId = const Uuid().v4();
      intent = await _showAdminFormDialog<AdminReceiptCancelIntent>(
        context: context,
        builder: (dialogContext) => _AdminSessionDialog(
          scope: scope,
          child: _ReceiptCancelDialog(
            outboxId: widget.outboxId,
            revision: inspection.revision!,
            requestId: requestId,
            onConfirm: (reason) => Navigator.pop(
              dialogContext,
              AdminReceiptCancelIntent(
                requestId: requestId,
                outboxId: widget.outboxId,
                revision: inspection.revision!,
                reason: reason,
              ),
            ),
          ),
        ),
      );
      if (!mounted || intent == null || !scope.isCurrent) return;
      final actor = await scope.repository.currentIdentity();
      if (!mounted || !scope.isCurrent) return;
      if (actor?.userId != scope.actorId || !_receiptCancelCanManage(actor)) {
        throw const AdminReceiptCancelDenied();
      }
      final current = ref.read(
        adminReceiptCancelInspectionProvider(widget.outboxId),
      );
      if (current.isLoading ||
          current.hasError ||
          current.asData?.value.isFresh(ref.read(adminClockProvider)()) !=
              true ||
          current.asData?.value.canCancel != true ||
          current.asData?.value.revision != intent.revision ||
          _ownerDigest != owner ||
          _storageFailed ||
          ref.read(adminReceiptCancelCheckpointStoreProvider) != store) {
        cancelInvalid();
      }
      final checkpoint = AdminReceiptCancelCheckpoint(owner, intent);
      try {
        if (store.read(owner) != null) {
          throw const FormatException('An original request is already stored.');
        }
        store.write(owner, checkpoint.encode());
        final saved = store.read(owner);
        if (saved == null ||
            AdminReceiptCancelCheckpoint.parse(saved, owner).encode() !=
                checkpoint.encode()) {
          throw const FormatException('Recovery storage readback failed.');
        }
      } catch (_) {
        _storageFailed = true;
        rethrow;
      }
      if (!mounted ||
          !scope.isCurrent ||
          _ownerDigest != owner ||
          ref.read(adminReceiptCancelCheckpointStoreProvider) != store) {
        return;
      }
      setState(() {
        _checkpoint = checkpoint;
        _saving = true;
      });
      submitted = true;
      final receipt = await scope.repository.cancelUnstartedReceipt(intent);
      if (!mounted ||
          !scope.isCurrent ||
          _ownerDigest != owner ||
          ref.read(adminReceiptCancelCheckpointStoreProvider) != store) {
        return;
      }
      if (!receipt.matches(intent)) cancelInvalid();
      observed = receipt;
      _clear(store, checkpoint);
      setState(() {
        _receipt = receipt;
        _checkpoint = null;
        _message =
            'Cancellation recorded. Refreshing current receipt evidence; the payment was not reversed and carrier delivery is not verified.';
      });
      _refresh();
      widget.onRecorded?.call();
    } catch (_) {
      if (!mounted ||
          !scope.isCurrent ||
          _ownerDigest != owner ||
          ref.read(adminReceiptCancelCheckpointStoreProvider) != store) {
        return;
      }
      setState(() {
        _receipt = observed;
        _message = observed != null
            ? 'Cancellation recorded, but recovery storage could not be cleared. Check the original request before another cancellation.'
            : submitted
            ? 'Cancellation outcome unconfirmed. The original request is retained; check it without replaying or creating another request.'
            : 'Cancellation was not submitted. Current authority, fresh eligibility and verified recovery storage are required.';
      });
      if (observed != null) {
        _refresh();
        widget.onRecorded?.call();
      }
    } finally {
      if (mounted && _scope == operationScope) {
        setState(() {
          _busy = false;
          _saving = false;
        });
      }
    }
  }
}

class _ReceiptCancelDialog extends StatefulWidget {
  const _ReceiptCancelDialog({
    required this.outboxId,
    required this.revision,
    required this.requestId,
    required this.onConfirm,
  });
  final String outboxId, requestId;
  final int revision;
  final ValueChanged<AdminReceiptCancelReason> onConfirm;
  @override
  State<_ReceiptCancelDialog> createState() => _ReceiptCancelDialogState();
}

class _ReceiptCancelDialogState extends State<_ReceiptCancelDialog> {
  AdminReceiptCancelReason? _reason;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Review receipt cancellation'),
    scrollable: true,
    content: SizedBox(
      width: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Stop this definitely unstarted primary receipt. The backend rechecks its revision and recorded transport history. This does not reverse a payment, send a replacement or verify delivery.',
          ),
          const SizedBox(height: 12),
          SelectableText('Receipt ID: ${widget.outboxId}'),
          Text('Expected revision: ${widget.revision}'),
          SelectableText('Original request ID: ${widget.requestId}'),
          const SizedBox(height: 16),
          DropdownButtonFormField<AdminReceiptCancelReason>(
            key: const Key('receipt-cancel-reason'),
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Cancellation reason'),
            items: [
              for (final reason in AdminReceiptCancelReason.values)
                DropdownMenuItem(value: reason, child: Text(reason.label)),
            ],
            onChanged: (reason) => setState(() => _reason = reason),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Keep receipt'),
      ),
      FilledButton(
        onPressed: _reason == null ? null : () => widget.onConfirm(_reason!),
        child: const Text('Confirm cancellation'),
      ),
    ],
  );
}

class _CancelNotice extends StatelessWidget {
  const _CancelNotice(this.title, this.message);
  final String title, message;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(message),
      ],
    ),
  );
}

Widget _cancelError(Object error) => _CancelNotice(
  error is AdminReceiptCancelDenied
      ? 'Cancellation access denied'
      : error is AdminReceiptCancelBusy
      ? 'Cancellation authority busy'
      : error is AdminSessionChanged
      ? 'Admin session changed'
      : error is UnsupportedError
      ? 'Cancellation service unavailable'
      : 'Cancellation read failed',
  error is AdminReceiptCancelBusy
      ? 'Current authority or source is busy. No request outcome is disclosed; the original reference is retained.'
      : 'Evidence could not be read or authorized. Refresh with the current approved email-owner session. No cancellation or replacement request is inferred.',
);

class _CancelReceiptView extends StatelessWidget {
  const _CancelReceiptView({required this.receipt});
  final AdminReceiptCancelReceipt receipt;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const AdminStatusChip(
        label: 'Cancellation recorded',
        tone: CollectStatusTone.info,
      ),
      const SizedBox(height: 8),
      SelectableText('Request ID: ${receipt.requestId}'),
      SelectableText('Receipt ID: ${receipt.outboxId}'),
      Text(
        'Revision ${receipt.expectedRevision} → ${receipt.revision} · queued → suppressed',
      ),
      Text(receipt.reason.label),
      Text('Recorded ${_cancelTime(receipt.recordedAt)}'),
      const Text(
        'Primary receipt retained · No financial or send action · Carrier delivery unverified',
      ),
    ],
  );
}
