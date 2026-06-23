part of 'device_privacy_screens.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenScaffold(
      title: 'WhatsApp support',
      children: [
        CollectVisualFeatureCard(
          asset: 'assets/brand/generated/collect_visual_momo_signal.png',
          title: 'Support without secrets',
          message:
              'Collect support never needs MoMo PINs, OTPs, raw SMS, or private credentials.',
          icon: CollectIcons.support,
          tone: CollectStatusTone.privacy,
        ),
        CollectCard(
          emphasis: CollectCardEmphasis.flat,
          child: Column(
            children: [
              CollectListTile(
                leading: CollectIcons.privacy,
                title: 'No PINs',
                subtitle: 'Never share payment credentials.',
              ),
              CollectListTile(
                leading: CollectIcons.sms,
                title: 'No raw SMS',
                subtitle: 'Use support review flows.',
              ),
              CollectListTile(
                leading: CollectIcons.public,
                title: 'Support',
                subtitle: 'Share safe account context.',
              ),
            ],
          ),
        ),
        CollectButton(
          label: 'Open WhatsApp',
          icon: CollectIcons.support,
          onPressed: openCollectWhatsAppSupport,
          expand: true,
        ),
      ],
    );
  }
}
