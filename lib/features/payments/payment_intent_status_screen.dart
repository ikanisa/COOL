import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/providers/collect_app_state.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class PaymentIntentStatusScreen extends ConsumerStatefulWidget {
  const PaymentIntentStatusScreen({
    required this.collectionId,
    required this.intentId,
    super.key,
  });

  final String collectionId;
  final String intentId;

  @override
  ConsumerState<PaymentIntentStatusScreen> createState() =>
      _PaymentIntentStatusScreenState();
}

class _PaymentIntentStatusScreenState
    extends ConsumerState<PaymentIntentStatusScreen> {
  bool _refreshing = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(collectRepositoryProvider.notifier);
    final uiStatus = ref.watch(
      paymentUiStatusProvider(
        PaymentStatusKey(
          collectionId: widget.collectionId,
          intentId: widget.intentId,
        ),
      ),
    );
    final intent = repo.intentById(widget.intentId);
    final collection = repo.collectionById(widget.collectionId);

    return ScreenScaffold(
      title: 'Payment',
      subtitle: collection.title,
      showHeader: false,
      persistentPill: CollectTopChrome(
        avatarLabel: ref.watch(
          collectRepositoryProvider.select(
            (state) => state.currentProfile?.publicId,
          ),
        ),
        searchLabel: collection.title,
        onAvatarTap: () => context.go('/settings/profile'),
        actions: [
          CollectTopChromeAction(
            icon: _refreshing ? CollectIcons.pending : CollectIcons.sync,
            tooltip: 'Refresh',
            onPressed: _refreshing ? null : _refreshStatus,
          ),
          CollectTopChromeAction(
            icon: CollectIcons.ledger,
            tooltip: 'Open ledger',
            onPressed: () =>
                context.go('/groups/${widget.collectionId}/ledger'),
          ),
        ],
      ),
      bottomAction: BottomActionSurface(
        children: [
          CollectButton(
            label: 'Open ledger',
            icon: CollectIcons.ledger,
            onPressed: () =>
                context.go('/groups/${widget.collectionId}/ledger'),
            expand: true,
          ),
          CollectButton(
            label: _stateActionLabel(uiStatus),
            icon: _stateActionIcon(uiStatus),
            onPressed: () => context.go(
              '/groups/${widget.collectionId}/pay/${widget.intentId}/state/${_statePath(uiStatus)}',
            ),
            variant: CollectButtonVariant.secondary,
            expand: true,
          ),
          if (uiStatus == PaymentUiStatus.expired ||
              uiStatus == PaymentUiStatus.needsReview)
            CollectButton(
              label: 'Support review',
              icon: CollectIcons.support,
              onPressed: () => context.go(
                '/groups/${widget.collectionId}/support/payment/${widget.intentId}',
              ),
              variant: CollectButtonVariant.subtle,
              expand: true,
            ),
        ],
      ),
      children: [
        if (_error != null)
          InfoSecurityBanner(
            title: 'Refresh failed',
            message: _error!,
            tone: CollectStatusTone.warning,
          ),
        CollectCard(
          emphasis: CollectCardEmphasis.glow,
          accentColor: context.collectColors.statusForeground(
            paymentStatusTone(intent.status),
          ),
          child: Row(
            children: [
              CollectStatusChip(
                label: paymentStatusLabel(intent.status),
                tone: paymentStatusTone(intent.status),
                icon: _stateActionIcon(uiStatus),
              ),
              CollectSpacing.gapW12,
              Expanded(
                child: Text(
                  _statusMessage(uiStatus),
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        PaymentIntentStatusCard(
          amountRwf: intent.expectedAmountRwf,
          receiverLabel: intent.receiverLabel,
          receiverMomoNumber: intent.receiverMomoNumber,
          status: intent.status,
        ),
        PaymentPipelineIndicator(status: intent.status),
        const CollectCard(
          emphasis: CollectCardEmphasis.flat,
          child: Column(
            children: [
              CollectListTile(
                leading: CollectIcons.sms,
                title: 'MoMo SMS',
                subtitle: 'Used to confirm payment status.',
              ),
              CollectListTile(
                leading: CollectIcons.ledger,
                title: 'Ledger',
                subtitle: 'Updated after verification.',
              ),
              CollectListTile(
                leading: CollectIcons.privacy,
                title: 'Privacy',
                subtitle: 'No private credentials or message bodies shown.',
              ),
            ],
          ),
        ),
      ],
    );
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

String _statePath(PaymentUiStatus status) {
  return switch (status) {
    PaymentUiStatus.confirmed => 'confirmed',
    PaymentUiStatus.expired => 'expired',
    PaymentUiStatus.needsReview => 'needs-review',
    PaymentUiStatus.pending => 'pending',
  };
}

String _stateActionLabel(PaymentUiStatus status) {
  return switch (status) {
    PaymentUiStatus.confirmed => 'Confirmed',
    PaymentUiStatus.expired => 'Retry',
    PaymentUiStatus.needsReview => 'Review',
    PaymentUiStatus.pending => 'Status',
  };
}

IconData _stateActionIcon(PaymentUiStatus status) {
  return switch (status) {
    PaymentUiStatus.confirmed => CollectIcons.check,
    PaymentUiStatus.expired => CollectIcons.error,
    PaymentUiStatus.needsReview => CollectIcons.warning,
    PaymentUiStatus.pending => CollectIcons.pending,
  };
}

String _statusMessage(PaymentUiStatus status) {
  return switch (status) {
    PaymentUiStatus.confirmed => 'Recorded on the group ledger.',
    PaymentUiStatus.expired => 'Start a fresh contribution.',
    PaymentUiStatus.needsReview => 'Support review is available.',
    PaymentUiStatus.pending => 'Waiting for MoMo SMS verification.',
  };
}
