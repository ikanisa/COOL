part of 'collect_financial_components.dart';

class BankTransferPipelineIndicator extends StatelessWidget {
  const BankTransferPipelineIndicator({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final activeStep = _pipelineStep(status);
    const stages = [
      (label: 'Prepared', icon: CollectIcons.pending),
      (label: 'Evidence', icon: CollectIcons.sms),
      (label: 'Reconciled', icon: CollectIcons.ledger),
    ];
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Bank transfer progress: ${paymentStatusLabel(status)}',
      child: CollectCard(
        emphasis: CollectCardEmphasis.flat,
        padding: const EdgeInsets.all(CollectSpacing.x4),
        child: Row(
          children: [
            for (var index = 0; index < stages.length; index++) ...[
              Expanded(
                child: _PipelineStage(
                  label: stages[index].label,
                  icon: stages[index].icon,
                  complete: activeStep > index,
                  current: activeStep == index,
                ),
              ),
              if (index != stages.length - 1)
                Expanded(child: _PipelineLine(active: activeStep > index + 1)),
            ],
          ],
        ),
      ),
    );
  }
}

int _pipelineStep(String status) {
  return switch (status) {
    'reconciled' || 'confirmed' => 3,
    'received_unreconciled' || 'needs_review' || 'review' => 2,
    'expired' || 'failed' => 1,
    _ => 1,
  };
}

class _PipelineStage extends StatelessWidget {
  const _PipelineStage({
    required this.label,
    required this.icon,
    required this.complete,
    required this.current,
  });

  final String label;
  final IconData icon;
  final bool complete;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final tone = complete
        ? CollectStatusTone.success
        : current
        ? CollectStatusTone.info
        : CollectStatusTone.neutral;
    final foreground = colors.statusForeground(tone);
    final stateLabel = complete
        ? 'complete'
        : current
        ? 'current'
        : 'pending';
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '$label step $stateLabel',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.statusBackground(tone),
              border: Border.all(
                color: CollectRuntimeTokens.badgeBorder(colors, foreground),
              ),
            ),
            child: SizedBox.square(
              dimension: 38,
              child: Icon(
                complete ? CollectIcons.check : icon,
                color: foreground,
              ),
            ),
          ),
          CollectSpacing.gap8,
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: CollectTypography.weightBold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PipelineLine extends StatelessWidget {
  const _PipelineLine({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Container(
        height: 3,
        decoration: BoxDecoration(
          color: CollectRuntimeTokens.paymentStepLine(colors, active: active),
          borderRadius: CollectRadius.pillBorder,
        ),
      ),
    );
  }
}
