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
      subtitle: 'Confirmed support, posted immutably.',
      children: [
        MoneyHeroCard(
          amount: total,
          label: 'Confirmed total',
          detail: '${contributions.length} verified contributions',
          chips: const [
            CollectStatusChip(
              label: 'Immutable',
              tone: CollectStatusTone.success,
            ),
            CollectStatusChip(
              label: 'Private evidence',
              tone: CollectStatusTone.privacy,
            ),
          ],
        ),
        const SecurityNotice(
          title: 'Ledger safety',
          message:
              'Public feeds use safe labels. Raw SMS and phone fields stay restricted.',
        ),
        const SectionHeader(title: 'Confirmed activity'),
        if (contributions.isEmpty)
          const EmptyIllustrationState(
            icon: CollectIcons.ledger,
            title: 'No confirmed contributions',
            message: 'MOMO evidence will appear here after verification.',
          )
        else
          for (final contribution in contributions)
            LedgerRow.confirmed(contribution: contribution),
      ],
    );
  }
}
