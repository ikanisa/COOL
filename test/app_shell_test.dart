import 'dart:io';

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/app/theme/collect_motion.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app opens with Collect launch splash', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(const ProviderScope(child: CollectApp()));
      await tester.pump();

      expect(find.text('Collect'), findsOneWidget);
      expect(find.text('Groups. MoMo. Done.'), findsNothing);
      expect(find.byTooltip('Open profile'), findsNothing);
      expect(find.text('TOTAL COLLECTED'), findsNothing);
      expect(find.text('Home'), findsNothing);
      expect(find.text('Settings'), findsNothing);
      expect(find.text('CONFIRMED'), findsNothing);
      expect(find.text('PENDING'), findsNothing);
      expect(find.text('FAILED'), findsNothing);
      expect(find.text('Platform admin'), findsNothing);
      expect(find.textContaining('BioPay'), findsNothing);
      expect(find.textContaining('wallet'), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('app boots with persisted dark-first theme mode', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CollectApp()));
    await tester.pump();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });

  testWidgets('unknown routes render branded recovery actions', (tester) async {
    final semantics = tester.ensureSemantics();
    final router = createAppRouter(initialLocation: '/missing-route');
    addTearDown(router.dispose);

    try {
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      );
      await tester.pump();

      expect(find.text('Screen not found'), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.text('This screen is unavailable.'), findsOneWidget);
      expect(find.textContaining('verified groups'), findsNothing);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Groups'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('offline and sync routes render recovery states', (tester) async {
    for (final route in <String>['/offline', '/sync']) {
      final router = createAppRouter(initialLocation: route);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      if (route == '/offline') {
        expect(find.text('Offline mode'), findsOneWidget);
        expect(find.text('Showing saved collection data'), findsOneWidget);
        expect(find.text('Saved'), findsOneWidget);
      } else {
        expect(find.text('Sync status'), findsOneWidget);
        expect(find.text('Sync needs attention'), findsOneWidget);
        expect(find.text('Queued updates'), findsOneWidget);
      }
      expect(find.text('Home'), findsWidgets);
    }
  });

  test('main Collect routes are registered', () {
    expect(
      collectRoutePaths,
      containsAll(<String>[
        '/',
        '/auth',
        '/home',
        '/groups',
        '/groups/scan',
        '/groups/create',
        '/groups/:collectionId',
        '/groups/:collectionId/members',
        '/groups/:collectionId/manage',
        '/groups/:collectionId/profile',
        '/groups/:collectionId/contribute',
        '/groups/:collectionId/share',
        '/groups/:collectionId/invite',
        '/groups/:collectionId/ledger',
        '/c/:slug',
        '/app',
        '/invite/:publicId',
        '/settings',
        '/settings/profile',
        '/settings/account',
        '/settings/account/delete',
        '/settings/legal/terms',
        '/settings/legal/privacy',
      ]),
    );
    expect(
      collectRoutePaths,
      isNot(
        containsAll(<String>[
          '/onboarding',
          '/notifications',
          '/permissions/device',
          '/groups/:collectionId/pay/:intentId/state/:state',
          '/groups/:collectionId/support/payment/:intentId',
        ]),
      ),
    );

    final router = createAppRouter();
    addTearDown(router.dispose);
    expect(router.configuration.routes, isNotEmpty);
  });

  testWidgets('large-width shell uses three-destination navigation rail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(820, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = createAppRouter(initialLocation: '/home');
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appRouterProvider.overrideWithValue(router)],
        child: const CollectApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Groups'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Admin'), findsNothing);
  });

  test('main mobile routes use the shared transition page helper', () {
    final routerSource = File('lib/app/router.dart').readAsStringSync();
    final shellSource = File(
      'lib/core/widgets/collect_shell.dart',
    ).readAsStringSync();

    expect(routerSource, contains('CustomTransitionPage<void>'));
    expect(routerSource, contains('pageBuilder:'));
    expect(
      routerSource,
      contains('MediaQuery.maybeOf(context)?.disableAnimations'),
    );
    expect(
      routerSource,
      isNot(contains('builder: (context, state) => const HomeScreen()')),
    );
    expect(
      routerSource,
      isNot(contains('builder: (context, state) => const CollectionsScreen()')),
    );
    expect(
      routerSource,
      isNot(contains("GoRoute(path: '/offline', redirect:")),
    );
    expect(routerSource, contains('const OfflineRecoveryScreen()'));
    expect(routerSource, contains('const SyncRecoveryScreen()'));
    expect(routerSource, contains('StatefulShellRoute.indexedStack'));
    expect(routerSource, contains('StatefulShellBranch'));
    expect(routerSource, contains("initialLocation: '/home'"));
    expect(routerSource, contains("initialLocation: '/groups'"));
    expect(routerSource, contains("initialLocation: '/settings'"));
    expect(
      routerSource,
      contains('CollectShell(navigationShell: navigationShell)'),
    );
    expect(routerSource, isNot(contains('ShellRoute(')));
    expect(shellSource, contains('StatefulNavigationShell? navigationShell'));
    expect(shellSource, contains('navigationShell?.currentIndex'));
    expect(shellSource, contains('statefulShell.goBranch('));
    expect(
      shellSource,
      contains('initialLocation: index == statefulShell.currentIndex'),
    );

    final recoveryScreens = File(
      'lib/features/status/connection_recovery_screens.dart',
    ).readAsStringSync();
    expect(recoveryScreens, contains('CollectConnectivityBanner'));
    expect(recoveryScreens, contains('ConnectivityStatus.offlineStale'));
    expect(recoveryScreens, contains('ConnectivityStatus.degraded'));
    expect(recoveryScreens, contains('Privacy stays on'));
    expect(recoveryScreens, contains('receiver MoMo numbers'));
    expect(recoveryScreens, contains("primaryLabel: 'Review groups'"));
    expect(recoveryScreens, contains("primaryLabel: 'Refresh groups'"));

    final shareScreen = File(
      'lib/features/collections/share_screen.dart',
    ).readAsStringSync();
    expect(shareScreen, isNot(contains('const Spacer()')));
    expect(shareScreen, contains('Privacy-safe link'));
    expect(shareScreen, contains('summaryFor(collectionId)'));
  });

  test('mobile chrome exposes native refresh and haptic affordances', () {
    final haptics = File(
      'lib/shared/utils/collect_haptics.dart',
    ).readAsStringSync();
    final foundation = File(
      'lib/shared/widgets/collect_foundation.dart',
    ).readAsStringSync();
    final chromeLibrary = File(
      'lib/shared/widgets/collect_chrome.dart',
    ).readAsStringSync();
    final scaffoldChrome = File(
      'lib/shared/widgets/collect_scaffold_chrome.dart',
    ).readAsStringSync();
    final topChrome = File(
      'lib/shared/widgets/collect_top_chrome.dart',
    ).readAsStringSync();
    final shell = File(
      'lib/core/widgets/collect_shell.dart',
    ).readAsStringSync();
    final nativePermissionSheets = File(
      'lib/features/status/native_permission_sheets.dart',
    ).readAsStringSync();
    final primaryScreens = [
      'lib/features/home/home_screen.dart',
      'lib/features/collections/collections_screen.dart',
      'lib/features/collections/collection_detail_screen.dart',
      'lib/features/ledger/ledger_screen.dart',
      'lib/features/settings/settings_screen.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    expect(haptics, contains('HapticFeedback.selectionClick'));
    expect(haptics, contains('HapticFeedback.lightImpact'));
    expect(haptics, contains('HapticFeedback.mediumImpact'));
    expect(haptics, contains('HapticFeedback.vibrate'));
    expect(chromeLibrary, contains("import '../utils/collect_haptics.dart';"));
    expect(foundation, contains('CollectHaptics.lightImpact();'));
    expect(foundation, contains('CollectHaptics.selection();'));
    expect(scaffoldChrome, contains('RefreshIndicator.adaptive'));
    expect(scaffoldChrome, contains('AlwaysScrollableScrollPhysics'));
    expect(scaffoldChrome, contains('CollectHaptics.lightImpact();'));
    expect(topChrome, contains('CollectHaptics.selection();'));
    expect(shell, contains('CollectHaptics.selection();'));
    expect(primaryScreens, contains('onRefresh:'));
    expect(primaryScreens, contains('collectRepositoryProvider.notifier'));
    expect(primaryScreens, contains('loadInitial()'));
    expect(nativePermissionSheets, contains('requestNativeNotifications(ref)'));
  });

  test('mobile native performance profiling has a device evidence gate', () {
    final profileScript = File(
      'scripts/mobile_native_performance_profile.sh',
    ).readAsStringSync();

    expect(profileScript, contains('flutter'));
    expect(profileScript, contains('drive'));
    expect(profileScript, contains('--profile'));
    expect(profileScript, contains('--trace-startup'));
    expect(profileScript, contains(r'--trace-to-file="$TRACE_FILE"'));
    expect(
      profileScript,
      contains('--dart-define=COLLECT_MOBILE_EVIDENCE_MODE=true'),
    );
    expect(profileScript, contains('timeline.binpb'));
    expect(profileScript, contains('runner_result.json'));
    expect(profileScript, contains('summary.json'));
    expect(profileScript, contains('trace_bytes'));
    expect(
      profileScript,
      contains('Profile-mode runner did not exit cleanly.'),
    );
    expect(profileScript, contains('Perfetto timeline trace was not written.'));
    expect(profileScript, contains('exit 99'));
  });

  test(
    'mobile route screenshot smoke covers every production screen route',
    () {
      final script = File(
        'scripts/mobile_route_render_smoke.sh',
      ).readAsStringSync();
      final smokeRoutes = RegExp(
        r'"[^"|]+\|([^"|]+)(?:\|[^"]+)?"',
      ).allMatches(script).map((match) => match.group(1)!).toSet();
      final productionScreenRoutes = collectRoutePaths
          .map(_materializeRouteForSmoke)
          .toSet();

      expect(smokeRoutes, containsAll(productionScreenRoutes));
    },
  );

  test(
    'DESIGN.md requires route screenshot coverage without legacy baseline files',
    () {
      final design = File('DESIGN.md').readAsStringSync();
      final smokeScript = File(
        'scripts/mobile_route_render_smoke.sh',
      ).readAsStringSync();
      final smokeRouteBlock = _routeSpecsBlock(smokeScript);
      final smokeRoutes = RegExp(
        r'^\s*"[^"|]+\|([^"|]+)(?:\|[^"]+)?"',
        multiLine: true,
      ).allMatches(smokeRouteBlock).map((match) => match.group(1)!).toSet();

      expect(design, contains('route screenshot coverage'));
      expect(design, contains('golden or snapshot tests'));
      expect(smokeRoutes, hasLength(greaterThanOrEqualTo(10)));
      expect(Directory('docs/design').existsSync(), isFalse);
    },
  );

  test(
    'physical-device route matrix covers mobile screenshot smoke routes',
    () {
      final smokeScript = File(
        'scripts/mobile_route_render_smoke.sh',
      ).readAsStringSync();
      final deviceTest = File(
        'integration_test/mobile_route_matrix_device_uat_test.dart',
      ).readAsStringSync();
      final smokeRouteBlock = _routeSpecsBlock(smokeScript);
      final smokeRoutes = RegExp(
        r'^\s*"[^"|]+\|([^"|]+)(?:\|[^"]+)?"',
        multiLine: true,
      ).allMatches(smokeRouteBlock).map((match) => match.group(1)!).toSet();
      final deviceRoutes = RegExp(
        r"_RouteSpec\(\s*'[^']+',\s*'([^']+)'\s*,?\s*'[^']+'\s*,?\s*\)",
        multiLine: true,
      ).allMatches(deviceTest).map((match) => match.group(1)!).toSet();

      expect(deviceRoutes, containsAll(smokeRoutes));
    },
  );

  test('Android UAT records early device blockers as summary evidence', () {
    final script = File('scripts/android_device_uat.sh').readAsStringSync();

    expect(script, contains('write_early_failure_summary'));
    expect(script, contains('"runner" => "not_started"'));
    expect(
      script,
      contains('"device_id" => ENV.fetch("ANDROID_UAT_DEVICE_ID")'),
    );
    expect(script, contains('is not connected and authorized over ADB'));
    expect(script, contains('Unlock it and keep it awake'));
  });

  test('repo-wide QA includes the mobile design compliance gate', () {
    final qaRunner = File('scripts/repo_wide_qa_uat.sh').readAsStringSync();
    final designAudit = File(
      'scripts/collect_mobile_design_compliance_audit.sh',
    ).readAsStringSync();

    expect(qaRunner, contains('collect_mobile_design_compliance_audit'));
    expect(qaRunner, contains('mobile_design_compliance'));
    expect(designAudit, contains('single_universal_design_contract'));
    expect(designAudit, contains('no_secondary_design_authority'));
    expect(designAudit, contains('universal_component_state_contract'));
    expect(designAudit, contains('responsive_adaptive_contract'));
    expect(designAudit, contains('route_screenshot_evidence_optional'));
    expect(designAudit, contains('android_device_uat_evidence_optional'));
  });

  test('single DESIGN.md enforces universal mobile design standard', () {
    final design = File('DESIGN.md').readAsStringSync();

    expect(design, contains('Universal Mobile App Design Standard 2026'));
    expect(design, contains('Universal Token Model'));
    expect(design, contains('Universal Component Library'));
    expect(design, contains('Visual QA Standard'));
    expect(design, contains('Flutter Implementation Standard'));
    expect(design, contains('route screenshot coverage'));
    expect(design, contains('golden or snapshot tests'));
    expect(Directory('docs/design').existsSync(), isFalse);
  });

  test('orange is reserved away from routine CTA and decorative surfaces', () {
    for (final path in <String>[
      'lib/features/landing/collect_landing_page.dart',
      'lib/features/landing/collect_home_access_trust.dart',
      'lib/features/landing/collect_home_hero.dart',
      'lib/features/landing/public_infographic_content.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        isNot(contains('brandOrangeRed')),
        reason: path,
      );
    }

    final groupCardMedia = File(
      'lib/shared/widgets/collect_group_card_media.dart',
    ).readAsStringSync();
    expect(groupCardMedia, isNot(contains('orangePaint')));
    expect(groupCardMedia, isNot(contains('brandAction,')));
    expect(groupCardMedia, contains('colors.rosePaint'));

    final staticSite = File(
      'scripts/public_static_site_build.rb',
    ).readAsStringSync();
    expect(staticSite, isNot(contains('var(--orange)')));
    expect(
      staticSite,
      contains('.button.cta-touch { background: var(--black)'),
    );
    expect(staticSite, contains('.brand-word { color: var(--periwinkle); }'));
  });

  test('design compliance audit reads only the universal contract', () {
    final designAudit = File(
      'scripts/collect_mobile_design_compliance_audit.sh',
    ).readAsStringSync();
    final runtimeAssets = File(
      'lib/app/theme/collect_runtime_assets.dart',
    ).readAsStringSync();

    expect(designAudit, contains('DESIGN.md'));
    expect(designAudit, contains('Universal Mobile App Design Standard 2026'));
    expect(designAudit, contains('no_secondary_design_authority'));
    expect(runtimeAssets, contains('wordmarkAssetPath = expectedWordmarkPath'));
    expect(runtimeAssets, contains('appIconAssetPath = expectedAppIconPath'));
  });

  test('theme loads', () {
    expect(AppTheme.light(), isA<ThemeData>());
    expect(AppTheme.dark(), isA<ThemeData>());
    expect(AppTheme.dark().brightness, Brightness.dark);
  });

  test('member and admin apps use persisted Collect theme mode', () {
    final memberApp = File('lib/app/app.dart').readAsStringSync();
    final adminApp = File('lib/admin/admin_app.dart').readAsStringSync();

    expect(memberApp, contains('collectThemeModeProvider'));
    expect(adminApp, contains('collectThemeModeProvider'));
    expect(memberApp, isNot(contains('themeMode: ThemeMode.system')));
    expect(adminApp, isNot(contains('themeMode: ThemeMode.system')));
  });

  test(
    'mobile route smoke uses sanitized fixture evidence mode only by flag',
    () {
      final main = File('lib/main.dart').readAsStringSync();
      final smokeScript = File(
        'scripts/mobile_route_render_smoke.sh',
      ).readAsStringSync();

      expect(main, contains('COLLECT_MOBILE_EVIDENCE_MODE'));
      expect(main, contains('CollectRepository.fixture()'));
      expect(main, contains('CollectRepository.appReviewDemo()'));
      expect(
        smokeScript,
        contains('--dart-define=COLLECT_MOBILE_EVIDENCE_MODE=true'),
      );
      expect(
        File(
          'lib/shared/repositories/collect_repository.dart',
        ).readAsStringSync(),
        contains('_emptyCollectState(),\n         true'),
      );
    },
  );

  test('primary mobile screens delete redundant top search chrome', () {
    final home = [
      'lib/features/home/home_screen.dart',
      'lib/features/home/home_action_strip.dart',
      'lib/features/home/home_public_groups_section.dart',
      'lib/features/home/home_total_collected_card.dart',
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
    final sharedBarrel = File(
      'lib/shared/widgets/collect_components.dart',
    ).readAsStringSync();
    final chromeModule = [
      'lib/shared/widgets/collect_chrome.dart',
      'lib/shared/widgets/collect_top_chrome.dart',
      'lib/shared/widgets/collect_scaffold_chrome.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    expect(home, isNot(contains('CollectTopChrome(')));
    expect(home, isNot(contains("context.go('/groups/search')")));
    expect(home, isNot(contains("label: 'Join'")));
    expect(home, isNot(contains("context.go('/groups/join')")));
    expect(home, contains("label: 'Scan QR'"));
    expect(home, contains("onTap: () => context.go('/groups/scan'),"));
    expect(groups, isNot(contains('CollectTopChrome(')));
    expect(groups, isNot(contains("'Search groups'")));
    expect(settings, isNot(contains('CollectTopChrome(')));
    expect(settings, isNot(contains("'Search settings'")));
    expect(groupDetail, isNot(contains('CollectTopChrome')));
    expect(groupDetail, isNot(contains('persistentPill')));
    expect(sharedBarrel, contains("export 'collect_chrome.dart';"));
    expect(sharedBarrel, isNot(contains('class CollectTopChrome')));
    expect(chromeModule, contains('class CollectTopChrome'));
    expect(chromeModule, isNot(contains('searchLabel')));
    expect(chromeModule, isNot(contains('onSearchTap')));
    expect(chromeModule, isNot(contains('onSearchChanged')));
    expect(chromeModule, isNot(contains('CollectIcons.search')));
    expect(chromeModule, contains('class ScreenHeader'));
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
    expect(groupCards, contains('_GroupCoverMedia'));
    expect(home, contains('widgets/collect_group_cards.dart'));
    expect(groups, contains('widgets/collect_group_cards.dart'));
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
      expect(
        profile,
        contains("CollectPlainPageHeader(title: 'Edit profile')"),
      );
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
      expect(groupCards, contains('_GroupCoverTitleOverlay'));
      expect(collectComponents, isNot(contains('plateFill')));
      expect(collectComponents, isNot(contains('plateBorder')));
    },
  );

  testWidgets('reduced motion returns zero animation duration', (tester) async {
    late Duration duration;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              duration = CollectMotion.duration(context, CollectMotion.medium);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(duration, Duration.zero);
  });

  test('environment defaults keep Android SMS access disabled', () {
    final env = AppEnv.fromEnvironment();
    final app = File('lib/app/app.dart').readAsStringSync();

    expect(env.enableSmsReader, isFalse);
    expect(env.enableAndroidSmsAccess, isFalse);
    expect(env.enableAdminPanel, isFalse);
    expect(env.enableAdminDevTools, isFalse);
    expect(
      app,
      contains(
        'if (!env.enableAndroidSmsAccess && !env.enableSmsReader) return;',
      ),
    );
  });
}

String _materializeRouteForSmoke(String route) {
  return route
      .replaceAll(':collectionId', 'col-church')
      .replaceAll(':intentId', 'intent-render')
      .replaceAll(':state', 'pending')
      .replaceAll(':publicId', '038491')
      .replaceAll(':slug', 'st-michel-building-fund');
}

String _routeSpecsBlock(String script) {
  final start = script.indexOf('route_specs=(');
  if (start < 0) {
    throw StateError('route_specs block not found');
  }
  final tail = script.substring(start);
  final terminator = RegExp(r'^\)$', multiLine: true).firstMatch(tail);
  if (terminator == null) {
    throw StateError('route_specs block terminator not found');
  }
  return script.substring(start, start + terminator.end);
}
