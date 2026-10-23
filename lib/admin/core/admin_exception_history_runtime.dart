part of 'admin_runtime.dart';

final adminExceptionHistoryProvider = FutureProvider.autoDispose
    .family<AdminExceptionHistorySnapshot, AdminEntityAuditQuery>((
      ref,
      query,
    ) async {
      adminExceptionHistoryParameters(query);
      final session = ref.watch(adminAuthSessionScopeProvider);
      ref.watch(_adminIdentityRevisionProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      if (session == null ||
          identity?.userId != session.key.userId ||
          !adminEntityAuditCanRead(identity, AdminAuditEntityKind.exception)) {
        throw const AdminEntityAuditDenied();
      }
      try {
        final data = await repository
            .exceptionEntityAudit(query)
            .timeout(const Duration(seconds: 15));
        if (!current) throw const AdminSessionChanged();
        return AdminExceptionHistorySnapshot.parse(data, query: query);
      } on CollectApiException catch (error) {
        if (!current) throw const AdminSessionChanged();
        if (error.code == '42501') throw const AdminEntityAuditDenied();
        if (error.code == '55P03' || error.code == '40001') {
          throw const AdminEntityAuditAuthorityBusy();
        }
        if (error.code == 'operation_unavailable' || error.code == '501') {
          throw UnsupportedError('Joined exception history is unavailable.');
        }
        rethrow;
      } catch (_) {
        if (!current) throw const AdminSessionChanged();
        rethrow;
      }
    });

final adminExceptionEscalationInboxPageProvider = FutureProvider.autoDispose
    .family<
      AdminExceptionEscalationInboxSnapshot,
      AdminExceptionEscalationInboxQuery
    >((ref, query) async {
      query.validate();
      final session = ref.watch(adminAuthSessionScopeProvider);
      ref.watch(_adminIdentityRevisionProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      if (session == null ||
          identity?.userId != session.key.userId ||
          !_exceptionFollowupCanRead(identity)) {
        throw const AdminExceptionDenied();
      }
      final raw = await repository
          .exceptionEscalationInboxPage(query)
          .timeout(const Duration(seconds: 15));
      if (!current) throw const AdminSessionChanged();
      return AdminExceptionEscalationInboxSnapshot.parse(
        raw,
        query: query,
        recipientId: identity!.userId,
      );
    });

/// Joined immutable review, assignment and Admin-inbox evidence on the existing route.
class AdminExceptionHistoryPage extends ConsumerStatefulWidget {
  const AdminExceptionHistoryPage({
    required this.exceptionId,
    this.pageSize = 20,
    super.key,
  });
  final String exceptionId;
  final int pageSize;
  @override
  ConsumerState<AdminExceptionHistoryPage> createState() =>
      _ExceptionHistoryPageState();
}

class _ExceptionHistoryPageState
    extends ConsumerState<AdminExceptionHistoryPage> {
  Object? _scope;
  AdminEntityAuditQuery? _query;
  final _previous = <AdminEntityAuditQuery>[];
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

  AdminEntityAuditQuery get _first => AdminEntityAuditQuery(
    kind: AdminAuditEntityKind.exception,
    id: widget.exceptionId,
    limit: widget.pageSize,
  );
  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/admin/audit-logs');
    }
  }

  void _refresh() {
    setState(() {
      _previous.clear();
      _query = _first;
    });
    ref.invalidate(adminExceptionHistoryProvider(_first));
  }

  @override
  Widget build(BuildContext context) {
    try {
      adminExceptionHistoryParameters(_first);
    } on FormatException {
      return AdminPage(
        title: 'Action history',
        leading: IconButton(
          onPressed: _back,
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
        ),
        child: const _AuditNotice(
          title: 'Action history link unavailable',
          message:
              'This link does not identify a supported exception. Open the record again to read its action history.',
        ),
      );
    }
    final session = ref.watch(adminAuthSessionScopeProvider);
    final repository = ref.watch(adminRepositoryProvider);
    final identityState = ref.watch(adminIdentityProvider);
    final identity = _adminResolvedIdentity(identityState);
    final scope = (
      session,
      repository,
      identity?.userId,
      ref.watch(_adminIdentityRevisionProvider),
      widget.exceptionId,
      widget.pageSize,
    );
    if (_scope != scope) {
      _scope = scope;
      _previous.clear();
      _query = _first;
    }
    if (identityState.isLoading) {
      return const AdminLoadingState(
        title: 'Checking action history access',
        message: 'Checking current Admin permissions.',
      );
    }
    if (session == null ||
        identity?.userId != session.key.userId ||
        !adminEntityAuditCanRead(identity, AdminAuditEntityKind.exception)) {
      return AdminPage(
        title: 'Operational exception · Action history',
        leading: IconButton(
          onPressed: _back,
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
        ),
        child: const _AuditDenied(kind: AdminAuditEntityKind.exception),
      );
    }
    final history = ref.watch(adminExceptionHistoryProvider(_query!));
    final now = ref.watch(adminClockProvider)();
    return AdminPage(
      title: 'Operational exception · Action history',
      subtitle: 'Review, assignment and Admin inbox evidence',
      leading: IconButton(
        onPressed: _back,
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back),
      ),
      trailing: OutlinedButton.icon(
        onPressed: history.isLoading ? null : _refresh,
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh evidence'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AuditIdentifier(
            label: 'Operational exception ID',
            value: widget.exceptionId,
          ),
          const SizedBox(height: 18),
          const _AuditNotice(
            title: 'History is incomplete',
            message:
                'This page joins retained review, assignment and escalation evidence. Earlier escalation transitions may not have been retained. An empty window does not prove that no action occurred.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Admin inbox delivery and opening are separate from source resolution and SMS delivery. Historical evidence does not establish current access, health or financial finality.',
          ),
          const SizedBox(height: 20),
          history.when(
            skipLoadingOnRefresh: false,
            loading: () => const AdminLoadingState(
              title: 'Loading action evidence',
              message: 'Reading retained actions for this exception.',
            ),
            error: (error, _) => error is AdminEntityAuditDenied
                ? const _AuditDenied(kind: AdminAuditEntityKind.exception)
                : _AuditNotice(
                    title: error is UnsupportedError
                        ? 'Action history service unavailable'
                        : error is AdminEntityAuditAuthorityBusy
                        ? 'Action history authority unavailable'
                        : error is AdminSessionChanged
                        ? 'Admin session changed'
                        : 'Action history read failed',
                    message: error is UnsupportedError
                        ? 'The service does not provide joined exception history. No empty history is inferred.'
                        : error is AdminEntityAuditAuthorityBusy
                        ? 'Current authority could not be established. Refresh evidence manually after it is available.'
                        : error is AdminSessionChanged
                        ? 'Reopen this record under your current Admin session.'
                        : 'The action evidence could not be loaded or validated. Refresh evidence to try this read again.',
                  ),
            data: (snapshot) => _evidence(snapshot, now),
          ),
        ],
      ),
    );
  }

  Widget _evidence(AdminExceptionHistorySnapshot snapshot, DateTime now) {
    if (!snapshot.isFresh(now)) {
      return const _AuditNotice(
        title: 'Action history read expired',
        message:
            'Refresh evidence before viewing retained actions or changing history pages. Previous rows are hidden.',
      );
    }
    if (!snapshot.available) {
      return const _AuditNotice(
        title: 'Record unavailable in this scope',
        message:
            'This service could not establish a current supported record. No action history is inferred.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Evidence checked ${_auditTime(snapshot.checkedAt)}'),
        const SizedBox(height: 12),
        if (snapshot.rows.isEmpty)
          const _AuditNotice(
            title: 'No retained actions in this history window',
            message:
                'No action records were returned for this window. Historical coverage remains incomplete.',
          )
        else
          for (final event in snapshot.rows)
            _ExceptionHistoryEventView(
              key: ValueKey(event.eventId),
              event: event,
            ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            if (_previous.isNotEmpty)
              OutlinedButton(
                onPressed: () =>
                    setState(() => _query = _previous.removeLast()),
                child: const Text('Newer actions'),
              ),
            if (snapshot.nextCursor case final cursor?)
              OutlinedButton(
                onPressed: () => setState(() {
                  _previous.add(_query!);
                  _query = AdminEntityAuditQuery(
                    kind: AdminAuditEntityKind.exception,
                    id: widget.exceptionId,
                    limit: widget.pageSize,
                    before: cursor,
                  );
                }),
                child: const Text('Older actions'),
              ),
          ],
        ),
      ],
    );
  }
}

