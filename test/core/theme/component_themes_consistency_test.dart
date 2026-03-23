import 'dart:convert';
import 'dart:io';

import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/core/theme/cool_foundations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/src/google_fonts_base.dart';

/// Tests that ThemeData component themes use the correct semantic tokens.
void main() {
  late ThemeData darkTheme;
  late ThemeData lightTheme;

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    assetManifest = const _ManropeAssetManifest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', _handleMockAssetLoad);

    // Build themes once — this triggers GoogleFonts loading.
    darkTheme = AppTheme.dark;
    lightTheme = AppTheme.light;
  });

  tearDownAll(() {
    clearCache();
    assetManifest = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  for (final entry in {
    'dark': (
      theme: () => darkTheme,
      semantics: CoolSemanticColors.dark,
    ),
    'light': (
      theme: () => lightTheme,
      semantics: CoolSemanticColors.light,
    ),
  }.entries) {
    final label = entry.key;
    final themeData = entry.value.theme;
    final semanticColors = entry.value.semantics;

    group('$label component themes', () {
      test('AppBar background is transparent', () {
        expect(themeData().appBarTheme.backgroundColor, Colors.transparent);
      });

      test('ElevatedButton uses primary action color', () {
        final style = themeData().elevatedButtonTheme.style!;
        final bgColor = style.backgroundColor!.resolve({});
        expect(bgColor, semanticColors.buttonPrimaryBackground);
      });

      test('FAB uses primary action color', () {
        expect(
          themeData().floatingActionButtonTheme.backgroundColor,
          semanticColors.buttonPrimaryBackground,
        );
      });

      test('Scaffold background matches appBackground', () {
        expect(themeData().scaffoldBackgroundColor, semanticColors.appBackground);
      });

      test('Card uses cardSurface', () {
        expect(themeData().cardTheme.color, semanticColors.cardSurface);
      });

      test('Divider uses semantic divider color', () {
        expect(themeData().dividerTheme.color, semanticColors.divider);
      });

      test('ColorScheme primary matches buttonPrimaryBackground', () {
        expect(
          themeData().colorScheme.primary,
          semanticColors.buttonPrimaryBackground,
        );
      });

      test('CoolSemanticColors extension is registered', () {
        expect(themeData().extension<CoolSemanticColors>(), isNotNull);
      });

      test('CoolPalette extension is registered (backcompat)', () {
        expect(themeData().extension<CoolPalette>(), isNotNull);
      });

      test('BottomAppBar uses glass surface', () {
        expect(
          themeData().bottomAppBarTheme.color,
          semanticColors.glassSurface,
        );
      });
    });
  }
}

Future<ByteData?> _handleMockAssetLoad(ByteData? message) async {
  if (message == null) return null;
  final key = utf8.decode(message.buffer.asUint8List());
  if (!key.startsWith('google_fonts/Manrope-')) return null;
  final isRegular = key.contains('Regular');
  final path = isRegular
      ? 'assets/fonts/Lato-Regular.ttf'
      : 'assets/fonts/Lato-Bold.ttf';
  final bytes = await File(path).readAsBytes();
  return ByteData.sublistView(Uint8List.fromList(bytes));
}

class _ManropeAssetManifest implements AssetManifest {
  const _ManropeAssetManifest();

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
