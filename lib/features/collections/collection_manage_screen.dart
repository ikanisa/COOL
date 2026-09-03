import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/money_format.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/utils/support_contact.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import 'group_empty_state.dart';

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
    if (collection.isArchived) {
      return ArchivedGroupStateScreen(
        collectionId: widget.collectionId,
        groupTitle: collection.title,
      );
    }
    final summary = repo.summaryFor(widget.collectionId);
    final profile = state.currentProfile;
    final isOwner = profile != null && collection.creatorUserId == profile.id;

    if (collection.isPlatformSponsored || collection.isPublic) {
      return ScreenScaffold(
        title: 'Group settings',
        subtitle: collection.title,
        children: const [
          MinimalStatePanel(
            icon: CollectIcons.lock,
            title: 'Managed in Admin',
            message: 'This group is managed by Collect.',
            tone: CollectStatusTone.privacy,
          ),
        ],
      );
    }

    if (!isOwner) {
      return ScreenScaffold(
        title: 'Group settings',
        subtitle: collection.title,
        children: [
          const MinimalStatePanel(
            icon: CollectIcons.lock,
            title: 'Owner only',
            message:
                'Only the current group owner can change group details, add group admins, transfer ownership, or archive this group.',
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
          currency: summary.currency,
          totalsByCurrency: summary.totalsByCurrency,
          label: collection.title,
          chips: [CollectPeopleCount(count: summary.supporterCount)],
        ),
        _SettingsSection(
          children: [
            _ManageTile(
              icon: CollectIcons.info,
              title: 'Group profile',
              onTap: () => context.go('/groups/${widget.collectionId}/profile'),
            ),
            _ManageTile(
              icon: CollectIcons.share,
              title: 'Share group',
              subtitle: 'Share the group link or QR code',
              onTap: () => context.go('/groups/${widget.collectionId}/share'),
            ),
          ],
        ),
        _SettingsSection(
          children: [
            _ManageTile(
              icon: CollectIcons.people,
              title: 'Members',
              subtitle: 'View and manage active membership',
              onTap: () => context.go('/groups/${widget.collectionId}/members'),
            ),
            _ManageTile(
              icon: CollectIcons.admin,
              title: 'Add admin',
              onTap: _showAddAdminSheet,
            ),
            _ManageTile(
              icon: CollectIcons.ledger,
              title: 'Ledger',
              subtitle: formatCurrencyTotals(
                summary.totalsByCurrency,
                separator: '\n',
              ),
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
              onTap: _showTransferSheet,
            ),
            _ManageTile(
              icon: Icons.archive_rounded,
              title: 'Archive group',
              subtitle: 'Hide the group from active use',
              onTap: _showArchiveSheet,
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
      supportingText:
          'Enter the six-digit Collect ID of an active group member.',
      successMessage: 'Group admin added.',
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
      actionLabel: 'Transfer ownership',
      supportingText:
          'This removes your owner controls. The new owner must use a different six-digit Collect ID.',
      destructive: true,
      successMessage: 'Group ownership transferred.',
      onSuccess: () => context.go('/groups/${widget.collectionId}'),
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
    required String supportingText,
    required Future<void> Function(String publicId) onSubmit,
    String? successMessage,
    VoidCallback? onSuccess,
    bool destructive = false,
  }) {
    controller.clear();
    String? error;
    var working = false;
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: context.collectColors.transparent,
      sheetAnimationStyle: CollectMotion.animationStyle(context),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              if (working) return;
              setSheetState(() {
                working = true;
                error = null;
              });
              try {
                await onSubmit(controller.text);
                if (!sheetContext.mounted || !mounted) return;
                Navigator.of(sheetContext).pop();
                onSuccess?.call();
                if (successMessage != null) {
                  _showSuccessMessage(successMessage);
                }
              } catch (exception) {
                if (!sheetContext.mounted) return;
                setSheetState(() {
                  error = _safeGroupActionError(
                    exception,
                    fallbackAction: title.toLowerCase(),
                  );
                });
              } finally {
                if (sheetContext.mounted) {
                  setSheetState(() => working = false);
                }
              }
            }

            return AnimatedPadding(
              duration: CollectMotion.duration(context, CollectMotion.fast),
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: CollectBottomSheet(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    CollectSpacing.gap8,
                    Text(
                      supportingText,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.collectColors.textSecondary,
                      ),
                    ),
                    CollectSpacing.gap16,
                    CollectTextInput(
                      controller: controller,
                      label: 'Collect ID',
                      helper: 'Six digits',
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => submit(),
                    ),
                    if (error != null) ...[
                      CollectSpacing.gap12,
                      Semantics(
                        liveRegion: true,
                        excludeSemantics: true,
                        label: error,
                        child: Text(
                          error!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: context.collectColors.danger),
                        ),
                      ),
                    ],
                    CollectSpacing.gap20,
                    CollectButton(
                      label: working ? 'Saving' : actionLabel,
                      icon: destructive
                          ? Icons.switch_account_rounded
                          : CollectIcons.check,
                      variant: destructive
                          ? CollectButtonVariant.danger
                          : CollectButtonVariant.primary,
                      onPressed: working ? null : submit,
                      expand: true,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showArchiveSheet() {
    String? error;
    var working = false;
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: context.collectColors.transparent,
      sheetAnimationStyle: CollectMotion.animationStyle(context),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> archive() async {
              if (working) return;
              setSheetState(() {
                working = true;
                error = null;
              });
              try {
                await ref
                    .read(collectRepositoryProvider.notifier)
                    .archiveCollection(widget.collectionId);
                if (!sheetContext.mounted || !mounted) return;
                Navigator.of(sheetContext).pop();
                context.go('/groups');
                _showSuccessMessage(
                  'Group archived. Ledger records were kept.',
                );
              } catch (exception) {
                if (!sheetContext.mounted) return;
                setSheetState(() {
                  error = _safeGroupActionError(
                    exception,
                    fallbackAction: 'archive the group',
                  );
                });
              } finally {
                if (sheetContext.mounted) {
                  setSheetState(() => working = false);
                }
              }
            }

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
                    'The group leaves Home, Groups, Contribute, sharing, and invitations. Existing confirmed ledger records stay available.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (error != null) ...[
                    CollectSpacing.gap12,
                    Semantics(
                      liveRegion: true,
                      excludeSemantics: true,
                      label: error,
                      child: Text(
                        error!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.collectColors.danger,
                        ),
                      ),
                    ),
                  ],
                  CollectSpacing.gap20,
                  CollectButton(
                    label: working ? 'Archiving' : 'Archive group',
                    icon: Icons.archive_rounded,
                    variant: CollectButtonVariant.danger,
                    onPressed: working ? null : archive,
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

  void _showSuccessMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _safeGroupActionError(
    Object exception, {
    required String fallbackAction,
  }) {
    if (exception is FormatException) {
      return exception.message.toString();
    }
    if (exception is StateError) {
      return exception.message.toString();
    }
    return 'Could not $fallbackAction. Check your connection and try again.';
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
