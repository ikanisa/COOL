part of 'admin_runtime.dart';

final _reconciliationUuid = RegExp(
  r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$',
);
void _requireReconciliationUuid(String value) {
  if (!_reconciliationUuid.hasMatch(value)) {
    throw const FormatException('Invalid reconciliation reference.');
  }
}

String? _reconciliationSessionKey(Session? session) {
  if (session == null) return null;
  try {
    final payload = jsonDecode(
      utf8.decode(
        base64Url.decode(
          base64Url.normalize(session.accessToken.split('.')[1]),
        ),
      ),
    );
    if (payload is! Map ||
        payload['sub'] != session.user.id ||
        payload['session_id'] is! String ||
        payload['exp'] is! int ||
        (payload['exp'] as int) <=
            DateTime.now().millisecondsSinceEpoch ~/ 1000 ||
        (payload['session_id'] as String).isEmpty) {
      return null;
    }
    return '${session.user.id}/${payload['session_id']}';
  } catch (_) {
    return null;
  }
}

final adminReconciliationSessionKeyProvider = Provider<String?>((ref) {
  final scope = ref.watch(adminAuthSessionScopeProvider);
  // Also expire open dialogs when no Auth stream event arrives at token expiry.
  final expiryCheck = Timer(const Duration(seconds: 30), ref.invalidateSelf);
  ref.onDispose(expiryCheck.cancel);
  return _reconciliationSessionScopeKey(
    ref.watch(supabaseClientProvider)?.auth.currentSession,
    scope,
  );
});

String? _reconciliationSessionScopeKey(
  Session? session,
  AdminSessionScope? scope,
) {
  final key = _reconciliationSessionKey(session);
  if (scope == null || key == null || adminSessionKey(session) != scope.key) {
    return null;
  }
  // A -> B -> A can be coalesced into one widget rebuild. Preserve the Auth
  // generation so a dialog from the first A can never become current again.
  return '$key/${scope.generation}';
}

AdminIdentity? _reconciliationIdentity(AsyncValue<AdminIdentity?> value) =>
    value.isLoading || value.hasError ? null : value.valueOrNull;

bool _validReconciliationReview(Map<Object?, Object?> raw, String? paymentId) =>
    raw['id'] is String &&
    _reconciliationUuid.hasMatch(raw['id'] as String) &&
    raw['payment_id'] is String &&
    _reconciliationUuid.hasMatch(raw['payment_id'] as String) &&
    (paymentId == null || raw['payment_id'] == paymentId) &&
    {
      'proposed',
      'approved',
      'expired',
      'legacy_review_required',
      'finalized',
    }.contains(raw['status']) &&
    raw['source_reference'] is String &&
    raw['evidence_sha256'] is String &&
    RegExp(r'^[0-9a-f]{64}$').hasMatch(raw['evidence_sha256'] as String) &&
    raw['proposed_by'] is String &&
    _reconciliationUuid.hasMatch(raw['proposed_by'] as String) &&
    _reconciliationTimestamp(raw['proposed_at']) != null &&
    _reconciliationTimestamp(raw['occurred_at']) != null &&
    (raw['approved_by'] == null ||
        (raw['approved_by'] is String &&
            _reconciliationUuid.hasMatch(raw['approved_by'] as String))) &&
    (raw['status'] != 'approved' ||
        (raw['approved_by'] != null &&
            _reconciliationTimestamp(raw['approved_at']) != null));

DateTime? _reconciliationTimestamp(Object? value) {
  if (value == null) return null;
  try {
    return exactJsonTimestamp(value, field: 'reconciliation timestamp');
  } on FormatException {
    return null;
  }
}

