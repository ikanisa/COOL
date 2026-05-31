import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../shared/models/collect_models.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class DesignSystemCatalogScreen extends StatelessWidget {
  const DesignSystemCatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const CollectErrorState(
        title: 'Catalog unavailable',
        message: 'The design system catalog is available only in debug builds.',
      );
    }
    final now = DateTime(2026, 5, 23, 10, 30);
    final contribution = Contribution(
      id: 'demo-contribution',
      collectionId: 'demo',
      amountRwf: 25000,
      supporterLabel: '#038491',
      createdAt: now,
      transactionId: 'MTN12345',
    );
    final event = ParsedPaymentEvent(
      id: 'demo-event',
      amountRwf: 15000,
      transactionId: 'AMB-901',
      senderLabel: 'SMS',
      allocationStatus: 'needs_review',
      confidence: .78,
      createdAt: now,
    );
    return ScreenScaffold(
      title: 'Collect Premium',
      subtitle: 'Debug catalog for tokens, components, motion, and states.',
      children: [
        const InfoSecurityBanner(
          title: 'Reference boundary',
          message:
              'Collect uses original tokens and components. No reference brand assets, fonts, colors, or screens are copied.',
          tone: CollectStatusTone.info,
        ),
        const MoneyHeroCard(
          amount: 125000,
          label: 'Total',
          detail: '2 groups',
          primaryAction: CollectButton(
            label: 'Primary action',
            icon: CollectIcons.arrowForward,
          ),
        ),
        const SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              QuickActionButton(
                icon: CollectIcons.add,
                label: 'Create',
                detail: 'New group',
              ),
              CollectSpacing.gapW12,
              QuickActionButton(
                icon: CollectIcons.momo,
                label: 'Pay',
                detail: 'Direct',
                tone: CollectStatusTone.privacy,
              ),
              CollectSpacing.gapW12,
              QuickActionButton(
                icon: CollectIcons.ledger,
                label: 'Ledger',
                detail: 'Activity',
                tone: CollectStatusTone.success,
              ),
            ],
          ),
        ),
        const CollectCard(
          child: Wrap(
            spacing: CollectSpacing.x2,
            runSpacing: CollectSpacing.x2,
            children: [
              CollectStatusChip(label: 'Neutral'),
              CollectStatusChip(
                label: 'Success',
                tone: CollectStatusTone.success,
              ),
              CollectStatusChip(
                label: 'Warning',
                tone: CollectStatusTone.warning,
              ),
              CollectStatusChip(
                label: 'Danger',
                tone: CollectStatusTone.danger,
              ),
              CollectStatusChip(
                label: 'Privacy',
                tone: CollectStatusTone.privacy,
              ),
            ],
          ),
        ),
        GroupCard(
          collection: CollectCollection(
            id: 'demo',
            slug: 'demo-group',
            creatorUserId: 'local-user',
            title: 'St Michel group',
            description: 'Demo group card',
            receiverMomoNumber: '+250788123456',
            createdAt: now,
          ),
          summary: const CollectionSummary(
            amountRaisedRwf: 125000,
            supporterCount: 12,
          ),
        ),
        const MoneyCard(
          label: 'Total',
          amount: 125000,
          detail: '12 supporters · 50% funded',
        ),
        const PaymentIntentStatusCard(
          amountRwf: 5000,
          receiverLabel: 'St Michel treasury',
          receiverMomoNumber: '+250788123456',
          status: 'pending',
        ),
        ReceiverConsentCard(
          flagsEnabled: true,
          consented: false,
          isSyncing: false,
          onConsentChanged: (_) {},
          onSync: () {},
        ),
        LedgerRow.confirmed(contribution: contribution),
        const ActivityFeedItem(
          title: '#038491',
          amount: 25000,
          meta: '2026-05-23 10:30:00',
          transactionId: 'MTN12345',
        ),
        const InsightCard(
          title: 'Contextual tip',
          message:
              'Short, human guidance that makes the next safe action clear.',
          tone: CollectStatusTone.success,
        ),
        LedgerRow.review(
          event: event,
          action: const CollectButton(
            label: 'Request reparse',
            icon: CollectIcons.check,
            expand: true,
          ),
        ),
        const LoadingSkeleton(),
        const CollectEmptyState(
          icon: CollectIcons.public,
          title: 'Empty state',
          message: 'Helpful empty copy explains the next safe action.',
        ),
      ],
    );
  }
}
