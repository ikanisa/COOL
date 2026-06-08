import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/env/app_env.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import 'group_share_service.dart';

class ShareScreen extends ConsumerWidget {
  const ShareScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.collectColors;
    final env = ref.watch(appEnvProvider);
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collection = repo.collectionById(collectionId);
    final link = groupDeepLinkFor(env, collection);
    final filename = '${collection.slug}-qr';
    final shareText = groupShareMessageFor(env, collection);

    return SafeArea(
      child: ColoredBox(
        color: colors.surface,
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
                        color: colors.border.withValues(alpha: 0.82),
                        borderRadius: CollectRadius.pillBorder,
                      ),
                      child: const SizedBox(width: 44, height: 4),
                    ),
                    CollectSpacing.gap16,
                    Row(
                      children: [
                        IconButton.filledTonal(
                          tooltip: 'Close',
                          onPressed: () => context.go('/groups/$collectionId'),
                          icon: const Icon(Icons.close_rounded),
                        ),
                        CollectSpacing.gapW12,
                        Expanded(
                          child: Text(
                            collection.title,
                            style: Theme.of(context).textTheme.titleLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    CollectSpacing.gap20,
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: CollectRadius.cardLargeBorder,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 28,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(CollectSpacing.x5),
                        child: QrImageView(
                          data: link,
                          size: 238,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.circle,
                            color: Color(0xFF171013),
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.circle,
                            color: Color(0xFF171013),
                          ),
                        ),
                      ),
                    ),
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
  final painter = QrPainter(
    data: link,
    version: QrVersions.auto,
    gapless: true,
    eyeStyle: const QrEyeStyle(
      eyeShape: QrEyeShape.circle,
      color: Color(0xFF171013),
    ),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.circle,
      color: Color(0xFF171013),
    ),
  );
  final data = await painter.toImageData(960, format: ui.ImageByteFormat.png);
  if (data == null) {
    throw StateError('QR export failed');
  }
  return data.buffer.asUint8List();
}
