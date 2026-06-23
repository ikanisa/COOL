import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class LegalScreen extends StatelessWidget {
  const LegalScreen({required this.kind, super.key});

  final String kind;

  @override
  Widget build(BuildContext context) {
    final isPrivacy = kind == 'privacy';
    final sections = isPrivacy ? _privacyPolicySections : _termsSections;
    final title = isPrivacy ? 'Privacy Policy' : 'Terms & Conditions';
    return ScreenScaffold(
      title: title,
      showHeader: false,
      children: [
        _LegalPageHeader(title: title),
        CollectVisualFeatureCard(
          asset: isPrivacy
              ? 'assets/brand/generated/collect_visual_qr_share.png'
              : 'assets/brand/generated/collect_visual_momo_signal.png',
          title: isPrivacy ? 'Privacy boundary' : 'Safe use',
          message: isPrivacy
              ? 'Public sharing stays Collect ID first.'
              : 'Approve MoMo only after checking group and amount.',
          icon: isPrivacy ? CollectIcons.privacy : CollectIcons.warning,
          tone: isPrivacy
              ? CollectStatusTone.privacy
              : CollectStatusTone.warning,
        ),
        CollectCard(
          emphasis: CollectCardEmphasis.glow,
          accentColor: context.collectColors.statusForeground(
            isPrivacy ? CollectStatusTone.privacy : CollectStatusTone.warning,
          ),
          child: Column(
            children: [
              CollectListTile(
                leading: CollectIcons.public,
                title: isPrivacy ? 'Public data' : 'Group checks',
                subtitle: isPrivacy
                    ? 'Collect IDs and safe status.'
                    : 'Group, receiver, amount.',
              ),
              CollectListTile(
                leading: CollectIcons.lock,
                title: isPrivacy ? 'Private data' : 'Secret boundary',
                subtitle: isPrivacy
                    ? 'Credentials never public.'
                    : 'No OTPs, PINs, raw SMS.',
              ),
            ],
          ),
        ),
        CollectCard(
          emphasis: CollectCardEmphasis.flat,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final section in sections) _LegalText(section)],
          ),
        ),
        InfoSecurityBanner(
          title: isPrivacy ? 'Public boundary' : 'Security responsibility',
          message: isPrivacy
              ? 'Private message content, receiver MoMo numbers, and support evidence are not public group content. Public screens use Collect IDs, amounts, group names, and safe status labels.'
              : 'Confirm the group, receiver label, and amount before approving MoMo. Collect support messages do not request payment credentials or sign-in secrets.',
          tone: isPrivacy
              ? CollectStatusTone.privacy
              : CollectStatusTone.warning,
        ),
      ],
    );
  }
}

class _LegalPageHeader extends StatelessWidget {
  const _LegalPageHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.onImagePrimary;
    return Semantics(
      container: true,
      header: true,
      label: title,
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: 'Back',
            style: IconButton.styleFrom(
              backgroundColor: foreground.withValues(alpha: 0.10),
              foregroundColor: foreground,
              side: BorderSide(color: foreground.withValues(alpha: 0.16)),
              fixedSize: const Size(44, 44),
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
            ),
            onPressed: () => goBackOrHome(context),
            icon: const Icon(Icons.arrow_back_rounded, size: 22),
          ),
          CollectSpacing.gapW12,
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w900,
                height: 1,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalSection {
  const _LegalSection({required this.title, required this.body});

  final String title;
  final String body;
}

class _LegalText extends StatelessWidget {
  const _LegalText(this.section);

