part of 'app_shell_test.dart';

void _registerAppShellThemeContracts() {
  test('runtime assets preserve Collect identity', () {
    final runtimeAssets = File(
      'lib/app/theme/collect_runtime_assets.dart',
    ).readAsStringSync();

    expect(runtimeAssets, contains('usesRepoVisualAssets = true'));
    expect(runtimeAssets, contains('officialLogoSha256'));
    expect(runtimeAssets, isNot(contains('assets/runtime')));
    expect(runtimeAssets, isNot(contains('assets/fonts')));
  });

  test('theme loads', () {
    expect(AppTheme.light(), isA<ThemeData>());
    expect(AppTheme.dark(), isA<ThemeData>());
    expect(AppTheme.dark().brightness, Brightness.dark);
    expect(
      AppTheme.highContrastLight()
          .extension<CollectUniversalTokens>()
          ?.highContrast,
      isTrue,
    );
    expect(
      AppTheme.highContrastDark()
          .extension<CollectUniversalTokens>()
          ?.highContrast,
      isTrue,
    );
    expect(
      AppTheme.highContrastDark()
          .inputDecorationTheme
          .focusedBorder
          ?.borderSide
          .width,
      3,
    );
  });

  test('theme controller supports a deterministic initial mode', () {
    final controller = CollectThemeModeController(
      initialMode: ThemeMode.light,
      loadPersistedMode: false,
    );

    expect(controller.state, ThemeMode.light);
  });

  test('member and admin apps use persisted Collect theme mode', () {
    final memberApp = File('lib/app/app.dart').readAsStringSync();
    final adminApp = File('lib/admin/admin_app.dart').readAsStringSync();
    final controller = File(
      'lib/app/theme/collect_theme_controller.dart',
    ).readAsStringSync();

    expect(memberApp, contains('collectThemeModeProvider'));
    expect(adminApp, contains('collectThemeModeProvider'));
    expect(memberApp, contains('highContrastTheme'));
    expect(memberApp, contains('highContrastDarkTheme'));
    expect(adminApp, contains('highContrastTheme'));
    expect(adminApp, contains('highContrastDarkTheme'));
    expect(memberApp, isNot(contains('themeMode: ThemeMode.system')));
    expect(adminApp, isNot(contains('themeMode: ThemeMode.system')));
    expect(controller, contains("'system' => ThemeMode.system"));
    expect(controller, isNot(contains('_concreteMode')));
  });

  testWidgets('system mode activates the high-contrast runtime theme', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(highContrast: true);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    final themeController = CollectThemeModeController();
    await themeController.setMode(ThemeMode.system);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appEnvProvider.overrideWithValue(_noSmsAccessEnv),
          collectThemeModeProvider.overrideWith((ref) => themeController),
        ],
        child: const CollectApp(),
      ),
    );
    await tester.pump();

    final runtimeTheme = Theme.of(tester.element(find.byType(Scaffold).first));
    expect(runtimeTheme.brightness, Brightness.light);
    expect(
      runtimeTheme.extension<CollectUniversalTokens>()?.highContrast,
      isTrue,
    );
    expect(runtimeTheme.colorScheme.outline, CollectColors.publicBlack);
  });

  test('mobile route smoke never injects fixture data at runtime', () {
    final main = File('lib/main.dart').readAsStringSync();
    final smokeScript = File(
      'scripts/mobile_route_render_smoke.sh',
    ).readAsStringSync();

    expect(main, contains('COLLECT_MOBILE_EVIDENCE_MODE'));
    expect(main, isNot(contains('CollectRepository.fixture()')));
    expect(main, isNot(contains('CollectRepository.appReviewDemo(')));
    expect(
      smokeScript,
      contains('--dart-define=COLLECT_MOBILE_EVIDENCE_MODE=true'),
    );
    expect(
      File(
        'lib/shared/repositories/collect_repository.dart',
      ).readAsStringSync(),
      contains('required CollectState initialState'),
    );
  });

  test('App Store artwork uses an isolated synthetic preview target', () {
    final captureScript = File(
      'scripts/app_store_ios_capture_assets.sh',
    ).readAsStringSync();
    final preview = File('tool/main_store_preview.dart').readAsStringSync();
    final productionBuild = File(
      'scripts/ios_app_store_build.sh',
    ).readAsStringSync();
    final fastfile = File('fastlane/Fastfile').readAsStringSync();

    expect(captureScript, contains('-t tool/main_store_preview.dart'));
    expect(preview, contains('FixtureCollectRepository'));
    expect(
      preview,
      contains('../test/fixtures/collect_repository_fixture.dart'),
    );
    expect(preview, contains("environmentName: 'store-preview'"));
    expect(productionBuild, isNot(contains('main_store_preview.dart')));
    expect(fastfile, isNot(contains('main_store_preview.dart')));
  });

  test('primary mobile screens use their reference chrome patterns', () {
    final home = [
      'lib/features/home/home_screen.dart',
      'lib/features/home/home_public_groups_section.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');
    final groups = File(
      'lib/features/collections/collections_screen.dart',
    ).readAsStringSync();
    final groupDetail = File(
      'lib/features/collections/collection_detail_screen.dart',
    ).readAsStringSync();
    final settings = File(
      'lib/features/settings/settings_screen.dart',
    ).readAsStringSync();
    final shell = File(
      'lib/core/widgets/collect_shell.dart',
    ).readAsStringSync();
    final sharedBarrel = File(
      'lib/shared/widgets/collect_components.dart',
    ).readAsStringSync();
    final chromeModule = [
      'lib/shared/widgets/collect_chrome.dart',
      'lib/shared/widgets/collect_top_chrome.dart',
      'lib/shared/widgets/collect_scaffold_chrome.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    expect(home, contains('CollectScreenTopChrome('));
    expect(home, isNot(contains("context.go('/groups/search')")));
    expect(home, isNot(contains("label: 'Join'")));
    expect(home, isNot(contains("context.go('/groups/join')")));
    expect(home, contains("label: 'Explore Groups'"));
    expect(home, contains("context.go('/groups?filter=featured')"));
    expect(groups, contains('CollectScreenTopChrome('));
    expect(groups, contains("'Search groups'"));
    expect(settings, isNot(contains('class _SettingsTopBar')));
    expect(settings, isNot(contains('CollectScreenTopChrome(')));
    expect(settings, isNot(contains("searchLabel: 'Settings'")));
    expect(groupDetail, contains('CollectPlainPageHeader'));
    expect(groupDetail, isNot(contains('CollectScreenTopChrome')));
    expect(groupDetail, isNot(contains('persistentPill')));
    expect(shell, isNot(contains('BackdropFilter')));
    expect(shell, isNot(contains("import 'dart:ui'")));
    expect(sharedBarrel, contains("export 'collect_chrome.dart';"));
    expect(sharedBarrel, isNot(contains('class CollectScreenTopChrome')));
    expect(chromeModule, contains('class CollectScreenTopChrome'));
    expect(chromeModule, contains('searchLabel'));
    expect(chromeModule, contains('onSearchTap'));
    expect(chromeModule, isNot(contains('onSearchChanged')));
    expect(chromeModule, contains('CollectIcons.search'));
    expect(chromeModule, contains('class ScreenHeader'));
  });

  test('member feedback surfaces do not render raw exception strings', () {
    for (final path in <String>[
      'lib/features/collections/collection_create_screen.dart',
      'lib/features/collections/group_profile_screen.dart',
      'lib/features/collections/group_qr_scanner_screen.dart',
      'lib/features/profile/profile_edit_screen.dart',
      'lib/features/settings/settings_subscreens.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        isNot(contains('_error = error.toString()')),
        reason: path,
      );
      expect(
        source,
        isNot(contains("Text('Could not save notifications: ")),
        reason: path,
      );
    }

    final contribution = [
      'lib/features/payments/contribution_flow_screen.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');
    final localizations = File(
      'lib/l10n/collect_localizations.dart',
    ).readAsStringSync();
    expect(contribution, contains('String _safeFlowError(Object error)'));
    expect(localizations, contains('Check your connection and try again.'));
    expect(contribution, isNot(contains('_error = error.toString()')));
  });

  test('group card media primitives stay out of the base component barrel', () {
    final sharedBarrel = File(
      'lib/shared/widgets/collect_components.dart',
    ).readAsStringSync();
    final groupCards = [
      'lib/shared/widgets/collect_group_cards.dart',
      'lib/shared/widgets/collect_group_card_media.dart',
      'lib/shared/widgets/collect_group_card_metrics.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');
    final home = File('lib/features/home/home_screen.dart').readAsStringSync();
    final groups = File(
      'lib/features/collections/collections_screen.dart',
    ).readAsStringSync();

    expect(sharedBarrel, isNot(contains('class GroupCard')));
    expect(sharedBarrel, isNot(contains('_GroupCoverMedia')));
    expect(groupCards, contains('class GroupCard'));
    expect(groupCards, contains('class GroupListPanel'));
    expect(groupCards, contains('_GroupCoverMedia'));
    expect(home, contains('widgets/collect_group_cards.dart'));
    expect(home, isNot(contains('GroupListPanel(')));
    expect(home, contains('_HomeGroupsSection('));
    expect(groups, contains('widgets/collect_group_cards.dart'));
    expect(groups, contains('_GroupsCardGrid('));
    expect(groups, contains('GroupCard('));
  });

  test(
    'review-note cleanup removes verbose permission and group filter UI',
    () {
      final groups = File(
        'lib/features/collections/collections_screen.dart',
      ).readAsStringSync();
      final profile = File(
        'lib/features/profile/profile_edit_screen.dart',
      ).readAsStringSync();
      final statusScreens = File(
        'lib/features/status/production_state_screens.dart',
      ).readAsStringSync();
      final devicePrivacyScreens = [
        'lib/features/status/native_permission_sheets.dart',
      ].map((path) => File(path).readAsStringSync()).join('\n');
      expect(
        File('lib/features/status/device_privacy_screens.dart').existsSync(),
        isFalse,
      );
      expect(
        File(
          'lib/features/status/device_privacy_data_screen.dart',
        ).existsSync(),
        isFalse,
      );
      expect(
        File('lib/features/status/device_support_screen.dart').existsSync(),
        isFalse,
      );
      expect(
        File('lib/features/status/access_state_screens.dart').existsSync(),
        isFalse,
      );
      final settings = File(
        'lib/features/settings/settings_screen.dart',
      ).readAsStringSync();
      final scanner = File(
        'lib/features/collections/group_qr_scanner_screen.dart',
      ).readAsStringSync();
      final groupCards = [
        'lib/shared/widgets/collect_group_cards.dart',
        'lib/shared/widgets/collect_group_card_media.dart',
        'lib/shared/widgets/collect_group_card_metrics.dart',
      ].map((path) => File(path).readAsStringSync()).join('\n');
      final createGroup = File(
        'lib/features/collections/collection_create_screen.dart',
      ).readAsStringSync();
      final collectComponents = File(
        'lib/shared/widgets/collect_components.dart',
      ).readAsStringSync();

      expect(groups, isNot(contains('_GroupControlDock')));
      expect(groups, isNot(contains('Visibility')));
      expect(groups, isNot(contains('Sort groups')));
      expect(profile, isNot(contains("label: 'Device permissions'")));
      expect(profile, contains('_ProfileAppBar('));
      expect(profile, isNot(contains('InfoSecurityBanner(')));
      expect(profile, isNot(contains('Back to settings')));
      expect(profile, isNot(contains('MoMo receipt access')));
      expect(profile, isNot(contains('Account and session')));
      expect(settings, isNot(contains('Ready for group activity')));
      expect(
        statusScreens,
        isNot(contains("export 'device_privacy_screens.dart';")),
      );
      expect(statusScreens, isNot(contains('SharedLinkProblemScreen')));
      expect(statusScreens, isNot(contains('FreshLinkRequestScreen')));
      expect(devicePrivacyScreens, contains('Open app settings'));
      expect(devicePrivacyScreens, contains('openAppSettings()'));
      expect(
        createGroup,
        contains("CollectPlainPageHeader(title: 'Create group')"),
      );
      expect(createGroup, isNot(contains('_createStepSubtitle')));
      expect(createGroup, isNot(contains('subtitle: _createStepSubtitle')));
      expect(
        scanner,
        isNot(contains("CollectPlainPageHeader(title: 'Scan QR')")),
      );
      expect(scanner, contains('MobileScanner('));
      expect(scanner, contains("label: 'Close scanner'"));
      expect(scanner, isNot(contains('analyzeImage')));
      expect(scanner, isNot(contains("'Gallery'")));
      expect(scanner, isNot(contains("label: 'Enter link'")));
      expect(groupCards, contains('_EditorialGroupCard'));
      expect(collectComponents, isNot(contains('plateFill')));
      expect(collectComponents, isNot(contains('plateBorder')));
    },
  );

  testWidgets('reduced motion returns zero animation duration', (tester) async {
    late Duration duration;
    late AnimationStyle? animationStyle;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              duration = CollectMotion.duration(context, CollectMotion.medium);
              animationStyle = CollectMotion.animationStyle(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(duration, Duration.zero);
    expect(animationStyle, AnimationStyle.noAnimation);
  });

  testWidgets('normal motion preserves declared animation timing', (
    tester,
  ) async {
    late Duration duration;
    late AnimationStyle? animationStyle;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            duration = CollectMotion.duration(context, CollectMotion.medium);
            animationStyle = CollectMotion.animationStyle(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(duration, CollectMotion.medium);
    expect(animationStyle, isNull);
  });

  test('all owned modal and route motion uses the reduced-motion policy', () {
    final modalFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) {
          final source = file.readAsStringSync();
          return source.contains('showModalBottomSheet') ||
              source.contains('showDialog<');
        })
        .toList(growable: false);

    var modalSheetCount = 0;
    var sheetPolicyCount = 0;
    var dialogCount = 0;
    var dialogPolicyCount = 0;
    for (final file in modalFiles) {
      final source = file.readAsStringSync();
      modalSheetCount += 'showModalBottomSheet'.allMatches(source).length;
      sheetPolicyCount +=
          'sheetAnimationStyle: CollectMotion.animationStyle(context)'
              .allMatches(source)
              .length;
      dialogCount += 'showDialog<'.allMatches(source).length;
      dialogPolicyCount += RegExp(
        r'\banimationStyle\s*:\s*CollectMotion\.animationStyle\(\s*context\s*,?\s*\)',
      ).allMatches(source).length;
    }

    expect(modalSheetCount, greaterThan(0));
    expect(sheetPolicyCount, modalSheetCount);
    expect(dialogCount, greaterThan(0));
    expect(dialogPolicyCount, dialogCount);

    final router = File('lib/app/router.dart').readAsStringSync();
    final manage = File(
      'lib/features/collections/collection_manage_screen.dart',
    ).readAsStringSync();
    expect(router, contains('final duration = CollectMotion.duration('));
    expect(router, contains('transitionDuration: duration'));
    expect(router, contains('reverseTransitionDuration: duration'));
    expect(
      manage,
      contains('duration: CollectMotion.duration(context, CollectMotion.fast)'),
    );
    expect(manage, isNot(contains('Duration(milliseconds: 160)')));
  });

  test('native SMS capability is not hidden behind legacy feature flags', () {
    final env = AppEnv.fromEnvironment();
    final app = File('lib/app/app.dart').readAsStringSync();

    expect(env.enableSmsReader, isFalse);
    // Eligibility defaults on; device support and explicit consent still gate
    // native capture independently of the retired SMS-reader flag.
    expect(env.enableAndroidSmsAccess, isTrue);
    expect(env.enableAdminPanel, isFalse);
    expect(env.enableAdminDevTools, isFalse);
    expect(app, isNot(contains('if (!env.enableAndroidSmsAccess')));
    expect(app, contains('syncPendingSmsAccess()'));
  });
}
