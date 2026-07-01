import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/money_format.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/utils/support_contact.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import 'group_empty_state.dart';
import 'group_share_service.dart';

class CollectionManageScreen extends ConsumerStatefulWidget {
  const CollectionManageScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  ConsumerState<CollectionManageScreen> createState() =>
      _CollectionManageScreenState();
}

class _CollectionManageScreenState
    extends ConsumerState<CollectionManageScreen> {
  final _adminPublicId = TextEditingController();
  final _ownerPublicId = TextEditingController();
  bool _working = false;

  @override
  void dispose() {
    _adminPublicId.dispose();
    _ownerPublicId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collectRepositoryProvider);
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collection = repo.maybeCollectionById(widget.collectionId);
    if (collection == null) return const MissingGroupStateScreen();
    final summary = repo.summaryFor(widget.collectionId);
    final profile = state.currentProfile;
    final isOwner = profile != null && collection.creatorUserId == profile.id;

    if (!isOwner) {
      return ScreenScaffold(
        title: 'Group settings',
        subtitle: collection.title,
        children: [
          const MinimalStatePanel(
            icon: CollectIcons.lock,
            title: 'Owner only',
            message: '',
            tone: CollectStatusTone.privacy,
          ),
          CollectButton(
            label: 'Open group',
            icon: CollectIcons.collections,
            onPressed: () => context.go('/groups/${widget.collectionId}'),
            expand: true,
          ),
        ],
      );
    }

    return ScreenScaffold(
      title: 'Group settings',
      subtitle: collection.title,
      children: [
        MoneyHeroCard(
          amount: summary.amountRaisedRwf,
          label: collection.title,
          detail: '${summary.supporterCount} members',
        ),
        _SettingsSection(
          children: [
            _ManageTile(
              icon: CollectIcons.info,
              title: 'Group profile',
              onTap: () => context.go('/groups/${widget.collectionId}/profile'),
            ),
            _ManageTile(
              icon: CollectIcons.qr,
              title: 'Group QR',
              onTap: () => context.go('/groups/${widget.collectionId}/share'),
            ),
            _ManageTile(
              icon: CollectIcons.share,
              title: 'Share group',
              onTap: () => shareGroupDeepLink(
                context: context,
                ref: ref,
                collection: collection,
              ),
            ),
          ],
        ),
        _SettingsSection(
          children: [
            _ManageTile(
              icon: CollectIcons.people,
              title: 'Members',
              subtitle: '${summary.supporterCount}',
              onTap: () => context.go('/groups/${widget.collectionId}/members'),
            ),
            _ManageTile(
              icon: CollectIcons.admin,
              title: 'Add admin',
              subtitle: 'more group admin',
              onTap: _working ? null : _showAddAdminSheet,
            ),
            _ManageTile(
              icon: CollectIcons.ledger,
              title: 'Ledger',
              subtitle: formatRwf(summary.amountRaisedRwf),
              onTap: () => context.go('/groups/${widget.collectionId}/ledger'),
            ),
          ],
        ),
        _SettingsSection(
          destructive: true,
          children: [
            _ManageTile(
              icon: Icons.switch_account_rounded,
              title: 'Transfer ownership',
              subtitle: 'Move owner rights to another Collect ID',
              onTap: _working ? null : _showTransferSheet,
            ),
            _ManageTile(
              icon: Icons.archive_rounded,
              title: 'Archive group',
              subtitle: 'Hide the group from active use',
              onTap: _working ? null : _showArchiveSheet,
            ),
            const _ManageTile(
              icon: CollectIcons.support,
              title: 'Support',
              onTap: openCollectWhatsAppSupport,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showAddAdminSheet() {
    return _showPublicIdSheet(
      title: 'Add admin',
      controller: _adminPublicId,
      actionLabel: 'Add admin',
      onSubmit: (publicId) async {
        await ref
            .read(collectRepositoryProvider.notifier)
            .inviteCollectionAdmin(
              collectionId: widget.collectionId,
              publicId: publicId,
            );
      },
    );
  }

  Future<void> _showTransferSheet() {
    return _showPublicIdSheet(
      title: 'Transfer ownership',
      controller: _ownerPublicId,
      actionLabel: 'Transfer',
      destructive: true,
      onSubmit: (publicId) async {
        await ref
            .read(collectRepositoryProvider.notifier)
            .transferCollectionOwnership(
              collectionId: widget.collectionId,
              publicId: publicId,
            );
      },
    );
  }

  Future<void> _showPublicIdSheet({
    required String title,
    required TextEditingController controller,
    required String actionLabel,
    required Future<void> Function(String publicId) onSubmit,
    bool destructive = false,
  }) {
    controller.clear();
    String? error;
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: context.collectColors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return CollectBottomSheet(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  CollectSpacing.gap16,
                  CollectTextInput(
                    controller: controller,
                    label: 'Collect ID',
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                  ),
                  if (error != null) ...[
                    CollectSpacing.gap12,
                    Text(
                      error!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.collectColors.danger,
                      ),
                    ),
                  ],
                  CollectSpacing.gap20,
                  CollectButton(
                    label: _working ? 'Saving' : actionLabel,
                    icon: destructive
                        ? Icons.switch_account_rounded
                        : CollectIcons.check,
                    variant: destructive
                        ? CollectButtonVariant.secondary
                        : CollectButtonVariant.primary,
                    onPressed: _working
                        ? null
                        : () async {
                            final navigator = Navigator.of(sheetContext);
                            setState(() => _working = true);
                            setSheetState(() => error = null);
                            try {
                              await onSubmit(controller.text);
                              if (!sheetContext.mounted) return;
                              navigator.pop();
                            } catch (exception) {
                              if (!mounted) return;
                              setSheetState(() => error = exception.toString());
                            } finally {
                              if (mounted) setState(() => _working = false);
                            }
                          },
                    expand: true,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showArchiveSheet() {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: context.collectColors.transparent,
      builder: (sheetContext) {
        return CollectBottomSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Archive group',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              CollectSpacing.gap12,
              Text(
                'The group leaves active lists. Existing ledger records stay in the system.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              CollectSpacing.gap20,
              CollectButton(
                label: _working ? 'Archiving' : 'Archive group',
                icon: Icons.archive_rounded,
                variant: CollectButtonVariant.secondary,
                onPressed: _working
                    ? null
                    : () async {
                        final navigator = Navigator.of(sheetContext);
                        setState(() => _working = true);
                        try {
                          await ref
                              .read(collectRepositoryProvider.notifier)
                              .archiveCollection(widget.collectionId);
                          if (!sheetContext.mounted || !mounted) return;
                          navigator.pop();
                          context.go('/groups');
                        } finally {
                          if (mounted) setState(() => _working = false);
                        }
                      },
                expand: true,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.children, this.destructive = false});

  final List<Widget> children;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      emphasis: CollectCardEmphasis.flat,
      accentColor: destructive ? context.collectColors.danger : null,
      child: Column(children: children),
    );
  }
}

class _ManageTile extends StatelessWidget {
  const _ManageTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return CollectListTile(
      leading: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
    );
  }
}
