import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/repositories/collect_repository.dart';
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
  @override
  Widget build(BuildContext context) {
    final repo = ref.read(collectRepositoryProvider.notifier);
    final intent = repo.intentById(widget.intentId);
    final collection = repo.collectionById(widget.collectionId);

    return ScreenScaffold(
      title: 'Payment intent',
      subtitle: collection.title,
      children: [
        const InsightCard(
          title: 'Waiting for MoMo SMS',
          message:
              'Complete the MoMo payment off app. Confirmation is posted automatically after SMS parsing and allocation.',
          icon: CollectIcons.momo,
          tone: CollectStatusTone.info,
        ),
        PaymentIntentStatusCard(
          amountRwf: intent.expectedAmountRwf,
          receiverLabel: intent.receiverLabel,
          receiverMomoNumber: intent.receiverMomoNumber,
          contributionCode: intent.contributionCode,
          network: intent.network,
          status: intent.status,
        ),
        CollectCard(
          padding: CollectSpacing.cardPaddingComfortable,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SMS confirmation',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              CollectSpacing.gap8,
              Text(
                'Do not paste SMS or payment references. The MoMo SMS is ingested, parsed, and allocated automatically.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              CollectSpacing.gap16,
              CollectButton(
                label: 'Open ledger',
                icon: CollectIcons.ledger,
                onPressed: () =>
                    context.go('/groups/${widget.collectionId}/ledger'),
                expand: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
