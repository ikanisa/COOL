part of 'profile_sub_screens.dart';

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

class OrderHistoryScreen extends StatelessWidget {
  const OrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return _ProfileSubScaffold(
      title: 'ORDERS',
      subtitle: 'PURCHASE HISTORY',
      icon: Icons.receipt_long_outlined,
      slivers: [
        const _SectionLabel(label: 'RECENT ORDERS'),
        const SizedBox(height: CoolSpace.x3),
        _GlassCard(
          child: Column(
            children: [
              const SizedBox(height: CoolSpace.x4),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: RsColors.rsBlue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.shopping_bag_outlined,
                  color: RsColors.rsBlue,
                  size: 32,
                ),
              ),
              const SizedBox(height: CoolSpace.x4),
              Text(
                'NO ORDERS YET',
                style: context.coolText.rayonCondensed(
                  Theme.of(context).textTheme.titleLarge,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: CoolSpace.x2),
              Text(
                'Your purchase history will appear here after your first order from the Rayon Sports shop.',
                textAlign: TextAlign.center,
                style: context.coolText.mono(
                  Theme.of(context).textTheme.bodySmall,
                  fontWeight: FontWeight.w600,
                  color: colors.secondaryText,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: CoolSpace.x5),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.push('/partners/rayon-sports/shop'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: RsColors.rsBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(CoolRadii.lg),
                    ),
                  ),
                  child: Text(
                    'VISIT SHOP',
                    style: context.coolText.mono(
                      Theme.of(context).textTheme.labelLarge,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: CoolSpace.x3),
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
                subtitle: 'support@rayonsports.rw',
                onTap: () async {
                  final uri = Uri.parse('mailto:support@rayonsports.rw');
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
