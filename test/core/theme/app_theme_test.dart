import 'dart:convert';
import 'dart:io';

import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/core/theme/cool_foundations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/src/google_fonts_base.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    assetManifest = const _BundledGoogleFontsAssetManifest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', _handleMockAssetLoad);
  });

  tearDown(() {
    clearCache();
    assetManifest = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  group('AppTheme', () {
    test('dark theme exposes the institutional dark palette', () {
      final theme = AppTheme.dark;
      final palette = theme.extension<CoolPalette>();
      final semanticColors = theme.extension<CoolSemanticColors>();

      expect(theme.brightness, Brightness.dark);
      expect(
        theme.scaffoldBackgroundColor,
        CoolSemanticColors.dark.appBackground,
      );
      expect(
        theme.colorScheme.primary,
        CoolSemanticColors.dark.buttonPrimaryBackground,
      );
      expect(palette, isNotNull);
      expect(palette!.bg, CoolSemanticColors.dark.appBackground);
      expect(palette.text, CoolSemanticColors.dark.primaryText);
      expect(semanticColors, isNotNull);
      expect(
        semanticColors!.cardSurfaceStrong,
        CoolSemanticColors.dark.cardSurfaceStrong,
      );
    });

    test('light theme exposes the institutional light palette', () {
      final theme = AppTheme.light;
      final palette = theme.extension<CoolPalette>();
      final semanticColors = theme.extension<CoolSemanticColors>();

      expect(theme.brightness, Brightness.light);
      expect(
        theme.scaffoldBackgroundColor,
        CoolSemanticColors.light.appBackground,
      );
      expect(theme.colorScheme.brightness, Brightness.light);
      expect(
        theme.colorScheme.primary,
        CoolSemanticColors.light.buttonPrimaryBackground,
      );
      expect(palette, isNotNull);
      expect(palette!.bg, CoolSemanticColors.light.appBackground);
      expect(palette.text, CoolSemanticColors.light.primaryText);
      expect(semanticColors, isNotNull);
      expect(
        semanticColors!.cardSurfaceStrong,
        CoolSemanticColors.light.cardSurfaceStrong,
      );
    });
  });
}

Future<ByteData?> _handleMockAssetLoad(ByteData? message) async {
  if (message == null) {
    return null;
  }

  final key = utf8.decode(message.buffer.asUint8List());
  if (!key.startsWith('google_fonts/Manrope-')) {
    return null;
  }

  final isRegular = key.contains('Regular');
  final path = isRegular
      ? 'assets/fonts/Lato-Regular.ttf'
      : 'assets/fonts/Lato-Bold.ttf';
  final bytes = await File(path).readAsBytes();
  return ByteData.sublistView(Uint8List.fromList(bytes));
}

class _BundledGoogleFontsAssetManifest implements AssetManifest {
  const _BundledGoogleFontsAssetManifest();

  @override
  List<String> listAssets() => const <String>[
    'google_fonts/Manrope-Regular.ttf',
    'google_fonts/Manrope-Medium.ttf',
    'google_fonts/Manrope-SemiBold.ttf',
    'google_fonts/Manrope-Bold.ttf',
    'google_fonts/Manrope-ExtraBold.ttf',
  ];

  @override
  List<AssetMetadata>? getAssetVariants(String key) => null;
}
