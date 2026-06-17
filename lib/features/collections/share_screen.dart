import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/env/app_env.dart';
import '../../shared/repositories/collect_repository.dart';
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
    final link = groupDeepLinkFor(env, collection);
    final filename = '${collection.slug}-qr';
    final shareText = groupShareMessageFor(env, collection);

    return CollectGradientBackground(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            CollectSpacing.x5,
            CollectSpacing.x4,
            CollectSpacing.x5,
            CollectSpacing.x5,
          ),
          child: Column(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => context.go('/groups/$collectionId'),
                ),
              ),
              CollectBottomSheet(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.glassBorder,
                        borderRadius: CollectRadius.pillBorder,
                      ),
                      child: const SizedBox(width: 44, height: 4),
                    ),
                    CollectSpacing.gap16,
                    Row(
                      children: [
                        const _ShareBrandMark(),
                        CollectSpacing.gapW16,
                        Expanded(
                          child: Text(
                            collection.title,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        CollectSpacing.gapW12,
                        IconButton.filledTonal(
                          tooltip: 'Close',
                          onPressed: () => context.go('/groups/$collectionId'),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    CollectSpacing.gap20,
                    _BrandedQrCard(data: link),
                    CollectSpacing.gap20,
                    Row(
                      children: [
                        Expanded(
                          child: CollectButton(
                            label: 'Share',
                            icon: CollectIcons.share,
                            onPressed: () =>
                                _shareQr(context, link, filename, shareText),
                            expand: true,
                          ),
                        ),
                        CollectSpacing.gapW12,
                        Expanded(
                          child: CollectButton(
                            label: 'Save',
                            icon: CollectIcons.download,
                            onPressed: () => _saveQr(context, link, filename),
                            variant: CollectButtonVariant.secondary,
                            expand: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
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
      final bytes = await _qrPngBytes(link);
      await SharePlus.instance.share(
        ShareParams(
          title: 'Group QR',
          text: text,
          files: [
            XFile.fromData(bytes, mimeType: 'image/png', name: '$filename.png'),
          ],
          fileNameOverrides: ['$filename.png'],
          downloadFallbackEnabled: true,
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Open on your phone to share QR.')),
      );
    }
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
  const outerPadding = 54.0;
  const innerPadding = 84.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));
  final outerRect = RRect.fromRectAndRadius(
    const Rect.fromLTWH(0, 0, size, size),
    const Radius.circular(96),
  );
  final gradientPaint = Paint()
    ..shader = const LinearGradient(
      colors: CollectColors.brandPrimaryColors,
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).createShader(const Rect.fromLTWH(0, 0, size, size));
  canvas.drawRRect(outerRect, gradientPaint);
  final innerRect = RRect.fromRectAndRadius(
    const Rect.fromLTWH(
      outerPadding,
      outerPadding,
      size - (outerPadding * 2),
      size - (outerPadding * 2),
    ),
    const Radius.circular(78),
  );
  canvas.drawRRect(innerRect, Paint()..color = CollectColors.brandPaper);
  final painter = QrPainter(
    data: link,
    version: QrVersions.auto,
    errorCorrectionLevel: QrErrorCorrectLevel.H,
    gapless: true,
    eyeStyle: const QrEyeStyle(
      eyeShape: QrEyeShape.circle,
      color: CollectColors.brandPeriwinkle,
    ),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.circle,
      color: CollectColors.brandPeriwinkle,
    ),
  );
  const qrRect = Rect.fromLTWH(
    innerPadding,
    innerPadding,
    size - (innerPadding * 2),
    size - (innerPadding * 2),
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
        gradient: const LinearGradient(
          colors: CollectColors.brandPrimaryColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: CollectRadius.cardLargeBorder,
        boxShadow: [
          BoxShadow(
            color: colors.shadowPaint.withValues(alpha: 0.18),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(CollectSpacing.x3),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colors.exportCanvas,
                CollectColors.brandPaper,
                CollectColors.brandMintGreen.withValues(alpha: 0.20),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: CollectRadius.cardLargeBorder,
          ),
          child: Padding(
            padding: const EdgeInsets.all(CollectSpacing.x4),
            child: Stack(
              alignment: Alignment.center,
              children: [
                QrImageView(
                  data: data,
                  size: 196,
                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                  backgroundColor: colors.transparent,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.circle,
                    color: CollectColors.inkPrimary,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.circle,
                    color: CollectColors.inkPrimary,
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

class _ShareBrandMark extends StatelessWidget {
  const _ShareBrandMark();

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      label: 'Collect',
      image: true,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.onImagePrimary.withValues(alpha: 0.10),
            borderRadius: CollectRadius.pillBorder,
            border: Border.all(
              color: colors.onImagePrimary.withValues(alpha: 0.16),
            ),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: CollectSpacing.x3,
              vertical: CollectSpacing.x2,
            ),
            child: CollectBrandMark(
              compact: true,
              framed: false,
              width: 104,
              height: 30,
            ),
          ),
        ),
      ),
    );
  }
}
