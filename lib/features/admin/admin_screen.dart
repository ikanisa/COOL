import 'package:flutter/material.dart';

import '../../shared/widgets/collect_components.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenScaffoldLayout(
      title: 'Admin approval',
      subtitle:
          'Dense review for public requests, payment states, and receiver risk.',
      children: [
        InfoSecurityBanner(
          title: 'Admin review',
          message:
              'Collect does not move money. Admin review verifies visibility and risk without exposing phone, MOMO, or raw SMS publicly.',
          tone: CollectStatusTone.privacy,
        ),
        SectionHeader(title: 'Public directory approval'),
        AdminReviewCard(
          title: 'Kigali Lions away kit',
          status: 'pending',
          detail:
              'Review public listing only. Receiver phone, MOMO number, raw SMS, and private supporter identity stay hidden from public surfaces.',
          confidence: .86,
          primaryLabel: 'Approve',
          secondaryLabel: 'Reject',
        ),
        SectionHeader(title: 'Unallocated MOMO review'),
        AdminReviewCard(
          title: 'AMB-901',
          status: 'needs_review',
          detail:
              'Low-confidence MOMO event. Admin must verify collection, amount, and transaction code before ledger allocation.',
          amountRwf: 15000,
          confidence: .78,
          primaryLabel: 'Mark reviewed',
        ),
      ],
    );
  }
}
