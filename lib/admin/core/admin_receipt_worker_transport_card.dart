part of 'admin_runtime.dart';

typedef AdminReceiptWorkerTransportQuery = ({
  String requestId,
  DateTime expiresAt,
});
typedef AdminReceiptWorkerTransportAccess = ({
  AdminReceiptWorkerTransportQuery query,
  AdminSessionScope session,
});

final adminReceiptWorkerTransportProvider = FutureProvider.autoDispose
    .family<AdminReceiptWorkerTransport, AdminReceiptWorkerTransportAccess>((
      ref,
      access,
    ) async {
      final session = ref.watch(adminAuthSessionScopeProvider);
      if (session != access.session) throw const AdminSessionChanged();
      ref.watch(_adminIdentityRevisionProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      if (session == null ||
          identity?.userId != session.key.userId ||
          !_receiptWorkerCanRead(identity)) {
        throw const AdminExceptionDenied();
      }
      final raw = await repository
          .receiptWorkerTransport(
            access.query.requestId,
            expectedExpiresAt: access.query.expiresAt,
          )
          .timeout(const Duration(seconds: 15));
      if (!current) throw const AdminSessionChanged();
      return AdminReceiptWorkerTransport.parse(
        raw,
        requestId: access.query.requestId,
        expectedExpiresAt: access.query.expiresAt,
      );
    });

Future<void> _showAdminReceiptWorkerTransport(
  BuildContext context,
  _AdminActionScope scope,
  AdminReceiptWorkerHealth health,
) async {
  if (!scope.isCurrent || health.requestId == null) return;
  await _showAdminFormDialog<void>(
    context: context,
    builder: (dialogContext) => _AdminSessionDialog(
      scope: scope,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
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
                      'Original job transport evidence',
                      style: Theme.of(dialogContext).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: 12),
                  AdminReceiptWorkerTransportCard(
                    session: scope.session!,
                    query: (
                      requestId: health.requestId!,
                      expiresAt: health.expiresAt!,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Close job transport evidence'),
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

class AdminReceiptWorkerTransportCard extends ConsumerStatefulWidget {
  const AdminReceiptWorkerTransportCard({
    required this.query,
    this.session,
    super.key,
  });
  final AdminReceiptWorkerTransportQuery query;
  final AdminSessionScope? session;
  @override
  ConsumerState<AdminReceiptWorkerTransportCard> createState() =>
      _AdminReceiptWorkerTransportCardState();
}

class _AdminReceiptWorkerTransportCardState
    extends ConsumerState<AdminReceiptWorkerTransportCard> {
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

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(adminAuthSessionScopeProvider);
    final identityState = ref.watch(adminIdentityProvider);
    final identity = _adminResolvedIdentity(identityState);
    if (identityState.isLoading) {
      return const Text('Checking job transport access…');
    }
    if (session == null ||
        widget.session != null && session != widget.session ||
        identity?.userId != session.key.userId ||
        !_receiptWorkerCanRead(identity)) {
      return const Text(
        'Current platform-owner receipt investigation access is required.',
      );
    }
    final access = (query: widget.query, session: widget.session ?? session);
    final sample = ref.watch(adminReceiptWorkerTransportProvider(access));
    final transport = sample.isLoading ? null : sample.asData?.value;
    final fresh = transport?.isFresh(ref.watch(adminClockProvider)()) == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'HTTP observations describe transport. Only a durable original worker receipt records its processing outcome; HTTP acceptance does not establish receipt creation or SMS delivery.',
        ),
        const SizedBox(height: 12),
        if (sample.isLoading)
          const Text('Loading original job transport…')
        else if (sample.hasError)
          const Text(
            'Job transport evidence could not be verified. Refresh and check current access.',
          )
        else if (!fresh)
          const Text(
            'Job transport evidence expired. Refresh before using its observations.',
          )
        else if (transport != null) ...[
          Text(transport.originalStatusLabel),
          const Text('Original scheduled job ID'),
          SelectableText(transport.requestId),
          Text(
            'Original deadline ${adminKigaliDateTime(transport.originalExpiresAt)}',
          ),
          if (transport.originalReceiptStatus != null)
            Text(
              'Recorded original worker result: ${transport.originalReceiptStatus}',
            ),
          if (transport.scanRequestId != null) ...[
            const Text('Durable scan acknowledgement ID'),
            SelectableText(transport.scanRequestId!),
          ],
          const SizedBox(height: 12),
          if (transport.rows.isEmpty)
            const Text(
              'No HTTP dispatch observations are recorded for this job.',
            ),
          for (final row in transport.rows) ...[
            Semantics(
              header: true,
              child: Text(
                'Dispatch attempt ${row.attempt}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(row.outcomeLabel),
            Text('HTTP request ID ${row.httpRequestId}'),
            if (row.httpStatus != null) Text('HTTP status ${row.httpStatus}'),
            if (row.workerErrorCode != null)
              Text('Recorded worker code ${row.workerErrorCode}'),
            Text(
              row.transportTerminal
                  ? 'Transport observation is terminal'
                  : 'Transport observation remains open',
            ),
            if (row.evidenceRevision != null)
              Text('Evidence revision ${row.evidenceRevision}'),
            Text('Dispatched ${adminKigaliDateTime(row.dispatchedAt)}'),
            if (row.responseAt != null)
              Text('Response ${adminKigaliDateTime(row.responseAt!)}'),
            if (row.observedAt != null)
              Text('Observed ${adminKigaliDateTime(row.observedAt!)}'),
            const SizedBox(height: 12),
          ],
          Semantics(
            header: true,
            child: Text(
              'Transport collector',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Text('Configuration revision ${transport.collector.revision}'),
          Text(
            'UTC-day inspections: ${transport.collector.dayInspections} / ${transport.collector.dayCap}',
          ),
          Text(
            transport.collector.sourceSchemaValid
                ? 'Response-source schema verified'
                : 'Response-source schema unverified',
          ),
          if (transport.collector.quotaExhausted)
            const Text('Collector inspection budget exhausted'),
          if (transport.alerts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Semantics(
              header: true,
              child: Text(
                'Transport alerts',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final alert in transport.alerts)
              Text(AdminReceiptWorkerTransport.alertLabels[alert]!),
          ],
          const Text(
            'This bounded sample does not declare all source history inspected.',
          ),
          Text('Checked ${adminKigaliDateTime(transport.checkedAt)}'),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: sample.isLoading
                ? null
                : () => ref.invalidate(
                    adminReceiptWorkerTransportProvider(access),
                  ),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh original job transport'),
          ),
        ),
      ],
    );
  }
}
