import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_spacing.dart';
import '../../app/theme/collect_typography.dart';
import '../../shared/repositories/collect_repository.dart';
import 'public_content.dart';

export 'public_content.dart';

class CollectLandingPage extends ConsumerWidget {
  const CollectLandingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(collectRuntimeConfigProvider);
    return Scaffold(
      backgroundColor: CollectColors.brandPaper,
      body: SelectionArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: CollectColors.brandPaper,
              foregroundColor: CollectColors.referenceChromeBlack,
              title: const Text('Collect'),
              actions: [
                IconButton(
                  tooltip: 'How it works',
                  onPressed: () => context.go('/group-savings'),
                  icon: const Icon(Icons.menu_book_outlined),
                ),
                IconButton(
                  tooltip: 'Trust and security',
                  onPressed: () => context.go('/trust'),
                  icon: const Icon(Icons.shield_outlined),
                ),
                const SizedBox(width: 8),
              ],
            ),
            SliverToBoxAdapter(
              child: _PageWidth(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 72),
                  child: Wrap(
                    spacing: 56,
                    runSpacing: 40,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 620,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'MoMo contributions, captured automatically.',
                              style: Theme.of(context).textTheme.displayMedium
                                  ?.copyWith(
                                    color: CollectColors.referenceChromeBlack,
                                    fontWeight: CollectTypography.weightBold,
                                    height: CollectTypography.leadingDisplay,
                                  ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Create a group, invite members and contribute through MoMo. On Android, Collect listens only after clear SMS permission, sends opted-in payment receipts to its secure backend, uses OpenAI to extract the receipt facts and updates the group ledger when one exact payer request matches.',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: CollectColors.inkSecondary,
                                    height: CollectTypography.leadingBody,
                                  ),
                            ),
                            const SizedBox(height: 28),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                FilledButton.icon(
                                  onPressed: () =>
                                      _openUri(context, config.appDownloadUrl),
                                  icon: const Icon(Icons.download_rounded),
                                  label: const Text('Get the App'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => context.go('/group-savings'),
                                  icon: const Icon(Icons.groups_rounded),
                                  label: const Text('Create Group'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 330, child: _JourneyPreview()),
                    ],
                  ),
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
    );
  }
}

class CollectPublicPage extends ConsumerWidget {
  const CollectPublicPage({required this.data, super.key});

  final CollectPublicPageData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(collectRuntimeConfigProvider);
    return Scaffold(
      backgroundColor: CollectColors.brandPaper,
      appBar: AppBar(
        backgroundColor: CollectColors.brandPaper,
        title: Text(data.navLabel),
        leading: IconButton(
          tooltip: 'Collect home',
          onPressed: () => context.go('/'),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          IconButton(
            tooltip: 'Get the App',
            onPressed: () => _openUri(context, config.appDownloadUrl),
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
                        color: CollectColors.brandPeriwinkle,
                        fontWeight: CollectTypography.weightBold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      data.title,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: CollectColors.referenceChromeBlack,
                        fontWeight: CollectTypography.weightBold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Text(
                        data.intro,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: CollectColors.inkSecondary,
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
                              _openUri(context, config.appDownloadUrl),
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('Get the App'),
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
    );
  }
}

class _JourneyPreview extends StatelessWidget {
  const _JourneyPreview();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: CollectColors.publicWhite,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contribution received',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: CollectTypography.weightBold,
              ),
            ),
            const SizedBox(height: 18),
            const _PreviewRow(label: 'Payment request', value: 'RWF 10,000'),
            const _PreviewRow(label: 'Receipt', value: 'Captured'),
            const _PreviewRow(label: 'Match', value: 'Exact'),
            const Divider(height: 28),
            const _PreviewRow(label: 'Group balance', value: '+ RWF 10,000'),
            const _PreviewRow(label: 'Your balance', value: '+ RWF 10,000'),
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
              fontWeight: CollectTypography.weightBold,
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
                  fontWeight: CollectTypography.weightBold,
                ),
              ),
              const SizedBox(height: 28),
              const Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _StepCard(
                    number: '1',
                    title: 'Create or join',
                    body: 'Use a private link or QR code to join the group.',
                  ),
                  _StepCard(
                    number: '2',
                    title: 'Request an amount',
                    body: 'Collect creates one pending request for this payer.',
                  ),
                  _StepCard(
                    number: '3',
                    title: 'Pay through MoMo',
                    body: 'The member approves payment outside Collect.',
                  ),
                  _StepCard(
                    number: '4',
                    title: 'See the ledger update',
                    body: 'One exact receipt match updates both balances.',
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
        color: CollectColors.brandPaper,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(child: Text(number)),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: CollectTypography.weightBold,
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
                fontWeight: CollectTypography.weightBold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Collect records direct MoMo contributions. It does not hold group funds, sell financial products or ask members to paste receipts and transaction IDs.',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: CollectColors.inkSecondary,
                height: CollectTypography.leadingBody,
              ),
            ),
            const SizedBox(height: 24),
            const Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _SafetyCard(
                  icon: Icons.sms_outlined,
                  title: 'Clear SMS permission',
                  body: 'Android explains access before the system prompt.',
                ),
                _SafetyCard(
                  icon: Icons.auto_awesome_outlined,
                  title: 'OpenAI extraction',
                  body: 'The secure backend extracts only receipt facts.',
                ),
                _SafetyCard(
                  icon: Icons.rule_rounded,
                  title: 'Exact server match',
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
              Icon(icon, color: CollectColors.brandPeriwinkle),
              const SizedBox(height: 14),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: CollectTypography.weightBold,
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
        color: CollectColors.publicWhite,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: CollectTypography.weightBold,
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
      color: CollectColors.referenceChromeBlack,
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
                  fontWeight: CollectTypography.weightBold,
                ),
              ),
              TextButton(
                onPressed: () => context.go('/group-savings'),
                child: const Text('How it works'),
              ),
              TextButton(
                onPressed: () => context.go('/privacy'),
                child: const Text('Privacy'),
              ),
              TextButton(
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
