import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/amount_input.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class ContributionFlowScreen extends ConsumerStatefulWidget {
  const ContributionFlowScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  ConsumerState<ContributionFlowScreen> createState() =>
      _ContributionFlowScreenState();
}

class _ContributionFlowScreenState
    extends ConsumerState<ContributionFlowScreen> {
  final _amount = TextEditingController(text: '5000');
  final _sender = TextEditingController();
  String _anonymity = 'anonymous';

  @override
  void dispose() {
    _amount.dispose();
    _sender.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collection = ref
        .read(collectRepositoryProvider.notifier)
        .collectionById(widget.collectionId);
    return ScreenScaffold(
      title: 'Contribute',
      subtitle: collection.title,
      children: [
        MoneyHeroCard(
          amount: int.tryParse(_amount.text) ?? 0,
          label: 'Prepare direct MOMO',
          detail: 'You stay in control. Collect only verifies evidence.',
          chips: const [
            CollectStatusChip(
              label: 'Step 1 of 2',
              tone: CollectStatusTone.info,
            ),
            CollectStatusChip(
              label: 'No money held',
              tone: CollectStatusTone.privacy,
            ),
          ],
        ),
        const SecurityNotice(
          title: 'Direct payment',
          message:
              'Collect does not move money. Pay directly through MOMO, then verification comes from receiver notification.',
          tone: CollectStatusTone.privacy,
        ),
        CollectCard(
          padding: CollectSpacing.cardPaddingComfortable,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Amount', style: Theme.of(context).textTheme.titleMedium),
              CollectSpacing.gap12,
              AmountInput(controller: _amount),
              CollectSpacing.gap16,
              Text(
                'Public identity',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              CollectSpacing.gap8,
              PremiumSegmentedFilter<String>(
                values: const ['anonymous', 'public_id', 'display_name'],
                selected: _anonymity,
                labelFor: (value) => switch (value) {
                  'public_id' => 'User ID',
                  'display_name' => 'Name',
                  _ => 'Anonymous',
                },
                onChanged: (value) => setState(() => _anonymity = value),
              ),
              CollectSpacing.gap12,
              TextField(
                controller: _sender,
                keyboardType: TextInputType.phone,
                decoration: collectInputDecoration(
                  context,
                  label: 'Sender MOMO phone, optional',
                  helper: 'Used only to improve matching; never public.',
                ),
              ),
              CollectSpacing.gap16,
              CollectButton(
                label: 'Continue to MOMO instructions',
                icon: CollectIcons.momo,
                onPressed: () async {
                  final intent = await ref
                      .read(collectRepositoryProvider.notifier)
                      .createPaymentIntent(
                        PaymentIntentDraft(
                          collectionId: widget.collectionId,
                          amountRwf: int.tryParse(_amount.text) ?? 0,
                          anonymityChoice: _anonymity,
                          senderPhone: _sender.text,
                        ),
                      );
                  if (!context.mounted) return;
                  context.go(
                    '/collections/${widget.collectionId}/pay/${intent.id}',
                  );
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
