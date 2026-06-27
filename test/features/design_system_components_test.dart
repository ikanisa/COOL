import 'dart:io';
import 'dart:typed_data';

import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/utils/money_format.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
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

  test('official Collect brand tokens are source controlled', () {
    expect(CollectColors.brandPaper, const Color(0xFFFAF8F5));
    expect(CollectColors.brandPeriwinkle, const Color(0xFF8885F0));
    expect(CollectColors.brandMintGreen, const Color(0xFF3CD070));
    expect(CollectColors.brandDustyRose, const Color(0xFFD38B96));
    expect(CollectColors.brandOrangeRed, const Color(0xFFFF5E43));
    expect(CollectColors.brandPrimaryColors, const <Color>[
      Color(0xFF8885F0),
      Color(0xFF3CD070),
      Color(0xFFD38B96),
      Color(0xFFFF5E43),
    ]);
    expect(CollectColors.brandPrimaryHexes, const <String>[
      '#8885F0',
      '#3CD070',
      '#D38B96',
      '#FF5E43',
    ]);
    expect(CollectColors.referenceAccountNavy, const Color(0xFF000840));
    expect(CollectColors.referenceAccountBlue, const Color(0xFF0818A0));
    expect(CollectColors.referenceAccountBlueMid, const Color(0xFF0F198E));
    expect(CollectColors.referenceAccountBlueDeep, const Color(0xFF070D60));
    expect(CollectColors.referencePaymentsPurple, const Color(0xFF181038));
    expect(CollectColors.referencePaymentsPurpleMid, const Color(0xFF302848));
    expect(CollectColors.referencePaymentsPurpleDeep, const Color(0xFF100820));
    expect(CollectColors.referenceAssetNavy, const Color(0xFF101830));
    expect(CollectColors.referenceAssetNavyMid, const Color(0xFF303870));
    expect(CollectColors.referenceAssetNavySoft, const Color(0xFF202858));
    expect(CollectColors.referenceRewardsViolet, const Color(0xFF302878));
    expect(CollectColors.referenceRewardsVioletBright, const Color(0xFF7050E8));
    expect(CollectColors.referenceRewardsVioletHot, const Color(0xFF9838F0));
    expect(CollectColors.referenceWealthTeal, const Color(0xFF102028));
    expect(CollectColors.referenceWealthTealMid, const Color(0xFF204050));
    expect(CollectColors.referenceWealthTealSoft, const Color(0xFF183848));
    expect(CollectColors.referenceContentDark, const Color(0xFF101018));
    expect(CollectColors.referenceContentBronze, const Color(0xFF303020));
    expect(CollectColors.referenceInvestTeal, const Color(0xFF202828));
    expect(CollectColors.referenceStockTealBlack, const Color(0xFF001010));
    expect(CollectColors.brandPrimaryColors, hasLength(4));
    expect(
      CollectColors.brandPrimaryColors,
      isNot(contains(CollectColors.brandPaper)),
    );
    expect(
      CollectColors.brandPrimaryColors,
      isNot(contains(CollectColors.transparentColor)),
    );
  });

  test('borrowed Revolut token layer preserves full secondary colors', () {
    expect(RevolutBorrowedTokens.secondaryColorRoles, hasLength(17));
    expect(
      RevolutBorrowedTokens.secondaryColorHexes,
      containsAll(<String>[
        '#252044',
        '#4B4664',
        '#5F5A76',
        '#FFFDFB',
        '#F1ECF7',
        '#DED8EA',
        '#CDC7F5',
        '#6F67E8',
        '#137A3F',
        '#514DD2',
        '#B9472E',
        '#B3261E',
        '#E7F8ED',
        '#ECEBFF',
        '#FFE9E3',
        '#FFE5DF',
      ]),
    );
    expect(
      RevolutBorrowedTokens.secondaryColorRoles.values.toSet().intersection(
        CollectColors.brandPrimaryColors.toSet(),
      ),
      isEmpty,
    );
  });

  test('Revolut reference background families are applied by route', () {
    final light = AppTheme.light().extension<CollectColors>()!;

    expect(
      (light.screenGradientForPath('/home') as LinearGradient).begin,
      Alignment.topCenter,
    );
    expect(
      (light.screenGradientForPath('/home') as LinearGradient).end,
      Alignment.bottomCenter,
    );
    expect(_gradientColors(light.screenGradientForPath('/home')), const [
      Color(0xFF0818A0),
      Color(0xFF0F198E),
      Color(0xFF000838),
      Color(0xFF000030),
    ]);
    expect(_gradientColors(light.screenGradientForPath('/groups')), const [
      Color(0xFF302848),
      Color(0xFF181038),
      Color(0xFF100820),
    ]);
    expect(
      _gradientColors(
        light.screenGradientForPath(
          '/groups/group_1/pay/intent_1/state/pending',
        ),
      ),
      const [
        Color(0xFF303870),
        Color(0xFF202858),
        Color(0xFF101830),
        Color(0xFF000818),
      ],
    );
    expect(
      _gradientColors(light.screenGradientForPath('/groups/group_1/share')),
      const [
        Color(0xFF9838F0),
        Color(0xFF7050E8),
        Color(0xFF302878),
        Color(0xFF100820),
      ],
    );
    expect(
      _gradientColors(light.screenGradientForPath('/groups/create')),
      const [
        Color(0xFF204050),
        Color(0xFF183848),
        Color(0xFF102028),
        Color(0xFF081820),
      ],
    );
    expect(
      _gradientColors(light.screenGradientForPath('/permissions/sms-denied')),
      const [
        Color(0xFF204050),
        Color(0xFF183848),
        Color(0xFF102028),
        Color(0xFF081820),
      ],
    );
    expect(
      _gradientColors(
        light.screenGradientForPath('/permissions/camera-denied'),
      ),
      const [
        Color(0xFF204050),
        Color(0xFF183848),
        Color(0xFF102028),
        Color(0xFF081820),
      ],
    );
    expect(
      _gradientColors(
        light.screenGradientForPath('/platform/iphone-create-unavailable'),
      ),
      const [
        Color(0xFF204050),
        Color(0xFF183848),
        Color(0xFF102028),
        Color(0xFF081820),
      ],
    );
    expect(
      _gradientColors(light.screenGradientForPath('/settings/help')),
      const [Color(0xFF303020), Color(0xFF181038), Color(0xFF101018)],
    );
    expect(_gradientColors(light.screenGradientForPath('/offline')), const [
      Color(0xFF202828),
      Color(0xFF102028),
      Color(0xFF001010),
    ]);
    expect(
      _gradientColors(light.screenGradientForPath('/notifications')),
      const [Color(0xFF302848), Color(0xFF181038), Color(0xFF101018)],
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
          showSearch: false,
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

  test('borrowed asset switchpoints use installed runtime inputs', () {
    expect(_pngSize('assets/brand/collect_app_icon_static.png'), (
      width: 512,
      height: 512,
    ));
    expect(_pngSize('assets/brand/generated/collect_app_icon_rule.png'), (
      width: 512,
      height: 512,
    ));
    expect(
      _pngSize('assets/brand/generated/collect_wordmark_transparent.png'),
      (width: 1024, height: 299),
    );
    expect(_pngSize('assets/brand/generated/collect_mark_transparent.png'), (
      width: 512,
      height: 512,
    ));
    expect(
      File('lib/features/launch/launch_splash_screen.dart').readAsStringSync(),
      contains('RevolutBorrowedAssets.splashMarkAssetPath'),
    );
    expect(
      RevolutBorrowedAssets.splashMarkAssetPath,
      'assets/brand/revolut_borrowed/splash/splash_mark.png',
    );
    expect(_pngSize(RevolutBorrowedAssets.wordmarkAssetPath), (
      width: 1024,
      height: 299,
    ));
    expect(_pngSize(RevolutBorrowedAssets.appIconAssetPath), (
      width: 512,
      height: 512,
    ));
    expect(_pngSize(RevolutBorrowedAssets.splashMarkAssetPath), (
      width: 512,
      height: 512,
    ));
    expect(
      RevolutBorrowedAssets.expectedWordmarkPath,
      'assets/brand/revolut_borrowed/logos/wordmark.png',
    );
    expect(
      RevolutBorrowedAssets.expectedAppIconPath,
      'assets/brand/revolut_borrowed/app_icons/app_icon.png',
    );
    expect(
      RevolutBorrowedAssets.expectedSplashMarkPath,
      'assets/brand/revolut_borrowed/splash/splash_mark.png',
    );
    expect(
      File('lib/features/launch/launch_splash_screen.dart').readAsStringSync(),
      contains('SizedBox.expand'),
    );
    expect(
      File('assets/brand/generated/collect_symbol_compact.png').existsSync(),
      isFalse,
    );
    expect(_pngSize('web/icons/revolut-borrowed-web-512.png'), (
      width: 512,
      height: 512,
    ));
    expect(File('web/icons/collect-admin.svg').existsSync(), isFalse);
    expect(
      File('android/app/src/main/res/drawable/ic_launcher.xml').existsSync(),
      isFalse,
    );
  });

  test('native Android launch splash uses Collect brand resources', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android:theme="@style/LaunchTheme"'));
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
      expect(text, contains('@drawable/collect_splash_logo'), reason: path);
    }

    final expectedSplashSizes = <String, ({int width, int height})>{
      'android/app/src/main/res/drawable/collect_splash_logo.png': (
        width: 280,
        height: 82,
      ),
      'android/app/src/main/res/drawable-mdpi/collect_splash_logo.png': (
        width: 280,
        height: 82,
      ),
      'android/app/src/main/res/drawable-hdpi/collect_splash_logo.png': (
        width: 420,
        height: 123,
      ),
      'android/app/src/main/res/drawable-xhdpi/collect_splash_logo.png': (
        width: 560,
        height: 163,
      ),
      'android/app/src/main/res/drawable-xxhdpi/collect_splash_logo.png': (
        width: 840,
        height: 245,
      ),
      'android/app/src/main/res/drawable-xxxhdpi/collect_splash_logo.png': (
        width: 1120,
        height: 327,
      ),
      'android/app/src/main/res/drawable-night/collect_splash_logo.png': (
        width: 280,
        height: 82,
      ),
      'android/app/src/main/res/drawable-night-mdpi/collect_splash_logo.png': (
        width: 280,
        height: 82,
      ),
      'android/app/src/main/res/drawable-night-hdpi/collect_splash_logo.png': (
        width: 420,
        height: 123,
      ),
      'android/app/src/main/res/drawable-night-xhdpi/collect_splash_logo.png': (
        width: 560,
        height: 163,
      ),
      'android/app/src/main/res/drawable-night-xxhdpi/collect_splash_logo.png':
          (width: 840, height: 245),
      'android/app/src/main/res/drawable-night-xxxhdpi/collect_splash_logo.png':
          (width: 1120, height: 327),
      'android/app/src/main/res/drawable/collect_launcher_icon.png': (
        width: 512,
        height: 512,
      ),
    };
    for (final entry in expectedSplashSizes.entries) {
      expect(_pngSize(entry.key), entry.value, reason: entry.key);
    }
  });

  testWidgets('brand mark uses the borrowed asset switchpoint', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpCollect(tester, const CollectBrandMark());

      expect(find.bySemanticsLabel('Collect logo'), findsOneWidget);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<AssetImage>());
      expect((image.image as AssetImage).assetName, CollectBrandMark.assetPath);
      expect(
        CollectBrandMark.assetPath,
        RevolutBorrowedAssets.wordmarkAssetPath,
      );
    } finally {
      semantics.dispose();
    }
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
        receiverMomoNumber: '+250788123456',
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
    expect(find.text('MTN-001'), findsOneWidget);
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
            message: 'Enable SMS access before creating groups.',
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

  testWidgets('list tile separates static information from actions', (
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
      findsNothing,
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

  testWidgets('top chrome exposes avatar search and circular actions', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      CollectTopChrome(
        avatarLabel: '038491',
        hasUnread: true,
        searchLabel: 'Search groups',
        onSearchTap: () {},
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
    expect(find.text('Search groups'), findsOneWidget);
    expect(find.byIcon(CollectIcons.qr), findsOneWidget);
    expect(find.byIcon(CollectIcons.settings), findsOneWidget);
  });

  test('primary route smoke list keeps admin out of member app', () {
    expect(
      collectRoutePaths,
      containsAll(<String>[
        '/home',
        '/groups/:collectionId/contribute',
        '/groups/:collectionId/pay/:intentId',
        '/dev/design-system',
      ]),
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

({int width, int height}) _pngSize(String path) {
  final bytes = File(path).readAsBytesSync();
  expect(bytes.length, greaterThanOrEqualTo(24), reason: path);
  expect(bytes.sublist(0, 8), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  return (width: data.getUint32(16), height: data.getUint32(20));
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
