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
import 'group_empty_state.dart';
import 'group_share_service.dart';

class ShareScreen extends ConsumerWidget {
  const ShareScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.collectColors;
    final env = ref.watch(appEnvProvider);
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collection = repo.maybeCollectionById(collectionId);
    if (collection == null) return const MissingGroupStateScreen();
    if (collection.isArchived) {
      return ArchivedGroupStateScreen(
        collectionId: collectionId,
        groupTitle: collection.title,
      );
    }
    final summary = repo.summaryFor(collectionId);
    final link = groupDeepLinkFor(env, collection);
    final filename = '${collection.slug}-qr';
    final shareText = groupShareMessageFor(env, collection);

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
                                    'Group QR',
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
                                    '${collection.collectionType.shortPurpose} link',
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
                                  context.go('/groups/$collectionId'),
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
                              label: '${summary.supporterCount} members',
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
                              'The QR shares the group invitation. Receiver MoMo numbers, raw SMS, and private member phones stay hidden.',
                          tone: CollectStatusTone.privacy,
                          messageMaxLines: 2,
                        ),
                        CollectSpacing.gap16,
                        Row(
                          children: [
                            Expanded(
                              child: CollectButton(
                                label: 'Share',
                                icon: CollectIcons.share,
                                onPressed: () => _shareQr(
                                  context,
                                  link,
                                  filename,
                                  shareText,
                                ),
                                expand: true,
                              ),
                            ),
                            CollectSpacing.gapW12,
                            Expanded(
                              child: CollectButton(
                                label: 'Save',
                                icon: CollectIcons.download,
                                onPressed: () =>
                                    _saveQr(context, link, filename),
                                variant: CollectButtonVariant.secondary,
                                expand: true,
                              ),
                            ),
                          ],
                        ),
                        CollectSpacing.gap12,
                        CollectButton(
                          label: 'Copy group link',
                          icon: CollectIcons.copy,
                          onPressed: () => _copyLink(context, link),
                          variant: CollectButtonVariant.subtle,
                          expand: true,
                        ),
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