  final _LegalSection section;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          CollectSpacing.gap8,
          Text(
            section.body,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

const _privacyPolicySections = [
  _LegalSection(
    title: 'Data we collect',
    body:
        'Collect stores your Collect ID, WhatsApp sign-in phone, optional MoMo account, group memberships, group profile details, payment requests, contribution records, and permission status. Group owners may allow Collect to process MoMo SMS evidence for payment matching.',
  ),
  _LegalSection(
    title: 'How we use data',
    body:
        'We use this data to create and join groups, verify contributions, keep ledgers accurate, show notifications, prevent misuse, provide support, and maintain audit records for payment disputes.',
  ),
  _LegalSection(
    title: 'What stays private',
    body:
        'Receiver MoMo numbers, private confirmation text, sign-in phones, and support evidence are not shown on public group cards or public share links. Member-facing screens use Collect IDs and safe payment status.',
  ),
  _LegalSection(
    title: 'Sharing',
    body:
        'We share only what is needed with service providers that operate authentication, hosting, storage, messaging, support, analytics, or payment verification. We do not sell personal data.',
  ),
  _LegalSection(
    title: 'Choices and retention',
    body:
        'You can update your MoMo account, request account deletion, leave groups where supported, and contact support for correction requests. Ledger records may be retained where needed for audit, security, dispute, and legal reasons.',
  ),
];

const _termsSections = [
  _LegalSection(
    title: 'Using Collect',
    body:
        'Collect helps groups organize contributions, create payment requests, scan or share group QR codes, and maintain a verified contribution ledger. You must use accurate group, receiver, and payment information.',
  ),
  _LegalSection(
    title: 'MoMo payments',
    body:
        'Payments are approved outside Collect through MoMo or the mobile money flow shown on your device. Collect does not ask for payment credentials or sign-in secrets.',
  ),
  _LegalSection(
    title: 'Group ownership',
    body:
        'Group owners are responsible for group profile details, receiver setup, recurring settings, member management, and permission readiness. Android SMS access may be required for owner-side payment verification.',
  ),
  _LegalSection(
    title: 'Disputes and corrections',
    body:
        'If a payment is missing, duplicated, incorrect, or needs review, contact support. Collect may use payment status, transaction references, SMS evidence, and audit logs to investigate.',
  ),
  _LegalSection(
    title: 'Acceptable use',
    body:
        'Do not create misleading groups, impersonate another person, abuse QR links, submit false payment claims, or use Collect to request illegal or unauthorized payments.',
  ),
];

class AccountSessionScreen extends ConsumerWidget {
  const AccountSessionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(
      collectRepositoryProvider.select((state) => state.currentProfile),
    );
    final maskedMomo = profile?.momoNumber == null
        ? 'MoMo not linked'
        : maskMomoNumberForDisplay(profile!.momoNumber!);
    return ScreenScaffold(
      title: 'Account',
      subtitle: profile == null ? 'No active profile' : profile.publicId,
      children: [
        CollectVisualFeatureCard(
          asset: 'assets/brand/generated/collect_visual_momo_signal.png',
          title: profile == null ? 'Account pending' : profile.publicId,
          message: 'Profile, session, and data controls.',
          icon: CollectIcons.profile,
          tone: CollectStatusTone.info,
        ),
        CollectCard(
          emphasis: CollectCardEmphasis.glow,
          accentColor: context.collectColors.statusForeground(
            CollectStatusTone.info,
          ),
          child: Column(
            children: [
              CollectListTile(
                leading: CollectIcons.profile,
                title: 'Profile and MoMo',
                subtitle: maskedMomo,
                onTap: () => context.go('/settings/profile'),
              ),
              CollectListTile(
                leading: CollectIcons.error,
                title: 'Delete data',
                subtitle: 'Auditable request.',
                onTap: () => context.go('/settings/account/delete'),
              ),
              CollectListTile(
                leading: CollectIcons.lock,
                title: 'Sign out',
                subtitle: 'End session.',
                onTap: () => _confirmSignOut(context, ref),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'End this Collect session on this device. Group ledgers and verified records stay available after you sign in again.',
        ),
        actions: [
          CollectButton(
            label: 'Cancel',
            icon: CollectIcons.chevron,
            variant: CollectButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          CollectButton(
            label: 'Sign out',
            icon: CollectIcons.lock,
            variant: CollectButtonVariant.danger,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(collectRepositoryProvider.notifier).signOut();
    if (context.mounted) context.go('/auth');
  }
}

class DeleteAccountRequestScreen extends ConsumerStatefulWidget {
  const DeleteAccountRequestScreen({super.key});

  @override
  ConsumerState<DeleteAccountRequestScreen> createState() =>
      _DeleteAccountRequestScreenState();
}

class _DeleteAccountRequestScreenState
    extends ConsumerState<DeleteAccountRequestScreen> {
  static const _reasonOptions = [
    'I no longer use Collect',
    'I joined by mistake',
    'I prefer not to keep my data',
  ];

  final Set<String> _selectedReasons = {};
  bool _submitted = false;
  bool _submitting = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Delete request',
      children: [
        if (_error != null)
          InfoSecurityBanner(
            title: 'Request failed',
            message: _error!,
            tone: CollectStatusTone.warning,
          ),
        const CollectVisualFeatureCard(
          asset: 'assets/brand/generated/collect_visual_momo_signal.png',
          title: 'Auditable request',
          message: 'Deletion is reviewed against ledger and security records.',
          icon: CollectIcons.error,
          tone: CollectStatusTone.privacy,
        ),
        if (_submitted)
          const _StateHero(
            icon: CollectIcons.check,
            title: 'Request submitted.',
            tone: CollectStatusTone.success,
          )
        else
          CollectCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final reason in _reasonOptions)
                  _DeleteReasonOption(
                    label: reason,
                    selected: _selectedReasons.contains(reason),
                    onTap: () {
                      setState(() {
                        if (_selectedReasons.contains(reason)) {
                          _selectedReasons.remove(reason);
                        } else {
                          _selectedReasons.add(reason);
                        }
                      });
                    },
                  ),
                CollectSpacing.gap16,
                CollectButton(
                  label: _submitting ? 'Submitting' : 'Submit',
                  icon: CollectIcons.error,
                  variant: CollectButtonVariant.danger,
                  onPressed: _submitting || _selectedReasons.isEmpty
                      ? null
                      : _confirmAndSubmit,
                  expand: true,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _confirmAndSubmit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit delete request?'),
        content: const Text(
          'This creates an auditable data deletion request. Some ledger, security, dispute, and legal records may be retained.',
        ),
        actions: [
          CollectButton(
            label: 'Cancel',
            icon: CollectIcons.chevron,
            variant: CollectButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          CollectButton(
            label: 'Submit',
            icon: CollectIcons.error,
            variant: CollectButtonVariant.danger,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(collectRepositoryProvider.notifier)
          .requestAccountDeletion(reason: _selectedReasons.join('; '));
      if (mounted) setState(() => _submitted = true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _DeleteReasonOption extends StatelessWidget {
  const _DeleteReasonOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x2),
      child: InkWell(
        borderRadius: CollectRadius.mdBorder,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? colors.statusBlocked.withValues(alpha: 0.14)
                : colors.glassControl,
            borderRadius: CollectRadius.mdBorder,
            border: Border.all(
              color: selected ? colors.statusBlocked : colors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(CollectSpacing.x3),
            child: Row(
              children: [
                Icon(
                  selected ? CollectIcons.check : CollectIcons.error,
                  color: selected ? colors.statusBlocked : colors.textMuted,
                ),
                CollectSpacing.gapW12,
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(color: colors.textPrimary),
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

class _StateHero extends StatelessWidget {
  const _StateHero({
    required this.icon,
    required this.title,
    this.tone = CollectStatusTone.info,
  });

  final IconData icon;
  final String title;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      padding: CollectSpacing.cardPaddingComfortable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CollectStatusChip(label: title, tone: tone, icon: icon),
          CollectSpacing.gap20,
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
        ],
      ),
    );
  }
}
