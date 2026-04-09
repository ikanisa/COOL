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
  final path = switch (key) {
    'google_fonts/DMSans-Regular.ttf' => 'assets/fonts/Lato-Regular.ttf',
    'google_fonts/DMSans-Medium.ttf' => 'assets/fonts/Lato-Regular.ttf',
    'google_fonts/DMSans-SemiBold.ttf' => 'assets/fonts/Lato-Bold.ttf',
    'google_fonts/DMSans-Bold.ttf' => 'assets/fonts/Lato-Bold.ttf',
    'google_fonts/DMSans-ExtraBold.ttf' => 'assets/fonts/Lato-Bold.ttf',
    'google_fonts/DMMono-Regular.ttf' => 'assets/fonts/Lato-Regular.ttf',
    'google_fonts/DMMono-Medium.ttf' => 'assets/fonts/Lato-Bold.ttf',
    'google_fonts/DMMono-Bold.ttf' => 'assets/fonts/Lato-Bold.ttf',
    'google_fonts/Inter-Regular.ttf' => 'assets/fonts/Lato-Regular.ttf',
    'google_fonts/Inter-Italic.ttf' => 'assets/fonts/Lato-Regular.ttf',
    'google_fonts/Inter-Medium.ttf' => 'assets/fonts/Lato-Regular.ttf',
    'google_fonts/Inter-MediumItalic.ttf' => 'assets/fonts/Lato-Regular.ttf',
    'google_fonts/Inter-SemiBold.ttf' => 'assets/fonts/Lato-Bold.ttf',
    'google_fonts/Inter-SemiBoldItalic.ttf' => 'assets/fonts/Lato-Bold.ttf',
    'google_fonts/Inter-Bold.ttf' => 'assets/fonts/Lato-Bold.ttf',
    'google_fonts/Inter-BoldItalic.ttf' => 'assets/fonts/Lato-Bold.ttf',
    'google_fonts/Inter-ExtraBold.ttf' => 'assets/fonts/Lato-Bold.ttf',
    'google_fonts/Inter-ExtraBoldItalic.ttf' => 'assets/fonts/Lato-Bold.ttf',
    'google_fonts/Inter-Black.ttf' => 'assets/fonts/Lato-Bold.ttf',
    'google_fonts/Inter-BlackItalic.ttf' => 'assets/fonts/Lato-Bold.ttf',
    'google_fonts/Barlow-Regular.ttf' => 'assets/fonts/Lato-Regular.ttf',
    'google_fonts/Barlow-Medium.ttf' => 'assets/fonts/Lato-Regular.ttf',
    'google_fonts/Barlow-SemiBold.ttf' => 'assets/fonts/Lato-Bold.ttf',
    'google_fonts/Barlow-Bold.ttf' => 'assets/fonts/Lato-Bold.ttf',
    'google_fonts/Barlow-ExtraBold.ttf' => 'assets/fonts/Lato-Bold.ttf',
    'google_fonts/BarlowCondensed-Regular.ttf' =>
      'assets/fonts/Lato-Regular.ttf',
    'google_fonts/BarlowCondensed-Bold.ttf' => 'assets/fonts/Lato-Bold.ttf',
    'google_fonts/BarlowCondensed-ExtraBold.ttf' =>
      'assets/fonts/Lato-Bold.ttf',
    'google_fonts/BarlowCondensed-Black.ttf' => 'assets/fonts/Lato-Bold.ttf',
    'google_fonts/Manrope-Regular.ttf' => 'assets/fonts/Lato-Regular.ttf',
    'google_fonts/Manrope-Medium.ttf' => 'assets/fonts/Lato-Regular.ttf',
    'google_fonts/Manrope-SemiBold.ttf' => 'assets/fonts/Lato-Bold.ttf',
    'google_fonts/Manrope-Bold.ttf' => 'assets/fonts/Lato-Bold.ttf',
    'google_fonts/Manrope-ExtraBold.ttf' => 'assets/fonts/Lato-Bold.ttf',
    'google_fonts/Manrope-Black.ttf' => 'assets/fonts/Lato-Bold.ttf',
    _ => null,
  };

  if (path == null) {
    return null;
  }

  final bytes = await File(path).readAsBytes();
  return ByteData.sublistView(Uint8List.fromList(bytes));
}

class _BundledGoogleFontsAssetManifest implements AssetManifest {
  const _BundledGoogleFontsAssetManifest();

  @override
  List<String> listAssets() => const <String>[
    'google_fonts/DMSans-Regular.ttf',
    'google_fonts/DMSans-Medium.ttf',
    'google_fonts/DMSans-SemiBold.ttf',
    'google_fonts/DMSans-Bold.ttf',
    'google_fonts/DMSans-ExtraBold.ttf',
    'google_fonts/DMMono-Regular.ttf',
    'google_fonts/DMMono-Medium.ttf',
    'google_fonts/DMMono-Bold.ttf',
    'google_fonts/Inter-Regular.ttf',
    'google_fonts/Inter-Italic.ttf',
    'google_fonts/Inter-Medium.ttf',
    'google_fonts/Inter-MediumItalic.ttf',
    'google_fonts/Inter-SemiBold.ttf',
    'google_fonts/Inter-SemiBoldItalic.ttf',
    'google_fonts/Inter-Bold.ttf',
    'google_fonts/Inter-BoldItalic.ttf',
    'google_fonts/Inter-ExtraBold.ttf',
    'google_fonts/Inter-ExtraBoldItalic.ttf',
    'google_fonts/Inter-Black.ttf',
    'google_fonts/Inter-BlackItalic.ttf',
    'google_fonts/Barlow-Regular.ttf',
    'google_fonts/Barlow-Medium.ttf',
    'google_fonts/Barlow-SemiBold.ttf',
    'google_fonts/Barlow-Bold.ttf',
    'google_fonts/Barlow-ExtraBold.ttf',
    'google_fonts/BarlowCondensed-Regular.ttf',
    'google_fonts/BarlowCondensed-Bold.ttf',
    'google_fonts/BarlowCondensed-ExtraBold.ttf',
    'google_fonts/BarlowCondensed-Black.ttf',
    'google_fonts/Manrope-Regular.ttf',
    'google_fonts/Manrope-Medium.ttf',
    'google_fonts/Manrope-SemiBold.ttf',
    'google_fonts/Manrope-Bold.ttf',
    'google_fonts/Manrope-ExtraBold.ttf',
    'google_fonts/Manrope-Black.ttf',
  ];

  @override
  List<AssetMetadata>? getAssetVariants(String key) => null;
}
