part of 'collect_landing_page.dart';

class _LandingFooter extends ConsumerWidget {
  const _LandingFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(collectRuntimeConfigProvider);
    return ColoredBox(
      color: CollectColors.referenceChromeBlack,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 22),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 28,
              runSpacing: 18,
              children: [
                SizedBox(
                  width: 280,
                  child: Text(
                    'Collect by IKANISA',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: CollectColors.brandPaper,
                      fontWeight: CollectTypography.weightBold,
                    ),
                  ),
                ),
                _FooterLink(label: 'Home', onPressed: () => context.go('/')),
                _FooterLink(
                  label: 'Group Savings',
                  onPressed: () => context.go('/group-savings'),
                ),
                _FooterLink(
                  label: 'Diaspora',
                  onPressed: () => context.go('/diaspora'),
                ),
                _FooterLink(
                  label: 'Insurance',
                  onPressed: () => context.go('/insurance'),
                ),
                _FooterLink(
                  label: 'CRaaS',
                  onPressed: () => context.go('/craas'),
                ),
                _FooterLink(
                  label: 'Community Groups',
                  onPressed: () => context.go('/community-groups'),
                ),
                _FooterLink(
                  label: 'Our Partners',
                  onPressed: () => context.go('/our-partners'),
                ),
                _FooterLink(
                  label: 'Privacy Policy',
                  onPressed: () => context.go('/privacy'),
                ),
                _FooterLink(
                  label: 'Terms of Service',
                  onPressed: () => context.go('/terms'),
                ),
                _FooterLink(
                  label: config.supportEmail,
                  onPressed: () async => _openEmail(context),
                ),
                _FooterLink(
                  label: config.whatsAppSupportDisplay,
                  onPressed: () async => _openWhatsApp(
                    context,
                    'Hello IKANISA, I need support with Collect.',
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: Text(
                    'Customer support: app access, group savings setup and account questions.',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: CollectColors.brandPaper.withValues(alpha: 0.66),
                      fontWeight: CollectTypography.weightBold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed ?? () => _scrollToCustomerAction(context),
      style: TextButton.styleFrom(
        foregroundColor: CollectColors.brandPaper.withValues(alpha: 0.78),
        textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: CollectTypography.weightBold,
        ),
      ),
      child: Text(label),
    );
  }
}
