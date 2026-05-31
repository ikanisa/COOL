import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class LedgerScreen extends ConsumerWidget {
  const LedgerScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contributions = ref.watch(
      contributionsForCollectionProvider(collectionId),
    );
    final total = contributions.fold<int>(
      0,
      (sum, item) => sum + item.amountRwf,
    );

    return ScreenScaffold(
      title: 'Ledger',
      children: [
        MoneyHeroCard(
          amount: total,
          label: '',
          detail: '${contributions.length} entries',
        ),
        const SectionHeader(title: 'Activity'),
        if (contributions.isEmpty)
          const EmptyIllustrationState(
            icon: CollectIcons.ledger,
            title: 'No support',
            message: '',
          )
        else
          for (final contribution in contributions)
            LedgerRow.confirmed(contribution: contribution),
      ],
    );
  }
}
