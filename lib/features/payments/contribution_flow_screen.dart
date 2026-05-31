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
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
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
          label: 'Create payment intent',
          detail:
              'Collect links this amount to your 6-digit ID before MoMo opens.',
          chips: const [
            CollectStatusChip(
              label: 'Payment intent',
              tone: CollectStatusTone.info,
            ),
            CollectStatusChip(
              label: 'Collect ID',
              tone: CollectStatusTone.privacy,
            ),
          ],
        ),
        const SecurityNotice(
          title: 'Automated SMS match',
          message:
              'After MoMo payment, the MoMo SMS is parsed and matched to this intent automatically.',
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
              if (_error != null) ...[
                CollectSpacing.gap8,
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              CollectSpacing.gap16,
              CollectButton(
                label: 'Contribute',
                icon: CollectIcons.momo,
                onPressed: () async {
                  final amount = int.tryParse(_amount.text) ?? 0;
                  if (amount <= 0) {
                    setState(() {
                      _error = 'Contribution amount must be above zero';
                    });
                    return;
                  }
                  setState(() => _error = null);
                  final intent = await ref
                      .read(collectRepositoryProvider.notifier)
                      .createPaymentIntent(
                        PaymentIntentDraft(
                          collectionId: widget.collectionId,
                          amountRwf: amount,
                        ),
                      );
                  if (!context.mounted) return;
                  context.go(
                    '/groups/${widget.collectionId}/pay/${intent.id}/handoff',
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

@visibleForTesting
Uri momoUssdUri() => Uri.parse('tel:${Uri.encodeComponent('*182#')}');
