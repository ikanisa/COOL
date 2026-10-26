import '../fixtures/collect_repository_fixture.dart';

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

part 'runtime_component_interaction_cases.dart';

void main() {
  test('metadata group creation is available across app platforms', () {
    for (final platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.windows,
      TargetPlatform.fuchsia,
    ]) {
      expect(
        groupCreationPlatformAllowed(isWeb: false, targetPlatform: platform),
        isTrue,
      );
    }
    expect(
      groupCreationPlatformAllowed(
        isWeb: true,
        targetPlatform: TargetPlatform.android,
      ),
      isTrue,
    );
    expect(
      groupCreationPlatformAllowed(
        isWeb: true,
        targetPlatform: TargetPlatform.android,
        mobileEvidencePlatform: 'ios',
      ),
      isTrue,
    );
    expect(
      groupCreationPlatformAllowed(
        isWeb: true,
        targetPlatform: TargetPlatform.iOS,
        mobileEvidencePlatform: 'android',
      ),
      isTrue,
      reason: 'Evidence labels do not restrict metadata creation.',
    );
  });

  test('Collect routes use a neutral canvas independent of logo colors', () {
    final light = AppTheme.light().extension<CollectColors>();
    expect(light, isNotNull);
    expect(light!.surface, const Color(0xFFF7F7F8));
    expect(light.screenBase, light.canvas);
    expect(light.screenBase, isNot(CollectColors.referenceAccountHighlight));
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
    expect(light.panelSurface, isNot(dark.panelSurface));
    expect(light.onAccent, CollectColors.publicWhite);
    expect(dark.onAccent, CollectColors.publicBlack);
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
      expect(CollectColors.groupAccentColors, hasLength(4));
      expect(CollectColors.groupAccentColors.toSet(), hasLength(4));
      final paletteHexes = CollectColors.groupAccentOptions
          .map((option) => option.hex)
          .toList(growable: false);
      expect(paletteHexes, hasLength(CollectColors.groupAccentColors.length));
      expect(paletteHexes, everyElement(matches(RegExp(r'^#[0-9A-F]{6}$'))));
      expect(
        CollectColors.groupAccentColors,
        isNot(contains(CollectColors.publicWhite)),
      );
      expect(
        CollectColors.groupAccentColors,
        isNot(contains(CollectColors.transparentColor)),
      );
    },
  );

  test('reference colour swatches keep readable selection marks', () {
    for (final color in CollectColors.groupAccentColors) {
      expect(
        _contrastRatio(CollectColors.foregroundOn(color), color),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test('Collect runtime token layer contains no retired chrome vocabulary', () {
    final source = File(
      'lib/app/theme/collect_runtime_tokens.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('secondaryColorRoles')));
    expect(source, isNot(contains('glassPanel')));
    expect(source, isNot(contains('periwinklePaint')));
  });

  test('customer routes share a scoped reference background system', () {
    final source = File(
      'lib/shared/widgets/collect_scaffold_chrome.dart',
    ).readAsStringSync();

    expect(source, contains('CollectRuntimeTokens.overviewBackdrop('));
    expect(source, contains('CollectBackdropScope.of(context)'));
    expect(
      source,
      contains('highContrast: MediaQuery.highContrastOf(context)'),
    );
    expect(source, isNot(contains('screenGradient')));
  });

  test('member and admin source rejects retired decorative chrome', () {
    const roots = <String>[
      'lib/admin',
      'lib/core/widgets',
      'lib/features/auth',
      'lib/features/collections',
      'lib/features/launch',
      'lib/features/ledger',
      'lib/features/settings',
      'lib/features/status',
      'lib/shared',
    ];
    final files = <File>[];
    for (final root in roots) {
      final entity = Directory(root);
      if (!entity.existsSync()) continue;
      files.addAll(
        entity
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .where(
              (file) =>
                  !file.path.endsWith('collect_group_card_media.dart') &&
                  !file.path.endsWith('collect_group_card_metrics.dart') &&
                  // The selected native Security header uses a gradient only
                  // as its dotted-wave illustration shader, not page chrome.
                  !file.path.endsWith('security_hub_header.dart') &&
                  // The observed signed-out Business entry uses a dark
                  // gradient. It is separate from quiet operator workspace
                  // chrome (Revolut state/lifecycle capture, 5 September).
                  !file.path.endsWith('admin_public_account_page.dart'),
            ),
      );
    }
    final sources = {
      for (final file in files) file.path: file.readAsStringSync(),
    };
    List<String> filesContaining(String token) => sources.entries
        .where((entry) => entry.value.contains(token))
        .map((entry) => entry.key)
        .toList(growable: false);

    expect(filesContaining('LinearGradient('), isEmpty);
    expect(filesContaining('screenGradient'), isEmpty);
    expect(filesContaining('adminScreenGradient'), isEmpty);
    expect(filesContaining('colors.periwinklePaint'), isEmpty);
    expect(filesContaining('CollectColors.publicInk'), isEmpty);
    expect(filesContaining('qr-share.png'), isEmpty);
    expect(filesContaining('group-momentum.png'), isEmpty);
    expect(filesContaining('mobile-money-ussd-signal.png'), isEmpty);
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
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  useSafeArea: true,
                  backgroundColor: context.collectColors.transparent,
                  sheetAnimationStyle: CollectMotion.animationStyle(context),
                  builder: (_) =>
                      const CollectBottomSheet(child: Text('Sheet content')),
                ),
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

    expect(find.text('Sheet content'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);

    Navigator.of(tester.element(find.text('Sheet content'))).pop();
    await tester.pump();

    expect(find.text('Sheet content'), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  test(
    'Collect keeps Inter product roles and supplied Pro marketing faces',
    () {
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
      const removedLegacyFamilies = <String>[
        'Robo'
            'to',
        'JetBrains'
            ' Mono',
      ];
      // An icon font is not a body/display typeface. Apple-platform controls
      // require this asset; text roles use the licensed Inter adapter.
      expect(pubspec, contains('cupertino_icons:'));
      expect(lockfile, contains('cupertino_icons:'));
      expect(
        RegExp(
          r'^\s*- family:\s*([^\r\n]+)',
          multiLine: true,
        ).allMatches(pubspec).map((match) => match.group(1)?.trim()),
        ['Inter'],
      );
      expect(pubspec, isNot(contains('Collect Runtime')));
      expect(pubspec, isNot(contains('Collect Display')));
      expect(CollectRuntimeTypography.fontFamily, 'Inter');
      expect(CollectRuntimeTypography.displayFontFamily, 'Inter');
      expect(CollectRuntimeTypography.financialFontFamily, 'Inter');
      expect(CollectRuntimeTypography.marketingFontFamily, 'Inter');
      expect(
        pubspec,
        isNot(contains('assets/typefaces/AeonikPro-Regular.ttf')),
      );
      expect(pubspec, isNot(contains('assets/typefaces/AeonikPro-Medium.ttf')));
      expect(pubspec, isNot(contains('TRIAL')));
      expect(runtimeTypography, isNot(contains('fontFamilyFallback')));
      for (final family in removedLegacyFamilies) {
        expect(runtimeTypography, isNot(contains(family)));
        expect(libSources, isNot(contains(family)));
      }
      expect(launch, contains('SizedBox.expand'));
      expect(launch, isNot(contains('CollectRuntimeAssets.officialLogo')));
      expect(launch, isNot(contains('LinearProgressIndicator')));
      expect(launch, isNot(contains('Timer(')));
      expect(launch, isNot(contains("context.go('/auth')")));
      expect(launch, contains('CollectColors.referenceChromeBlack'));
      expect(libSources, contains('Image.asset'));
      expect(libSources, isNot(contains('AssetImage')));
      expect(libSources, isNot(contains('SvgPicture')));
      expect(libSources, contains('collect_top_chrome_official_logo'));
      expect(libSources, isNot(contains('collect_top_chrome_avatar_initial')));
    },
  );

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
      r'\b(?:TextStyle|copyWith)\s*\([^)]{0,500}\bheight\s*:\s*[0-9]',
      dotAll: true,
    );

    for (final file in files) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(matches(RegExp(r'\bTextStyle\s*\('))),
        reason: file.path,
      );
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
    expect(staticSite, contains('web/public/layout.css'));
    final publicCss = [
      File('web/public/layout.css').readAsStringSync(),
      File('web/public/revolut.css').readAsStringSync(),
    ].join('\n');
    // Source adapters may define numeric metrics centrally. Runtime component
    // rules must consume those roles, including the external served stylesheets.
    final featureCss = publicCss
        .replaceAll(RegExp(r'@font-face\s*\{[^}]*\}', dotAll: true), '')
        .replaceAll(RegExp(r':root\s*\{[^}]*\}', dotAll: true), '');
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
    expect(publicCss, contains('font-weight: 400 700;'));
    expect(publicCss, isNot(contains('font-weight: 100 900;')));
    expect(
      publicCss,
      isNot(
        matches(RegExp(r'font-weight:\s*(?:7[1-9][0-9]|8[0-9]{2}|9[0-9]{2})')),
      ),
    );
  });

  test('tracked visual assets exclude SVG and unapproved brand artwork', () {
    final tracked = Process.runSync(
      'git',
      ['ls-files', '--cached', '--others', '--exclude-standard'],
      workingDirectory: Platform.environment['COLLECT_REPOSITORY_CUSTODY_ROOT'],
    );
    expect(tracked.exitCode, 0);
    final deleted = Process.runSync(
      'git',
      ['ls-files', '--deleted'],
      workingDirectory: Platform.environment['COLLECT_REPOSITORY_CUSTODY_ROOT'],
    );
    expect(deleted.exitCode, 0);
    final deletedPaths = (deleted.stdout as String)
        .split('\n')
        .where((path) => path.isNotEmpty)
        .toSet();
    final paths = (tracked.stdout as String)
        .split('\n')
        .where((path) => path.isNotEmpty && !deletedPaths.contains(path))
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
    // Exact inventory equality and content hashes cover the Rwanda photo bank
    // as well as brand and website assets; the former fixed count predated it.
    expect(productVisualAssets, approvedVisualAssets.keys.toSet());
    expect(approvedVisualAssets, isNotEmpty);
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
      'android/app/src/main/res/drawable-nodpi/collect_launcher_icon.png',
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

  test('mobile visual foundation uses compact clean geometry', () {
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
    expect(shell, contains("ValueKey('collect-floating-navigation')"));
    expect(shell, contains('final showLabels = textScale <= 1.3;'));
    expect(shell, contains('size: selected ? 23 : 21'));
    expect(shell, isNot(contains('BackdropFilter')));
    expect(shell, isNot(contains('ImageFilter.blur')));
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
    expect(light.touchTarget, greaterThanOrEqualTo(48));
    expect(light.iconTarget, greaterThanOrEqualTo(44));
    expect(light.spacingStep, 4);
    expect(light.cardRadius, lessThanOrEqualTo(8));
    expect(light.motionFast.inMilliseconds, inInclusiveRange(120, 180));
    expect(light.motionStandard.inMilliseconds, inInclusiveRange(200, 280));
    expect(light.motionSlow.inMilliseconds, inInclusiveRange(320, 420));

    expect(dark, isNotNull);
    final darkTokens = dark!;
    expect(darkTokens.focusRing, CollectColors.dark.focusRing);
    expect(darkTokens.adminWorkspace, CollectColors.dark.canvas);
    expect(
      CollectUniversalTokens.highContrastDark().focusRing,
      CollectColors.publicWhite,
    );
    expect(CollectUniversalTokens.highContrastDark().highContrast, isTrue);
    expect(
      CollectUniversalTokens.highContrastDark().focusRingWidth,
      greaterThan(darkTokens.focusRingWidth),
    );
  });

  test('Android owns the only visible Collect launch screen', () {
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
        contains('<item name="android:windowFullscreen">true</item>'),
        reason: path,
      );
    }

    for (final path in <String>[
      'android/app/src/main/res/values-v27/styles.xml',
      'android/app/src/main/res/values-night-v27/styles.xml',
      'android/app/src/main/res/values-v29/styles.xml',
      'android/app/src/main/res/values-night-v29/styles.xml',
    ]) {
      final text = File(path).readAsStringSync();
      expect(
        text,
        contains('<item name="android:windowLightNavigationBar">false</item>'),
        reason: path,
      );
    }

    for (final path in <String>[
      'android/app/src/main/res/values-v29/styles.xml',
      'android/app/src/main/res/values-night-v29/styles.xml',
    ]) {
      final text = File(path).readAsStringSync();
      expect(
        text,
        contains('<item name="android:forceDarkAllowed">false</item>'),
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

    final launchResources = Directory('android/app/src/main/res')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('/launch_background.xml'))
        .toList();
    // Android resolves the default and night drawables for API 21 as well.
    // Inspect every present variant without requiring removed duplicate files.
    expect(
      launchResources.map((file) => file.path),
      containsAll([
        'android/app/src/main/res/drawable/launch_background.xml',
        'android/app/src/main/res/drawable-night/launch_background.xml',
      ]),
    );
    for (final file in launchResources) {
      final path = file.path;
      final text = file.readAsStringSync();
      expect(text, contains('@color/collect_launch_background'), reason: path);
      expect(text, isNot(contains('@color/collect_paper')), reason: path);
      expect(text, contains('<bitmap'), reason: path);
      expect(text, contains('@drawable/collect_launcher_icon'), reason: path);
    }

    for (final path in <String>[
      'android/app/src/main/res/values-v31/styles.xml',
      'android/app/src/main/res/values-night-v31/styles.xml',
    ]) {
      final text = File(path).readAsStringSync();
      expect(text, isNot(contains('@drawable/transparent')), reason: path);
      expect(text, contains('@drawable/collect_launcher_icon'), reason: path);
    }

    final colors = File(
      'android/app/src/main/res/values/colors.xml',
    ).readAsStringSync();
    expect(
      colors,
      contains('<color name="collect_launch_background">#000000</color>'),
    );

    final playStoreIcon = File(
      'fastlane/metadata/android/en-US/images/icon.png',
    );
    final iosAppIcon = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    expect(playStoreIcon.existsSync(), isTrue);
    expect(
      sha256.convert(playStoreIcon.readAsBytesSync()).toString(),
      '211362791b75bb0e3959d9671532e4736c4dcb545dcc77699ad1d88c6cae9206',
    );
    expect(
      sha256.convert(iosAppIcon.readAsBytesSync()).toString(),
      '25fabc042f4e2b90ba385388542cfbea764b34e0e8cbeaa18dda12045f277738',
    );
  });

  _registerRuntimeComponentInteractions();
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
  bool? get permissionGranted =>
      registrationStatus.value == CollectNotificationStatus.ready;

  @override
  Future<bool> enableDevice(CollectRepository repository) async {
    final allowed = await requestPermission();
    registrationStatus.value = allowed
        ? CollectNotificationStatus.ready
        : CollectNotificationStatus.permissionDenied;
    if (allowed) return registerDevice(repository);
    return false;
  }

  @override
  Future<bool> registerDevice(CollectRepository repository) async {
    registrationCalls += 1;
    return true;
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    String? eventType,
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
