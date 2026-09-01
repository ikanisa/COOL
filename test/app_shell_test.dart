import 'dart:async';
import 'dart:io';

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/app/theme/collect_colors.dart';
import 'package:collect_app/app/theme/collect_motion.dart';
import 'package:collect_app/app/theme/collect_spacing.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/app/theme/collect_universal_tokens.dart';
import 'package:collect_app/core/notifications/collect_notification_service.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('customer screens do not render global connectivity banners', () {
    final appSource = File('lib/app/app.dart').readAsStringSync();
    final feedbackSource = File(
      'lib/shared/widgets/collect_state_feedback.dart',
    ).readAsStringSync();

    expect(appSource, isNot(contains('_CollectConnectivityOverlay')));
    expect(appSource, isNot(contains('CollectConnectivityBanner')));
    expect(feedbackSource, isNot(contains('Connection needs attention')));
  });

  test('member frontend omits verbose device-session labels', () {
    final accountSource = File(
      'lib/features/status/account_legal_screens.dart',
    ).readAsStringSync();

    expect(accountSource, isNot(contains('Signed in on this device')));
    expect(
      accountSource,
      isNot(contains('restores and refreshes this session')),
    );
  });

  test('notification deep links are constrained to existing safe routes', () {
    expect(normalizeNotificationDeepLink('/home'), '/home');
    expect(
      normalizeNotificationDeepLink('/groups/group-1/ledger'),
      '/groups/group-1/ledger',
    );
    expect(
      normalizeNotificationDeepLink('/settings/notifications'),
      '/settings/notifications',
    );
    expect(normalizeNotificationDeepLink('https://evil.example/home'), isNull);
    expect(normalizeNotificationDeepLink('/settings/account/delete'), isNull);
    expect(normalizeNotificationDeepLink('/groups/group-1/share'), isNull);
  });

  testWidgets('app opens authentication without a second Flutter splash', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(const ProviderScope(child: CollectApp()));
      await tester.pump();

      expect(find.text('Collect'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await tester.pumpAndSettle();

      expect(find.text("Let's get started!"), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
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

  testWidgets(
    'SMS access sync runs after launch and each completed foreground resume',
    (tester) async {
      final repository = _LifecycleCollectRepository();
      final notifications = _LifecycleNotificationService(enabled: true);
      final router = createAppRouter(initialLocation: '/home');
      final container = ProviderContainer(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          appEnvProvider.overrideWithValue(_smsAccessEnv),
          collectRepositoryProvider.overrideWith((ref) => repository),
          collectNotificationServiceProvider.overrideWithValue(notifications),
        ],
      );
      addTearDown(router.dispose);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CollectApp(),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(repository.syncCalls, 1);
      expect(notifications.initializeCalls, 2);
      expect(notifications.permissionChecks, 1);
      expect(
        container.read(notificationPermissionStatusProvider),
        CollectDevicePermissionStatus.granted,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(repository.syncCalls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(repository.syncCalls, 2);
      expect(notifications.initializeCalls, 4);
      expect(notifications.permissionChecks, 2);
    },
  );

  testWidgets(
    'native permission refresh is independent of internal SMS capture',
    (tester) async {
      final repository = _LifecycleCollectRepository();
      final notifications = _LifecycleNotificationService(enabled: true);
      final router = createAppRouter(initialLocation: '/home');
      final container = ProviderContainer(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          appEnvProvider.overrideWithValue(_noSmsAccessEnv),
          collectRepositoryProvider.overrideWith((ref) => repository),
          collectNotificationServiceProvider.overrideWithValue(notifications),
        ],
      );
      addTearDown(router.dispose);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CollectApp(),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(repository.syncCalls, 0);
      expect(notifications.initializeCalls, 2);
      expect(notifications.permissionChecks, 1);
      expect(
        container.read(notificationPermissionStatusProvider),
        CollectDevicePermissionStatus.granted,
      );

      notifications.enabled = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();

      expect(repository.syncCalls, 0);
      expect(notifications.initializeCalls, 3);
      expect(notifications.permissionChecks, 2);
      expect(
        container.read(notificationPermissionStatusProvider),
        CollectDevicePermissionStatus.denied,
      );

      container.read(notificationPermissionStatusProvider.notifier).state =
          CollectDevicePermissionStatus.denied;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();

      expect(notifications.initializeCalls, 4);
      expect(notifications.permissionChecks, 3);
      expect(
        container.read(notificationPermissionStatusProvider),
        CollectDevicePermissionStatus.denied,
      );
    },
  );

  testWidgets('notification taps navigate only through the safe route bridge', (
    tester,
  ) async {
    final notifications = _LifecycleNotificationService(enabled: true);
    final router = createAppRouter(initialLocation: '/home');
    final container = ProviderContainer(
      overrides: [
        appRouterProvider.overrideWithValue(router),
        appEnvProvider.overrideWithValue(_noSmsAccessEnv),
        collectRepositoryProvider.overrideWith(
          (ref) => CollectRepository.fixture(),
        ),
        collectNotificationServiceProvider.overrideWithValue(notifications),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(container.dispose);
    addTearDown(notifications.disposeTestStream);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CollectApp(),
      ),
    );
    await tester.pump();
    expect(notifications.hasTapListener, isTrue);
    notifications.emitTap('/settings/notifications');
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.path,
      '/settings/notifications',
    );
    expect(find.text('Contribution confirmations'), findsOneWidget);
  });

  testWidgets(
    'SMS access sync coalesces overlapping resumes and retries after failure',
    (tester) async {
      final repository = _LifecycleCollectRepository(blockFirstSync: true);
      final notifications = _LifecycleNotificationService(enabled: false);
      final router = createAppRouter(initialLocation: '/home');
      final container = ProviderContainer(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          appEnvProvider.overrideWithValue(_smsAccessEnv),
          collectRepositoryProvider.overrideWith((ref) => repository),
          collectNotificationServiceProvider.overrideWithValue(notifications),
        ],
      );
      addTearDown(router.dispose);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CollectApp(),
        ),
      );
      await tester.pump();
      expect(repository.syncCalls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(repository.syncCalls, 1);

      repository.releaseFirstSync();
      await tester.pump();
      await tester.pump();
      expect(
        container.read(notificationPermissionStatusProvider),
        CollectDevicePermissionStatus.notRequested,
      );

      notifications.throwOnPermissionCheck = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(repository.syncCalls, 2);

      notifications.throwOnPermissionCheck = false;
      notifications.enabled = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(repository.syncCalls, 3);
      expect(
        container.read(notificationPermissionStatusProvider),
        CollectDevicePermissionStatus.granted,
      );
    },
  );

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
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
        expect(find.text('Offline mode'), findsNothing);
        expect(find.text('You are offline'), findsOneWidget);
        expect(find.text('Saved'), findsOneWidget);
        expect(find.text('Scan/share'), findsNothing);
      } else {
        expect(find.text('Sync status'), findsNothing);
        expect(find.text('Sync needs attention'), findsOneWidget);
        expect(find.text('Queued updates'), findsOneWidget);
        expect(find.text('Verified ledger'), findsNothing);
      }
      expect(find.text('Review groups'), findsOneWidget);
      expect(
        tester.getBottomRight(find.text('Review groups')).dy,
        lessThan(844),
      );
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
        '/contribute',
        '/activity',
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
        '/settings/notifications',
        '/settings/appearance',
        '/settings/security',
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

  testWidgets('large-width shell uses consolidated four-destination rail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
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

    final rail = find.byType(NavigationRail);
    expect(rail, findsOneWidget);
    expect(
      find.descendant(of: rail, matching: find.text('Home')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rail, matching: find.text('Groups')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rail, matching: find.text('Contribute')),
      findsNothing,
    );
    expect(
      find.descendant(of: rail, matching: find.text('Activity')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rail, matching: find.text('Profile')),
      findsOneWidget,
    );
    expect(find.text('Admin'), findsNothing);
    expect(
      tester.getSize(find.byType(ListView).first).width,
      lessThanOrEqualTo(CollectSpacing.contentMaxWidth),
    );
  });

  test('main mobile routes use the shared transition page helper', () {
    final routerSource = File('lib/app/router.dart').readAsStringSync();
    final shellSource = File(
      'lib/core/widgets/collect_shell.dart',
    ).readAsStringSync();

    expect(routerSource, contains('CustomTransitionPage<void>'));
    expect(routerSource, contains('CupertinoPage<void>'));
    expect(routerSource, contains('platform == TargetPlatform.iOS'));
    expect(
      routerSource,
      contains('fullscreenDialog: transition == _CollectRouteTransition.modal'),
    );
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
    expect(routerSource, contains("initialLocation: '/contribute'"));
    expect(routerSource, contains("initialLocation: '/activity'"));
    expect(routerSource, contains("initialLocation: '/settings'"));
    expect(
      routerSource,
      contains('CollectShell(navigationShell: navigationShell)'),
    );
    expect(routerSource, isNot(contains('ShellRoute(')));
    expect(shellSource, contains('StatefulNavigationShell? navigationShell'));
    expect(shellSource, contains('_destinationIndexForBranch('));
    expect(shellSource, contains('navigationShell!.currentIndex'));
    expect(shellSource, contains('statefulShell.goBranch('));
    expect(
      shellSource,
      contains(
        'initialLocation: destination.branchIndex == statefulShell.currentIndex',
      ),
    );

    final recoveryScreens = File(
      'lib/features/status/connection_recovery_screens.dart',
    ).readAsStringSync();
    expect(recoveryScreens, isNot(contains('CollectConnectivityBanner')));
    expect(recoveryScreens, contains('CollectStatusTone.warning'));
    expect(recoveryScreens, contains('CollectStatusTone.info'));
    expect(recoveryScreens, contains('Privacy in recovery'));
    expect(recoveryScreens, isNot(contains('Privacy stays on')));
    expect(recoveryScreens, contains("primaryLabel: 'Review groups'"));
    expect(recoveryScreens, isNot(contains("primaryLabel: 'Refresh groups'")));

    final shareScreen = File(
      'lib/features/collections/share_screen.dart',
    ).readAsStringSync();
    expect(shareScreen, isNot(contains('const Spacer()')));
    expect(shareScreen, contains('Privacy-safe link'));
    expect(shareScreen, contains('summaryFor(widget.collectionId)'));
  });

  testWidgets('iOS detail screens use native Cupertino navigation', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final router = createAppRouter(initialLocation: '/groups/col-church');
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appRouterProvider.overrideWithValue(router),
            collectRepositoryProvider.overrideWith(
              (ref) => CollectRepository.fixture(),
            ),
          ],
          child: const CollectApp(),
        ),
      );
      await tester.pumpAndSettle();

      final detailContext = tester.element(
        find.text('St Michel building fund').first,
      );
      final route = ModalRoute.of(detailContext);
      expect(route?.settings, isA<CupertinoPage<void>>());
      expect((route as PageRoute<void>).popGestureEnabled, isTrue);
    } finally {
      router.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
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
    expect(profileScript, contains('--keep-app-running'));
    expect(
      profileScript,
      contains('--dart-define=COLLECT_MOBILE_EVIDENCE_MODE=true'),
    );
    expect(profileScript, contains('--dart-define=COLLECT_PERF_RUN_ID='));
    expect(profileScript, contains('timeline.binpb'));
    expect(profileScript, contains('runner_result.json'));
    expect(profileScript, contains('summary.json'));
    expect(profileScript, contains('trace_bytes'));
    expect(
      profileScript,
      contains('Profile-mode runner did not exit cleanly.'),
    );
    expect(profileScript, contains('All tests passed completion marker.'));
    expect(profileScript, contains('completion_marker'));
    expect(profileScript, contains('device_locked_after_run'));
    expect(profileScript, contains('NotificationShade'));
    expect(profileScript, contains('mDreamingLockscreen=true'));
    expect(profileScript, contains('Perfetto timeline trace was not written.'));
    expect(profileScript, contains('representative rendered-frame sample'));
    expect(profileScript, contains('total_frames.to_i >= 10'));
    expect(profileScript, contains('collect_perf_metric:'));
    expect(profileScript, contains('collect_perf_complete:'));
    expect(profileScript, contains('collect_perf_target:'));
    expect(profileScript, contains('flutter_engine_frame_metrics'));
    expect(profileScript, contains('flutter_engine_representative'));
    expect(profileScript, contains('"limited"'));
    expect(
      profileScript,
      contains('flutter_total_frames >= flutter_min_frames'),
    );
    expect(profileScript, contains(r'shell pidof "$PACKAGE_ID"'));
    expect(profileScript, contains('cmd package resolve-activity --brief'));
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
      expect(
        Directory(['docs', 'design'].join(Platform.pathSeparator)).existsSync(),
        isFalse,
      );
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
        r"_RouteSpec\(\s*'[^']+',\s*'([^']+)'",
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
    expect(script, contains('ANDROID_UAT_VARIANT_NAME'));
    expect(script, contains('COLLECT_UAT_THEME_MODE'));
    expect(script, contains('COLLECT_UAT_TEXT_SCALE'));
    expect(script, contains('COLLECT_UAT_HIGH_CONTRAST'));
    expect(script, contains('COLLECT_UAT_REDUCED_MOTION'));
    expect(script, contains('"variant" => {'));
  });

  test('repo-wide QA includes the mobile contract compliance gate', () {
    final qaRunner = File('scripts/repo_wide_qa_uat.sh').readAsStringSync();
    final designAudit = File(
      'scripts/universal_contract_audit.sh',
    ).readAsStringSync();

    expect(qaRunner, contains('universal_contract_audit'));
    expect(qaRunner, contains('mobile_contract_compliance'));
    expect(designAudit, contains('single_universal_contract'));
    expect(designAudit, contains('no_secondary_contract_sources'));
    expect(designAudit, contains('tracked_design_source_paths'));
    expect(designAudit, contains('universal_component_state_contract'));
    expect(designAudit, contains('responsive_adaptive_contract'));
    expect(designAudit, contains('route_screenshot_evidence_optional'));
    expect(designAudit, contains('android_device_uat_evidence_optional'));
  });

  test('single DESIGN.md enforces universal app design standard', () {
    final design = File('DESIGN.md').readAsStringSync();

    expect(design, contains('Universal App Design Standard 2026'));
    expect(design, contains('Universal Token Model'));
    expect(design, contains('Universal Component Library'));
    expect(design, contains('Native Flutter TV Standard'));
    expect(design, contains('not_applicable_for_cool'));
    expect(design, contains('COOL has no TV product surface in this release'));
    expect(design, contains('Admin Panel Standard'));
    expect(design, contains('Visual QA Standard'));
    expect(design, contains('Flutter Implementation Standard'));
    expect(design, contains('route screenshot coverage'));
    expect(design, contains('golden or snapshot tests'));
    expect(
      Directory(['docs', 'design'].join(Platform.pathSeparator)).existsSync(),
      isFalse,
    );
  });

  test('orange is reserved away from routine CTA and decorative surfaces', () {
    for (final path in <String>[
      'lib/features/landing/collect_landing_page.dart',
      'lib/features/landing/public_marketing_page_content.dart',
      'lib/features/landing/public_page_content.dart',
      'lib/features/landing/public_policy_page_content.dart',
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
    expect(groupCardMedia, isNot(contains('rosePaint')));
    expect(groupCardMedia, isNot(contains('periwinklePaint')));
    expect(groupCardMedia, isNot(contains('CollectColors.brandMintGreen')));
    expect(groupCardMedia, contains('CollectColors.brandPeriwinkle'));
    expect(groupCardMedia, contains('CollectColors.brandDustyRose'));
    expect(groupCardMedia, contains('CollectColors.brandOrangeRed'));

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

  test('contract compliance audit reads only the universal contract', () {
    final designAudit = File(
      'scripts/universal_contract_audit.sh',
    ).readAsStringSync();
    final runtimeAssets = File(
      'lib/app/theme/collect_runtime_assets.dart',
    ).readAsStringSync();

    expect(designAudit, contains('DESIGN.md'));
    expect(designAudit, contains('Universal App Design Standard 2026'));
    expect(designAudit, contains('no_secondary_contract_sources'));
    expect(designAudit, contains('tracked_design_source_paths'));
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
      contains('_emptyCollectState(),\n         true'),
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
    expect(preview, contains('CollectRepository.fixture'));
    expect(preview, contains("environmentName: 'store-preview'"));
    expect(preview, contains('supabaseUrl: \'\''));
    expect(preview, contains('supabaseAnonKey: \'\''));
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
    expect(home, contains("label: 'Scan QR'"));
    expect(home, contains("onTap: () => context.go('/groups/scan'),"));
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

    final contribution = File(
      'lib/features/payments/contribution_flow_screen.dart',
    ).readAsStringSync();
    final localizations = File(
      'lib/l10n/collect_localizations.dart',
    ).readAsStringSync();
    expect(contribution, contains('throw StateError(revolutCouldNotOpen);'));
    expect(contribution, contains('String _safeError(Object error)'));
    expect(localizations, contains('Check your connection and try again.'));
    expect(localizations, contains('Revolut could not open on this device.'));
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
    expect(home, contains('GroupListPanel('));
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
      expect(profile, contains("CollectPlainPageHeader(title: 'Profile')"));
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
      dialogPolicyCount +=
          'animationStyle: CollectMotion.animationStyle(context)'
              .allMatches(source)
              .length;
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
    expect(env.enableAndroidSmsAccess, isFalse);
    expect(env.enableAdminPanel, isFalse);
    expect(env.enableAdminDevTools, isFalse);
    expect(app, isNot(contains('if (!env.enableAndroidSmsAccess')));
    expect(app, contains('syncPendingSmsAccess()'));
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

const _smsAccessEnv = AppEnv(
  supabaseUrl: '',
  supabaseAnonKey: '',
  publicUrl: '',
  adminAppUrl: '',
  enableSmsReader: false,
  enableAndroidSmsAccess: true,
  enableAdminPanel: false,
  enableAdminDevTools: false,
  authCaptchaEnabled: false,
  authCaptchaProvider: '',
  authCaptchaSiteKey: '',
);

const _noSmsAccessEnv = AppEnv(
  supabaseUrl: '',
  supabaseAnonKey: '',
  publicUrl: '',
  adminAppUrl: '',
  enableSmsReader: false,
  enableAndroidSmsAccess: false,
  enableAdminPanel: false,
  enableAdminDevTools: false,
  authCaptchaEnabled: false,
  authCaptchaProvider: '',
  authCaptchaSiteKey: '',
);

class _LifecycleCollectRepository extends CollectRepository {
  _LifecycleCollectRepository({this.blockFirstSync = false}) : super.fixture();

  final bool blockFirstSync;
  final _firstSyncCompleter = Completer<void>();
  int syncCalls = 0;

  @override
  Future<int> syncPendingSmsAccess() async {
    syncCalls += 1;
    if (blockFirstSync && syncCalls == 1) {
      await _firstSyncCompleter.future;
    }
    return 0;
  }

  void releaseFirstSync() {
    if (!_firstSyncCompleter.isCompleted) {
      _firstSyncCompleter.complete();
    }
  }
}

class _LifecycleNotificationService extends CollectNotificationService {
  _LifecycleNotificationService({required this.enabled});

  bool enabled;
  bool throwOnPermissionCheck = false;
  int initializeCalls = 0;
  int permissionChecks = 0;
  final _tapController = StreamController<CollectNotificationIntent>.broadcast(
    sync: true,
  );

  @override
  Stream<CollectNotificationIntent> get notificationTapPayloads =>
      _tapController.stream;

  void emitTap(String target) =>
      _tapController.add(CollectNotificationIntent(deepLink: target));

  bool get hasTapListener => _tapController.hasListener;

  void disposeTestStream() => _tapController.close();

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
  }

  @override
  Future<bool> areNotificationsEnabled() async {
    permissionChecks += 1;
    if (throwOnPermissionCheck) {
      throw StateError('permission check unavailable');
    }
    return enabled;
  }
}
