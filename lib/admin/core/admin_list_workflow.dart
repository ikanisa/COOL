part of 'admin_runtime.dart';

class _AdminQueueSummary extends StatelessWidget {
  const _AdminQueueSummary({required this.spec});

  final _AdminListSpec spec;

  @override
  Widget build(BuildContext context) {
    if (spec.prioritySignals.isEmpty) return const SizedBox.shrink();
    final colors = context.collectColors;
    final maxChipWidth = math.max(
      0.0,
      math.min(260.0, MediaQuery.sizeOf(context).width - 48),
    );
    return Semantics(
      container: true,
      label: '${spec.title} operator workflow signals',
      hint: spec.subtitle,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.textPrimary.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: colors.surfaceReadable.withValues(alpha: 0.12),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final signal in spec.prioritySignals)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceReadable.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(CollectRadius.md),
                    border: Border.all(
                      color: colors.surfaceReadable.withValues(alpha: 0.14),
                    ),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxChipWidth),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            signal.icon,
                            size: 18,
                            color: colors.surfaceReadable,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              signal.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: colors.surfaceReadable,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminWorkflowSteps extends StatelessWidget {
  const _AdminWorkflowSteps({required this.spec});

  final _AdminListSpec spec;

  @override
  Widget build(BuildContext context) {
    if (spec.workflowSteps.isEmpty) return const SizedBox.shrink();
    final colors = context.collectColors;
    return Semantics(
      container: true,
      label: '${spec.title} operator workflow',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceReadable.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.borderAccent),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var index = 0; index < spec.workflowSteps.length; index += 1)
                _AdminWorkflowStepChip(
                  index: index + 1,
                  signal: spec.workflowSteps[index],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminWorkflowStepChip extends StatelessWidget {
  const _AdminWorkflowStepChip({required this.index, required this.signal});

  final int index;
  final _AdminQueueSignal signal;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceMuted.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(CollectRadius.md),
          border: Border.all(color: colors.borderAccent),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.textPrimary,
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(
                  dimension: 28,
                  child: Center(
                    child: Text(
                      '$index',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.surfaceReadable,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(signal.icon, size: 18, color: colors.textSecondary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  signal.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminSlaPanel extends StatelessWidget {
  const _AdminSlaPanel({required this.spec, required this.future});

  final _AdminListSpec spec;
  final Future<AdminQueueSla?> future;

  @override
  Widget build(BuildContext context) {
    final fallback = _slaForAdminQueue(spec.title);
    return FutureBuilder<AdminQueueSla?>(
      future: future,
      initialData: fallback,
      builder: (context, snapshot) {
        return _AdminSlaContent(
          spec: spec,
          sla: snapshot.hasError ? fallback : snapshot.data ?? fallback,
        );
      },
    );
  }
}

class _AdminSlaContent extends StatelessWidget {
  const _AdminSlaContent({required this.spec, required this.sla});

  final _AdminListSpec spec;
  final AdminQueueSla sla;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      container: true,
      label: '${spec.title} SLA state',
      hint: '${sla.target}. ${sla.escalation}.',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceReadable.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.borderAccent),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _AdminSlaChip(
                icon: Icons.timer_outlined,
                label: 'Target',
                value: sla.target,
              ),
              _AdminSlaChip(
                icon: Icons.assignment_ind_outlined,
                label: 'Owner',
                value: sla.owner,
              ),
              _AdminSlaChip(
                icon: Icons.escalator_warning_outlined,
                label: 'Escalation',
                value: sla.escalation,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminSlaChip extends StatelessWidget {
  const _AdminSlaChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceMuted.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(CollectRadius.md),
          border: Border.all(color: colors.borderAccent),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: colors.textSecondary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '$label: $value',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

AdminQueueSla _slaForAdminQueue(String title) {
  return switch (title) {
    'SMS parsing' => const AdminQueueSla(
      target: 'Review ambiguous SMS within 4 business hours',
      owner: 'Payments operations',
      escalation: 'Escalate failed allocation after same-day retry',
    ),
    'Allocations' => const AdminQueueSla(
      target: 'Clear allocation reviews by next business day',
      owner: 'Payments operations',
      escalation: 'Escalate mismatched ledger impact immediately',
    ),
    'Exceptions' => const AdminQueueSla(
      target: 'Triage open exceptions within 4 business hours',
      owner: 'Payments support',
      escalation: 'Escalate unresolved member impact same day',
    ),
    'SMS metadata' => const AdminQueueSla(
      target: 'Review failed parser metadata within 1 business day',
      owner: 'Compliance support',
      escalation: 'Escalate raw reveal requests to compliance owner',
    ),
    'Groups' => const AdminQueueSla(
      target: 'Respond to group support requests within 1 business day',
      owner: 'Group operations',
      escalation: 'Escalate receiver-readiness blockers same day',
    ),
    'Members' => const AdminQueueSla(
      target: 'Respond to account support requests within 1 business day',
      owner: 'Member support',
      escalation: 'Escalate identity or access risk immediately',
    ),
    'Payment intents' => const AdminQueueSla(
      target: 'Review pending or expired intents within 1 business day',
      owner: 'Payments support',
      escalation: 'Escalate duplicate or disputed intent same day',
    ),
    'Receivers' => const AdminQueueSla(
      target: 'Review receiver setup changes within 1 business day',
      owner: 'Group operations',
      escalation: 'Escalate inactive receiver routes before launch',
    ),
    'Ledger' => const AdminQueueSla(
      target: 'Review ledger exceptions within 1 business day',
      owner: 'Finance operations',
      escalation: 'Escalate correction path before member messaging',
    ),
    'Audit logs' => const AdminQueueSla(
      target: 'Review sensitive audit events daily',
      owner: 'Compliance owner',
      escalation: 'Escalate unexplained sensitive access immediately',
    ),
    'Settings' => const AdminQueueSla(
      target: 'Review config changes before release window',
      owner: 'Platform owner',
      escalation: 'Escalate unapproved production change immediately',
    ),
    'Feature flags' => const AdminQueueSla(
      target: 'Review rollout flags before activation',
      owner: 'Product operations',
      escalation: 'Escalate degraded health signal immediately',
    ),
    'Admin users' => const AdminQueueSla(
      target: 'Review operator access weekly',
      owner: 'Platform owner',
      escalation: 'Revoke stale or overbroad access immediately',
    ),
    _ => const AdminQueueSla(
      target: 'Review queue daily',
      owner: 'Operations',
      escalation: 'Escalate stale review items',
    ),
  };
}