String _reconciliationError(Object error) {
  if (error is AdminReconciliationStepUpException) return error.message;
  String? code;
  if (error is PostgrestException) code = error.message;
  if (error is FunctionException && error.details is Map) {
    code = '${(error.details as Map)['error']}';
  }
  return switch (code) {
    'reconciliation_step_up_required' =>
      'Verify your authenticator again before continuing.',
    'reconciliation_actor_unavailable' =>
      'An operator approval, role or sign-in is no longer valid. Refresh and record a new review with authorized operators.',
    'reconciliation_approver_required' =>
      'Only the independent reviewer, using the same approved sign-in, can finalize this evidence.',
    'reconciliation_independent_approval_required' =>
      'A different approved operator must review this evidence.',
    'reconciliation_approval_expired' || 'reconciliation_proposal_expired' =>
      'This evidence review expired. Record a new proposal and obtain independent approval.',
    'reconciliation_payment_changed' || 'reconciliation_conflict' =>
      'The payment or its evidence review changed or expired. Refresh the audit trail before continuing.',
    'reconciliation_permission_required' =>
      'Your current Admin role cannot perform this action.',
    _ => adminSafeErrorMessage(error),
  };
}

class AdminReconciliationPage extends ConsumerStatefulWidget {
  const AdminReconciliationPage({super.key});
  @override
  ConsumerState<AdminReconciliationPage> createState() =>
      _AdminReconciliationPageState();
}

