import 'dart:ui' as ui;

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/env/app_env.dart';
import '../../core/utils/money_format.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/utils/collect_share_origin.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import 'group_empty_state.dart';
import 'group_share_service.dart';

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

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadShareCode);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final env = ref.watch(appEnvProvider);
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
    if (_loadError != null) {
      return ScreenScaffold(
        title: 'Share group',
        showHeader: false,
        children: [
          EmptyIllustrationState(
            icon: CollectIcons.lock,
            title: 'Invitation unavailable',
            message: _loadError!,
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
                                    'Choose a link or QR code',
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
                              label: formatRwf(summary.amountRaisedRwf),
                              tone: CollectStatusTone.info,
                              icon: CollectIcons.ledger,
                            ),
                            CollectStatusChip(
                              label:
                                  '${summary.supporterCount} ${summary.supporterCount == 1 ? 'supporter' : 'supporters'}',
                              tone: CollectStatusTone.neutral,
                              icon: CollectIcons.people,
                            ),
                          ],
                        ),
                        CollectSpacing.gap16,
                        _BrandedQrCard(data: link),
                        CollectSpacing.gap16,
                        const InfoSecurityBanner(
                          title: 'Privacy-safe link',
                          message:
                              'Share the group invitation as a native link or QR code. Receiver MoMo numbers, raw SMS, and private member phones stay hidden.',
                          tone: CollectStatusTone.privacy,
                          messageMaxLines: 4,
                        ),
                        CollectSpacing.gap16,
                        CollectButton(
                          label: 'Share link',
                          icon: CollectIcons.share,
                          onPressed: () => shareGroupDeepLink(
                            context: context,
                            ref: ref,
                            collection: collection,
                            shareCode: _shareCode,
                          ),
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
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final code = await ref
          .read(collectRepositoryProvider.notifier)
          .getGroupShareCode(widget.collectionId);
      if (!mounted) return;
      setState(() {
        _shareCode = code;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'The secure group link could not be loaded.';
      });
    }
  }

  Future<void> _rotateShareCode() async {
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: CollectMotion.animationStyle(context),
      builder: (dialogContext) => AlertDialog(
        title: const Text('Replace invitation link?'),
        content: const Text(
          'Every older private link and QR code will stop working. Existing members stay in the group.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep current link'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Replace link'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _rotating = true);
    try {
      final code = await ref
          .read(collectRepositoryProvider.notifier)
          .rotateGroupShareCode(widget.collectionId);
      if (!mounted) return;
      setState(() {
        _shareCode = code;
        _rotating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new invitation link is ready.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _rotating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not replace the link.')),
      );
    }
  }

  Future<void> _shareQr(
    BuildContext context,
    String link,
    String filename,
    String text,
  ) async {
    try {
      final sharePositionOrigin = collectSharePositionOrigin(context);
      final bytes = await _qrPngBytes(link);
      await SharePlus.instance.share(
        ShareParams(
          title: 'Group QR',
          text: text,
          files: [
            XFile.fromData(bytes, mimeType: 'image/png', name: '$filename.png'),
          ],
          fileNameOverrides: ['$filename.png'],
          sharePositionOrigin: sharePositionOrigin,
          downloadFallbackEnabled: true,
        ),
      );
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: link));
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Group link copied.')));
    }
  }

  Future<void> _copyLink(BuildContext context, String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Group link copied.')));
  }

  Future<void> _saveQr(
    BuildContext context,
    String link,
    String filename,
  ) async {
    try {
      final bytes = await _qrPngBytes(link);
      await FileSaver.instance.saveFile(
        name: filename,
        bytes: bytes,
        fileExtension: 'png',
        mimeType: MimeType.png,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('QR saved.')));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not save QR.')));
    }
  }
}

Future<Uint8List> _qrPngBytes(String link) async {
  const size = 1080.0;
  const qrPadding = 96.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));
  final canvasRect = RRect.fromRectAndRadius(
    const Rect.fromLTWH(0, 0, size, size),
    const Radius.circular(72),
  );
  canvas.drawRRect(canvasRect, Paint()..color = CollectColors.brandPaper);
  final painter = QrPainter(
    data: link,
    version: QrVersions.auto,
    errorCorrectionLevel: QrErrorCorrectLevel.H,
    gapless: true,
    eyeStyle: const QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: CollectColors.publicBlack,
    ),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: CollectColors.publicBlack,
    ),
  );
  const qrRect = Rect.fromLTWH(
    qrPadding,
    qrPadding,
    size - (qrPadding * 2),
    size - (qrPadding * 2),
  );
  canvas.save();
  canvas.translate(qrRect.left, qrRect.top);
  painter.paint(canvas, qrRect.size);
  canvas.restore();
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.toInt(), size.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) {
    throw StateError('QR export failed');
  }
  return data.buffer.asUint8List();
}

class _BrandedQrCard extends StatelessWidget {
  const _BrandedQrCard({required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CollectColors.brandPaper,
        borderRadius: CollectRadius.cardLargeBorder,
        border: Border.all(color: colors.panelBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(CollectSpacing.x5),
        child: QrImageView(
          data: data,
          size: 196,
          errorCorrectionLevel: QrErrorCorrectLevel.H,
          backgroundColor: CollectColors.brandPaper,
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
