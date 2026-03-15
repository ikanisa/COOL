import 'dart:convert';
import 'dart:io';

import 'package:cool_app/core/theme/app_colors.dart';
import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/core/theme/cool_palette.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_fonts/src/google_fonts_base.dart';

void main() {
  setUp(() {
    AppColors.applyBrightness(Brightness.dark);
    GoogleFonts.config.allowRuntimeFetching = false;
    assetManifest = const _BundledGoogleFontsAssetManifest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', _handleMockAssetLoad);
  });

  tearDown(() {
    clearCache();
    GoogleFonts.config.allowRuntimeFetching = false;
    assetManifest = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  group('AppTheme', () {
    test('dark theme preserves the existing dark palette', () async {
      final theme = AppTheme.dark;
      final palette = theme.extension<CoolPalette>();

      await GoogleFonts.pendingFonts();

      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, AppColors.darkBg);
      expect(theme.colorScheme.surface, AppColors.darkSurface);
      expect(palette, isNotNull);
      expect(palette!.bg, AppColors.darkBg);
      expect(palette.text, AppColors.darkText);
    });

    test('light theme exposes a light semantic palette', () async {
      final theme = AppTheme.light;
      final palette = theme.extension<CoolPalette>();

      await GoogleFonts.pendingFonts();

      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, AppColors.lightBg);
      expect(theme.colorScheme.brightness, Brightness.light);
      expect(palette, isNotNull);
      expect(palette!.bg, AppColors.lightBg);
      expect(palette.text, AppColors.lightText);
    });
  });
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
  ];

  @override
  List<AssetMetadata>? getAssetVariants(String key) => null;
}
