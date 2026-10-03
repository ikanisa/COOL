part of 'admin_runtime.dart';

String _principalActionLabel(AdminReceiptPrincipalAction action) =>
    switch (action) {
      AdminReceiptPrincipalAction.enroll => 'Enrollment',
      AdminReceiptPrincipalAction.activate => 'Activation',
      AdminReceiptPrincipalAction.revoke => 'Revocation',
    };

/// Owner-scoped metadata and explicit original-request recovery. Possession of
/// a signing key is proved by the existing signed service, never by this form.
class AdminReceiptPrincipalCard extends ConsumerStatefulWidget {
  const AdminReceiptPrincipalCard({super.key});
  @override
  ConsumerState<AdminReceiptPrincipalCard> createState() =>
      _AdminReceiptPrincipalCardState();
}

class _AdminReceiptPrincipalCardState
    extends ConsumerState<AdminReceiptPrincipalCard> {
  var _query = const AdminReceiptPrincipalDirectoryQuery();
  final _previous = <AdminReceiptPrincipalDirectoryQuery>[];
  AdminSessionScope? _session;
  int? _revision;
  String? _error;
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

  Future<void> _enroll() async {
    final scope = _AdminActionScope(ref);
    if (!scope.isCurrent) return;
    final draft =
        await _showAdminFormDialog<
          ({AdminReceiptPrincipalPublicKey key, DateTime expiresAt})
        >(
          context: context,
          builder: (_) => _AdminSessionDialog(
            scope: scope,
            child: _AdminReceiptPrincipalEnrollmentDialog(
              now: ref.read(adminClockProvider)(),
            ),
          ),
        );
    if (!mounted || draft == null || !scope.isCurrent) return;
    try {
      final now = ref.read(adminClockProvider)().toUtc();
      await ref
          .read(adminReceiptPrincipalControllerProvider.notifier)
          .submit(
            AdminReceiptPrincipalIntent.enroll(
              requestId: const Uuid().v4(),
              createdAt: now,
              requestExpiresAt: now.add(const Duration(seconds: 90)),
              identityExpiresAt: draft.expiresAt,
              publicKey: draft.key,
            ),
          );
      if (!mounted || !scope.isCurrent) return;
      setState(() {
        _query = const AdminReceiptPrincipalDirectoryQuery();
        _previous.clear();
        _error = null;
      });
      ref.invalidate(adminReceiptPrincipalsProvider);
    } catch (_) {
      if (mounted && scope.isCurrent) {
        setState(
          () => _error =
              'Enrollment could not be prepared. Review the public key and expiry.',
        );
      }
    }
  }

  Future<void> _inspect(AdminReceiptPrincipalIdentity target) async {
    final scope = _AdminActionScope(ref);
    if (!scope.isCurrent || scope.session == null) return;
    await _showAdminFormDialog<void>(
      context: context,
      builder: (_) => _AdminSessionDialog(
        scope: scope,
        child: Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: AdminReceiptPrincipalDetail(
                  access: (
                    principalId: target.principalId,
                    session: scope.session!,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (mounted && scope.isCurrent) {
      ref.invalidate(adminReceiptPrincipalsProvider);
      ref.invalidate(adminReceiptOperationsPolicyProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final identityState = ref.watch(adminIdentityProvider);
    final identity = _adminResolvedIdentity(identityState);
    final session = ref.watch(adminAuthSessionScopeProvider);
    final revision = ref.watch(_adminIdentityRevisionProvider);
    if (session != _session || revision != _revision) {
      _session = session;
      _revision = revision;
      _query = const AdminReceiptPrincipalDirectoryQuery();
      _previous.clear();
      _error = null;
    }
    if (identityState.isLoading) {
      return const Text('Checking receipt identity access…');
    }
    if (session == null ||
        identity?.userId != session.key.userId ||
        !adminReceiptOperationsCanManage(identity)) {
      return const Text(
        'A current platform owner with user administration, notifications management and system health access is required.',
      );
    }
    final access = (query: _query, session: session);
    final sample = ref.watch(adminReceiptPrincipalsProvider(access));
    final directory = sample.isLoading ? null : sample.asData?.value;
    final now = ref.watch(adminClockProvider)();
    final fresh = directory?.isFresh(now) == true;
    final control = ref.watch(adminReceiptPrincipalControllerProvider);
    final scope = _AdminActionScope(ref);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Signing identities belong to this operator. Enrollment records a public key; activation requires recent signed possession proof. Sending follows the current operating policy.',
        ),
        const SizedBox(height: 12),
        if (control.message case final message?)
          Semantics(liveRegion: true, child: Text(message)),
        if (_error case final error?) Text(error),
        if (control.storageBlocked)
          OutlinedButton(
            onPressed: control.busy
                ? null
                : () => unawaited(
                    ref
                        .read(adminReceiptPrincipalControllerProvider.notifier)
                        .reload(),
                  ),
            child: const Text('Check identity recovery storage'),
          ),
        for (final original in control.pending) ...[
          const SizedBox(height: 12),
          Text(
            '${_principalActionLabel(original.binding.action)} outcome needs reconciliation',
          ),
          const Text('Original identity request ID'),
          SelectableText(original.binding.requestId),
          Text(
            'Deadline ${adminKigaliDateTime(original.binding.requestExpiresAt)}',
          ),
          OutlinedButton(
            onPressed: control.busy
                ? null
                : () async {
                    if (!scope.isCurrent) return;
                    await ref
                        .read(adminReceiptPrincipalControllerProvider.notifier)
                        .reconcile(original);
                    if (mounted && scope.isCurrent) {
                      ref.invalidate(adminReceiptPrincipalsProvider);
                    }
                  },
            child: const Text('Check original identity request'),
          ),
        ],
        if (control.receipt case final receipt?) ...[
          const SizedBox(height: 12),
          Text(
            '${_principalActionLabel(receipt.action)} recorded: ${receipt.stateAtAction.label}',
          ),
          const Text('Recorded identity request ID'),
          SelectableText(receipt.requestId),
          const Text('Recorded principal ID'),
          SelectableText(receipt.principalId),
          Text('Recorded ${adminKigaliDateTime(receipt.recordedAt)}'),
          const Text(
            'This is the original action receipt. Refresh the directory for current identity state.',
          ),
        ],
        const SizedBox(height: 12),
        if (sample.isLoading)
          const Text('Loading receipt signing identities…')
        else if (sample.hasError)
          const Text(
            'Receipt signing identities could not be verified. Refresh and check current access.',
          )
        else if (!fresh)
          const Text(
            'Identity directory evidence expired. Refresh before using its entries.',
          )
        else if (directory != null) ...[
          if (directory.rows.isEmpty)
            const Text('No receipt signing identities in this page.'),
          for (final target in directory.rows) ...[
            const SizedBox(height: 12),
            Text('Identity state: ${target.state.label}'),
            if (target.isExpired(now))
              const Text('Identity expiry has elapsed'),
            const Text('Signing principal ID'),
            SelectableText(target.principalId),
            Text('Expires ${adminKigaliDateTime(target.expiresAt)}'),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: () {
                  if (scope.isCurrent &&
                      directory.isFresh(ref.read(adminClockProvider)())) {
                    unawaited(_inspect(target));
                  }
                },
                child: const Text('Review signing identity'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_previous.isNotEmpty)
                TextButton(
                  onPressed: () =>
                      setState(() => _query = _previous.removeLast()),
                  child: const Text('Previous identity page'),
                ),
              if (directory.nextCursor != null)
                TextButton(
                  onPressed: _previous.length >= 100
                      ? null
                      : () {
                          if (!scope.isCurrent ||
                              !directory.isFresh(
                                ref.read(adminClockProvider)(),
                              )) {
                            return;
                          }
                          setState(() {
                            _previous.add(_query);
                            _query = AdminReceiptPrincipalDirectoryQuery(
                              before: directory.nextCursor,
                            );
                          });
                        },
                  child: const Text('Next identity page'),
                ),
            ],
          ),
          Text('Checked ${adminKigaliDateTime(directory.checkedAt)}'),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: sample.isLoading
                  ? null
                  : () =>
                        ref.invalidate(adminReceiptPrincipalsProvider(access)),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh signing identities'),
            ),
            FilledButton(
              onPressed:
                  !fresh ||
                      control.busy ||
                      control.storageBlocked ||
                      control.pending.isNotEmpty
                  ? null
                  : () {
                      if (scope.isCurrent &&
                          directory!.isFresh(ref.read(adminClockProvider)())) {
                        unawaited(_enroll());
                      }
                    },
              child: const Text('Enroll signing identity'),
            ),
          ],
        ),
      ],
    );
  }
}

