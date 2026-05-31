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
        MoneyHeroCard(amount: int.tryParse(_amount.text) ?? 0, label: ''),
        CollectCard(
          padding: CollectSpacing.cardPaddingComfortable,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Amount', style: Theme.of(context).textTheme.titleMedium),
              CollectSpacing.gap12,
              AmountInput(controller: _amount),
              CollectSpacing.gap12,
              Wrap(
                spacing: CollectSpacing.x2,
                runSpacing: CollectSpacing.x2,
                children: [
                  for (final option in const [1000, 5000, 10000, 20000])
                    ChoiceChip(
                      label: Text(_quickAmountLabel(option)),
                      selected: int.tryParse(_amount.text) == option,
                      onSelected: (_) => setState(() {
                        _amount.text = option.toString();
                        _error = null;
                      }),
                    ),
                ],
              ),
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
                      _error = 'Enter an amount above zero.';
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

String _quickAmountLabel(int amount) {
  return switch (amount) {
    1000 => '1k',
    5000 => '5k',
    10000 => '10k',
    20000 => '20k',
    _ => amount.toString(),
  };
}
