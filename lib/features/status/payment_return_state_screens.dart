part of 'payment_status_screens.dart';

PaymentIntentModel? _safeIntent(CollectRepository repo, String intentId) {
  return repo.maybeIntentById(intentId);
}

class PaymentStateDetailScreen extends ConsumerWidget {
  const PaymentStateDetailScreen({
    required this.collectionId,
    required this.intentId,
    required this.state,
    super.key,
  });

  final String collectionId;
  final String intentId;
  final PaymentUiStatus state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collection = _safeCollection(ref, collectionId);
    final intent = _safeIntent(repo, intentId);
    final needsSupport =
        state == PaymentUiStatus.expired ||
        state == PaymentUiStatus.needsReview;
    final (title, message, tone) = switch (state) {
      PaymentUiStatus.confirmed => (
        'Payment confirmed',
        'Recorded on the group ledger.',
        CollectStatusTone.success,
      ),
      PaymentUiStatus.expired => (
        'Payment expired',
        'Start a fresh contribution.',
        CollectStatusTone.danger,
      ),
      PaymentUiStatus.needsReview => (
        'Payment needs review',
        'Support can match it safely.',
        CollectStatusTone.warning,
      ),
      PaymentUiStatus.pending => (
        'Payment pending',
        'Checking MoMo confirmation.',
        CollectStatusTone.info,
      ),
    };

    if (intent == null) {
      return ScreenScaffold(
        title: title,
        subtitle: collection?.title,
        children: [
          MinimalStatePanel(
            icon: _iconForTone(tone),
            title: 'Payment not on this device.',
            message:
                'Open the ledger, start a fresh contribution, or contact support.',
            tone: tone,
          ),
          CollectButton(
            label: state == PaymentUiStatus.expired
                ? 'Contribute again'
                : 'Open ledger',
            icon: state == PaymentUiStatus.expired
                ? CollectIcons.momo
                : CollectIcons.ledger,
            onPressed: () => context.go(
              state == PaymentUiStatus.expired
                  ? '/groups/$collectionId/contribute'
                  : '/groups/$collectionId/ledger',
            ),
            expand: true,
          ),
          const CollectButton(
            label: 'Get help',
            icon: CollectIcons.support,
            onPressed: openCollectWhatsAppSupport,
            variant: CollectButtonVariant.secondary,
            expand: true,
          ),
        ],
      );
    }

    return ScreenScaffold(
      title: title,
      subtitle: collection?.title,
      children: [
        if (state == PaymentUiStatus.confirmed)
          const PaymentVerifiedRing()
        else
          _PaymentStatusHero(
            icon: _iconForTone(tone),
            title: title,
            subtitle: message,
            tone: tone,
          ),
        _PaymentStateGuidance(
          status: state,
          meaning: _stateMeaning(state),
          nextAction: state == PaymentUiStatus.expired
              ? 'Contribute again'
              : 'Open ledger',
          fallback: _stateFallback(state),
        ),
        PaymentIntentStatusCard(
          amountRwf: intent.expectedAmountRwf,
          receiverLabel: intent.receiverLabel,
          receiverMomoNumber: intent.receiverMomoNumber,
          status: _statusForPipeline(state),
        ),
        PaymentPipelineIndicator(status: _statusForPipeline(state)),
        CollectCard(
          emphasis: CollectCardEmphasis.flat,
          child: Column(
            children: [
              CollectListTile(
                leading: _iconForTone(tone),
                title: _stateDetailTitle(state),
                subtitle: message,
              ),
              CollectListTile(
                leading: CollectIcons.privacy,
                title: 'Private review',
                subtitle: state == PaymentUiStatus.confirmed
                    ? 'Receiver details stay private.'
                    : 'No pasted SMS is shown in the group.',
              ),
            ],
          ),
        ),
        CollectButton(
          label: state == PaymentUiStatus.expired
              ? 'Contribute again'
              : 'Open ledger',
          icon: state == PaymentUiStatus.expired
              ? CollectIcons.momo
              : CollectIcons.ledger,
          onPressed: () => context.go(
            state == PaymentUiStatus.expired
                ? '/groups/$collectionId/contribute'
                : '/groups/$collectionId/ledger',
          ),
          expand: true,
        ),
        CollectButton(
          label: _secondaryStateActionLabel(state),
          icon: _secondaryStateActionIcon(state),
          onPressed: needsSupport
              ? () => context.go(
                  '/groups/$collectionId/support/payment/$intentId',
                )
              : () => context.go(_secondaryStateActionPath(state)),
          variant: CollectButtonVariant.secondary,
          expand: true,
        ),
      ],
    );
  }

  String _secondaryStateActionPath(PaymentUiStatus state) {
    return switch (state) {
      PaymentUiStatus.confirmed => '/groups/$collectionId',
      PaymentUiStatus.pending => '/groups/$collectionId/pay/$intentId',
      PaymentUiStatus.expired || PaymentUiStatus.needsReview => '/settings',
    };
  }
}

