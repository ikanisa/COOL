part of 'admin_runtime.dart';

bool _receiptWorkerCanRead(AdminIdentity? identity) =>
    identity?.roles.contains('platform_owner') == true &&
    _exceptionCanRead(identity);

final adminReceiptWorkerHealthProvider =
    FutureProvider.autoDispose<AdminReceiptWorkerHealth>((ref) async {
      final session = ref.watch(adminAuthSessionScopeProvider);
      ref.watch(_adminIdentityRevisionProvider);
      ref.watch(adminRealtimeTickProvider);
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
      final raw = await repository.receiptExceptionWorkerHealth().timeout(
        const Duration(seconds: 15),
      );
      if (!current) throw const AdminSessionChanged();
      return AdminReceiptWorkerHealth.parse(raw);
    });

class AdminReceiptWorkerCard extends ConsumerStatefulWidget {
  const AdminReceiptWorkerCard({super.key});
  @override
  ConsumerState<AdminReceiptWorkerCard> createState() =>
      _AdminReceiptWorkerCardState();
}

class _AdminReceiptWorkerCardState
    extends ConsumerState<AdminReceiptWorkerCard> {
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
      return const Text('Checking exception worker access…');
    }
    if (session == null ||
        identity?.userId != session.key.userId ||
        !_receiptWorkerCanRead(identity)) {
      return const Text(
        'A current platform owner with payment, notification and system health read access is required.',
      );
    }
    final sample = ref.watch(adminReceiptWorkerHealthProvider);
    final health = sample.isLoading ? null : sample.asData?.value;
    final fresh = health?.isFresh(ref.watch(adminClockProvider)()) == true;
    final scope = _AdminActionScope(ref);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'This worker scans receipt deferrals and routes internal escalations. Receipt creation, financial handling and SMS delivery have separate evidence.',
        ),
        const SizedBox(height: 12),
        if (sample.isLoading)
          Semantics(
            liveRegion: true,
            child: const Text('Loading exception worker evidence…'),
          )
        else if (sample.hasError)
          const Text(
            'Exception worker evidence could not be verified. Refresh and check current access.',
          )
        else if (!fresh)
          const Text(
            'Exception worker evidence expired. Refresh to inspect the current worker.',
          )
        else if (health != null) ...[
          Semantics(liveRegion: true, child: Text(health.stateLabel)),
          Text('Configuration revision ${health.revision}'),
          Text(
            health.transportConfigured
                ? 'Worker transport configured'
                : 'Worker transport unconfigured',
          ),
          Text('Pending source work: ${health.pendingSources}'),
          const SizedBox(height: 12),
          Semantics(
            header: true,
            child: Text(
              'UTC-day reservations',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final entry in health.budgets.entries)
            Text(
              '${AdminReceiptWorkerHealth.budgetLabels[entry.key]}: '
              '${entry.value.reserved} reserved / ${entry.value.cap} cap',
            ),
          const Text(
            'Reservations cover whole batches. They do not count completed scans or escalations. Source history has not been declared fully scanned.',
          ),
          if (health.requestId != null) ...[
            const SizedBox(height: 12),
            const Text('Latest scheduled job ID'),
            SelectableText(health.requestId!),
            Text('Created ${adminKigaliDateTime(health.createdAt!)}'),
            Text('Deadline ${adminKigaliDateTime(health.expiresAt!)}'),
          ],
          if (health.recordedAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Most recent recorded worker result: '
              '${health.outcome == 'completed' ? 'completed' : 'busy'}',
            ),
            Text('Recorded ${adminKigaliDateTime(health.recordedAt!)}'),
            const Text(
              'This recorded result can belong to an earlier job. It does not resolve a newer unknown job.',
            ),
          ],
          if (health.alerts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Semantics(
              header: true,
              child: Text(
                'Worker alerts',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final alert in health.alerts)
              Text(AdminReceiptWorkerHealth.alertLabels[alert]!),
          ],
          Text('Checked ${adminKigaliDateTime(health.checkedAt)}'),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () {
                if (scope.isCurrent &&
                    health.isFresh(ref.read(adminClockProvider)())) {
                  context.go('/admin/exceptions');
                }
              },
              icon: const Icon(Icons.manage_search_outlined),
              label: const Text('Open receipt exceptions'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: sample.isLoading
                ? null
                : () => ref.invalidate(adminReceiptWorkerHealthProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh exception worker'),
          ),
        ),
      ],
    );
  }
}
