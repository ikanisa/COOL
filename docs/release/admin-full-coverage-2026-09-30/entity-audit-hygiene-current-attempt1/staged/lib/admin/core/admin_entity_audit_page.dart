part of 'admin_runtime.dart';

String _auditTime(DateTime value) =>
    '${adminKigaliDate(value)} · ${adminKigaliTime(value)}:${value.second.toString().padLeft(2, '0')} · Africa/Kigali';

/// Historical action evidence. Reading or changing pages never invokes an action.
class AdminEntityAuditPage extends ConsumerStatefulWidget {
  const AdminEntityAuditPage({
    required this.entityKind,
    required this.entityId,
    this.pageSize = 20,
    super.key,
  });
  final String entityKind, entityId;
  final int pageSize;
  @override
  ConsumerState<AdminEntityAuditPage> createState() =>
      _AdminEntityAuditPageState();
}

class _AdminEntityAuditPageState extends ConsumerState<AdminEntityAuditPage> {
  AdminEntityAuditQuery? _query;
  final _previous = <AdminEntityAuditQuery>[];
  Object? _scope;
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

  void _refresh() {
    final query = _query!;
    final first = AdminEntityAuditQuery(
      kind: query.kind,
      id: query.id,
      limit: query.limit,
    );
    setState(() {
      _previous.clear();
      _query = first;
    });
    ref.invalidate(adminEntityAuditProvider(first));
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/admin/audit-logs');
    }
  }

  @override
  Widget build(BuildContext context) {
    AdminAuditEntityKind kind;
    try {
      kind = AdminAuditEntityKind.parse(widget.entityKind);
      AdminEntityAuditQuery(
        kind: kind,
        id: widget.entityId,
        limit: widget.pageSize,
      ).validate();
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
              'This link does not identify a supported record. Open the record again to read its action history.',
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
      kind,
      widget.entityId,
      widget.pageSize,
    );
    if (_scope != scope) {
      _scope = scope;
      _previous.clear();
      _query = AdminEntityAuditQuery(
        kind: kind,
        id: widget.entityId,
        limit: widget.pageSize,
      );
    }
    if (identityState.isLoading) {
      return const AdminLoadingState(
        title: 'Checking action history access',
        message: 'Checking current Admin permissions.',
      );
    }
    if (session == null ||
        identity?.userId != session.key.userId ||
        !adminEntityAuditCanRead(identity, kind)) {
      return AdminPage(
        title: '${kind.label} · Action history',
        leading: IconButton(
          onPressed: _back,
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
        ),
        child: _AuditDenied(kind: kind),
      );
    }
    final history = ref.watch(adminEntityAuditProvider(_query!));
    final now = ref.watch(adminClockProvider)();
    return AdminPage(
      title: '${kind.label} · Action history',
      subtitle: 'Original recorded actions · Rwanda operator scope',
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
          _AuditIdentifier(label: '${kind.label} ID', value: widget.entityId),
          const SizedBox(height: 18),
          const _AuditNotice(
            title: 'History is incomplete',
            message:
                'This page shows retained action records. An empty history does not prove that no action occurred. Historical shadow actions were not backfilled.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Action records do not establish current health, policy approval, financial finality, delivered escalations or SMS delivery.',
          ),
          const SizedBox(height: 20),
          history.when(
            skipLoadingOnRefresh: false,
            loading: () => const AdminLoadingState(
              title: 'Loading action evidence',
              message: 'Reading retained actions for this record.',
            ),
            error: (error, _) => error is AdminEntityAuditDenied
                ? _AuditDenied(kind: kind)
                : _AuditNotice(
                    title: error is UnsupportedError
                        ? 'Action history service unavailable'
                        : error is AdminEntityAuditAuthorityBusy
                        ? 'Action history authority unavailable'
                        : error is AdminSessionChanged
                        ? 'Admin session changed'
                        : 'Action history read failed',
                    message: error is UnsupportedError
                        ? 'This service does not provide entity action history. No empty history is inferred.'
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

  Widget _evidence(AdminEntityAuditSnapshot snapshot, DateTime now) {
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
            _AuditEventView(
              key: ValueKey(event.eventId),
              event: event,
              kind: snapshot.query.kind,
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
                    kind: snapshot.query.kind,
                    id: snapshot.query.id,
                    limit: snapshot.query.limit,
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

class _AuditDenied extends StatelessWidget {
  const _AuditDenied({required this.kind});
  final AdminAuditEntityKind kind;
  @override
  Widget build(BuildContext context) => _AuditNotice(
    title: 'Action history access denied',
    message:
        'A current verified email platform owner with ${kind.requiredPermissions.join(', ')} is required. The service verifies current authority.',
  );
}

class _AuditNotice extends StatelessWidget {
  const _AuditNotice({required this.title, required this.message});
  final String title, message;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(message),
      ],
    ),
  );
}

class _AuditIdentifier extends StatelessWidget {
  const _AuditIdentifier({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      SelectableText(value),
    ],
  );
}

class _AuditEventView extends StatelessWidget {
  const _AuditEventView({required this.event, required this.kind, super.key});
  final AdminEntityAuditEvent event;
  final AdminAuditEntityKind kind;
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
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    constraints.maxWidth < 760 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.3;
                final width = compact
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 24) / 2;
                return Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: width,
                      child: _AuditIdentifier(
                        label: 'Original request ID',
                        value: event.requestId,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _AuditIdentifier(
                        label: 'Actor ID',
                        value: event.actorId ?? 'Actor not recorded',
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _AuditIdentifier(
                        label: 'Event ID',
                        value: event.eventId,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _AuditIdentifier(
                        label: 'Retained source',
                        value: switch (kind) {
                          AdminAuditEntityKind.shadowRun =>
                            'Manual shadow audit event',
                          AdminAuditEntityKind.gatewayDevice =>
                            'Gateway owner request',
                          AdminAuditEntityKind.supervisorIdentity =>
                            'Supervisor owner request',
                          AdminAuditEntityKind.exception =>
                            'Exception review action',
                          AdminAuditEntityKind.receipt =>
                            'Unstarted receipt cancellation',
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
            if (event.fenceVersion != null) ...[
              const SizedBox(height: 12),
              Text('Recorded fence ${event.fenceVersion}'),
            ],
            if (event.revision != null) ...[
              const SizedBox(height: 12),
              Text(
                kind == AdminAuditEntityKind.exception
                    ? 'Reviewed source revision ${event.revision}'
                    : 'Receipt revision after cancellation ${event.revision}',
              ),
            ],
            if (event.reasonLabel != null) ...[
              const SizedBox(height: 8),
              Text('Recorded reason: ${event.reasonLabel}'),
            ],
          ],
        ),
      ),
    ),
  );
}