class _ExceptionHistoryEventView extends StatelessWidget {
  const _ExceptionHistoryEventView({required this.event, super.key});
  final AdminExceptionHistoryEvent event;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.collectColors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                event.actionLabel,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            Text('Recorded ${_auditTime(event.recordedAt)}'),
            Text('Source: ${event.sourceLabel}'),
            Text('Provenance: ${event.originLabel}'),
            Text('Actor: ${event.actorKindLabel}'),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    constraints.maxWidth < 760 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.3;
                final width = compact
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 24) / 2;
                final values = <(String, String)>[
                  ('Event ID', event.eventId),
                  ('Retained source record ID', event.sourceRecordId),
                  if (event.requestId != null)
                    ('Original request ID', event.requestId!),
                  if (event.actorId != null) ('Operator ID', event.actorId!),
                  if (event.escalationId != null)
                    ('Escalation ID', event.escalationId!),
                  if (event.assigneeId != null)
                    ('Assigned operator ID', event.assigneeId!),
                ];
                return Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  children: [
                    for (final (label, value) in values)
                      SizedBox(
                        width: width,
                        child: _AuditIdentifier(label: label, value: value),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Text('Recorded source revision: ${event.revision}'),
            if (event.workflowRevision != null)
              Text('Recorded workflow revision: ${event.workflowRevision}'),
            if (event.dueAt != null)
              Text('Recorded deadline ${_auditTime(event.dueAt!)}'),
            if (event.reasonLabel != null) Text('Reason: ${event.reasonLabel}'),
          ],
        ),
      ),
    ),
  );
}
