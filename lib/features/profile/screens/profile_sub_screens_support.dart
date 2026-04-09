part of 'profile_sub_screens.dart';

class ProfileAccessScreen extends StatelessWidget {
  const ProfileAccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _ProfileSubScaffold(
      title: 'APP ACCESS',
      subtitle: 'PERMISSIONS & SERVICES',
      icon: Icons.admin_panel_settings_outlined,
      slivers: [
        const _SectionLabel(label: 'ACCESS OVERVIEW'),
        const SizedBox(height: CoolSpace.x3),
        const ProfileAppAccessPanel(embedded: true),
      ],
    );
  }
}

class PrivacySecurityScreen extends StatelessWidget {
  const PrivacySecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _ProfileSubScaffold(
      title: 'PRIVACY',
      subtitle: 'SECURITY SETTINGS',
      icon: Icons.lock_outline_rounded,
      slivers: [
        const _SectionLabel(label: 'AUTHENTICATION'),
        const SizedBox(height: CoolSpace.x3),
        _GlassCard(
          child: Column(
            children: [
              _ToggleRow(
                icon: Icons.fingerprint_rounded,
                title: 'BIOMETRIC LOGIN',
                subtitle: 'FACE ID / FINGERPRINT',
                value: false,
                isLoading: false,
                onChanged: (value) => CoolToast.info(
                  context,
                  'Biometrics disabled on this device',
                ),
              ),
              const _RowDivider(),
              _ToggleRow(
                icon: Icons.pin_outlined,
                title: 'TRANSACTION PIN',
                subtitle: 'PAYMENT SECURITY',
                value: true,
                isLoading: false,
                onChanged: (value) =>
                    CoolToast.info(context, 'PIN required for payments'),
              ),
            ],
          ),
        ),
        const SizedBox(height: CoolSpace.x6),
        const _SectionLabel(label: 'DATA & PRIVACY'),
        const SizedBox(height: CoolSpace.x3),
        _GlassCard(
          child: Column(
            children: [
              _ToggleRow(
                icon: Icons.visibility_off_outlined,
                title: 'HIDE BALANCES',
                subtitle: 'PRIVACY MODE',
                value: false,
                isLoading: false,
                onChanged: (value) =>
                    CoolToast.info(context, 'Balances visible'),
              ),
              const _RowDivider(),
              _SettingsActionRow(
                icon: Icons.delete_sweep_outlined,
                title: 'CLEAR CACHE',
                subtitle: 'FREE UP STORAGE',
                onTap: () => CoolToast.success(context, 'Cache cleared'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}


class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _ProfileSubScaffold(
      title: 'HELP',
      subtitle: 'SUPPORT CENTER',
      icon: Icons.help_outline_rounded,
      slivers: [
        const _SectionLabel(label: 'FAQ'),
        const SizedBox(height: CoolSpace.x3),
        const _GlassCard(
          child: Column(
            children: [
              _FaqItem(
                question: 'HOW DO I BUY TICKETS?',
                answer:
                    'Go to Tickets from the home screen, select a match, and choose your seat category. Payment is handled via MoMo USSD.',
              ),
              _RowDivider(),
              _FaqItem(
                question: 'HOW DO I EARN TOKENS?',
                answer:
                    'Attend matches, complete missions, purchase from the shop, and refer friends to earn fan tokens.',
              ),
              _RowDivider(),
              _FaqItem(
                question: 'WHAT IS BIOPAY?',
                answer:
                    'BioPay lets you authorize MoMo payments with facial recognition or QR codes — no PIN entry needed.',
              ),
              _RowDivider(),
              _FaqItem(
                question: 'HOW DO I JOIN A GROUP?',
                answer:
                    'Ask a group admin for an invite link or code. Open the link to automatically join the savings group.',
              ),
            ],
          ),
        ),
        const SizedBox(height: CoolSpace.x6),
        const _SectionLabel(label: 'CONTACT US'),
        const SizedBox(height: CoolSpace.x3),
        _GlassCard(
          child: Column(
            children: [
              _SettingsActionRow(
                icon: Icons.email_outlined,
                title: 'EMAIL SUPPORT',
                subtitle: 'support@partnersports.rw',
                onTap: () async {
                  final uri = Uri.parse('mailto:support@partnersports.rw');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else if (context.mounted) {
                    CoolToast.info(context, 'No email app found');
                  }
                },
              ),
              const _RowDivider(),
              _SettingsActionRow(
                icon: Icons.chat_rounded,
                title: 'WHATSAPP SUPPORT',
                subtitle: '+250 795 588 248',
                onTap: () async {
                  final uri = Uri.parse('https://wa.me/250795588248');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else if (context.mounted) {
                    CoolToast.error(context, 'Could not open WhatsApp');
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