class _AdminReconciliationPageState
    extends ConsumerState<AdminReconciliationPage> {
  Future<AdminLoadedPage>? _reviews;
  AdminTableRowData? _payment;
  String? _scope;
  String? _notice;
  Object? _error;
  bool _busy = false;
  bool _history = false;
  bool _hadReadAccess = false;
  int _reviewPage = 0;
  int _generation = 0;
  int _reviewRequest = 0;
  int _appliedReviewTick = 0;
  bool _reviewLoadInFlight = false;
  bool _reviewLiveRefreshScheduled = false;
  Timer? _expiryTimer;
  static const _pageSize = 25;

  @override
  void initState() {
    super.initState();
    _expiryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  bool _sameScope(String? scope, {bool write = false}) {
    if (!mounted ||
        scope == null ||
        ref.read(adminReconciliationSessionKeyProvider) != scope) {
      return false;
    }
    final client = ref.read(supabaseClientProvider);
    if (client != null &&
        _reconciliationSessionScopeKey(
              client.auth.currentSession,
              ref.read(adminAuthSessionScopeProvider),
            ) !=
            scope) {
      return false;
    }
    final identity = _reconciliationIdentity(ref.read(adminIdentityProvider));
    return identity != null &&
        identity.userId == ref.read(adminAuthUserIdProvider) &&
        scope.startsWith('${identity.userId}/') &&
        identity.permissions.contains('payments.read') &&
        (!write ||
            (identity.permissions.contains('payments.allocate') ||
                identity.permissions.contains('payments.propose')));
  }

  String? get _paymentId {
    final payment = _payment;
    if (payment == null) return null;
    final id = payment.extra['payment_id'];
    if (id is String && _reconciliationUuid.hasMatch(id)) return id;
    // Retain the existing direct-payment caller contract. Canonical transaction
    // references are momo:<raw-sms-id> and must never become payment UUIDs.
    return _reconciliationUuid.hasMatch(payment.id) ? payment.id : null;
  }

  Future<AdminLoadedPage> _loadReviews() async {
    final scope = _scope;
    final paymentId = _paymentId;
    final request = ++_reviewRequest;
    _reviewLoadInFlight = true;
    _appliedReviewTick = ref.read(adminRealtimeTickProvider);
    final repository = ref.read(adminRepositoryProvider);
    try {
      final loaded = await loadAdminListPage(
        fetch: (limit, offset) => repository.paymentReconciliationReviews(
          paymentId,
          limit: limit,
          offset: offset,
        ),
        page: _reviewPage,
        pageSize: _pageSize,
        isCurrent: () =>
            request == _reviewRequest &&
            _sameScope(scope) &&
            identical(ref.read(adminRepositoryProvider), repository) &&
            paymentId == _paymentId,
      );
      _reviewPage = loaded.page;
      ref.read(adminLastSuccessfulRefreshProvider.notifier).state = ref.read(
        adminClockProvider,
      )();
      return loaded;
    } finally {
      if (mounted && request == _reviewRequest) {
        _reviewLoadInFlight = false;
        if (ref.read(adminRealtimeTickProvider) != _appliedReviewTick) {
          _scheduleReviewLiveRefresh();
        }
      }
    }
  }

  void _scheduleReviewLiveRefresh() {
    if (_reviewLiveRefreshScheduled || !mounted) return;
    _reviewLiveRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reviewLiveRefreshScheduled = false;
      if (!mounted || _busy || _reviewLoadInFlight || !_sameScope(_scope)) {
        return;
      }
      if (_paymentId == null && !_history) return;
      if (ref.read(adminRealtimeTickProvider) == _appliedReviewTick) return;
      _refresh();
    });
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      if (_paymentId != null || _history) _reviews = _loadReviews();
    });
  }

  Future<T?> _dialog<T>(String scope, Widget child, {bool write = false}) =>
      showDialog<T>(
        context: context,
        animationStyle: CollectMotion.animationStyle(context),
        builder: (_) =>
            _ReconciliationScopeGate(scope: scope, write: write, child: child),
      );

  Future<void> _perform(
    String scope,
    Future<String> Function() operation, {
    String permission = 'payments.allocate',
  }) async {
    if (_busy ||
        !_sameScope(scope, write: true) ||
        !_adminHasPermission(
          _reconciliationIdentity(ref.read(adminIdentityProvider)),
          permission,
        )) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final verified = await _dialog<bool>(
        scope,
        const _ReconciliationStepUpDialog(),
        write: true,
      );
      if (verified != true ||
          !_sameScope(scope, write: true) ||
          generation != _generation) {
        return;
      }
      if (!_adminHasPermission(
        _reconciliationIdentity(ref.read(adminIdentityProvider)),
        permission,
      )) {
        return;
      }
      final message = await operation();
      if (!_sameScope(scope, write: true) || generation != _generation) return;
      setState(() => _notice = message);
      _refresh();
    } catch (error) {
      if (_sameScope(scope) && generation == _generation) {
        setState(() => _error = error);
      }
    } finally {
      if (_sameScope(scope) && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _propose() async {
    final paymentId = _paymentId;
    final scope = _scope;
    if (paymentId == null || scope == null || !_sameScope(scope, write: true)) {
      return;
    }
    final evidence = await _dialog<Map<String, dynamic>>(
      scope,
      _ReconciliationEvidenceDialog(paymentId: paymentId),
      write: true,
    );
    if (evidence == null || !_sameScope(scope, write: true)) return;
    final repository = ref.read(adminRepositoryProvider);
    await _perform(
      scope,
      () async {
        await repository.proposePaymentReconciliation(evidence);
        return 'Evidence recorded. An independent reviewer must approve it.';
      },
      permission:
          _adminHasPermission(
            _reconciliationIdentity(ref.read(adminIdentityProvider)),
            'payments.propose',
          )
          ? 'payments.propose'
          : 'payments.allocate',
    );
  }

  Future<void> _approve(Map<String, dynamic> review) async {
    final scope = _scope;
    if (scope == null || !_sameScope(scope, write: true)) return;
    final reason = await _dialog<String>(
      scope,
      const _ReconciliationReasonDialog(),
      write: true,
    );
    if (reason == null || !_sameScope(scope, write: true)) return;
    final repository = ref.read(adminRepositoryProvider);
    await _perform(scope, () async {
      await repository.approvePaymentReconciliation(
        review['id'] as String,
        reason,
      );
      return 'Independent approval recorded. Finalize within 15 minutes using this sign-in.';
    });
  }

  Future<void> _finalize(Map<String, dynamic> review) async {
    final scope = _scope;
    if (scope == null) return;
    final repository = ref.read(adminRepositoryProvider);
    await _perform(
      scope,
      () async => (await repository.finalizePaymentReconciliation(
        review['id'] as String,
        paymentId: review['payment_id'] as String,
      )).message,
    );
  }

  Future<void> _showLineage(Map<String, dynamic> review) async {
    final scope = _scope;
    if (scope == null || _busy || !_sameScope(scope)) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final details = await ref
          .read(adminRepositoryProvider)
          .paymentReconciliationDetail(
            review['id'] as String,
            paymentId: review['payment_id'] as String,
          );
      if (!_sameScope(scope) || generation != _generation) return;
      await _dialog<void>(
        scope,
        _ReconciliationLineageDialog(details: details),
      );
    } catch (error) {
      if (_sameScope(scope) && generation == _generation) {
        setState(() => _error = error);
      }
    } finally {
      if (_sameScope(scope) && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = _reconciliationIdentity(ref.watch(adminIdentityProvider));
    final currentScope = ref.watch(adminReconciliationSessionKeyProvider);
    final currentOwner = ref.watch(adminAuthUserIdProvider);
    final realtimeTick = ref.watch(adminRealtimeTickProvider);
    if (currentScope != _scope) {
      _scope = currentScope;
      _generation++;
      _reviewRequest++;
      _reviews = null;
      _payment = null;
      _reviewPage = 0;
      _notice = null;
      _error = null;
      _busy = false;
      _reviewLoadInFlight = false;
      _history = false;
    }
    final canRead =
        identity?.userId == currentOwner && _sameScope(currentScope);
    if (_hadReadAccess && !canRead) {
      _generation++;
      _reviewRequest++;
      _reviews = null;
      _payment = null;
      _notice = null;
      _error = null;
      _busy = false;
      _reviewLoadInFlight = false;
      _history = false;
      _reviewPage = 0;
    }
    _hadReadAccess = canRead;
    final canWrite = canRead && _sameScope(currentScope, write: true);
    if (canRead &&
        !_busy &&
        (_paymentId != null || _history) &&
        realtimeTick != _appliedReviewTick) {
      _scheduleReviewLiveRefresh();
    }
    if (canRead && _payment == null && !_history) {
      return AdminRpcListPage(
        key: ValueKey(currentScope),
        title: 'Reconciliations',
        rpcName: 'admin_list_collect_reconciliations',
        subtitleOverride: 'Received payments awaiting allocation.',
        minimal: true,
        header: _navigation(),
        onOpen: (row) => setState(() {
          _payment = row;
          _history = false;
          _reviewPage = 0;
          _reviews = _paymentId == null ? null : _loadReviews();
          _error = null;
          _notice = null;
        }),
      );
    }
    return AdminPage(
      title: 'Reconciliations',
      subtitle: 'Review independent evidence before posting to the ledger.',
      trailing: IconButton(
        tooltip: 'Refresh reconciliations',
        onPressed: _busy || !canRead ? null : _refresh,
        icon: const Icon(Icons.refresh),
      ),
      child: !canRead
          ? const AdminEmptyState(
              title: 'Payment review access required',
              message:
                  'Use an authorized Admin sign-in to view reconciliation evidence.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _navigation(),
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Semantics(liveRegion: true, child: Text(_notice!)),
                  ),
                if (_error != null)
                  _ReconciliationErrorPanel(
                    message: _reconciliationError(_error!),
                    onRetry: _busy ? null : _refresh,
                  ),
                if (_busy) const LinearProgressIndicator(),
                if (_payment != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AdminRecordFactsTable(
                        key: const ValueKey(
                          'reconciliation-selected-payment-facts',
                        ),
                        semanticLabel: 'Selected payment facts',
                        fields: [
                          (
                            'Collect transaction ID',
                            _transactionReference(_payment!).isEmpty
                                ? 'Unavailable'
                                : _transactionReference(_payment!),
                          ),
                          (
                            'Amount',
                            _transactionDisplayAmount(_payment!).isEmpty
                                ? 'Unavailable'
                                : _transactionDisplayAmount(_payment!),
                          ),
                          if (_paymentId != null)
                            ('Payment record', _paymentId!),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _paymentId == null
                            ? 'Allocate to an existing member before recording independent evidence.'
                            : 'Use independently obtained provider or statement evidence. A receipt alone does not establish finality.',
                      ),
                      const SizedBox(height: 12),
                      if (_paymentId == null &&
                          _payment!.extra['event_id'] is String &&
                          _reconciliationUuid.hasMatch(
                            _payment!.extra['event_id'] as String,
                          ))
                        FilledButton(
                          onPressed:
                              _busy ||
                                  !(_adminHasPermission(
                                        identity,
                                        'payments.allocate',
                                      ) ||
                                      _adminHasPermission(
                                        identity,
                                        'payments.propose',
                                      ))
                              ? null
                              : () => allocateAdminExistingMember(
                                  context,
                                  ref,
                                  _payment!,
                                  () {
                                    if (!mounted || !_sameScope(currentScope)) {
                                      return;
                                    }
                                    setState(() {
                                      _payment = null;
                                      _reviews = null;
                                      _reviewRequest++;
                                    });
                                  },
                                ),
                          child: const Text('Allocate to member'),
                        ),
                      if (_paymentId != null)
                        FilledButton(
                          onPressed: _busy || !canWrite ? null : _propose,
                          child: const Text('Propose reconciliation'),
                        ),
                    ],
                  ),
                if (_paymentId != null || _history)
                  _reviewView(
                    identity,
                    canWrite &&
                        _adminHasPermission(identity, 'payments.allocate'),
                  ),
              ],
            ),
    );
  }

  Widget _navigation() => Wrap(
    spacing: 12,
    runSpacing: 8,
    children: [
      TextButton(
        onPressed: _busy
            ? null
            : () => setState(() {
                _history = false;
                _payment = null;
                _reviews = null;
                _reviewRequest++;
              }),
        child: const Text('Payment queue'),
      ),
      TextButton(
        onPressed: _busy
            ? null
            : () => setState(() {
                _history = true;
                _payment = null;
                _reviewPage = 0;
                _reviews = _loadReviews();
              }),
        child: const Text('All evidence reviews'),
      ),
    ],
  );

  Widget _paging(
    AdminLoadedPage page,
    String noun,
    void Function(int) change,
  ) => Wrap(
    spacing: 12,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        '${page.start}–${page.end} of ${page.total} $noun · Page ${page.page + 1}',
      ),
      TextButton(
        onPressed: _busy || page.page == 0 ? null : () => change(page.page - 1),
        child: Text('Previous $noun'),
      ),
      TextButton(
        onPressed: _busy || page.page >= page.lastPage
            ? null
            : () => change(page.page + 1),
        child: Text('Next $noun'),
      ),
    ],
  );

  Widget _reviewView(AdminIdentity? identity, bool canWrite) =>
      FutureBuilder<AdminLoadedPage>(
        future: _reviews ??= _loadReviews(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const AdminLoadingState(title: 'Loading evidence reviews');
          }
          if (snapshot.hasError) {
            return AdminSafeErrorPanel(
              error: snapshot.error!,
              onRetry: _refresh,
            );
          }
          final page = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (page.result.rows.isEmpty)
                const AdminEmptyState(
                  title: 'No evidence proposed',
                  message: 'Record independent evidence for review.',
                ),
              for (final row in page.result.rows)
                _reviewCard(
                  {'id': row.id, 'status': row.status, ...row.extra},
                  identity,
                  canWrite,
                ),
              _paging(page, 'reviews', (next) {
                _reviewPage = next;
                setState(() {
                  _reviews = _loadReviews();
                });
              }),
            ],
          );
        },
      );

  Widget _reviewCard(
    Map<String, dynamic> review,
    AdminIdentity? identity,
    bool canWrite,
  ) {
    final now = ref.read(adminClockProvider)().toUtc();
    final proposedAt = _reconciliationTimestamp(review['proposed_at']);
    final approvedAt = _reconciliationTimestamp(review['approved_at']);
    var status = '${review['status']}';
    if (status == 'proposed' || status == 'approved') {
      if (proposedAt == null ||
          now.isAfter(proposedAt.add(const Duration(hours: 24))) ||
          (status == 'approved' &&
              (approvedAt == null ||
                  now.isAfter(approvedAt.add(const Duration(minutes: 15)))))) {
        status = 'expired';
      }
    }
    final ownProposal = review['proposed_by'] == identity?.userId;
    final ownApproval = review['approved_by'] == identity?.userId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        AdminRecordFactsTable(
          semanticLabel: 'Reconciliation review facts',
          fields: [
            ('Source reference', '${review['source_reference']}'),
            (
              'Review status',
              switch (status) {
                'legacy_review_required' => 'New independent review required',
                _ => status.replaceAll('_', ' '),
              },
            ),
            (
              'Evidence time',
              adminKigaliDateTime(
                _reconciliationTimestamp(review['occurred_at']),
              ),
            ),
            if (_history) ('Payment record', '${review['payment_id']}'),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: _busy ? null : () => _showLineage(review),
              child: const Text('Evidence and audit'),
            ),
            if (status == 'proposed')
              FilledButton(
                onPressed: !canWrite || _busy || ownProposal
                    ? null
                    : () => _approve(review),
                child: const Text('Approve evidence'),
              ),
            if (status == 'approved')
              FilledButton(
                onPressed: !canWrite || _busy || !ownApproval
                    ? null
                    : () => _finalize(review),
                child: const Text('Finalize reconciliation'),
              ),
          ],
        ),
        if (status == 'proposed' && ownProposal)
          const Text(
            'A different approved operator must review this evidence.',
          ),
        if (status == 'approved')
          Text(
            ownApproval
                ? 'Approval is valid for 15 minutes. Finalize using this sign-in.'
                : 'The independent reviewer must finalize using the sign-in that approved this evidence.',
          ),
        if (status == 'expired' || status == 'legacy_review_required')
          const Text(
            'Record a new proposal from the payment queue and obtain independent approval.',
          ),
      ],
    );
  }
}

