import 'dart:ui' as ui;

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../shared/widgets/collect_components.dart';

final groupInvitationTransportProvider = Provider<GroupInvitationTransport>(
  (ref) => const GroupInvitationTransport(),
);

/// The real platform boundary, injectable for delayed/error transport tests.
/// Authority belongs to the caller and is checked before every dispatch.
class GroupInvitationTransport {
  const GroupInvitationTransport();
  Future<Uint8List> renderQr(String link) => _groupInvitationQrBytes(link);
  Future<void> shareLink(String title, String text, Rect origin) async {
    await SharePlus.instance.share(
      ShareParams(
        title: title,
        text: text,
        sharePositionOrigin: origin,
        downloadFallbackEnabled: true,
      ),
    );
  }

  Future<void> shareQr(
    Uint8List bytes,
    String filename,
    String text,
    Rect origin,
  ) async {
    await SharePlus.instance.share(
      ShareParams(
        title: 'Group QR',
        text: text,
        files: [
          XFile.fromData(bytes, mimeType: 'image/png', name: '$filename.png'),
        ],
        fileNameOverrides: ['$filename.png'],
        sharePositionOrigin: origin,
        downloadFallbackEnabled: true,
      ),
    );
  }

  Future<void> saveQr(Uint8List bytes, String filename) async {
    final receipt = await saveQrFile(bytes, filename);
    final nativePath = receipt.replaceAll('\\', '/');
    final confirmed = kIsWeb
        ? receipt == 'Downloads'
        : receipt == receipt.trim() &&
              !RegExp(r'[\x00-\x1f\x7f]').hasMatch(receipt) &&
              (nativePath.startsWith('/') ||
                  RegExp(r'^[A-Za-z]:/').hasMatch(nativePath)) &&
              nativePath.endsWith('/$filename.png');
    if (!confirmed) {
      throw StateError('QR save did not confirm the requested file.');
    }
  }

  /// Keep receipt checks in [saveQr] when testing the actual platform handler.
  @protected
  Future<String> saveQrFile(Uint8List bytes, String filename) =>
      FileSaver.instance.saveFile(
        name: filename,
        bytes: bytes,
        fileExtension: 'png',
        mimeType: MimeType.png,
      );

  Future<void> copyLink(String link) =>
      Clipboard.setData(ClipboardData(text: link));
}

Future<Uint8List> _groupInvitationQrBytes(String link) async {
  const size = 1080.0;
  const qrPadding = 96.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));
  final canvasRect = RRect.fromRectAndRadius(
    const Rect.fromLTWH(0, 0, size, size),
    const Radius.circular(72),
  );
  canvas.drawRRect(canvasRect, Paint()..color = CollectColors.publicWhite);
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
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('QR export failed');
    }
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
