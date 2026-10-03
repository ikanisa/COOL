import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

export '../privacy/privacy_request_screen.dart';

class LegalScreen extends ConsumerWidget {
  const LegalScreen({required this.kind, super.key});

  final String kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = CollectPolicyDocument.defaults(kind);
    final document =
        ref.watch(collectPolicyDocumentProvider(fallback.kind)).valueOrNull ??
        fallback;
    final isPrivacy = document.kind == 'privacy';
    return ScreenScaffold(
      title: document.title,
      showHeader: false,
      children: [
        _LegalPageHeader(title: document.title),
        CollectCard(
          emphasis: CollectCardEmphasis.flat,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final section in document.sections) _LegalText(section),
            ],
          ),
        ),
        InfoSecurityBanner(
          title: isPrivacy ? 'Public boundary' : 'Security responsibility',
          message: isPrivacy
              ? 'Private MoMo receipt evidence and support records are not public-group content. Public screens use Collect IDs, amounts, group names, and safe status labels.'
              : 'Confirm the MoMo receiver and RWF amount before approving in USSD. Collect support messages do not request a PIN or OTP.',
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
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    final colors = context.collectColors;
    final foreground = CollectRuntimeTokens.chromeForeground(colors);
    final control = CollectRuntimeTokens.chromeControl(colors);
    final border = CollectRuntimeTokens.chromeControlBorder(colors);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: 'Back',
            style: IconButton.styleFrom(
              backgroundColor: control,
              foregroundColor: foreground,
              side: BorderSide(color: border),
              fixedSize: const Size(44, 44),
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
            ),
            onPressed: () => goBackOrHome(context),
            icon: const Icon(Icons.arrow_back_rounded, size: 22),
          ),
          CollectSpacing.gapW12,
          Expanded(
            child: CollectHeadingText(
              title: title,
              maxLines: largeText ? null : 1,
              softWrap: largeText,
              overflow: largeText
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: foreground,
                fontWeight: CollectTypography.weightBold,
                height: CollectTypography.leadingSolid,
                letterSpacing: CollectTypography.trackingDefault,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalText extends StatelessWidget {
  const _LegalText(this.section);

  final CollectPolicySection section;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CollectHeadingText(
              title: section.title,
              level: 2,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: CollectTypography.weightBold,
              ),
            ),
            CollectSpacing.gap8,
            Text(
              section.body,
              softWrap: true,
              overflow: TextOverflow.visible,
              textWidthBasis: TextWidthBasis.parent,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class AccountSessionScreen extends ConsumerWidget {
  const AccountSessionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(
      collectRepositoryProvider.select((state) => state.currentProfile),
    );
    return ScreenScaffold(
      title: 'Account',
      subtitle: profile == null ? 'No active profile' : profile.publicId,
      children: [
        CollectCard(
          emphasis: CollectCardEmphasis.glow,
          accentColor: context.collectColors.statusForeground(
            CollectStatusTone.info,
          ),
          child: Column(
            children: [
              CollectListTile(
                leading: CollectIcons.profile,
                title: 'Profile',
                onTap: () => context.go('/settings/profile'),
              ),
              CollectListTile(
                leading: CollectIcons.error,
                title: 'Delete data',
                onTap: () => context.go('/settings/account/delete'),
              ),
              CollectListTile(
                leading: CollectIcons.lock,
                title: 'Sign out',
                onTap: () => _confirmSignOut(context, ref),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showCollectConfirmationSheet(
      context: context,
      title: 'Sign out?',
      message:
          'End this Collect session on this device. Group ledgers and verified records stay available after you sign in again.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(collectRepositoryProvider.notifier).signOut();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sign-out could not finish. Try again.'),
          ),
        );
      }
      return;
    }
    if (context.mounted) context.go('/auth');
  }
}
