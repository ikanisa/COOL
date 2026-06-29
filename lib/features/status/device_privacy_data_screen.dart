part of 'device_privacy_screens.dart';

class PrivacyDataScreen extends StatelessWidget {
  const PrivacyDataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Privacy and data',
      children: [
        const CollectVisualFeatureCard(
          asset: 'assets/brand/collect_runtime/media/qr-share.png',
          title: 'Private by default',
          message:
              'Public links use Collect IDs, safe amounts, group names, and payment status only.',
          icon: CollectIcons.privacy,
          tone: CollectStatusTone.privacy,
        ),
        const CollectBentoGrid(
          primary: BentoMetricCell(
            label: 'Public',
            value: 'ID first.',
            detail: 'No phone display',
            icon: CollectIcons.public,
            tone: CollectStatusTone.privacy,
            emphasis: true,
          ),
          top: BentoMetricCell(
            label: 'Payments',
            value: 'Bounded',
            detail: 'Owner and support',
            icon: CollectIcons.momo,
            tone: CollectStatusTone.info,
          ),
          bottom: BentoMetricCell(
            label: 'Evidence',
            value: 'Protected',
            detail: 'SMS and ledger',
            icon: CollectIcons.lock,
            tone: CollectStatusTone.success,
          ),
        ),
        CollectCard(
          emphasis: CollectCardEmphasis.glow,
          accentColor: context.collectColors.statusForeground(
            CollectStatusTone.privacy,
          ),
          child: const Column(
            children: [
              CollectListTile(
                leading: CollectIcons.public,
                title: 'Public group links',
                subtitle: 'Group name, QR, Collect IDs, and safe status only.',
              ),
              CollectListTile(
                leading: CollectIcons.privacy,
                title: 'Collect ID first.',
                subtitle: 'Public group surfaces stay member-safe.',
              ),
              CollectListTile(
                leading: CollectIcons.lock,
                title: 'Private payment data',
                subtitle: 'Receiver numbers and support evidence stay bounded.',
              ),
              CollectListTile(
                leading: CollectIcons.ledger,
                title: 'Ledger records',
                subtitle:
                    'Retained where audit, dispute, or security needs it.',
              ),
            ],
          ),
        ),
        CollectCard(
          emphasis: CollectCardEmphasis.flat,
          child: Column(
            children: [
              const CollectListTile(
                leading: CollectIcons.profile,
                title: 'Member identity',
                subtitle: 'Public group activity uses Collect ID only.',
              ),
              const CollectListTile(
                leading: CollectIcons.momo,
                title: 'MoMo data',
                subtitle:
                    'Receiver numbers stay inside payment and owner flows.',
              ),
              const CollectListTile(
                leading: CollectIcons.sms,
                title: 'SMS evidence',
                subtitle: 'Used for payment matching and support review only.',
              ),
              CollectListTile(
                leading: CollectIcons.privacy,
                title: 'Privacy policy',
                subtitle: 'Full data handling policy.',
                onTap: () => context.go('/settings/legal/privacy'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
