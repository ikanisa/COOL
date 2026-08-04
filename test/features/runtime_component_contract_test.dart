import 'dart:io';

import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/notifications/collect_notification_service.dart';
import 'package:collect_app/core/utils/money_format.dart';
import 'package:collect_app/features/collections/group_creation_platform.dart';
import 'package:collect_app/features/status/native_permission_sheets.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Collect color tokens separate brand canvas from screen background', () {
    final light = AppTheme.light().extension<CollectColors>();
    expect(light, isNotNull);
    expect(light!.surface, CollectColors.brandPaper);
    expect(light.screenBase, CollectColors.referencePaymentsPurple);
  });

  test('Collect light and dark modes are visually distinctive', () {
    final lightTheme = AppTheme.light();
    final darkTheme = AppTheme.dark();
    final light = lightTheme.extension<CollectColors>()!;
    final dark = darkTheme.extension<CollectColors>()!;

    expect(lightTheme.brightness, Brightness.light);
    expect(darkTheme.brightness, Brightness.dark);
    expect(light.surfaceReadable, isNot(dark.surfaceReadable));
    expect(light.surfaceMuted, isNot(dark.surfaceMuted));
    expect(light.textPrimary, isNot(dark.textPrimary));
    expect(light.textSecondary, isNot(dark.textSecondary));
    expect(light.neutralContainer, isNot(dark.neutralContainer));
    expect(light.glassPanel, isNot(dark.glassPanel));
    expect(light.onAccent, CollectColors.inkPrimary);
    expect(dark.onAccent, CollectColors.inkPrimary);
    expect(
      _contrastRatio(dark.textPrimary, dark.surfaceReadable),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrastRatio(dark.onAccent, dark.actionColor),
      greaterThanOrEqualTo(4.5),
    );
  });

  test(
    'Collect brand tokens are runtime implementation, not test authority',
    () {
      expect(CollectColors.brandPrimaryColors, hasLength(4));
      expect(CollectColors.brandPrimaryColors.toSet(), hasLength(4));
      final paletteHexes = CollectColors.brandPrimaryOptions
          .map((option) => option.hex)
          .toList(growable: false);
      expect(paletteHexes, hasLength(CollectColors.brandPrimaryColors.length));
      expect(paletteHexes, everyElement(matches(RegExp(r'^#[0-9A-F]{6}$'))));
      expect(
        CollectColors.brandPrimaryColors,
        isNot(contains(CollectColors.brandPaper)),
      );
      expect(
        CollectColors.brandPrimaryColors,
        isNot(contains(CollectColors.transparentColor)),
      );
    },
  );

  test('Collect runtime token layer preserves structured secondary colors', () {
    expect(CollectRuntimeTokens.secondaryColorRoles, hasLength(17));
    expect(
      CollectRuntimeTokens.secondaryColorRoles.values.toSet().intersection(
        CollectColors.brandPrimaryColors.toSet(),
      ),
      isEmpty,
    );
  });

  test('route background families are applied by route', () {
    final light = AppTheme.light().extension<CollectColors>()!;

    expect(
      (light.screenGradientForPath('/home') as LinearGradient).begin,
      Alignment.topCenter,
    );
    expect(
      (light.screenGradientForPath('/home') as LinearGradient).end,
      Alignment.bottomCenter,
    );
    final routeGradients = <String, List<Color>>{
      '/home': _gradientColors(light.screenGradientForPath('/home')),
      '/groups': _gradientColors(light.screenGradientForPath('/groups')),
      '/groups/group_1/contribute': _gradientColors(
        light.screenGradientForPath('/groups/group_1/contribute'),
      ),
      '/groups/group_1/share': _gradientColors(
        light.screenGradientForPath('/groups/group_1/share'),
      ),
      '/groups/create': _gradientColors(
        light.screenGradientForPath('/groups/create'),
      ),
      '/settings': _gradientColors(light.screenGradientForPath('/settings')),
      '/settings/legal/privacy': _gradientColors(
        light.screenGradientForPath('/settings/legal/privacy'),
      ),
    };
    expect(routeGradients.values, everyElement(isNotEmpty));
    expect(routeGradients['/home'], hasLength(greaterThanOrEqualTo(3)));
    expect(routeGradients['/groups'], isNot(routeGradients['/home']));
    expect(
      routeGradients['/groups/group_1/contribute'],
      isNot(routeGradients['/groups']),
    );
    expect(
      routeGradients['/groups/group_1/share'],
      isNot(routeGradients['/groups/group_1/contribute']),
    );
    expect(routeGradients['/groups/create'], isNot(routeGradients['/home']));
    expect(routeGradients['/settings'], isNot(routeGradients['/home']));
    expect(
      routeGradients['/settings/legal/privacy'],
      isNot(routeGradients['/settings']),
    );
  });

  testWidgets('top chrome profile control is visible and links to profile', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpCollect(
        tester,
        CollectTopChrome(
          avatarLabel: '038491',
          actions: [
            CollectTopChromeAction(
              icon: CollectIcons.pending,
              tooltip: 'Notifications',
              onPressed: () {},
            ),
          ],
        ),
      );

      expect(find.text('91'), findsNothing);
      expect(find.bySemanticsLabel('Open profile for 038491'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('dark glass cards use deep reference surfaces', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: CollectCard(child: Text('Deep glass'))),
      ),
    );

    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer).first,
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, isNotNull);
    expect(decoration.color!.a, greaterThan(0.80));
  });

  testWidgets('reduced motion opens and closes Collect sheets immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => showAndroidGroupCreationOnlyDialog(context),
                child: const Text('Open options'),
              );
            },
          ),
        ),
      ),
    );

    final openButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Open options'),
    );
    openButton.onPressed!();
    await tester.pump();

    expect(find.text('Join options'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);

    Navigator.of(tester.element(find.text('Join options'))).pop();
    await tester.pump();

    expect(find.text('Join options'), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('reduced motion updates amount receiver controls immediately', (
    tester,
  ) async {
    final numberController = TextEditingController();
    final codeController = TextEditingController();
    addTearDown(numberController.dispose);
    addTearDown(codeController.dispose);
    var mode = CollectMomoReceiverMode.momoNumber;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: CollectMomoReceiverCard(
                  mode: mode,
                  onChanged: (value) => setState(() => mode = value),
                  numberController: numberController,
                  codeController: codeController,
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Code'));
    await tester.pump();

    expect(mode, CollectMomoReceiverMode.momoPayCode);
    expect(
      find.byKey(const ValueKey(CollectMomoReceiverMode.momoPayCode)),
      findsOneWidget,
    );
    expect(
      tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .map((container) => container.duration),
      everyElement(Duration.zero),
    );
  });

  test('Collect uses only the bundled Inter typography family', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final lockfile = File('pubspec.lock').readAsStringSync();
    final launch = File(
      'lib/features/launch/launch_splash_screen.dart',
    ).readAsStringSync();
    final runtimeAssets = File(
      'lib/app/theme/collect_runtime_assets.dart',
    ).readAsStringSync();
    final runtimeTypography = File(
      'lib/app/theme/collect_runtime_typography.dart',
    ).readAsStringSync();
    final libSources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(CollectRuntimeAssets.usesRepoVisualAssets, isTrue);
    expect(CollectRuntimeAssets.requiredBlockerKeys, isEmpty);
    expect(runtimeAssets, contains('immutable pre-audit Collect logo'));
    expect(Directory('assets/runtime').existsSync(), isFalse);
    expect(Directory('assets/fonts').existsSync(), isFalse);
    expect(File('assets/typefaces/Inter-Variable.ttf').existsSync(), isTrue);
    expect(File('assets/typefaces/OFL-Inter.txt').existsSync(), isTrue);
    final officialLogo = File(CollectRuntimeAssets.officialLogo);
    expect(officialLogo.existsSync(), isTrue);
    expect(
      sha256.convert(officialLogo.readAsBytesSync()).toString(),
      CollectRuntimeAssets.officialLogoSha256,
    );
    expect(File('web/icons/collect-web-512.png').existsSync(), isTrue);
    expect(pubspec, isNot(contains('assets/runtime')));
    expect(pubspec, contains(CollectRuntimeAssets.officialLogo));
    expect(pubspec, contains('family: Inter'));
    expect(pubspec, contains('assets/typefaces/Inter-Variable.ttf'));
    expect(pubspec, contains('assets/typefaces/OFL-Inter.txt'));
    const removedPlatformIconPackage =
        'cupertino'
        '_icons';
    const removedLegacyFamilies = <String>[
      'Ae'
          'onik',
      'Robo'
          'to',
      'JetBrains'
          ' Mono',
    ];
    expect(pubspec, isNot(contains(removedPlatformIconPackage)));
    expect(lockfile, isNot(contains(removedPlatformIconPackage)));
    expect(pubspec, isNot(contains('Collect Runtime')));
    expect(pubspec, isNot(contains('Collect Display')));
    expect(CollectRuntimeTypography.fontFamily, 'Inter');
    expect(CollectRuntimeTypography.displayFontFamily, 'Inter');
    expect(CollectRuntimeTypography.financialFontFamily, 'Inter');
    expect(runtimeTypography, isNot(contains('fontFamilyFallback')));
    for (final family in removedLegacyFamilies) {
      expect(runtimeTypography, isNot(contains(family)));
      expect(libSources, isNot(contains(family)));
    }
    expect(launch, contains('SizedBox.expand'));
    expect(launch, contains('CollectRuntimeAssets.officialLogo'));
    expect(libSources, contains('Image.asset'));
    expect(libSources, isNot(contains('AssetImage')));
    expect(libSources, isNot(contains('SvgPicture')));
    expect(libSources, contains('collect_top_chrome_official_logo'));
    expect(libSources, isNot(contains('collect_top_chrome_avatar_initial')));
  });

  test('application typography has no raw or defaulted type styles', () {
    final centralTypography = File(
      'lib/app/theme/collect_typography.dart',
    ).readAsStringSync();
    final roleAssembly = centralTypography.substring(
      centralTypography.indexOf('static TextTheme textTheme'),
    );
    expect(
      roleAssembly,
      isNot(
        matches(
          RegExp(
            r'_(?:displayStyle|style|label)\([^)]*\b\d+(?:\.\d+)?',
            dotAll: true,
          ),
        ),
      ),
    );
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) =>
              !file.path.endsWith('collect_typography.dart') &&
              !file.path.endsWith('collect_runtime_typography.dart'),
        );
    final rawLeading = RegExp(
      r'(?:TextStyle|copyWith)\([^)]{0,500}\bheight\s*:\s*[0-9]',
      dotAll: true,
    );

    for (final file in files) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('TextStyle(')), reason: file.path);
      expect(source, isNot(contains('FontWeight.')), reason: file.path);
      expect(
        source,
        isNot(matches(RegExp(r'fontSize\s*:\s*[0-9]'))),
        reason: file.path,
      );
      expect(
        source,
        isNot(matches(RegExp(r'letterSpacing\s*:\s*[0-9]'))),
        reason: file.path,
      );
      expect(source, isNot(matches(rawLeading)), reason: file.path);
    }

    final staticSite = File(
      'scripts/public_static_site_build.rb',
    ).readAsStringSync();
    final generatedCss = staticSite.substring(
      staticSite.indexOf('def stylesheet'),
      staticSite.indexOf('def site_js'),
    );
    final featureCss = generatedCss.substring(
      generatedCss.lastIndexOf('font-family: "Inter";') +
          'font-family: "Inter";'.length,
    );
    expect(featureCss, isNot(matches(RegExp(r'font-weight:\s*[0-9]'))));
    expect(
      featureCss,
      isNot(matches(RegExp(r'font-size:\s*(?:[0-9.]|clamp\()'))),
    );
    expect(featureCss, isNot(matches(RegExp(r'line-height:\s*[0-9.]'))));
    expect(
      featureCss,
      isNot(matches(RegExp(r'letter-spacing:\s*(?:[0-9.]|-)'))),
    );
    expect(staticSite, contains('font-weight: 400 700;'));
    expect(staticSite, isNot(contains('font-weight: 100 900;')));
    expect(
      staticSite,
      isNot(
        matches(RegExp(r'font-weight:\s*(?:7[1-9][0-9]|8[0-9]{2}|9[0-9]{2})')),
      ),
    );
  });

  test('tracked visual assets exclude SVG and unapproved brand artwork', () {
    final tracked = Process.runSync('git', [
      'ls-files',
      '--cached',
      '--others',
      '--exclude-standard',
    ]);
    expect(tracked.exitCode, 0);
    final paths = (tracked.stdout as String)
        .split('\n')
        .where((path) => path.isNotEmpty)
        .toList();
    expect(paths.where((path) => path.toLowerCase().endsWith('.svg')), isEmpty);
    expect(
      paths.where((path) => path.toLowerCase().endsWith('.svgz')),
      isEmpty,
    );
    expect(paths.where((path) => path.toLowerCase().endsWith('.ico')), isEmpty);

    final brandImages = paths
        .where((path) => path.startsWith('assets/brand/collect_runtime/'))
        .toSet();
    expect(brandImages, {
      'assets/brand/collect_runtime/app_icons/app-icon-rule.png',
      'assets/brand/collect_runtime/media/group-momentum.png',
      'assets/brand/collect_runtime/media/mobile-money-ussd-signal.png',
      'assets/brand/collect_runtime/media/qr-share.png',
    });

    final approvedVisualAssets = <String, String>{};
    for (final line in File(
      'assets/brand/APPROVED_PRODUCT_VISUAL_ASSETS.sha256',
    ).readAsLinesSync()) {
      if (line.isEmpty) continue;
      final separator = line.indexOf('  ');
      expect(separator, 64, reason: line);
      final path = line.substring(separator + 2);
      expect(approvedVisualAssets, isNot(contains(path)), reason: path);
      approvedVisualAssets[path] = line.substring(0, separator);
    }
    final productVisualAssets = paths
        .where(
          (path) =>
              path.startsWith('assets/') ||
              path.startsWith('android/app/src/main/res/') ||
              path.startsWith('ios/Runner/Assets.xcassets/') ||
              path.startsWith('web/'),
        )
        .where((path) {
          final extensionStart = path.lastIndexOf('.');
          if (extensionStart < 0) return false;
          return const {
            '.png',
            '.jpg',
            '.jpeg',
            '.webp',
            '.svg',
            '.svgz',
            '.ico',
          }.contains(path.substring(extensionStart).toLowerCase());
        })
        .toSet();
    expect(productVisualAssets, approvedVisualAssets.keys.toSet());
    expect(approvedVisualAssets, hasLength(26));
    for (final entry in approvedVisualAssets.entries) {
      expect(
        sha256.convert(File(entry.key).readAsBytesSync()).toString(),
        entry.value,
        reason: entry.key,
      );
    }

    final officialSource = File(
      'assets/brand/collect_runtime/app_icons/app-icon-rule.png',
    );
    final androidSource = File(
      'android/app/src/main/res/drawable/collect_launcher_icon.png',
    );
    expect(
      sha256.convert(androidSource.readAsBytesSync()).toString(),
      sha256.convert(officialSource.readAsBytesSync()).toString(),
    );
    expect(
      sha256
          .convert(
            File(
              'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
              'Icon-App-1024x1024@1x.png',
            ).readAsBytesSync(),
          )
          .toString(),
      '25fabc042f4e2b90ba385388542cfbea764b34e0e8cbeaa18dda12045f277738',
    );
    expect(
      sha256
          .convert(File('web/icons/collect-web-512.png').readAsBytesSync())
          .toString(),
      'cae23ce3562e8aac2e248e7b22f7feed194f4fcfd2b57725ec1026f064bb0ad9',
    );

    final productSources = <File>[
      File('scripts/public_static_site_build.rb'),
      ...Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
    ];
    for (final file in productSources) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('<svg')), reason: file.path);
      expect(source, isNot(contains('collect_splash_logo')), reason: file.path);
    }
  });

  test('mobile visual foundation uses compact reference geometry', () {
    expect(CollectRadius.card, 16);
    expect(CollectRadius.cardLarge, 20);
    expect(CollectRadius.panel, 20);
    expect(CollectRadius.bottomSheet, 24);
    expect(CollectSpacing.screenCompact, 16);
    expect(CollectSpacing.screen, 20);
    expect(CollectSpacing.target, 48);

    final shell = File(
      'lib/core/widgets/collect_shell.dart',
    ).readAsStringSync();
    expect(shell, contains('final height = showLabels ? 60.0 : 52.0;'));
    expect(shell, contains('width: selected ? 44 : 38'));
    expect(shell, isNot(contains('width: selected ? 74 : 46')));
  });

  test('universal semantic token extension covers mobile and admin roles', () {
    final lightTheme = AppTheme.light();
    final darkTheme = AppTheme.dark();
    final light = lightTheme.extension<CollectUniversalTokens>();
    final dark = darkTheme.extension<CollectUniversalTokens>();

    expect(light, isNotNull);
    expect(dark, isNotNull);
    expect(light!.chromeDefault, CollectColors.referenceChromeBlack);
    expect(light.adminRail, CollectColors.referenceChromeBlack);
    expect(light.actionPrimary, CollectColors.light.actionColor);
    expect(light.actionDestructive, CollectColors.light.dangerForeground);
    expect(light.surfaceGlass, CollectColors.light.glassPanel);
    expect(light.touchTarget, greaterThanOrEqualTo(48));
    expect(light.iconTarget, greaterThanOrEqualTo(44));
    expect(light.spacingStep, 4);
    expect(light.cardRadius, lessThanOrEqualTo(8));
    expect(light.motionFast.inMilliseconds, inInclusiveRange(120, 180));
    expect(light.motionStandard.inMilliseconds, inInclusiveRange(200, 280));
    expect(light.motionSlow.inMilliseconds, inInclusiveRange(320, 420));

    expect(dark!.surfaceGlass, CollectColors.dark.glassPanel);
    expect(dark.focusRing, CollectColors.dark.focusRing);
    expect(dark.adminWorkspace, CollectColors.referenceAssetNavy);
    expect(
      CollectUniversalTokens.highContrastDark().focusRing,
      CollectColors.brandPaper,
    );
    expect(CollectUniversalTokens.highContrastDark().highContrast, isTrue);
    expect(
      CollectUniversalTokens.highContrastDark().focusRingWidth,
      greaterThan(dark.focusRingWidth),
    );
  });

  test('native Android launch and launcher use the official Collect mark', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android:theme="@style/LaunchTheme"'));
    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(manifest, contains('android:roundIcon="@mipmap/ic_launcher"'));
    expect(
      manifest,
      contains('android:name="io.flutter.embedding.android.NormalTheme"'),
    );
    expect(manifest, contains('android:resource="@style/NormalTheme"'));

    for (final path in <String>[
      'android/app/src/main/res/values/styles.xml',
      'android/app/src/main/res/values-night/styles.xml',
    ]) {
      final text = File(path).readAsStringSync();
      expect(
        text,
        contains(
          '<style name="LaunchTheme" parent="@android:style/Theme.Black.NoTitleBar">',
        ),
        reason: path,
      );
      expect(
        text,
        contains(
          '<item name="android:windowBackground">'
          '@drawable/launch_background</item>',
        ),
        reason: path,
      );
      expect(
        text,
        contains('<item name="android:forceDarkAllowed">false</item>'),
        reason: path,
      );
      expect(
        text,
        contains(
          '<item name="android:statusBarColor">@color/collect_launch_background</item>',
        ),
        reason: path,
      );
      expect(
        text,
        contains(
          '<item name="android:navigationBarColor">@color/collect_launch_background</item>',
        ),
        reason: path,
      );
      expect(
        text,
        contains('<item name="android:windowLightStatusBar">false</item>'),
        reason: path,
      );
      expect(
        text,
        contains('<item name="android:windowLightNavigationBar">false</item>'),
        reason: path,
      );
      expect(
        text,
        contains('<item name="android:windowFullscreen">true</item>'),
        reason: path,
      );
    }

    for (final path in <String>[
      'android/app/src/main/res/values-v31/styles.xml',
      'android/app/src/main/res/values-night-v31/styles.xml',
    ]) {
      final text = File(path).readAsStringSync();
      expect(
        text,
        contains(
          '<style name="LaunchTheme" parent="@android:style/Theme.Black.NoTitleBar">',
        ),
        reason: path,
      );
      expect(
        text,
        contains(
          '<item name="android:windowSplashScreenBackground">'
          '@color/collect_launch_background</item>',
        ),
        reason: path,
      );
      expect(
        text,
        contains(
          '<item name="android:windowSplashScreenAnimatedIcon">'
          '@drawable/collect_launcher_icon</item>',
        ),
        reason: path,
      );
      expect(
        text,
        contains('<item name="android:forceDarkAllowed">false</item>'),
        reason: path,
      );
      expect(
        text,
        contains(
          '<item name="android:statusBarColor">@color/collect_launch_background</item>',
        ),
        reason: path,
      );
      expect(
        text,
        contains(
          '<item name="android:navigationBarColor">@color/collect_launch_background</item>',
        ),
        reason: path,
      );
      expect(
        text,
        contains('<item name="android:windowLightStatusBar">false</item>'),
        reason: path,
      );
      expect(
        text,
        contains('<item name="android:windowLightNavigationBar">false</item>'),
        reason: path,
      );
      expect(
        text,
        contains('<item name="android:windowFullscreen">true</item>'),
        reason: path,
      );
    }

    for (final path in <String>[
      'android/app/src/main/res/drawable/launch_background.xml',
      'android/app/src/main/res/drawable-v21/launch_background.xml',
      'android/app/src/main/res/drawable-night/launch_background.xml',
      'android/app/src/main/res/drawable-night-v21/launch_background.xml',
    ]) {
      final text = File(path).readAsStringSync();
      expect(text, contains('@color/collect_launch_background'), reason: path);
      expect(text, isNot(contains('@color/collect_paper')), reason: path);
      expect(text, contains('<bitmap'), reason: path);
      expect(
        text,
        isNot(contains('@drawable/collect_splash_logo')),
        reason: path,
      );
      expect(text, contains('@drawable/collect_launcher_icon'), reason: path);
    }

    for (final path in <String>[
      'android/app/src/main/res/values-v31/styles.xml',
      'android/app/src/main/res/values-night-v31/styles.xml',
    ]) {
      final text = File(path).readAsStringSync();
      expect(text, contains('@drawable/collect_launcher_icon'), reason: path);
    }
  });

  testWidgets('brand mark renders the official Collect image asset', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpCollect(tester, const CollectBrandMark());

      expect(find.bySemanticsLabel('Collect logo'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Collect'), findsOneWidget);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<AssetImage>());
      expect(
        (image.image as AssetImage).assetName,
        CollectRuntimeAssets.officialLogo,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('brand mark supports inverse text on immersive surfaces', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      const CollectBrandMark(
        framed: false,
        foregroundColor: CollectColors.brandPaper,
      ),
    );

    expect(
      tester.widget<Text>(find.text('Collect')).style?.color,
      CollectColors.brandPaper,
    );
  });

  testWidgets('brand mark preserves its wordmark at accessibility text scale', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      const MediaQuery(
        data: MediaQueryData(
          size: Size(1024, 1366),
          textScaler: TextScaler.linear(2),
        ),
        child: CollectBrandMark(
          compact: true,
          framed: false,
          foregroundColor: CollectColors.brandPaper,
        ),
      ),
    );

    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('Collect'),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
  });

  test('secondary color system protects readable semantic roles', () {
    final light = AppTheme.light().extension<CollectColors>()!;

    expect(light.actionColor, CollectColors.brandPeriwinkle);
    expect(light.urgentAction, CollectColors.brandOrangeRed);
    expect(light.onAccent, CollectColors.inkPrimary);
    expect(light.selectedOnAccent, CollectColors.inkPrimary);
    expect(light.surfaceReadable, CollectColors.secondarySurfaceReadable);
    expect(light.surfaceRaised, CollectColors.secondarySurfaceReadable);
    expect(light.surfaceMuted, CollectColors.secondarySurfaceMuted);
    expect(light.borderSoft, CollectColors.secondaryBorderSoft);
    expect(light.borderAccent, CollectColors.secondaryBorderAccent);
    expect(light.focusRing, CollectColors.secondaryFocusRing);
    expect(light.info, CollectColors.semanticInfoForeground);
    expect(light.success, CollectColors.semanticSuccessForeground);
    expect(light.warning, CollectColors.semanticWarningForeground);
    expect(light.danger, CollectColors.semanticDangerForeground);
    expect(light.statusForeground(CollectStatusTone.info), light.info);
    expect(light.statusForeground(CollectStatusTone.success), light.success);
    expect(light.statusForeground(CollectStatusTone.warning), light.warning);
    expect(light.statusForeground(CollectStatusTone.danger), light.danger);
    expect(light.statusBackground(CollectStatusTone.info), light.infoContainer);
    expect(
      light.statusBackground(CollectStatusTone.success),
      light.successContainer,
    );
    expect(
      light.statusBackground(CollectStatusTone.warning),
      light.warningContainer,
    );
    expect(
      light.statusBackground(CollectStatusTone.danger),
      light.dangerContainer,
    );
    expect(
      <Color>{
        light.info,
        light.success,
        light.warning,
        light.danger,
      }.intersection(CollectColors.brandPrimaryColors.toSet()),
      isEmpty,
    );

    for (final color in <Color>[
      light.textPrimary,
      light.textSecondary,
      light.textMuted,
      light.info,
      light.success,
      light.warning,
      light.danger,
      light.onAccent,
    ]) {
      expect(_contrastRatio(color, CollectColors.brandPaper), greaterThan(4.5));
    }
  });

  test('RWF amount typography uses tabular numerals', () {
    final style = CollectTypography.amountHero(CollectColors.light.textPrimary);

    expect(formatRwf(1250000), 'RWF 1,250,000');
    expect(style.fontFamily, 'Inter');
    expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
  });

  testWidgets('button, card, and status chip expose labels', (tester) async {
    await _pumpCollect(
      tester,
      CollectCard(
        child: Column(
          children: [
            CollectButton(label: 'Continue safely', onPressed: () {}),
            const CollectStatusChip(
              label: 'Needs review',
              tone: CollectStatusTone.warning,
            ),
          ],
        ),
      ),
    );

    expect(find.text('Continue safely'), findsOneWidget);
    expect(find.text('Needs review'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(CollectStatusChip)),
      matchesSemantics(label: 'Status: Needs review'),
    );
  });

  testWidgets('payment status card carries SMS trust-boundary copy', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      const PaymentIntentStatusCard(
        amountRwf: 5000,
        receiverLabel: 'St Michel treasury',
        receiverMomoNumber: '0788123456',
        status: 'pending',
      ),
    );

    expect(find.text('RWF 5,000'), findsOneWidget);
    expect(find.text('St Michel treasury'), findsOneWidget);
    expect(find.text('+250788123456'), findsNothing);
    expect(find.text('078***3456'), findsOneWidget);
    expect(find.text('Payment intent'), findsNothing);
    expect(find.text('Intent'), findsNothing);
    expect(find.text('SMS verification'), findsOneWidget);
    expect(find.text('Recorded'), findsNothing);
    expect(find.textContaining('receiver-side MoMo SMS'), findsNothing);
    expect(find.textContaining('Do not paste SMS'), findsNothing);
    expect(find.textContaining('Code'), findsNothing);
  });

  testWidgets('amount hero scales large RWF values in narrow cards', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      const SizedBox(
        width: 220,
        child: AmountHero(
          amount: 12500000,
          label: 'Confirmed total',
          detail: 'SMS verified',
        ),
      ),
    );

    expect(find.text('RWF 12,500,000'), findsOneWidget);
    expect(find.text('SMS verified'), findsOneWidget);
  });

  testWidgets('payment pipeline exposes semantic progress state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpCollect(
        tester,
        const PaymentPipelineIndicator(status: 'pending'),
      );

      expect(
        find.bySemanticsLabel('Payment progress: Pending'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Start step complete'), findsOneWidget);
      expect(find.bySemanticsLabel('Check step current'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('payment pipeline marks confirmed payments complete', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpCollect(
        tester,
        const PaymentPipelineIndicator(status: 'confirmed'),
      );

      expect(
        find.bySemanticsLabel('Payment progress: Confirmed'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Start step complete'), findsOneWidget);
      expect(find.bySemanticsLabel('Check step complete'), findsOneWidget);
      expect(find.bySemanticsLabel('Done step complete'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Collect ID card renders identity without hash prefix', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      const SizedBox(width: 280, child: CollectIdCard(publicId: '038491')),
    );

    expect(find.byIcon(CollectIcons.profile), findsOneWidget);
    expect(find.text('038491'), findsOneWidget);
    expect(find.textContaining('#'), findsNothing);
  });

  testWidgets('receiver consent card shows SMS access privacy copy', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      ReceiverConsentCard(
        flagsEnabled: true,
        consented: false,
        isSyncing: false,
        onConsentChanged: (_) {},
        onSync: () {},
      ),
    );

    expect(find.text('Consent'), findsOneWidget);
    expect(find.text('Required'), findsOneWidget);
    expect(find.text('Sync'), findsOneWidget);
    expect(find.textContaining('Raw SMS is never public'), findsNothing);
    expect(find.textContaining('MoMo confirmation matching'), findsNothing);
  });

  testWidgets('ledger row renders tabular transaction details', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpCollect(
        tester,
        LedgerRow.confirmed(
          contribution: Contribution(
            id: 'con-1',
            collectionId: 'col-1',
            amountRwf: 15000,
            supporterLabel: 'Collect ID 038491',
            createdAt: DateTime(2026),
            transactionId: 'MTN-001',
          ),
        ),
      );

      expect(find.text('038491'), findsOneWidget);
      expect(find.text('RWF 15,000'), findsOneWidget);
      expect(find.text('Ref MTN-001'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'Transaction reference MTN-001')),
        findsWidgets,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('empty, error, and loading states render', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpCollect(
        tester,
        const Column(
          children: [
            Expanded(
              child: CollectEmptyState(
                icon: CollectIcons.collections,
                title: 'No groups yet',
                message: 'Create an SMS-first MoMo group.',
              ),
            ),
            Expanded(
              child: CollectErrorState(
                title: 'Could not load',
                message: 'Try again when the connection is stable.',
              ),
            ),
            LoadingSkeleton(lines: 2, semanticsLabel: 'Loading dashboard'),
          ],
        ),
      );

      expect(find.text('No groups yet'), findsOneWidget);
      expect(find.text('Could not load'), findsOneWidget);
      expect(find.byType(LoadingSkeleton), findsWidgets);
      expect(find.bySemanticsLabel('Loading dashboard'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('loading state panel exposes visible and semantic context', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpCollect(
        tester,
        const SizedBox(
          width: 360,
          child: LoadingStatePanel(
            title: 'Loading members',
            message: 'Fetching group members and Collect ID roles.',
            icon: CollectIcons.people,
            lines: 2,
          ),
        ),
      );

      expect(find.text('Loading members'), findsOneWidget);
      expect(
        find.text('Fetching group members and Collect ID roles.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Loading: Loading members')),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('shape-specific Collect skeletons expose stable semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpCollect(
        tester,
        const SingleChildScrollView(
          child: Column(
            children: [
              LoadingSkeleton.heroAmount(semanticsLabel: 'Loading amount card'),
              CollectSpacing.gap12,
              LoadingSkeleton.groupCard(semanticsLabel: 'Loading group card'),
              CollectSpacing.gap12,
              LoadingSkeleton.ledgerRow(semanticsLabel: 'Loading ledger row'),
              CollectSpacing.gap12,
              LoadingSkeleton.bottomSheet(
                semanticsLabel: 'Loading action sheet',
              ),
            ],
          ),
        ),
      );

      expect(find.bySemanticsLabel('Loading amount card'), findsOneWidget);
      expect(find.bySemanticsLabel('Loading group card'), findsOneWidget);
      expect(find.bySemanticsLabel('Loading ledger row'), findsOneWidget);
      expect(find.bySemanticsLabel('Loading action sheet'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Collect async state view renders loading error retry and data', (
    tester,
  ) async {
    var retryCount = 0;

    await _pumpCollect(
      tester,
      CollectAsyncStateView<int>(
        value: const AsyncLoading<int>(),
        data: (context, value) => Text('$value loaded'),
        loadingTitle: 'Loading members',
        loadingMessage: 'Fetching group members.',
      ),
    );
    expect(find.text('Loading members'), findsOneWidget);

    await _pumpCollect(
      tester,
      CollectAsyncStateView<int>(
        value: AsyncError<int>(StateError('private failure'), StackTrace.empty),
        data: (context, value) => Text('$value loaded'),
        errorTitle: 'Could not load members',
        errorMessage: 'Try again when the connection is stable.',
        onRetry: () => retryCount += 1,
      ),
    );
    expect(find.text('Could not load members'), findsOneWidget);
    expect(find.text('private failure'), findsNothing);
    await tester.tap(find.text('Try again'));
    expect(retryCount, 1);

    await _pumpCollect(
      tester,
      CollectAsyncStateView<int>(
        value: const AsyncData<int>(7),
        data: (context, value) => Text('$value loaded'),
      ),
    );
    expect(find.text('7 loaded'), findsOneWidget);
  });

  testWidgets('connectivity banner distinguishes offline status copy', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpCollect(
        tester,
        const Column(
          children: [
            CollectConnectivityBanner(status: ConnectivityStatus.online),
            CollectConnectivityBanner(status: ConnectivityStatus.degraded),
            CollectConnectivityBanner(status: ConnectivityStatus.offline),
            CollectConnectivityBanner(status: ConnectivityStatus.offlineStale),
          ],
        ),
      );

      expect(find.text('Connection needs attention'), findsOneWidget);
      expect(find.text('No connection'), findsOneWidget);
      expect(find.text('Showing saved data'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('permission education sheet explains the native prompt', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      const CollectPermissionEducationSheet(
        icon: CollectIcons.qr,
        title: 'Camera access',
        message: 'Use native phone settings.',
        education: 'Camera access lets Collect scan group QR codes.',
      ),
    );

    expect(find.text('Camera access'), findsOneWidget);
    expect(find.text('Before you continue'), findsOneWidget);
    expect(
      find.text('Camera access lets Collect scan group QR codes.'),
      findsOneWidget,
    );
  });

  testWidgets('notification denial stays in Collect and retry can recover', (
    tester,
  ) async {
    final service = _PermissionSequenceNotificationService([false, true]);
    final container = ProviderContainer(
      overrides: [
        collectNotificationServiceProvider.overrideWithValue(service),
        collectRepositoryProvider.overrideWith(
          (ref) => CollectRepository.fixture(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, child) {
                return TextButton(
                  onPressed: () => showNotificationSettingsSheet(context, ref),
                  child: const Text('Review permission'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Review permission'));
    await tester.pumpAndSettle();
    expect(find.text('Enable'), findsOneWidget);

    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Open app settings'), findsOneWidget);
    expect(
      container.read(notificationPermissionStatusProvider),
      CollectDevicePermissionStatus.denied,
    );

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsNothing);
    expect(
      container.read(notificationPermissionStatusProvider),
      CollectDevicePermissionStatus.granted,
    );
    expect(service.requestCalls, 2);
    expect(service.registrationCalls, 1);
    expect(service.notificationCalls, 1);
  });

  testWidgets('bento metrics adapt for text scaling without losing content', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      const MediaQuery(
        data: MediaQueryData(
          size: Size(340, 720),
          textScaler: TextScaler.linear(1.3),
        ),
        child: SizedBox(
          width: 340,
          child: CollectBentoGrid(
            primary: BentoMetricCell(
              label: 'Total confirmed support',
              value: 'RWF 1,250,000',
              detail: 'Confirmed by SMS',
              emphasis: true,
            ),
            top: BentoMetricCell(
              label: 'Groups',
              value: '12',
              detail: 'Active',
            ),
            bottom: BentoMetricCell(
              label: 'Payments',
              value: '3',
              detail: 'Need SMS',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Total confirmed support'), findsOneWidget);
    expect(find.text('RWF 1,250,000'), findsOneWidget);
    expect(find.text('Payments'), findsOneWidget);
  });

  testWidgets('bento metrics can render icon-first metadata', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpCollect(
        tester,
        const SizedBox(
          width: 320,
          child: BentoMetricCell(
            label: 'Supporters',
            value: '42',
            detail: 'Visible groups',
            icon: CollectIcons.people,
            iconOnly: true,
            semanticLabel: '42 group members',
          ),
        ),
      );

      expect(find.byIcon(CollectIcons.people), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('Supporters'), findsNothing);
      expect(find.text('Visible groups'), findsNothing);
      expect(find.bySemanticsLabel('42 group members'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  test('group metadata copy blockers are enforced by source contract', () {
    final semanticIcons = File(
      'lib/app/theme/collect_semantic_icons.dart',
    ).readAsStringSync();
    final design = File('DESIGN.md').readAsStringSync();
    final groupCards = File(
      'lib/shared/widgets/collect_group_cards.dart',
    ).readAsStringSync();
    final collectionCards =
        groupCards +
        File(
          'lib/shared/widgets/collect_group_card_media.dart',
        ).readAsStringSync() +
        File(
          'lib/shared/widgets/collect_group_card_metrics.dart',
        ).readAsStringSync();
    final collectionsScreen = File(
      'lib/features/collections/collections_screen.dart',
    ).readAsStringSync();
    final manageScreen = File(
      'lib/features/collections/collection_manage_screen.dart',
    ).readAsStringSync();
    final detailScreen = File(
      'lib/features/collections/collection_detail_screen.dart',
    ).readAsStringSync();
    final detailActions = detailScreen;
    final detailHero = detailScreen;
    final shareScreen = File(
      'lib/features/collections/share_screen.dart',
    ).readAsStringSync();
    final scaffoldChrome = File(
      'lib/shared/widgets/collect_scaffold_chrome.dart',
    ).readAsStringSync();
    final runtimeSources = [
      groupCards,
      collectionCards,
      collectionsScreen,
      manageScreen,
      detailActions,
      detailHero,
      shareScreen,
      scaffoldChrome,
    ];

    const requiredKeywords = [
      'support',
      'supporters',
      'members',
      'amount',
      'church',
      'football',
      'public',
      'private',
      'sport',
      'ikimina',
      'wedding',
      'momo',
      'qr',
      'owner',
      'visibility',
    ];
    for (final keyword in requiredKeywords) {
      expect(semanticIcons, contains("'$keyword':"));
    }

    expect(design, contains('Semantic'));
    expect(design, contains('Universal Component Library'));

    expect(collectionCards, contains('maxLines: 1'));
    expect(collectionCards, contains('softWrap: false'));
    expect(groupCards, contains('iconOnly: true'));
    expect(groupCards, isNot(contains('supporters\',')));
    expect(collectionsScreen, contains('GroupListPanel'));
    expect(collectionsScreen, isNot(contains('class _GroupsMetricPill')));
    expect(collectionsScreen, isNot(contains('Group activity')));
    expect(collectionsScreen, isNot(contains('Supported activity')));
    expect(collectionsScreen, isNot(contains('Total collected')));
    expect(detailActions, contains("label: 'Members'"));
    expect(detailActions, contains("label: 'Contribute'"));
    expect(detailActions, isNot(contains("label: 'People'")));
    expect(detailActions, isNot(contains("label: 'Pay'")));
    expect(detailActions, contains('/groups/\$collectionId/members'));
    expect(detailActions, isNot(contains('class _GroupMomentumRail')));
    expect(detailHero, contains('CollectScreenHero('));
    expect(detailHero, contains('semanticLabel:'));
    expect(shareScreen, contains("'Group QR'"));
    expect(shareScreen, contains("label: 'Share'"));
    expect(shareScreen, contains("label: 'Save'"));
    expect(
      shareScreen,
      isNot(
        contains('Text(\n                                  collection.title'),
      ),
    );
    expect(scaffoldChrome, contains('maxLines: 1'));
    expect(scaffoldChrome, contains('TextOverflow.ellipsis'));
    expect(collectionsScreen, isNot(contains("'Supporters'")));
    expect(collectionsScreen, isNot(contains("'Visible groups'")));
    expect(collectionsScreen, isNot(contains("'Share-ready'")));
    expect(runtimeSources, isNotEmpty);
    expect(
      manageScreen,
      isNot(contains('Name, image, visibility, recurrence, receiver.')),
    );
    expect(manageScreen, isNot(contains('Show, share, or save the QR image.')));
    expect(manageScreen, isNot(contains('Native share invite link.')));
  });

  testWidgets('quick action rail exposes stable premium action semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpCollect(
        tester,
        QuickActionRail(
          children: [
            QuickActionButton(
              icon: CollectIcons.add,
              label: 'Create',
              detail: 'Android owner',
              onTap: () {},
            ),
            QuickActionButton(
              icon: CollectIcons.collections,
              label: 'Groups',
              detail: '12 active',
              onTap: () {},
            ),
          ],
        ),
      );

      expect(find.bySemanticsLabel('Quick actions'), findsOneWidget);
      expect(find.bySemanticsLabel('Create, Android owner'), findsOneWidget);
      expect(find.text('Groups'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('segmented filter exposes premium horizontal controls', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var selected = 'All';
    try {
      await _pumpCollect(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            return PremiumSegmentedFilter<String>(
              values: const ['All', 'Confirmed', 'Pending', 'Needs review'],
              selected: selected,
              labelFor: (value) => value,
              onChanged: (value) => setState(() => selected = value),
            );
          },
        ),
      );

      expect(find.bySemanticsLabel('Filter options'), findsOneWidget);
      await tester.tap(find.text('Pending'));
      await tester.pump();
      expect(selected, 'Pending');
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('premium scaffold pins bottom action surface', (tester) async {
    await _pumpCollect(
      tester,
      const SizedBox(
        height: 520,
        child: PremiumScaffold(
          title: 'Contribute',
          bottomAction: BottomActionSurface(
            children: [CollectButton(label: 'Review contribution')],
          ),
          children: [
            AmountHero(
              amount: 5000,
              label: 'Amount',
              detail: 'SMS verified after MoMo confirmation.',
            ),
            InfoSecurityBanner(
              title: 'Target account',
              message: 'Receiver details are checked before handoff.',
            ),
          ],
        ),
      ),
    );

    expect(find.text('Review contribution'), findsOneWidget);
    expect(find.text('Target account'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Target account')).overflow,
      TextOverflow.clip,
    );
    expect(
      tester
          .widget<Text>(
            find.text('Receiver details are checked before handoff.'),
          )
          .overflow,
      TextOverflow.clip,
    );
  });

  testWidgets('form section card standardizes fields errors and actions', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      FormSectionCard(
        title: 'Group profile',
        message: 'Members see the group name and public link.',
        errorTitle: 'Create failed',
        errorMessage: 'Name required.',
        actions: [CollectButton(label: 'Create group', onPressed: () {})],
        children: const [
          TextField(decoration: InputDecoration(labelText: 'Group name')),
        ],
      ),
    );

    expect(find.text('Group profile'), findsOneWidget);
    expect(
      find.text('Members see the group name and public link.'),
      findsOneWidget,
    );
    expect(find.text('Group name'), findsOneWidget);
    expect(find.text('Create failed'), findsOneWidget);
    expect(find.text('Name required.'), findsOneWidget);
    expect(find.text('Create group'), findsOneWidget);
  });

  testWidgets('mobile completion components expose reusable semantics', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      const Column(
        children: [
          CollectWizardProgress(
            labels: ['Basics', 'Receiver', 'Review'],
            currentStep: 1,
          ),
          CollectPermissionRecoveryPanel(
            icon: CollectIcons.warning,
            title: 'SMS access required.',
            message: 'Enable SMS access to automate MoMo SMS capture.',
            settingsMessage: 'Open app settings if Android keeps blocking SMS.',
          ),
        ],
      ),
    );

    expect(find.text('Basics'), findsOneWidget);
    expect(find.text('Receiver'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('SMS access required.'), findsOneWidget);
    expect(
      find.text('Open app settings if Android keeps blocking SMS.'),
      findsOneWidget,
    );
  });

  testWidgets('list tile shows bounded helper text and action affordance', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      Column(
        children: [
          const CollectListTile(
            leading: CollectIcons.info,
            title: 'SMS matching',
            subtitle:
                'Receiver-side MoMo confirmations update the ledger without exposing raw SMS bodies publicly.',
          ),
          CollectListTile(
            leading: CollectIcons.profile,
            title: 'Profile',
            subtitle: 'Open setup.',
            onTap: () {},
          ),
        ],
      ),
    );

    expect(find.byIcon(CollectIcons.chevron), findsOneWidget);
    expect(find.text('SMS matching'), findsOneWidget);
    expect(
      find.textContaining('without exposing raw SMS bodies'),
      findsOneWidget,
    );
  });

  testWidgets('screen header keeps compact one-line title with back action', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      const SizedBox(
        width: 320,
        child: ScreenHeader(
          title: 'Collect verified support for St Michel medical group',
          subtitle: 'SMS-first MoMo evidence and private group links.',
          actions: [
            IconButton(onPressed: null, icon: Icon(CollectIcons.share)),
            IconButton(onPressed: null, icon: Icon(CollectIcons.copy)),
          ],
        ),
      ),
    );

    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(
      find.text('Collect verified support for St Michel medical group'),
      findsOneWidget,
    );
    expect(find.textContaining('SMS-first MoMo'), findsOneWidget);
    expect(find.byType(CollectBrandMark), findsNothing);
    expect(find.byIcon(CollectIcons.shield), findsNothing);
    expect(find.byIcon(CollectIcons.share), findsOneWidget);
    expect(find.byIcon(CollectIcons.copy), findsOneWidget);
  });

  testWidgets('top chrome exposes avatar title and circular actions', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      CollectTopChrome(
        avatarLabel: '038491',
        hasUnread: true,
        titleLabel: 'Payment status',
        actions: [
          CollectTopChromeAction(
            icon: CollectIcons.qr,
            tooltip: 'Scan QR code',
            onPressed: () {},
          ),
          CollectTopChromeAction(
            icon: CollectIcons.settings,
            tooltip: 'Settings',
            onPressed: () {},
          ),
        ],
      ),
    );

    expect(find.bySemanticsLabel('Open profile for 038491'), findsOneWidget);
    expect(find.text('91'), findsNothing);
    expect(find.text('Payment status'), findsOneWidget);
    expect(find.byIcon(CollectIcons.search), findsNothing);
    expect(find.byIcon(CollectIcons.qr), findsOneWidget);
    expect(find.byIcon(CollectIcons.settings), findsOneWidget);
  });

  testWidgets(
    'TalkBack reaches chrome and hero actions without duplicate group labels',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpCollect(
        tester,
        Column(
          children: [
            CollectScreenTopChrome(
              avatarTooltip: 'Profile',
              searchLabel: 'Search groups',
              onAvatarTap: () {},
              onSearchTap: () {},
              actions: [
                CollectChromeAction(
                  icon: CollectIcons.add,
                  tooltip: 'Create group',
                  onPressed: () {},
                ),
              ],
            ),
            CollectHeroQuickActionRow(
              actions: [
                CollectHeroQuickAction(
                  icon: CollectIcons.add,
                  label: 'Create',
                  onTap: () {},
                ),
                CollectHeroQuickAction(
                  icon: CollectIcons.qr,
                  label: 'Scan QR',
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
      );

      expect(find.semantics.byLabel('Screen actions'), findsNothing);
      expect(find.semantics.byLabel('Primary screen actions'), findsNothing);
      for (final label in const [
        'Profile',
        'Search groups',
        'Create group',
        'Create',
        'Scan QR',
      ]) {
        final node = find.semantics.byLabel(
          RegExp('^${RegExp.escape(label)}\$'),
        );
        expect(node, findsOne, reason: label);
        expect(
          find.semantics.descendant(
            of: node,
            matching: find.semantics.byAction(SemanticsAction.tap),
            matchRoot: true,
          ),
          findsOneWidget,
          reason: '$label must retain its TalkBack tap action.',
        );
      }
      semantics.dispose();
    },
  );

  testWidgets('screen top chrome retains the official logo at maximum text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: MediaQueryData.fromView(
            tester.view,
          ).copyWith(textScaler: const TextScaler.linear(3.2)),
          child: Scaffold(
            body: CollectScreenTopChrome(
              avatarLabel: '038491',
              avatarTooltip: 'Profile',
              searchLabel: 'Search activity',
              onAvatarTap: () {},
              onSearchTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final officialLogo = find.byKey(
      const Key('collect_top_chrome_official_logo'),
    );
    final avatar = find.byTooltip('Profile');
    expect(officialLogo, findsOneWidget);
    expect(avatar, findsOneWidget);
    expect(
      tester.getRect(avatar).contains(tester.getCenter(officialLogo)),
      isTrue,
    );
    expect(tester.getSize(officialLogo), const Size.square(24));
    expect(
      (tester.widget<Image>(officialLogo).image as AssetImage).assetName,
      CollectRuntimeAssets.officialLogo,
    );
    expect(tester.takeException(), isNull);
  });

  test('primary route smoke list keeps admin out of member app', () {
    expect(
      collectRoutePaths,
      containsAll(<String>['/home', '/groups/:collectionId/contribute']),
    );
    expect(
      collectRoutePaths,
      isNot(contains('/groups/:collectionId/pay/:intentId')),
    );
    expect(collectRoutePaths, isNot(contains('/admin')));
  });
}

List<Color> _gradientColors(Gradient gradient) {
  return switch (gradient) {
    LinearGradient(:final colors) => colors,
    RadialGradient(:final colors) => colors,
    SweepGradient(:final colors) => colors,
    _ => fail('Unsupported gradient type: ${gradient.runtimeType}'),
  };
}

Future<void> _pumpCollect(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}

class _PermissionSequenceNotificationService
    extends CollectNotificationService {
  _PermissionSequenceNotificationService(this._responses);

  final List<bool> _responses;
  int requestCalls = 0;
  int registrationCalls = 0;
  int notificationCalls = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async {
    final index = requestCalls;
    requestCalls += 1;
    return _responses[index];
  }

  @override
  Future<void> registerDevice(CollectRepository repository) async {
    registrationCalls += 1;
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    notificationCalls += 1;
  }
}

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
