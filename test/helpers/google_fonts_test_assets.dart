import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_fonts/src/google_fonts_base.dart';

void setUpBundledGoogleFonts() {
  GoogleFonts.config.allowRuntimeFetching = false;
  assetManifest = const _BundledGoogleFontsAssetManifest();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', _handleMockAssetLoad);
}

void tearDownBundledGoogleFonts() {
  clearCache();
  assetManifest = null;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', null);
}

Future<ByteData?> _handleMockAssetLoad(ByteData? message) async {
  if (message == null) {
    return null;
  }

  final key = utf8.decode(message.buffer.asUint8List());
  if (!key.startsWith('google_fonts/')) {
    return null;
  }

  final file = File(key);
  if (!file.existsSync()) {
    return null;
  }

  final bytes = await file.readAsBytes();
  return ByteData.sublistView(Uint8List.fromList(bytes));
}

class _BundledGoogleFontsAssetManifest implements AssetManifest {
  const _BundledGoogleFontsAssetManifest();

  @override
  List<String> listAssets() {
    final dir = Directory('google_fonts');
    if (!dir.existsSync()) {
      return const <String>[];
    }

    final assets =
        dir
            .listSync()
            .whereType<File>()
            .map((file) => 'google_fonts/${file.uri.pathSegments.last}')
            .toList()
          ..sort();
    return assets;
  }

  @override
  List<AssetMetadata>? getAssetVariants(String key) => null;
}
