part of 'payment_status_screens.dart';

class ReturnFromMomoWaitingScreen extends ConsumerStatefulWidget {
  const ReturnFromMomoWaitingScreen({
    required this.collectionId,
    required this.intentId,
    super.key,
  });

  final String collectionId;
  final String intentId;

  @override
  ConsumerState<ReturnFromMomoWaitingScreen> createState() =>
      _ReturnFromMomoWaitingScreenState();
}

class _ReturnFromMomoWaitingScreenState
    extends ConsumerState<ReturnFromMomoWaitingScreen> {
  bool _refreshing = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collection = repo.maybeCollectionById(widget.collectionId);
    if (collection == null) return const MissingGroupStateScreen();
    final intent = _safeIntent(repo, widget.intentId);

    if (intent == null) {
      return ScreenScaffold(
        title: 'Payment not found',
        subtitle: collection.title,
        children: [
          const MinimalStatePanel(
            icon: CollectIcons.warning,
            title: 'Payment not on this device.',
            message: 'Start a fresh contribution or ask support to review it.',
            tone: CollectStatusTone.warning,
          ),
          CollectButton(
            label: 'Contribute again',
            icon: CollectIcons.momo,
            onPressed: () =>
                context.go('/groups/${widget.collectionId}/contribute'),
            expand: true,
          ),
          CollectButton(
            label: 'Get help',
            icon: CollectIcons.support,
            onPressed: () => context.go(
              '/groups/${widget.collectionId}/support/payment/${widget.intentId}',
            ),
            variant: CollectButtonVariant.secondary,
            expand: true,
          ),
        ],
      );
    }

    return ScreenScaffold(
      title: 'Waiting for SMS',
      subtitle: collection.title,
      actions: [
        IconButton.filledTonal(
          tooltip: 'Refresh payment status',
          onPressed: _refreshing ? null : _refreshStatus,
          icon: Icon(_refreshing ? CollectIcons.pending : CollectIcons.sync),
        ),
      ],
      children: [
        if (_error != null)
          InfoSecurityBanner(
            title: 'Refresh failed',
            message: _error!,
            tone: CollectStatusTone.warning,
          ),
        const _PaymentStatusHero(
          icon: CollectIcons.sms,
          title: 'Waiting for MoMo SMS',
          subtitle: 'Keep this phone online after approving MoMo.',
          tone: CollectStatusTone.info,
        ),
        PaymentIntentStatusCard(
          amountRwf: intent.expectedAmountRwf,
          receiverLabel: intent.receiverLabel,
          receiverMomoNumber: intent.receiverMomoNumber,
          status: intent.status,
        ),
        const PaymentPipelineIndicator(status: 'pending'),
        CollectCard(
          emphasis: CollectCardEmphasis.flat,
          child: Column(
            children: [
              CollectListTile(
                leading: CollectIcons.pending,
                title: 'Started',
                subtitle: _relativeAge(intent.createdAt),
              ),
              CollectListTile(
                leading: CollectIcons.warning,
                title: 'Expires',
                subtitle: _relativeExpiry(intent.expiresAt),
              ),
              const CollectListTile(
                leading: CollectIcons.privacy,
                title: 'Private review',
                subtitle: 'Support can review without pasted SMS text.',
              ),
            ],
          ),
        ),
        CollectButton(
          label: 'Refresh status',
          icon: CollectIcons.pending,
          onPressed: _refreshing ? null : _refreshStatus,
          expand: true,
        ),
        CollectButton(
          label: 'View status',
          icon: CollectIcons.ledger,
          onPressed: () => context.go(
            '/groups/${widget.collectionId}/pay/${widget.intentId}',
          ),
          variant: CollectButtonVariant.secondary,
          expand: true,
        ),
        CollectButton(
          label: 'Open MoMo again',
          icon: CollectIcons.momo,
          onPressed: _openMomoAgain,
          variant: CollectButtonVariant.secondary,
          expand: true,
        ),
        const CollectButton(
          label: 'Get help',
          icon: CollectIcons.support,
          onPressed: openCollectWhatsAppSupport,
          variant: CollectButtonVariant.subtle,
          expand: true,
        ),
      ],
    );
  }

  Future<void> _openMomoAgain() async {
    try {
      await launchUrl(_momoUssdUri(), mode: LaunchMode.externalApplication);
    } catch (_) {
      // Browser and desktop test shells often cannot handle tel: links.
    }
  }

  Future<void> _refreshStatus() async {
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      await ref
          .read(collectRepositoryProvider.notifier)
          .refreshPaymentIntent(widget.intentId);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }
}

PaymentIntentModel? _safeIntent(CollectRepository repo, String intentId) {
  return repo.maybeIntentById(intentId);
}

String _relativeAge(DateTime startedAt) {
  final elapsed = DateTime.now().difference(startedAt);
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) {
    return '${elapsed.inMinutes} minute${elapsed.inMinutes == 1 ? '' : 's'} ago';
  }
  if (elapsed.inDays < 1) {
    return '${elapsed.inHours} hour${elapsed.inHours == 1 ? '' : 's'} ago';
  }
  return '${elapsed.inDays} day${elapsed.inDays == 1 ? '' : 's'} ago';
}

String _relativeExpiry(DateTime expiresAt) {
  final remaining = expiresAt.difference(DateTime.now());
  if (remaining.isNegative) return 'now';
  if (remaining.inMinutes < 1) return 'in less than 1 minute';
  if (remaining.inHours < 1) {
    return 'in ${remaining.inMinutes} minute${remaining.inMinutes == 1 ? '' : 's'}';
  }
  if (remaining.inDays < 1) {
    return 'in ${remaining.inHours} hour${remaining.inHours == 1 ? '' : 's'}';
  }
  return 'in ${remaining.inDays} day${remaining.inDays == 1 ? '' : 's'}';
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
        'Support can review the payment safely.',
        CollectStatusTone.warning,
      ),
      PaymentUiStatus.pending => (
        'Payment pending',
        'Waiting for MoMo SMS verification.',
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
                    ? 'Receiver details stay inside owner and payment screens.'
                    : 'No pasted SMS text is shown in the group.',
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
    PaymentUiStatus.pending => 'Waiting for SMS',
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
