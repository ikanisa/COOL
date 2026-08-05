import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

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
    final foreground = CollectRuntimeTokens.chromeForeground(colors);
    final control = CollectRuntimeTokens.chromeControl(colors);
    final border = CollectRuntimeTokens.chromeControlBorder(colors);
    return Semantics(
      container: true,
      header: true,
      label: title,
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
            child: Text(
              title,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
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
            Text(
              section.title,
              softWrap: true,
              overflow: TextOverflow.visible,
              textWidthBasis: TextWidthBasis.parent,
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
    final maskedMomo = profile?.momoNumber == null
        ? 'MoMo not linked'
        : maskMomoNumberForDisplay(profile!.momoNumber!);
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
                title: 'Edit profile',
                subtitle: maskedMomo,
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
    final confirmed = await _showAccountActionSheet(
      context: context,
      icon: CollectIcons.lock,
      title: 'Sign out?',
      message:
          'End this Collect session on this device. Group ledgers and verified records stay available after you sign in again.',
      confirmLabel: 'Sign out',
      confirmIcon: CollectIcons.lock,
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
  final Set<String> _selectedReasons = {};
  bool _submitted = false;
  bool _submitting = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final reasonOptions =
        ref.watch(collectAccountDeletionReasonsProvider).valueOrNull ??
        collectDefaultAccountDeletionReasons;
    return ScreenScaffold(
      title: 'Delete request',
      children: [
        if (_error != null)
          InfoSecurityBanner(
            title: 'Request failed',
            message: _error!,
            tone: CollectStatusTone.warning,
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
                for (final reason in reasonOptions.map((item) => item.label))
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
                Text(
                  _selectedReasons.isEmpty
                      ? 'Select a reason to submit.'
                      : 'Ready to submit.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.collectColors.textSecondary,
                    fontWeight: CollectTypography.weightBold,
                  ),
                ),
                CollectSpacing.gap8,
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
    final confirmed = await _showAccountActionSheet(
      context: context,
      icon: CollectIcons.error,
      title: 'Submit delete request?',
      message:
          'This creates an auditable data deletion request. Some ledger, security, dispute, and legal records may be retained.',
      confirmLabel: 'Submit',
      confirmIcon: CollectIcons.error,
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
      if (mounted) setState(() => _error = _safeAccountRequestError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

String _safeAccountRequestError(Object error) {
  if (error is FormatException) return error.message.toString();
  if (error is StateError) return error.message.toString();
  return 'The request could not be submitted. Check your connection and try again.';
}

Future<bool> _showAccountActionSheet({
  required BuildContext context,
  required IconData icon,
  required String title,
  required String message,
  required String confirmLabel,
  required IconData confirmIcon,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: context.collectColors.transparent,
    barrierColor: CollectColors.publicBlack.withValues(alpha: 0.64),
    sheetAnimationStyle: CollectMotion.animationStyle(context),
    builder: (sheetContext) {
      final colors = sheetContext.collectColors;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          CollectSpacing.x4,
          CollectSpacing.x2,
          CollectSpacing.x4,
          MediaQuery.viewInsetsOf(sheetContext).bottom + CollectSpacing.x4,
        ),
        child: CollectCard(
          emphasis: CollectCardEmphasis.glow,
          accentColor: colors.statusBlocked,
          padding: CollectSpacing.cardPaddingComfortable,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CollectToneIcon(icon: icon, tone: CollectStatusTone.warning),
                  CollectSpacing.gapW12,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(sheetContext).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: CollectTypography.weightBold,
                              ),
                        ),
                        CollectSpacing.gap8,
                        Text(
                          message,
                          softWrap: true,
                          style: Theme.of(sheetContext).textTheme.bodyMedium
                              ?.copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              CollectSpacing.gap20,
              Row(
                children: [
                  Expanded(
                    child: CollectButton(
                      label: 'Cancel',
                      icon: CollectIcons.chevron,
                      variant: CollectButtonVariant.secondary,
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                    ),
                  ),
                  CollectSpacing.gapW12,
                  Expanded(
                    child: CollectButton(
                      label: confirmLabel,
                      icon: confirmIcon,
                      variant: CollectButtonVariant.danger,
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  return result ?? false;
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
                : colors.controlSurface,
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
