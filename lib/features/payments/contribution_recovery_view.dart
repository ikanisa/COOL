part of 'contribution_flow_screen.dart';

class _ContributionRecoveryView extends StatelessWidget {
  const _ContributionRecoveryView({
    required this.groupTitle,
    required this.collectionId,
    required this.recovery,
    required this.unverified,
    required this.showPaymentHelp,
    required this.restoring,
    required this.recoveryReadFailed,
    required this.working,
    required this.error,
    required this.copyDetails,
    required this.onPaymentHelp,
    required this.onCheck,
  });

  final String groupTitle;
  final String collectionId;
  final ContributionCommandCheckpoint? recovery;
  final PaymentIntentModel? unverified;
  final bool showPaymentHelp;
  final bool restoring;
  final bool recoveryReadFailed;
  final bool working;
  final String? error;
  final void Function(String, String) copyDetails;
  final VoidCallback onPaymentHelp;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final recovery = this.recovery;
    final unverified = this.unverified;
    final error = this.error;
    return Scaffold(
      backgroundColor: context.collectColors.canvas,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 430,
            height: double.infinity,
            child: forms.CollectFormViewport(
              maxWidth: 430,
              header: _NativeContributionAppBar(
                title: groupTitle,
                onBack: () => context.go('/groups/$collectionId'),
              ),
              bodyPadding: const EdgeInsets.all(CollectSpacing.x5),
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _NativeMomoStatus(
                    title: restoring
                        ? 'Checking saved requests'
                        : recovery == null && unverified == null
                        ? 'Saved requests unavailable'
                        : 'Check your original request',
                    message: restoring
                        ? 'Loading protected payment recovery.'
                        : 'A payment outcome may be unknown. Check this request and your mobile money provider before another transfer.',
                  ),
                  if (recovery != null) ...[
                    CollectSpacing.gap20,
                    Text(
                      formatRwf(recovery.body.amountRwf),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    CollectSpacing.gap12,
                    SelectableText('Request ${recovery.body.requestId}'),
                    TextButton.icon(
                      onPressed: working
                          ? null
                          : () => copyDetails(
                              'Collect contribution request: ${recovery.body.requestId}\n'
                                  'Group: ${recovery.body.collectionId}\nAmount: ${recovery.body.amountRwf} RWF\n'
                                  'Outcome unknown; no new payment or support acknowledgement is confirmed.',
                              'Request details',
                            ),
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Copy request details'),
                    ),
                    CollectSpacing.gap12,
                    const Text(
                      'For help, contact Collect at info@ikanisa.com or +250 795 588 248 and share these request details. '
                      'Copying details does not send a support request.',
                    ),
                  ] else if (unverified != null) ...[
                    CollectSpacing.gap20,
                    Text(
                      formatRwf(unverified.expectedAmountRwf),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    CollectSpacing.gap12,
                    SelectableText('Payment request ${unverified.id}'),
                    if (unverified.hasCommittedContribution)
                      const Text(
                        'A contribution was previously recorded. Check Activity for its latest status.',
                      ),
                  ],
                  if (showPaymentHelp) ...[
                    CollectSpacing.gap12,
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: working || restoring || recoveryReadFailed
                            ? null
                            : onPaymentHelp,
                        icon: const Icon(CollectIcons.support),
                        label: const Text('Payment help'),
                      ),
                    ),
                  ] else if (unverified != null && recovery == null) ...[
                    CollectSpacing.gap12,
                    const Text(
                      'For help, contact Collect at info@ikanisa.com or +250 795 588 248 and share the payment request ID above.',
                    ),
                  ],
                  if (error != null) ...[
                    CollectSpacing.gap16,
                    _NativeMomoStatus(
                      title: 'Status could not be confirmed',
                      message: error,
                      isError: true,
                    ),
                  ],
                ],
              ),
              actions: _NativeContributionBottomBar(
                primaryLabel: restoring || working
                    ? 'Checking request'
                    : 'Check request',
                primaryIcon: Icons.refresh_rounded,
                onPrimary: restoring || working ? null : onCheck,
                secondaryLabel: 'Back to group',
                onSecondary: () => context.go('/groups/$collectionId'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
