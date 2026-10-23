part of 'admin_runtime.dart';

/// Read-only policy evidence. Refresh never configures a mode or a sender.
class AdminOperatingPolicyCard extends ConsumerStatefulWidget {
  const AdminOperatingPolicyCard({super.key});
  @override
  ConsumerState<AdminOperatingPolicyCard> createState() =>
      _AdminOperatingPolicyCardState();
}

class _AdminOperatingPolicyCardState
    extends ConsumerState<AdminOperatingPolicyCard> {
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
    final identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider));
    final session = ref.watch(adminAuthSessionScopeProvider);
    if (session == null ||
        identity?.userId != session.key.userId ||
        !adminOperatingPolicyCanRead(identity)) {
      return const Text(
        'Current platform owner access with notification and system health '
        'read permissions is required to view unattended policy.',
      );
    }
    final sample = ref.watch(adminOperatingPolicyProvider);
    final now = ref.watch(adminClockProvider)();
    void refresh() => ref.invalidate(adminOperatingPolicyProvider);
    Widget notice(String text) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: refresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh policy'),
        ),
      ],
    );
    return sample.when(
      skipLoadingOnRefresh: false,
      loading: () => Semantics(
        liveRegion: true,
        child: const Text('Checking unattended policy…'),
      ),
      error: (error, _) => notice(switch (error) {
        AdminOperatingPolicyDenied() =>
          'Current owner authority could not be verified. Sign in again.',
        AdminOperatingPolicyBusy() =>
          'Policy authority is busy. Refresh after the current operation finishes.',
        UnsupportedError() => 'Unattended policy service is unavailable.',
        _ => 'Unattended policy could not be verified. Refresh to investigate.',
      }),
      data: (policy) {
        if (!policy.isFresh(now)) {
          return notice(
            'Policy observation expired or has an unverified time. '
            'Refresh before relying on the current preferences.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Legacy unattended preferences',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Operational runs use Receipt operating controls. A legacy '
              'emergency stop also stops operational runs. Clearing this '
              'preference does not resume them. Assisted sending and manual '
              'shadow observations have separate authority.',
            ),
            const SizedBox(height: 16),
            _PolicyFact(
              label: 'Configured preference',
              value: policy.configuredMode.label,
            ),
            _PolicyFact(
              label: 'Preference after stop',
              value: policy.effectiveMode.label,
            ),
            _PolicyFact(
              label: 'Legacy emergency stop',
              value: policy.emergencyStop ? 'Set' : 'Clear',
            ),
            const _PolicyFact(
              label: 'Unattended execution',
              value: 'Unavailable',
            ),
            _PolicyFact(
              label: 'Assisted receipt gate',
              value: switch (policy.assistedDispatch) {
                'enabled' => 'Enabled · separate authority',
                'paused' => 'Paused · separate authority',
                _ => 'Unverified',
              },
            ),
            const SizedBox(height: 16),
            _PolicyFact(label: 'Policy revision', value: '${policy.revision}'),
            _PolicyFact(label: 'Policy ID', value: policy.id),
            if (policy.lastChangeRequestId case final request?)
              _PolicyFact(label: 'Last change request', value: request),
            _PolicyFact(
              label: 'Checked at',
              value:
                  '${adminKigaliDate(policy.checkedAt)} · '
                  '${adminKigaliTime(policy.checkedAt)} · Africa/Kigali',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh policy'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PolicyFact extends StatelessWidget {
  const _PolicyFact({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        SelectableText(value, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ),
  );
}