class _AdminReceiptPrincipalEnrollmentDialog extends StatefulWidget {
  const _AdminReceiptPrincipalEnrollmentDialog({required this.now});
  final DateTime now;
  @override
  State<_AdminReceiptPrincipalEnrollmentDialog> createState() =>
      _AdminReceiptPrincipalEnrollmentDialogState();
}

class _AdminReceiptPrincipalEnrollmentDialogState
    extends State<_AdminReceiptPrincipalEnrollmentDialog> {
  final _public = TextEditingController();
  late final _expiry = TextEditingController(
    text: operationsUtc(widget.now.toUtc().add(const Duration(days: 1))),
  );
  String? _error;
  @override
  void dispose() {
    _public.clear();
    _expiry.clear();
    _public.dispose();
    _expiry.dispose();
    super.dispose();
  }

  void _review() {
    try {
      final key = AdminReceiptPrincipalPublicKey.parseText(_public.text);
      final expiry = operationsInstant(_expiry.text.trim());
      AdminReceiptPrincipalIntent.enroll(
        requestId: const Uuid().v4(),
        createdAt: widget.now,
        requestExpiresAt: widget.now.add(const Duration(seconds: 90)),
        identityExpiresAt: expiry,
        publicKey: key,
      );
      Navigator.pop(context, (key: key, expiresAt: expiry));
    } catch (_) {
      setState(
        () => _error =
            'Use valid public signing-key metadata and a UTC expiry between 10 minutes and 30 days.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Enroll receipt signing identity',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Use the public metadata from the approved organizational signing key. The identity starts Pending until recent signed possession proof is verified for activation.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _public,
                minLines: 4,
                maxLines: 8,
                maxLength: 2048,
                decoration: const InputDecoration(
                  labelText: 'Public signing-key metadata',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _expiry,
                maxLength: 27,
                decoration: const InputDecoration(
                  labelText: 'Identity expiry (UTC)',
                  helperText: 'An explicit UTC timestamp ending in Z',
                ),
              ),
              if (_error case final error?)
                Semantics(liveRegion: true, child: Text(error)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel identity enrollment'),
                  ),
                  FilledButton(
                    onPressed: _review,
                    child: const Text('Record pending identity'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class AdminReceiptPrincipalDetail extends ConsumerStatefulWidget {
  const AdminReceiptPrincipalDetail({required this.access, super.key});
  final AdminReceiptPrincipalIdentityAccess access;
  @override
  ConsumerState<AdminReceiptPrincipalDetail> createState() =>
      _AdminReceiptPrincipalDetailState();
}

class _AdminReceiptPrincipalDetailState
    extends ConsumerState<AdminReceiptPrincipalDetail> {
  Timer? _timer;
  String? _error;
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

  Future<void> _safeAct(
    AdminReceiptPrincipalIdentity target, {
    required bool revoke,
  }) async {
    final scope = _AdminActionScope(ref);
    try {
      await _act(target, revoke: revoke);
    } catch (_) {
      if (mounted && scope.isCurrent) {
        setState(
          () => _error =
              'The identity action could not be prepared. Refresh and review current state.',
        );
      }
    }
  }

  Future<void> _act(
    AdminReceiptPrincipalIdentity target, {
    required bool revoke,
  }) async {
    final scope = _AdminActionScope(ref);
    if (!scope.isCurrent || scope.session != widget.access.session) return;
    final String? reason;
    if (revoke) {
      reason = await showAdminReasonDialog(
        context,
        title: 'Revoke receipt signing identity',
        actionLabel: 'Record identity revocation',
        minLength: 8,
        maxLength: 500,
        dialogWrapper: (_, child) =>
            _AdminSessionDialog(scope: scope, child: child),
      );
      if (reason == null) return;
    } else {
      reason = null;
    }
    if (!mounted || !scope.isCurrent) return;
    final now = ref.read(adminClockProvider)().toUtc();
    final intent = revoke
        ? AdminReceiptPrincipalIntent.revoke(
            requestId: const Uuid().v4(),
            createdAt: now,
            requestExpiresAt: now.add(const Duration(seconds: 90)),
            identityExpiresAt: target.expiresAt,
            principalId: target.principalId,
            keySha256: target.keySha256,
            reason: reason!,
          )
        : AdminReceiptPrincipalIntent.activate(
            requestId: const Uuid().v4(),
            createdAt: now,
            requestExpiresAt: now.add(const Duration(seconds: 90)),
            identityExpiresAt: target.expiresAt,
            principalId: target.principalId,
            keySha256: target.keySha256,
          );
    await ref
        .read(adminReceiptPrincipalControllerProvider.notifier)
        .submit(intent);
    if (!mounted || !scope.isCurrent) return;
    ref.invalidate(adminReceiptPrincipalProvider(widget.access));
    ref.invalidate(adminReceiptPrincipalsProvider);
    ref.invalidate(adminReceiptOperationsPolicyProvider);
  }

  @override
  Widget build(BuildContext context) {
    final identityState = ref.watch(adminIdentityProvider);
    final identity = _adminResolvedIdentity(identityState);
    final session = ref.watch(adminAuthSessionScopeProvider);
    if (identityState.isLoading) {
      return const Text('Checking signing identity access…');
    }
    if (session == null ||
        session != widget.access.session ||
        identity?.userId != session.key.userId ||
        !adminReceiptOperationsCanManage(identity)) {
      return const Text(
        'Current platform-owner signing identity access is required.',
      );
    }
    final sample = ref.watch(adminReceiptPrincipalProvider(widget.access));
    final observed = sample.isLoading ? null : sample.asData?.value;
    final now = ref.watch(adminClockProvider)();
    final fresh = observed?.isFresh(now) == true;
    final target = fresh ? observed?.identity : null;
    final control = ref.watch(adminReceiptPrincipalControllerProvider);
    final scope = _AdminActionScope(ref);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Receipt signing identity',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 12),
        if (control.message case final message?)
          Semantics(liveRegion: true, child: Text(message)),
        if (_error case final error?) Text(error),
        if (sample.isLoading)
          const Text('Loading current signing identity…')
        else if (sample.hasError)
          const Text(
            'The current signing identity could not be verified. Refresh and check access.',
          )
        else if (!fresh)
          const Text(
            'Signing identity evidence expired. Refresh before taking action.',
          )
        else if (target == null)
          const Text(
            'This signing identity is unavailable to the current operator.',
          )
        else ...[
          Text('Identity state: ${target.state.label}'),
          if (target.isExpired(now)) const Text('Identity expiry has elapsed'),
          const Text('Signing principal ID'),
          SelectableText(target.principalId),
          const SizedBox(height: 8),
          const Text('Public key fingerprint'),
          SelectableText(target.keySha256),
          Text('Created ${adminKigaliDateTime(target.createdAt)}'),
          Text('Expires ${adminKigaliDateTime(target.expiresAt)}'),
          if (target.activatedAt != null)
            Text('Activated ${adminKigaliDateTime(target.activatedAt!)}'),
          if (target.revokedAt != null)
            Text('Revoked ${adminKigaliDateTime(target.revokedAt!)}'),
          const SizedBox(height: 12),
          const Text(
            'Activation requires recent signed key-possession proof. Revocation also remains available for an expired Pending or Active identity.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (target.state == AdminReceiptPrincipalState.pending &&
                  !target.isExpired(now))
                FilledButton(
                  onPressed:
                      control.busy ||
                          control.storageBlocked ||
                          control.pending.isNotEmpty
                      ? null
                      : () {
                          if (scope.isCurrent &&
                              observed!.isFresh(
                                ref.read(adminClockProvider)(),
                              )) {
                            unawaited(_safeAct(target, revoke: false));
                          }
                        },
                  child: const Text('Activate signing identity'),
                ),
              if (target.state != AdminReceiptPrincipalState.revoked)
                OutlinedButton(
                  onPressed:
                      !ref
                          .read(
                            adminReceiptPrincipalControllerProvider.notifier,
                          )
                          .canBeginRevocation(target.principalId)
                      ? null
                      : () {
                          if (scope.isCurrent &&
                              observed!.isFresh(
                                ref.read(adminClockProvider)(),
                              )) {
                            unawaited(_safeAct(target, revoke: true));
                          }
                        },
                  child: const Text('Revoke signing identity'),
                ),
            ],
          ),
          Text('Checked ${adminKigaliDateTime(observed!.checkedAt)}'),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: sample.isLoading
                  ? null
                  : () => ref.invalidate(
                      adminReceiptPrincipalProvider(widget.access),
                    ),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh signing identity'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close signing identity'),
            ),
          ],
        ),
      ],
    );
  }
}
