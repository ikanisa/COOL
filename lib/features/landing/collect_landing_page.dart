import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_spacing.dart';
import '../../app/theme/collect_runtime_assets.dart';
import '../../app/theme/collect_typography.dart';
import '../../shared/repositories/collect_repository.dart';
import 'public_content.dart';
import 'public_marketing_hero.dart';
import 'public_marketing_theme.dart';

export 'public_content.dart';

class CollectLandingPage extends ConsumerStatefulWidget {
  const CollectLandingPage({super.key});

  @override
  ConsumerState<CollectLandingPage> createState() => _CollectLandingPageState();
}

class _CollectLandingPageState extends ConsumerState<CollectLandingPage> {
  final _scrollController = ScrollController();
  final _heroKey = GlobalKey();
  final _navigationKey = GlobalKey();
  bool _navigationOnLight = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_syncNavigation);
  }

  void _syncNavigation() {
    if (!mounted) return;
    final hero = _heroKey.currentContext?.findRenderObject();
    final navigation = _navigationKey.currentContext?.findRenderObject();
    if (hero is! RenderBox ||
        navigation is! RenderBox ||
        !hero.hasSize ||
        !navigation.hasSize) {
      return;
    }
    final onLight =
        hero.localToGlobal(Offset(0, hero.size.height)).dy <=
        navigation.localToGlobal(Offset(0, navigation.size.height)).dy;
    if (onLight != _navigationOnLight) {
      setState(() => _navigationOnLight = onLight);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(collectRuntimeConfigProvider);
    final downloadAction = collectPublicDownloadAction(config.appDownloadUrl);
    return PublicMarketingSurface(
      builder: (context) => Scaffold(
        backgroundColor: CollectColors.publicWhite,
        body: Stack(
          children: [
            SelectionArea(
              child: NotificationListener<ScrollMetricsNotification>(
                onNotification: (_) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _syncNavigation(),
                  );
                  return false;
                },
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverToBoxAdapter(
                      child: PublicMarketingHero(
                        key: _heroKey,
                        title: collectPublicHomeCopy['title']!,
                        intro: collectPublicHomeCopy['intro']!,
                        actions: [
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  CollectPublicMarketingTheme.action,
                              foregroundColor: CollectColors.publicWhite,
                            ),
                            onPressed: () =>
                                _openUri(context, downloadAction.href),
                            child: Text(downloadAction.label),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: CollectColors.publicWhite,
                            ),
                            onPressed: () => context.go('/group-savings'),
                            child: const Text('How groups work'),
                          ),
                        ],
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: _PageWidth(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: _JourneyPreview(),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: _JourneySection()),
                    const SliverToBoxAdapter(child: _SafetySection()),
                    SliverToBoxAdapter(
                      child: _PublicFooter(
                        supportEmail: config.supportEmail,
                        supportPhone: config.whatsAppSupportDisplay,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                key: _navigationKey,
                color: _navigationOnLight
                    ? CollectColors.publicWhite
                    : CollectColors.transparentColor,
                child: _PublicHomeNavigation(onLight: _navigationOnLight),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublicHomeNavigation extends StatelessWidget {
  const _PublicHomeNavigation({required this.onLight});

  final bool onLight;

  @override
  Widget build(BuildContext context) {
    final foreground = onLight
        ? CollectColors.publicInk
        : CollectColors.publicWhite;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Image.asset(
              CollectRuntimeAssets.officialLogo,
              width: 36,
              height: 36,
              excludeFromSemantics: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Collect',
                style: CollectTypography.marketingBody(foreground),
              ),
            ),
            IconButton(
              color: foreground,
              tooltip: 'How it works',
              onPressed: () => context.go('/group-savings'),
              icon: const Icon(Icons.menu_book_outlined),
            ),
            IconButton(
              color: foreground,
              tooltip: 'Trust and security',
              onPressed: () => context.go('/trust'),
              icon: const Icon(Icons.shield_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class CollectPublicPage extends ConsumerWidget {
  const CollectPublicPage({required this.data, super.key});

  final CollectPublicPageData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(collectRuntimeConfigProvider);
    final downloadAction = collectPublicDownloadAction(config.appDownloadUrl);
    return PublicMarketingSurface(
      builder: (context) => Scaffold(
        backgroundColor: CollectColors.publicWhite,
        appBar: AppBar(
          backgroundColor: CollectColors.publicWhite,
          title: Text(data.navLabel),
          leading: IconButton(
            tooltip: 'Collect home',
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          actions: [
            IconButton(
              tooltip: downloadAction.label,
              onPressed: () => _openUri(context, downloadAction.href),
              icon: const Icon(Icons.download_rounded),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SelectionArea(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 0),
            children: [
              _PageWidth(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 56),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        publicSummaryLabel(data),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: CollectColors.publicInk,
                          fontWeight: CollectTypography.weightMedium,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        data.title,
                        style: CollectTypography.marketingHeading(
                          CollectColors.publicInk,
                          compact: MediaQuery.sizeOf(context).width < 720,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Text(
                          data.intro,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: CollectColors.publicSecondary,
                                height: CollectTypography.leadingBody,
                              ),
                        ),
                      ),
                      const SizedBox(height: 36),
                      for (final section in data.sections)
                        _PublicSection(section: section),
                      if (!data.isPolicy)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: FilledButton.icon(
                            onPressed: () =>
                                _openUri(context, downloadAction.href),
                            icon: const Icon(Icons.download_rounded),
                            label: Text(downloadAction.label),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              _PublicFooter(
                supportEmail: config.supportEmail,
                supportPhone: config.whatsAppSupportDisplay,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JourneyPreview extends StatelessWidget {
  const _JourneyPreview();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: CollectPublicMarketingTheme.widget,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contribution received',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: CollectTypography.weightMedium,
              ),
            ),
            const SizedBox(height: 18),
            const _PreviewRow(label: 'MoMo request', value: 'RWF 25,000'),
            const _PreviewRow(label: 'Receipt SMS', value: 'Matched'),
            const _PreviewRow(label: 'Allocation', value: 'Reconciled'),
            const Divider(height: 28),
            const _PreviewRow(label: 'Group balance', value: '+ RWF 25,000'),
            const _PreviewRow(label: 'Your balance', value: '+ RWF 25,000'),
          ],
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: CollectTypography.weightMedium,
              fontFamily: value.contains('RWF')
                  ? CollectTypography.fontFamily
                  : CollectTypography.marketingFontFamily,
              fontFeatures: value.contains('RWF')
                  ? const [FontFeature.tabularFigures()]
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _JourneySection extends StatelessWidget {
  const _JourneySection();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: CollectColors.publicWhite,
      child: _PageWidth(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 64),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'One clear contribution journey',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: CollectTypography.weightMedium,
                ),
              ),
              const SizedBox(height: 28),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  const _StepCard(
                    number: '1',
                    title: 'Create or join',
                    body: 'Use a private link or QR code to join the group.',
                  ),
                  _StepCard(
                    number: '2',
                    title: 'Enter an amount',
                    body: collectPublicHomeCopy['request_body']!,
                  ),
                  _StepCard(
                    number: '3',
                    title: 'Approve outside Collect',
                    body: collectPublicHomeCopy['approve_body']!,
                  ),
                  _StepCard(
                    number: '4',
                    title: 'See the ledger update',
                    body: collectPublicHomeCopy['posting_body']!,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.title,
    required this.body,
  });

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      child: Card(
        color: CollectPublicMarketingTheme.widget,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: CollectPublicMarketingTheme.border,
                foregroundColor: CollectColors.publicInk,
                child: Text(number),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: CollectTypography.weightMedium,
                ),
              ),
              const SizedBox(height: 8),
              Text(body),
            ],
          ),
        ),
      ),
    );
  }
}

class _SafetySection extends StatelessWidget {
  const _SafetySection();

  @override
  Widget build(BuildContext context) {
    return _PageWidth(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 64),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Standalone and privacy-first',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: CollectTypography.weightMedium,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Collect records Rwanda MoMo contributions. It does not ask for MoMo PINs, payment provider OTPs or pasted transaction IDs. Your WhatsApp sign-in code is only for signing in to Collect.',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: CollectColors.publicSecondary,
                height: CollectTypography.leadingBody,
              ),
            ),
            const SizedBox(height: 24),
            const Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _SafetyCard(
                  icon: Icons.phone_android_outlined,
                  title: 'Verified MoMo receiver',
                  body: 'Check the group receiver before approving in USSD.',
                ),
                _SafetyCard(
                  icon: Icons.fact_check_outlined,
                  title: 'Controlled evidence',
                  body:
                      'MoMo receipt intake is authenticated and checked for duplicates.',
                ),
                _SafetyCard(
                  icon: Icons.rule_rounded,
                  title: 'Daily reconciliation',
                  body: 'Incomplete or ambiguous evidence posts nothing.',
                ),
                _SafetyCard(
                  icon: Icons.balance_rounded,
                  title: 'Balanced ledger',
                  body: 'Group and payer balances update together.',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SafetyCard extends StatelessWidget {
  const _SafetyCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: CollectColors.publicInk),
              const SizedBox(height: 14),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: CollectTypography.weightMedium,
                ),
              ),
              const SizedBox(height: 8),
              Text(body),
            ],
          ),
        ),
      ),
    );
  }
}

