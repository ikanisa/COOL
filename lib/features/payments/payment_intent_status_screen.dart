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
      actions: [
        IconButton.filledTonal(
          tooltip: 'Refresh',
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
        PaymentIntentStatusCard(
          amountRwf: intent.expectedAmountRwf,
          receiverLabel: intent.receiverLabel,
          receiverMomoNumber: intent.receiverMomoNumber,
          status: intent.status,
        ),
        PaymentPipelineIndicator(status: intent.status),
        InfoSecurityBanner(
          title: 'Reference',
          message:
              'Payment intent ${intent.id}. Collect posts to the ledger after receiver-side MoMo SMS verification.',
          tone: CollectStatusTone.privacy,
        ),
        CollectButton(
          label: 'Open ledger',
          icon: CollectIcons.ledger,
          onPressed: () => context.go('/groups/${widget.collectionId}/ledger'),
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
    PaymentUiStatus.confirmed => 'View confirmed state',
    PaymentUiStatus.expired => 'View retry options',
    PaymentUiStatus.needsReview => 'View review state',
    PaymentUiStatus.pending => 'View pending details',
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
