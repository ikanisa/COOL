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
      supporterLabel: 'Anonymous supporter',
      anonymityChoice: 'anonymous',
      createdAt: now,
      transactionId: 'MTN12345',
    );
    final event = ParsedPaymentEvent(
      id: 'demo-event',
      amountRwf: 15000,
      transactionId: 'AMB-901',
      senderLabel: 'Manual SMS paste',
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
              'Collect uses original Rwanda-first tokens and components. No reference brand assets, fonts, colors, or screens are copied.',
          tone: CollectStatusTone.info,
        ),
        const MoneyHeroCard(
          amount: 125000,
          label: 'Raised across Collect',
          detail: '2 goals · 1 pending MOMO check',
          chips: [
            CollectStatusChip(
              label: 'Direct MOMO',
              tone: CollectStatusTone.privacy,
            ),
            CollectStatusChip(
              label: 'Verified',
              tone: CollectStatusTone.success,
            ),
          ],
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
                detail: 'New goal',
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
                detail: 'Verified',
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
        CollectionGoalCard(
          collection: CollectCollection(
            id: 'demo',
            slug: 'demo-goal',
            creatorUserId: 'local-user',
            title: 'St Michel building fund',
            description: 'Demo goal card',
            category: 'Church',
            targetAmountRwf: 250000,
            publicStatus: 'public_approved',
            visibility: 'public_approved',
            receiverMomoNumber: '+250788123456',
            createdAt: now,
          ),
          summary: const CollectionSummary(
            amountRaisedRwf: 125000,
            supporterCount: 12,
          ),
        ),
        const MoneyCard(
          label: 'Raised',
          amount: 125000,
          detail: '12 supporters · 50% funded',
        ),
        MomoInstructionCard(
          amountRwf: 5000,
          receiverLabel: 'St Michel treasury',
          receiverMomoNumber: '+250788123456',
          contributionCode: 'ABC123',
          instructionTitle: 'Mobile money USSD',
          network: 'MTN MOMO',
          instructions:
              'Dial your MOMO menu, send RWF 5,000 to the receiver, and use ABC123 as the reference when available.',
          status: 'pending',
          onCopy: () => copyToClipboard(context, 'Demo instructions'),
        ),
        ReceiverConsentCard(
          flagsEnabled: true,
          consented: false,
          isSyncing: false,
          onConsentChanged: (_) {},
          onManualPaste: () {},
          onSync: () {},
        ),
        LedgerRow.confirmed(contribution: contribution),
        const ActivityFeedItem(
          title: 'Anonymous supporter',
          amount: 25000,
          meta: 'Verified MOMO contribution',
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
            label: 'Manual allocate with reason',
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
