import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/money_format.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class PaymentInstructionsScreen extends ConsumerStatefulWidget {
  const PaymentInstructionsScreen({
    required this.collectionId,
    required this.intentId,
    super.key,
  });

  final String collectionId;
  final String intentId;

  @override
  ConsumerState<PaymentInstructionsScreen> createState() =>
      _PaymentInstructionsScreenState();
}

class _PaymentInstructionsScreenState
    extends ConsumerState<PaymentInstructionsScreen> {
  final _transactionId = TextEditingController();

  @override
  void dispose() {
    _transactionId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(collectRepositoryProvider.notifier);
    final intent = repo.intentById(widget.intentId);
    final collection = repo.collectionById(widget.collectionId);
    final instructions =
        intent.instructionBody ??
        'Dial your MOMO or Airtel Money USSD menu, send ${formatRwf(intent.expectedAmountRwf)} to ${intent.receiverMomoNumber}, and use code ${intent.contributionCode} as reference when the menu allows it.';

    return ScreenScaffold(
      title: 'MOMO instructions',
      subtitle: collection.title,
      children: [
        const InsightCard(
          title: 'Step 2 of 2',
          message:
              'Send from your MOMO app or USSD menu, then come back and mark it paid.',
          icon: CollectIcons.momo,
          tone: CollectStatusTone.info,
        ),
        MomoInstructionCard(
          amountRwf: intent.expectedAmountRwf,
          receiverLabel: intent.receiverLabel,
          receiverMomoNumber: intent.receiverMomoNumber,
          contributionCode: intent.contributionCode,
          instructionTitle: intent.instructionTitle,
          network: intent.network,
          instructions: instructions,
          status: intent.status,
          onCopy: () => copyToClipboard(
            context,
            '${intent.receiverMomoNumber}\n$instructions',
            message: 'MOMO instructions copied.',
          ),
        ),
        CollectCard(
          padding: CollectSpacing.cardPaddingComfortable,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'After paying',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              CollectSpacing.gap8,
              Text(
                'Paste the transaction ID if you have it. Collect will still verify against receiver notifications.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              CollectSpacing.gap12,
              TextField(
                controller: _transactionId,
                decoration: collectInputDecoration(
                  context,
                  label: 'Transaction ID/reference, optional',
                ),
              ),
              CollectSpacing.gap16,
              CollectButton(
                label: 'Mark as paid',
                icon: CollectIcons.check,
                onPressed: () async {
                  await repo.markIntentPaid(
                    widget.intentId,
                    transactionId: _transactionId.text,
                  );
                  if (!context.mounted) return;
                  context.go('/collections/${widget.collectionId}/ledger');
                },
                expand: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