String _statusForPipeline(PaymentUiStatus state) {
  return switch (state) {
    PaymentUiStatus.confirmed => 'confirmed',
    PaymentUiStatus.expired => 'expired',
    PaymentUiStatus.needsReview => 'needs_review',
    PaymentUiStatus.pending => 'pending',
  };
}

String _stateDetailTitle(PaymentUiStatus state) {
  return switch (state) {
    PaymentUiStatus.confirmed => 'Ledger updated',
    PaymentUiStatus.expired => 'Expired',
    PaymentUiStatus.needsReview => 'Support review',
    PaymentUiStatus.pending => 'Payment pending',
  };
}

String _secondaryStateActionLabel(PaymentUiStatus state) {
  return switch (state) {
    PaymentUiStatus.confirmed => 'Open group',
    PaymentUiStatus.pending => 'View status',
    PaymentUiStatus.expired || PaymentUiStatus.needsReview => 'Get help',
  };
}

IconData _secondaryStateActionIcon(PaymentUiStatus state) {
  return switch (state) {
    PaymentUiStatus.confirmed => CollectIcons.collections,
    PaymentUiStatus.pending => CollectIcons.pending,
    PaymentUiStatus.expired ||
    PaymentUiStatus.needsReview => CollectIcons.support,
  };
}

String _stateMeaning(PaymentUiStatus state) {
  return switch (state) {
    PaymentUiStatus.confirmed => 'The ledger now includes this contribution.',
    PaymentUiStatus.expired => 'The old payment request can no longer be used.',
    PaymentUiStatus.needsReview =>
      'Collect could not safely match this payment automatically.',
    PaymentUiStatus.pending => 'Collect is still checking MoMo confirmation.',
  };
}

String _stateFallback(PaymentUiStatus state) {
  return switch (state) {
    PaymentUiStatus.confirmed => 'Open the group if you need more context.',
    PaymentUiStatus.expired => 'Get help if you already paid.',
    PaymentUiStatus.needsReview => 'Request support review.',
    PaymentUiStatus.pending => 'Return to status or open ledger.',
  };
}

class _PaymentStateGuidance extends StatelessWidget {
  const _PaymentStateGuidance({
    required this.status,
    required this.meaning,
    required this.nextAction,
    required this.fallback,
  });

  final PaymentUiStatus status;
  final String meaning;
  final String nextAction;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      emphasis: CollectCardEmphasis.flat,
      child: Column(
        children: [
          CollectListTile(
            leading: _stateGuidanceIcon(status),
            title: 'What this means',
            subtitle: meaning,
          ),
          CollectListTile(
            leading: status == PaymentUiStatus.expired
                ? CollectIcons.momo
                : CollectIcons.ledger,
            title: 'Next action',
            subtitle: nextAction,
          ),
          CollectListTile(
            leading: CollectIcons.support,
            title: 'Fallback',
            subtitle: fallback,
          ),
        ],
      ),
    );
  }
}

IconData _stateGuidanceIcon(PaymentUiStatus state) {
  return switch (state) {
    PaymentUiStatus.confirmed => CollectIcons.check,
    PaymentUiStatus.expired => CollectIcons.error,
    PaymentUiStatus.needsReview => CollectIcons.warning,
    PaymentUiStatus.pending => CollectIcons.pending,
  };
}
