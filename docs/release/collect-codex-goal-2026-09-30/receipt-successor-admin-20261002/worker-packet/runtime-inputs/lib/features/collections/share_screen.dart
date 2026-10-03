import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/env/app_env.dart';
import '../../core/utils/money_format.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/utils/collect_share_origin.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import 'group_empty_state.dart';
import 'group_share_service.dart';
import 'group_invitation_transport.dart';

class ShareScreen extends ConsumerStatefulWidget {
  const ShareScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  ConsumerState<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends ConsumerState<ShareScreen> {
  String? _shareCode;
  String? _loadError;
  bool _loading = true;
  bool _rotating = false;
  int _invitationEpoch = 0;
  GroupInvitationOutputScope? _sourceScope;

  @override
  void dispose() {
    ++_invitationEpoch;
    _sourceScope?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ShareScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collectionId == widget.collectionId) return;
    ++_invitationEpoch;
    _sourceScope?.dispose();
    _sourceScope = null;
    _shareCode = null;
    _loading = true;
    _loadError = null;
    Future<void>.microtask(_loadShareCode);
  }

  GroupInvitationOutputScope _beginOutput(
    BuildContext context, {
    bool requireOwner = false,
  }) {
    if (_sourceScope?.isCurrent != true) {
      throw StateError('Invitation changed. Refresh before sharing.');
    }
    return GroupInvitationOutputScope(
      context,
      ref,
      widget.collectionId,
      requireOwner: requireOwner,
    );
  }

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadShareCode);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final env = ref.watch(appEnvProvider);
    ref.watch(collectRepositoryProvider);
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collection = repo.maybeCollectionById(widget.collectionId);
    if (collection == null) return const MissingGroupStateScreen();
    if (collection.isArchived) {
      return ArchivedGroupStateScreen(
        collectionId: widget.collectionId,
        groupTitle: collection.title,
      );
    }
    if (_loading) {
      return const ScreenScaffold(
        title: 'Share group',
        showHeader: false,
        children: [
          CollectScreenLoadingState(
            title: 'Preparing secure invitation',
            message: 'Loading the current link and QR code.',
            icon: CollectIcons.share,
            skeletonCount: 2,
          ),
        ],
      );
    }
    final sourceInvalid = _sourceScope != null && !_sourceScope!.isCurrent;
    if (_loadError != null || sourceInvalid) {
      return ScreenScaffold(
        title: 'Share group',
        showHeader: false,
        children: [
          EmptyIllustrationState(
            icon: CollectIcons.lock,
            title: 'Invitation unavailable',
            message:
                _loadError ??
                'The invitation changed. Refresh before sharing it.',
            action: CollectButton(
              label: 'Try again',
              icon: Icons.refresh_rounded,
              onPressed: _loadShareCode,
              expand: true,
            ),
          ),
        ],
      );
    }
    final summary = repo.summaryFor(widget.collectionId);
    final link = groupDeepLinkForCode(env, collection, _shareCode);
    final filename = '${collection.slug}-qr';
    final shareText = groupShareMessageFor(
      env,
      collection,
      shareCode: _shareCode,
    );
    final profile = ref.watch(collectRepositoryProvider).currentProfile;
    final isOwner = profile?.id == collection.creatorUserId;

    return CollectGradientBackground(
      child: Scaffold(
        backgroundColor: colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(CollectSpacing.x4),
            child: Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: CollectBottomSheet(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.panelBorder,
                            borderRadius: CollectRadius.pillBorder,
                          ),
                          child: const SizedBox(width: 44, height: 4),
                        ),
                        CollectSpacing.gap12,
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Share group',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          fontWeight:
                                              CollectTypography.weightBold,
                                        ),
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  CollectSpacing.gap4,
                                  Text(
                                    collection.title,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: colors.textSecondary),
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            CollectSpacing.gapW12,
                            IconButton.filledTonal(
                              tooltip: 'Close',
                              onPressed: () =>
                                  context.go('/groups/${widget.collectionId}'),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        CollectSpacing.gap12,
                        Wrap(
                          spacing: CollectSpacing.x2,
                          runSpacing: CollectSpacing.x2,
                          alignment: WrapAlignment.center,
                          children: [
                            CollectStatusChip(
                              label: collection.isPublic ? 'Public' : 'Private',
                              tone: collection.isPublic
                                  ? CollectStatusTone.success
                                  : CollectStatusTone.privacy,
                              icon: collection.isPublic
                                  ? CollectIcons.check
                                  : CollectIcons.lock,
                            ),
                            CollectStatusChip(
                              label: summary == null
                                  ? 'Not available'
                                  : formatCurrencyTotals(
                                      summary.totalsByCurrency,
                                      separator: '\n',
                                    ),
                              tone: CollectStatusTone.info,
                              icon: CollectIcons.ledger,
                            ),
                            CollectPeopleCount(count: summary?.supporterCount),
                          ],
                        ),
                        CollectSpacing.gap16,
                        _BrandedQrCard(data: link),
                        CollectSpacing.gap16,
                        CollectButton(
                          label: 'Share link',
                          icon: CollectIcons.share,
                          onPressed: () => _shareLink(context, collection),
                          expand: true,
                        ),
                        CollectSpacing.gap12,
                        CollectButton(
                          label: 'Share QR code',
                          icon: CollectIcons.qr,
                          onPressed: () =>
                              _shareQr(context, link, filename, shareText),
                          variant: CollectButtonVariant.secondary,
                          expand: true,
                        ),
                        CollectSpacing.gap12,
                        Row(
                          children: [
                            Expanded(
                              child: CollectButton(
                                label: 'Save QR',
                                icon: CollectIcons.download,
                                onPressed: () =>
                                    _saveQr(context, link, filename),
                                variant: CollectButtonVariant.subtle,
                                expand: true,
                              ),
                            ),
                            CollectSpacing.gapW12,
                            Expanded(
                              child: CollectButton(
                                label: 'Copy link',
                                icon: CollectIcons.copy,
                                onPressed: () => _copyLink(context, link),
                                variant: CollectButtonVariant.subtle,
                                expand: true,
                              ),
                            ),
                          ],
                        ),
                        if (isOwner) ...[
                          CollectSpacing.gap12,
                          CollectButton(
                            label: _rotating
                                ? 'Rotating link'
                                : 'Replace invitation link',
                            icon: Icons.autorenew_rounded,
                            onPressed: _rotating ? null : _rotateShareCode,
                            variant: CollectButtonVariant.subtle,
                            expand: true,
                          ),
                          CollectSpacing.gap8,
                          Text(
                            'Replacing the link invalidates every older private invitation and QR code.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colors.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadShareCode() async {
    final epoch = ++_invitationEpoch;
    final groupId = widget.collectionId;
    _sourceScope?.dispose();
    _sourceScope = null;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
        _shareCode = null;
      });
    }
    GroupInvitationOutputScope? scope;
    try {
      scope = GroupInvitationOutputScope(context, ref, groupId);
      final code = await ref
          .read(collectRepositoryProvider.notifier)
          .getGroupShareCode(groupId);
      scope.check();
      if (!mounted ||
          epoch != _invitationEpoch ||
          widget.collectionId != groupId) {
        return;
      }
      _sourceScope = scope;
      scope = null;
      setState(() {
        _shareCode = code;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || epoch != _invitationEpoch) return;
      setState(() {
        _loading = false;
        _loadError =
            'The secure group link could not be loaded. Refresh before sharing.';
      });
    } finally {
      scope?.dispose();
    }
  }

  Future<void> _rotateShareCode() async {
    if (_rotating) return;
    GroupInvitationOutputScope? scope;
    try {
      scope = _beginOutput(context, requireOwner: true);
      final confirmed = await showCollectConfirmationSheet(
        context: context,
        title: 'Replace invitation link?',
        message:
            'Every older private link and QR code will stop working. Existing members stay in the group.',
        cancelLabel: 'Keep current link',
        confirmLabel: 'Replace link',
      );
      if (confirmed != true || !scope.isCurrent) return;
      setState(() => _rotating = true);
      final code = await ref
          .read(collectRepositoryProvider.notifier)
          .rotateGroupShareCode(widget.collectionId);
      scope.check();
      if (!mounted) return;
      setState(() {
        _shareCode = code;
        _rotating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new invitation link is ready.')),
      );
    } catch (_) {
      if (scope?.isCurrent != true) return;
      _sourceScope?.dispose();
      _sourceScope = null;
      setState(() {
        _rotating = false;
        _shareCode = null;
        _loadError =
            'The invitation replacement could not be confirmed. Refresh the current invitation before replacing it again.';
      });
    } finally {
      scope?.dispose();
      if (mounted && _rotating) setState(() => _rotating = false);
    }
  }

  Future<void> _shareLink(
    BuildContext context,
    CollectCollection collection,
  ) async {
    try {
      if (!context.mounted || _sourceScope?.isCurrent != true) return;
      await shareGroupDeepLink(
        context: context,
        ref: ref,
        collection: collection,
        shareCode: _shareCode,
      );
    } catch (_) {
      if (!context.mounted || _sourceScope?.isCurrent != true) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The invitation could not be shared. Refresh and try again.',
          ),
        ),
      );
    }
  }

  Future<void> _confirmSource(GroupInvitationOutputScope scope) async {
    final expected = _shareCode;
    final sourceScope = _sourceScope;
    final epoch = _invitationEpoch;
    try {
      final current = await ref
          .read(collectRepositoryProvider.notifier)
          .getGroupShareCode(widget.collectionId);
      scope.check();
      if (_sourceScope?.isCurrent != true ||
          expected == null ||
          current != expected) {
        throw const FormatException(
          'The invitation changed. Refresh before sharing.',
        );
      }
    } catch (_) {
      if (mounted &&
          epoch == _invitationEpoch &&
          identical(_sourceScope, sourceScope)) {
        _sourceScope?.dispose();
        _sourceScope = null;
        setState(() {
          _shareCode = null;
          _loadError =
              'The current invitation could not be verified. Refresh before sharing.';
        });
      }
      rethrow;
    }
  }

  Future<void> _shareQr(
    BuildContext context,
    String link,
    String filename,
    String text,
  ) async {
    GroupInvitationOutputScope? scope;
    try {
      scope = _beginOutput(context);
      await _confirmSource(scope);
      if (!context.mounted) return;
      final origin = collectSharePositionOrigin(context);
      final transport = ref.read(groupInvitationTransportProvider);
      final bytes = await transport.renderQr(link);
      scope.check();
      try {
        await transport.shareQr(bytes, filename, text, origin);
      } catch (_) {
        scope.check();
        await transport.copyLink(link);
        if (context.mounted && scope.isCurrent) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Group link copied.')));
        }
      }
    } catch (_) {
      if (context.mounted && scope?.isCurrent == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The QR could not be shared. Refresh and try again.'),
          ),
        );
      }
    } finally {
      scope?.dispose();
    }
  }

  Future<void> _copyLink(BuildContext context, String link) async {
    GroupInvitationOutputScope? scope;
    try {
      scope = _beginOutput(context);
      await _confirmSource(scope);
      await ref.read(groupInvitationTransportProvider).copyLink(link);
      if (context.mounted && scope.isCurrent) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Group link copied.')));
      }
    } catch (_) {
      if (context.mounted && scope?.isCurrent == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The invitation could not be copied.')),
        );
      }
    } finally {
      scope?.dispose();
    }
  }

  Future<void> _saveQr(
    BuildContext context,
    String link,
    String filename,
  ) async {
    GroupInvitationOutputScope? scope;
    try {
      scope = _beginOutput(context);
      await _confirmSource(scope);
      final transport = ref.read(groupInvitationTransportProvider);
      final bytes = await transport.renderQr(link);
      scope.check();
      await transport.saveQr(bytes, filename);
      if (context.mounted && scope.isCurrent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(kIsWeb ? 'QR download started.' : 'QR saved.'),
          ),
        );
      }
    } catch (_) {
      if (context.mounted && scope?.isCurrent == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save QR. Refresh and try again.'),
          ),
        );
      }
    } finally {
      scope?.dispose();
    }
  }
}

class _BrandedQrCard extends StatelessWidget {
  const _BrandedQrCard({required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CollectColors.publicWhite,
        borderRadius: CollectRadius.cardLargeBorder,
        border: Border.all(color: colors.panelBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(CollectSpacing.x5),
        child: QrImageView(
          data: data,
          size: 196,
          errorCorrectionLevel: QrErrorCorrectLevel.H,
          backgroundColor: CollectColors.publicWhite,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: CollectColors.publicBlack,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: CollectColors.publicBlack,
          ),
        ),
      ),
    );
  }
}
