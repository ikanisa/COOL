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
  ref.watch(adminAuthStateProvider);
  // Also expire open dialogs when no Auth stream event arrives at token expiry.
  final expiryCheck = Timer(const Duration(seconds: 30), ref.invalidateSelf);
  ref.onDispose(expiryCheck.cancel);
  return _reconciliationSessionKey(
    ref.watch(supabaseClientProvider)?.auth.currentSession,
  );
});

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
    DateTime.tryParse('${raw['proposed_at']}') != null &&
    DateTime.tryParse('${raw['occurred_at']}') != null &&
    (raw['approved_by'] == null ||
        (raw['approved_by'] is String &&
            _reconciliationUuid.hasMatch(raw['approved_by'] as String))) &&
    (raw['status'] != 'approved' ||
        (raw['approved_by'] != null &&
            DateTime.tryParse('${raw['approved_at']}') != null));

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
  Future<AdminLoadedPage>? _queue;
  Future<AdminLoadedPage>? _reviews;
  AdminTableRowData? _payment;
  String? _scope;
  String? _notice;
  Object? _error;
  bool _busy = false;
  bool _history = false;
  bool _hadReadAccess = false;
  int _page = 0;
  int _reviewPage = 0;
  int _generation = 0;
  int _queueRequest = 0;
  int _reviewRequest = 0;
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
        _reconciliationSessionKey(client.auth.currentSession) != scope) {
      return false;
    }
    final identity = _reconciliationIdentity(ref.read(adminIdentityProvider));
    return identity != null &&
        identity.userId == ref.read(adminAuthUserIdProvider) &&
        scope.startsWith('${identity.userId}/') &&
        identity.permissions.contains('payments.read') &&
        (!write ||
            (identity.roles.contains('platform_owner') &&
                identity.permissions.contains('payments.allocate')));
  }

  Future<AdminLoadedPage> _loadQueue() async {
    final scope = _scope;
    final request = ++_queueRequest;
    final repository = ref.read(adminRepositoryProvider);
    final loaded = await loadAdminListPage(
      fetch: (limit, offset) => repository.list(
        'admin_list_collect_reconciliations',
        limit: limit,
        offset: offset,
        countryCode: 'RW',
      ),
      page: _page,
      pageSize: _pageSize,
      isCurrent: () => request == _queueRequest && _sameScope(scope),
    );
    _page = loaded.page;
    return loaded;
  }

  Future<AdminLoadedPage> _loadReviews() async {
    final scope = _scope;
    final paymentId = _payment?.id;
    final request = ++_reviewRequest;
    final repository = ref.read(adminRepositoryProvider);
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
          paymentId == _payment?.id,
    );
    _reviewPage = loaded.page;
    return loaded;
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _queue = _loadQueue();
      if (_payment != null || _history) _reviews = _loadReviews();
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
    Future<String> Function() operation,
  ) async {
    if (_busy || !_sameScope(scope, write: true)) return;
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
    final payment = _payment;
    final scope = _scope;
    if (payment == null || scope == null || !_sameScope(scope, write: true)) {
      return;
    }
    final evidence = await _dialog<Map<String, dynamic>>(
      scope,
      _ReconciliationEvidenceDialog(paymentId: payment.id),
      write: true,
    );
    if (evidence == null || !_sameScope(scope, write: true)) return;
    final repository = ref.read(adminRepositoryProvider);
    await _perform(scope, () async {
      await repository.proposePaymentReconciliation(evidence);
      return 'Evidence recorded. An independent reviewer must approve it.';
    });
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
    if (currentScope != _scope) {
      _scope = currentScope;
      _generation++;
      _queueRequest++;
      _reviewRequest++;
      _queue = null;
      _reviews = null;
      _payment = null;
      _page = 0;
      _reviewPage = 0;
      _notice = null;
      _error = null;
      _busy = false;
      _history = false;
    }
    final canRead =
        identity?.userId == currentOwner && _sameScope(currentScope);
    if (_hadReadAccess && !canRead) {
      _generation++;
      _queueRequest++;
      _reviewRequest++;
      _queue = null;
      _reviews = null;
      _payment = null;
      _notice = null;
      _error = null;
      _busy = false;
      _history = false;
      _page = 0;
      _reviewPage = 0;
    }
    _hadReadAccess = canRead;
    final canWrite = canRead && _sameScope(currentScope, write: true);
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
                Wrap(
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
                ),
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
                if (_payment == null && !_history)
                  _queueView()
                else ...[
                  if (_payment != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _payment!.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(_payment!.amount),
                            const SizedBox(height: 12),
                            const Text(
                              'Use independently obtained provider or statement evidence. A receipt alone does not establish finality.',
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _busy || !canWrite ? null : _propose,
                              child: const Text('Propose reconciliation'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  _reviewView(identity, canWrite),
                ],
              ],
            ),
    );
  }

  Widget _queueView() => FutureBuilder<AdminLoadedPage>(
    future: _queue ??= _loadQueue(),
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const AdminLoadingState();
      }
      if (snapshot.hasError) {
        return AdminSafeErrorPanel(error: snapshot.error!, onRetry: _refresh);
      }
      final page = snapshot.data!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (page.result.rows.isEmpty)
            const AdminEmptyState(title: 'No payments awaiting review'),
          for (final row in page.result.rows)
            Card(
              child: ListTile(
                title: Text(row.title),
                subtitle: Text('${row.amount} · Awaiting independent review'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy
                    ? null
                    : () => setState(() {
                        _payment = row;
                        _history = false;
                        _reviewPage = 0;
                        _reviews = _loadReviews();
                        _error = null;
                        _notice = null;
                      }),
              ),
            ),
          _paging(page, 'payments', (next) {
            _page = next;
            _refresh();
          }),
        ],
      );
    },
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
    final proposedAt = DateTime.tryParse('${review['proposed_at']}');
    final approvedAt = DateTime.tryParse('${review['approved_at']}');
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${review['source_reference']}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(switch (status) {
              'legacy_review_required' => 'New independent review required',
              _ => status.replaceAll('_', ' '),
            }),
            Text('Evidence time: ${review['occurred_at']}'),
            if (_history) Text('Payment: ${review['payment_id']}'),
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
        ),
      ),
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
            _reconciliationSessionKey(client.auth.currentSession) == scope) &&
        (!write ||
            (identity?.roles.contains('platform_owner') == true &&
                identity?.permissions.contains('payments.allocate') == true));
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
  final parsed = DateTime.tryParse(raw);
  if (parsed == null ||
      parsed.year != int.parse(raw.substring(0, 4)) ||
      parsed.month != int.parse(raw.substring(5, 7)) ||
      parsed.day != int.parse(raw.substring(8, 10)) ||
      parsed.hour != int.parse(raw.substring(11, 13)) ||
      parsed.minute != int.parse(raw.substring(14, 16)) ||
      parsed.second != int.parse(raw.substring(17, 19))) {
    return null;
  }
  return parsed;
}