class _PublicSection extends StatelessWidget {
  const _PublicSection({required this.section});

  final CollectPublicSectionData section;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Card(
        color: CollectPublicMarketingTheme.widget,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: CollectTypography.weightMedium,
                ),
              ),
              const SizedBox(height: 12),
              Text(section.body),
              if (section.bullets.isNotEmpty) ...[
                const SizedBox(height: 16),
                for (final bullet in section.bullets)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 3),
                          child: Icon(Icons.check_circle_outline, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(bullet)),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PublicFooter extends StatelessWidget {
  const _PublicFooter({required this.supportEmail, required this.supportPhone});

  final String supportEmail;
  final String supportPhone;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: CollectColors.publicBlack,
      child: _PageWidth(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Wrap(
            spacing: 20,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Collect by IKANISA',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: CollectTypography.weightMedium,
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: CollectColors.publicWhite,
                ),
                onPressed: () => context.go('/group-savings'),
                child: const Text('How it works'),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: CollectColors.publicWhite,
                ),
                onPressed: () => context.go('/privacy'),
                child: const Text('Privacy'),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: CollectColors.publicWhite,
                ),
                onPressed: () => context.go('/terms'),
                child: const Text('Terms'),
              ),
              Text(
                '$supportEmail · $supportPhone',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageWidth extends StatelessWidget {
  const _PageWidth({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1160),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: CollectSpacing.x6),
          child: child,
        ),
      ),
    );
  }
}

Future<void> _openUri(BuildContext context, String rawUri) async {
  final uri = Uri.tryParse(rawUri.trim());
  if (uri != null &&
      await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    return;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This link is unavailable right now.')),
    );
  }
}
