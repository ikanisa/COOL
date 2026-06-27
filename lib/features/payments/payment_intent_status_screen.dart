import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/collect_models.dart';
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
    final appState = ref.watch(collectRepositoryProvider);
    final uiStatus = ref.watch(
      paymentUiStatusProvider(
        PaymentStatusKey(
          collectionId: widget.collectionId,
          intentId: widget.intentId,
        ),
      ),
    );
    final intent = _maybeIntent(appState.paymentIntents, widget.intentId);
    final collection = _maybeCollection(
      appState.collections,
      widget.collectionId,
    );
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    if (intent == null || collection == null) {
      return ScreenScaffold(
        title: 'Payment',
        subtitle: 'Status unavailable',
        showHeader: false,
        persistentPill: CollectTopChrome(
          avatarLabel: appState.currentProfile?.publicId,
          searchLabel: 'Payment status',
          onAvatarTap: () => context.go('/settings/profile'),
          actions: [
            CollectTopChromeAction(
              icon: CollectIcons.ledger,
              tooltip: 'Open groups',
              onPressed: () => context.go('/groups'),
            ),
          ],
        ),
        bottomAction: BottomActionSurface(
          children: [
            CollectButton(
              label: 'Open groups',
              icon: CollectIcons.collections,
              onPressed: () => context.go('/groups'),
              expand: true,
            ),
            CollectButton(
              label: 'Payment help',
              icon: CollectIcons.support,
              onPressed: () => context.go('/settings/help'),
              variant: CollectButtonVariant.secondary,
              expand: true,
            ),
          ],
        ),
        children: const [
          MinimalStatePanel(
            icon: CollectIcons.pending,
            title: 'Payment status is loading.',
            message:
                'Open the group again if this payment was already completed or expired.',
            tone: CollectStatusTone.info,
          ),
        ],
      );
    }

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
            label: _primaryPaymentActionLabel(uiStatus),
            icon: _primaryPaymentActionIcon(uiStatus),
            onPressed: _primaryPaymentAction(uiStatus),
            expand: true,
          ),
          CollectButton(
            label: 'Payment details',
            icon: _stateActionIcon(uiStatus),
            onPressed: () => context.go(
              '/groups/${widget.collectionId}/pay/${widget.intentId}/state/${_statePath(uiStatus)}',
            ),
            variant: CollectButtonVariant.secondary,
            expand: true,
          ),
          if (uiStatus != PaymentUiStatus.confirmed)
            CollectButton(
              label: 'Open ledger',
              icon: CollectIcons.ledger,
              onPressed: () =>
                  context.go('/groups/${widget.collectionId}/ledger'),
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
          child: textScale > 1.3
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CollectStatusChip(
                      label: paymentStatusLabel(intent.status),
                      tone: paymentStatusTone(intent.status),
                      icon: _stateActionIcon(uiStatus),
                    ),
                    CollectSpacing.gap8,
                    Text(
                      _statusMessage(uiStatus),
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.clip,
                    ),
                  ],
                )
              : Row(
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
                        softWrap: true,
                        overflow: TextOverflow.clip,
                      ),
                    ),
                  ],
                ),
        ),
        const CollectVisualFeatureCard(
          asset: 'assets/brand/generated/collect_visual_momo_signal.png',
          title: 'Verification trail',
          message: 'SMS confirms before ledger update.',
          icon: CollectIcons.sms,
          tone: CollectStatusTone.privacy,
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

  String _primaryPaymentActionLabel(PaymentUiStatus status) {
    return switch (status) {
      PaymentUiStatus.confirmed => 'Open ledger',
      PaymentUiStatus.expired => 'Contribute again',
      PaymentUiStatus.needsReview => 'Request review',
      PaymentUiStatus.pending => _refreshing ? 'Refreshing' : 'Refresh status',
    };
  }

  IconData _primaryPaymentActionIcon(PaymentUiStatus status) {
    return switch (status) {
      PaymentUiStatus.confirmed => CollectIcons.ledger,
      PaymentUiStatus.expired => CollectIcons.momo,
      PaymentUiStatus.needsReview => CollectIcons.support,
      PaymentUiStatus.pending => CollectIcons.sync,
    };
  }

  VoidCallback? _primaryPaymentAction(PaymentUiStatus status) {
    if (_refreshing) return null;
    return switch (status) {
      PaymentUiStatus.confirmed => () => context.go(
        '/groups/${widget.collectionId}/ledger',
      ),
      PaymentUiStatus.expired => () => context.go(
        '/groups/${widget.collectionId}/contribute',
      ),
      PaymentUiStatus.needsReview => () => context.go(
        '/groups/${widget.collectionId}/support/payment/${widget.intentId}',
      ),
      PaymentUiStatus.pending => _refreshStatus,
    };
  }
}

PaymentIntentModel? _maybeIntent(List<PaymentIntentModel> intents, String id) {
  for (final intent in intents) {
    if (intent.id == id) return intent;
  }
  return null;
}

CollectCollection? _maybeCollection(
  List<CollectCollection> collections,
  String id,
) {
  for (final collection in collections) {
    if (collection.id == id) return collection;
  }
  return null;
}

String _statePath(PaymentUiStatus status) {
  return switch (status) {
    PaymentUiStatus.confirmed => 'confirmed',
    PaymentUiStatus.expired => 'expired',
    PaymentUiStatus.needsReview => 'needs-review',
    PaymentUiStatus.pending => 'pending',
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
    PaymentUiStatus.confirmed => 'Confirmed and recorded on the ledger.',
    PaymentUiStatus.expired => 'This payment expired. Start again.',
    PaymentUiStatus.needsReview => 'Support can match this safely.',
    PaymentUiStatus.pending => 'Checking MoMo confirmation.',
  };
}
