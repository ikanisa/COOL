import 'package:flutter/material.dart';

import '../../shared/widgets/collect_components.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenScaffoldLayout(
      title: 'Admin operations',
      subtitle: 'SMS ingestion, payment intents, allocations, and ledger.',
      children: [
        InfoSecurityBanner(
          title: 'Realtime operations',
          message:
              'Admin monitors MoMo SMS rows, parser output, pending intents, allocation status, groups, members, and exceptions.',
          tone: CollectStatusTone.privacy,
        ),
        SectionHeader(title: 'Payment intent monitoring'),
        AdminReviewCard(
          title: 'INT-038491-5000',
          status: 'pending',
          detail:
              'Pending member intent linked to group, receiver MoMo number, amount, and 6-digit Collect ID.',
          confidence: .92,
          primaryLabel: 'Open intent',
        ),
        SectionHeader(title: 'Allocation exceptions'),
        AdminReviewCard(
          title: 'SMS-AMB-901',
          status: 'exception',
          detail:
              'Parser output did not match a pending payment intent. Keep out of ledger until automated allocation is resolved.',
          amountRwf: 15000,
          confidence: .78,
          primaryLabel: 'Open exception',
        ),
      ],
    );
  }
}
