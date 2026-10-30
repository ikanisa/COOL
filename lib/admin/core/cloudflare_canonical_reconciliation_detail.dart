part of 'cloudflare_canonical_reconciliation_pages.dart';

class CanonicalReconciliationDetailPage extends ConsumerStatefulWidget {
  const CanonicalReconciliationDetailPage({
    required this.transactionId,
    this.backPath = '/admin/reconciliations',
    super.key,
  });
  final String transactionId, backPath;
  @override
  ConsumerState<CanonicalReconciliationDetailPage> createState() =>
      _DetailState();
}

class _DetailState extends ConsumerState<CanonicalReconciliationDetailPage> {
  CanonicalReconciliationApi? _api;
  Future<CanonicalReconciliationDetail>? _future;
  CanonicalFinancialAttempt? _pending;
  ReconciliationReceipt? _receipt;
  bool _busy = false;
  bool _hasLiveChanges = false;
  String? _message;

  void _refresh() {
    setState(() {
      _hasLiveChanges = false;
      _future = _api!.detail(widget.transactionId);
    });
  }

  Future<void> _page(
    CanonicalReconciliationDetail current,
    String relation,
    int offset,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final page = await _api!.detail(
        current.id,
        relation: relation,
        offset: offset,
      );
      if (mounted) setState(() => _future = Future.value(current.merge(page)));
    } catch (error) {
      if (mounted) setState(() => _message = _safeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(CanonicalFinancialAttempt attempt) =>
      _confirmCanonicalAttempt(
        context,
        _api!,
        attempt,
        canConfirm: () =>
            mounted &&
            !_busy &&
            !_hasLiveChanges &&
            (_pending == null || identical(_pending, attempt)),
      );

  Future<void> _send(
    CanonicalFinancialAttempt attempt, {
    bool retry = false,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _pending = attempt;
      _message = null;
    });
    try {
      final receipt = await _api!.submit(attempt, confirmedRetry: retry);
      if (mounted) {
        setState(() {
          _receipt = receipt;
          _pending = null;
          _future = _api!.detail(widget.transactionId);
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          if (!attempt.needsLookup) _pending = null;
          _message = attempt.needsLookup
              ? '${_safeError(error)} Check the retained request before making another change.'
              : _safeError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _propose(CanonicalFinancialAttempt attempt) async {
    if (_busy || _pending != null || _hasLiveChanges) return;
    try {
      if (await _confirm(attempt) && mounted) await _send(attempt);
    } catch (error) {
      if (mounted) setState(() => _message = _safeError(error));
    }
  }

  Future<void> _lookup() async {
    final attempt = _pending;
    if (attempt == null || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await _api!.lookup(attempt);
      if (!mounted) return;
      setState(() {
        _receipt = result.receipt;
        _message = result.status == 'not_found'
            ? 'No committed request was found. An identical retry keeps the original reference and requires a fresh review.'
            : result.status == 'unconfirmed'
            ? 'The result remains unconfirmed. Check again before continuing.'
            : result.status == 'cancelled'
            ? 'The original reference is cancelled. A delayed retry cannot apply it.'
            : null;
        if (result.receipt != null || result.status == 'cancelled') {
          _pending = null;
          _future = _api!.detail(widget.transactionId);
        }
      });
    } catch (error) {
      if (mounted) setState(() => _message = _safeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showEvidence(
    CanonicalReconciliationDetail detail,
    Map<String, dynamic> row,
  ) async {
    if (_busy) return;
    final originalApi = _api,
        authority = ref
            .read(cloudflareAdminSessionProvider)
            .asData
            ?.value
            ?.authorityKey,
        protectedSource = retainedEvidenceRequiresReview(
          row['source_sensitivity'],
        );
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final reason = protectedSource
          ? await _reviewRetainedEvidence(context, authority)
          : null;
      if (!mounted ||
          (protectedSource && reason == null) ||
          !identical(
            originalApi,
            ref.read(canonicalReconciliationApiProvider),
          ) ||
          ref
                  .read(cloudflareAdminSessionProvider)
                  .asData
                  ?.value
                  ?.authorityKey !=
              authority) {
        return;
      }
      final text = await ref
          .read(cloudflareAdminSessionProvider.notifier)
          .retainedEvidence(
            row['id'] as String,
            sha256Hex: row['sha256'] as String,
            sizeBytes: row['size_bytes'] as int,
            sourceSensitivity: row['source_sensitivity'],
            reviewReason: reason,
          );
      if (!mounted ||
          !identical(
            originalApi,
            ref.read(canonicalReconciliationApiProvider),
          )) {
        return;
      }
      await showDialog<void>(
        context: context,
        animationStyle: CollectMotion.animationStyle(context),
        builder: (context) => _CanonicalEvidenceDialog(
          text,
          authority,
          protectedSource: protectedSource,
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _message = _safeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review(
    CanonicalReconciliationDetail detail,
    CanonicalReconciliationProposal proposal,
  ) async {
    if (_busy || _pending != null) return;
    final api = _api!;
    try {
      final attempt = await _independentCanonicalReview(
        context,
        api,
        detail,
        proposal,
      );
      if (attempt != null && mounted && identical(api, _api)) {
        await _send(attempt);
      }
    } catch (error) {
      if (mounted) setState(() => _message = _safeError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(adminRealtimeTickProvider, (_, _) {
      setState(() => _hasLiveChanges = true);
    });
    final api = ref.watch(canonicalReconciliationApiProvider),
        user = ref.watch(cloudflareAdminSessionProvider).asData?.value;
    if (!identical(api, _api)) {
      _hasLiveChanges = false;
      _api = api;
      _future = api.detail(widget.transactionId);
      _receipt = null;
      try {
        _pending = api.restore(widget.transactionId);
        _message = null;
      } catch (error) {
        _message = _safeError(error);
      }
    }
    return AdminPage(
      title: 'Retained payment review',
      subtitle:
          'Recorded evidence, member attribution and signed contribution history.',
      leading: IconButton(
        tooltip: 'Back to reconciliation',
        onPressed: () => context.go(widget.backPath),
        icon: const Icon(Icons.arrow_back),
      ),
      trailing: IconButton(
        tooltip: 'Refresh retained payment',
        onPressed: _busy ? null : _refresh,
        icon: const Icon(Icons.refresh),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_hasLiveChanges)
            const _Note(
              'New changes are available. Refresh the retained payment and review its evidence before another action. Your current selection and request are unchanged.',
            ),
          if (_message != null) _Note(_message!, error: true),
          if (_message != null &&
              _pending != null &&
              _pending!.kind == 'review' &&
              _pending!.body['outcome'] == 'approved')
            const _Note(
              'Check the original request first. Before retrying approval, refresh the retained evidence and ledger. Approval can be held for a missing reference or an existing contribution in the same recorded receiver and reference scope. Do not change the reference to bypass review. An unresolved proposal can be rejected without crediting a contribution.',
            ),
          if (_pending != null) ...[
            SelectableText('Unconfirmed request: ${_pending!.key}'),
            Wrap(
              spacing: 12,
              children: [
                FilledButton.tonal(
                  onPressed: _busy ? null : _lookup,
                  child: const Text('Check original request'),
                ),
                if (_pending!.canRetry)
                  OutlinedButton(
                    onPressed: _busy || !_fresh(user)
                        ? null
                        : () async {
                            final attempt = _pending!;
                            if (await _confirm(attempt) && mounted) {
                              await _send(attempt, retry: true);
                            }
                          },
                    child: const Text('Review identical retry'),
                  ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () =>
                            context.go('/admin/requests?key=${_pending!.key}'),
                  child: const Text('Open original request lookup'),
                ),
              ],
            ),
          ],
          if (_receipt != null) ...[
            Semantics(
              header: true,
              child: Text(
                'Recorded decision receipt',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            _records(
              'Recorded decision receipt',
              [
                {'id': _receipt!.values['request_id'], ..._receipt!.values},
              ],
              const {
                'request_id': 'Request',
                'proposal_status': 'Recorded decision',
                'transaction_id': 'Payment',
                'resource_id': 'Proposal',
                'settlement_status': 'Provider settlement',
              },
            ),
          ],
          FutureBuilder<CanonicalReconciliationDetail>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const AdminLoadingState(
                  title: 'Loading retained payment',
                );
              }
              if (snapshot.hasError) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Note(_safeError(snapshot.error!), error: true),
                    TextButton(
                      onPressed: _busy ? null : _refresh,
                      child: const Text('Try again'),
                    ),
                  ],
                );
              }
              final detail = snapshot.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _records(
                    'Retained payment',
                    [detail.transaction],
                    const {
                      'provider_reference': 'Evidence reference',
                      'group_name': 'Group',
                      'amount_rwf': 'Recorded amount (RWF)',
                      'status': 'Evidence status',
                      'evidence_level': 'Evidence basis',
                      'allocated_amount_rwf': 'Recorded contribution (RWF)',
                      'observed_at': 'Observed',
                      'settlement_status': 'Provider settlement',
                    },
                  ),
                  const _Note(
                    'Names and phone details are recorded evidence. Provider verification and settlement are not asserted.',
                  ),
                  if (detail.transaction['provider_reference'] == null ||
                      (detail.transaction['provider_reference'] as String)
                          .trim()
                          .isEmpty)
                    const _Note(
                      'Approval is unavailable without an event-specific evidence reference. Retained evidence cannot be edited. Leave this record unposted or reject its proposal. Record corrected evidence separately only after review, retaining the original record reference in the reason. Recording alone does not credit a contribution.',
                    ),
                  _CanonicalRelatedRecords(
                    detail: detail,
                    user: user,
                    busy: _busy,
                    pending: _pending != null || _hasLiveChanges,
                    onPage: (relation, offset) =>
                        _page(detail, relation, offset),
                    onReview: (proposal) => _review(detail, proposal),
                    onEvidence: (row) => _showEvidence(detail, row),
                  ),
                  if (!_fresh(user)) ...[
                    _Note(
                      user?.usesEmailVerification == true
                          ? 'Verify your email before revealing SMS-source evidence or recording a proposal, review or reversal.'
                          : 'Complete a current authenticator check before revealing SMS-source evidence or recording a proposal, review or reversal.',
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => context.go(
                          user?.usesEmailVerification == true
                              ? Uri(
                                  path: '/admin/security/verify-email',
                                  queryParameters: {
                                    'returnTo': GoRouterState.of(
                                      context,
                                    ).uri.toString(),
                                  },
                                ).toString()
                              : '/admin/security/authenticator',
                        ),
                        child: Text(
                          user?.usesEmailVerification == true
                              ? 'Verify email'
                              : 'Verify authenticator',
                        ),
                      ),
                    ),
                  ],
                  if (detail.canPropose && _pending == null)
                    _CanonicalMemberForm(
                      api: api,
                      detail: detail,
                      user: user,
                      disabled: _busy || _hasLiveChanges,
                      onProposed: _propose,
                    ),
                  TextButton(
                    onPressed: () =>
                        context.go('/admin/transactions/${detail.id}'),
                    child: const Text(
                      'Open payment details and contribution reversal',
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