/// A modal is its own route. Hide its child immediately on scope changes and
/// remove that specific route, rather than popping an unrelated newer dialog.
class _ReconciliationScopeGate extends ConsumerWidget {
  const _ReconciliationScopeGate({
    required this.scope,
    required this.child,
    this.write = false,
  });
  final String scope;
  final Widget child;
  final bool write;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(adminReconciliationSessionKeyProvider);
    final identity = _reconciliationIdentity(ref.watch(adminIdentityProvider));
    final user = ref.watch(adminAuthUserIdProvider);
    final client = ref.watch(supabaseClientProvider);
    final allowed =
        current == scope &&
        identity?.userId == user &&
        scope.startsWith('$user/') &&
        identity?.permissions.contains('payments.read') == true &&
        (client == null ||
            _reconciliationSessionScopeKey(
                  client.auth.currentSession,
                  ref.watch(adminAuthSessionScopeProvider),
                ) ==
                scope) &&
        (!write ||
            (identity?.permissions.contains('payments.allocate') == true ||
                identity?.permissions.contains('payments.propose') == true));
    if (!allowed) {
      final route = ModalRoute.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route?.isActive == true) route!.navigator?.removeRoute(route);
      });
      return const SizedBox.shrink();
    }
    return child;
  }
}

class _ReconciliationErrorPanel extends StatelessWidget {
  const _ReconciliationErrorPanel({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Refresh review')),
        ],
      ),
    ),
  );
}
