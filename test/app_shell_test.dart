import 'fixtures/collect_repository_fixture.dart';

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

part 'app_shell_theme_contract_cases.dart';

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
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appEnvProvider.overrideWithValue(_noSmsAccessEnv)],
          child: const CollectApp(),
        ),
      );
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
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appEnvProvider.overrideWithValue(_noSmsAccessEnv)],
        child: const CollectApp(),
      ),
    );
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
      // Signed-out registration stops before requesting a remote token.
      expect(notifications.initializeCalls, 1);
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
      expect(notifications.initializeCalls, 2);
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
      expect(notifications.initializeCalls, 1);
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
      expect(notifications.initializeCalls, 2);
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

      expect(notifications.initializeCalls, 3);
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
          (ref) => FixtureCollectRepository(),
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
    expect(find.text('Contribution updates'), findsOneWidget);
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
      expect(repository.syncCalls, 2);
      expect(
        container.read(notificationPermissionStatusProvider),
        CollectDevicePermissionStatus.notRequested,
      );

      notifications.throwOnPermissionCheck = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(repository.syncCalls, 3);

      notifications.throwOnPermissionCheck = false;
      notifications.enabled = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(repository.syncCalls, 4);
      expect(
        container.read(notificationPermissionStatusProvider),
        CollectDevicePermissionStatus.granted,
      );
    },
  );

  testWidgets('failed SMS drain retries with capped foreground backoff', (
    tester,
  ) async {
    final repository = _LifecycleCollectRepository(failSyncs: 2);
    final router = createAppRouter(initialLocation: '/home');
    final container = ProviderContainer(
      overrides: [
        appRouterProvider.overrideWithValue(router),
        appEnvProvider.overrideWithValue(_smsAccessEnv),
        collectRepositoryProvider.overrideWith((ref) => repository),
        collectNotificationServiceProvider.overrideWithValue(
          _LifecycleNotificationService(enabled: false),
        ),
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

    await tester.pump(const Duration(seconds: 4));
    expect(repository.syncCalls, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(repository.syncCalls, 2);

    await tester.pump(const Duration(seconds: 14));
    expect(repository.syncCalls, 2);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(repository.syncCalls, 3);

    await tester.pump(const Duration(minutes: 15));
    expect(repository.syncCalls, 3);
  });

  testWidgets('SMS retry pauses with app and resumes on user return', (
    tester,
  ) async {
    final repository = _LifecycleCollectRepository(failSyncs: 1);
    final router = createAppRouter(initialLocation: '/home');
    final container = ProviderContainer(
      overrides: [
        appRouterProvider.overrideWithValue(router),
        appEnvProvider.overrideWithValue(_smsAccessEnv),
        collectRepositoryProvider.overrideWith((ref) => repository),
        collectNotificationServiceProvider.overrideWithValue(
          _LifecycleNotificationService(enabled: false),
        ),
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

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 6));
    expect(repository.syncCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(repository.syncCalls, 2);
  });

  testWidgets(
    'repeated SMS failures cannot schedule faster than capped backoff',
    (tester) async {
      final repository = _LifecycleCollectRepository(failSyncs: 6);
      final router = createAppRouter(initialLocation: '/home');
      final container = ProviderContainer(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          appEnvProvider.overrideWithValue(_smsAccessEnv),
          collectRepositoryProvider.overrideWith((ref) => repository),
          collectNotificationServiceProvider.overrideWithValue(
            _LifecycleNotificationService(enabled: false),
          ),
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

      var expectedCalls = 1;
      for (final delay in <Duration>[
        const Duration(seconds: 5),
        const Duration(seconds: 15),
        const Duration(minutes: 1),
        const Duration(minutes: 5),
        const Duration(minutes: 15),
        const Duration(minutes: 15),
      ]) {
        await tester.pump(delay - const Duration(seconds: 1));
        expect(repository.syncCalls, expectedCalls);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(repository.syncCalls, ++expectedCalls);
      }
      expect(repository.syncCalls, 7);
      await tester.pump(const Duration(minutes: 15));
      expect(repository.syncCalls, 7);
    },
  );

  testWidgets('SMS retry is canceled when the owner signs out', (tester) async {
    final repository = _LifecycleCollectRepository(failSyncs: 1);
    final router = createAppRouter(initialLocation: '/home');
    final container = ProviderContainer(
      overrides: [
        appRouterProvider.overrideWithValue(router),
        appEnvProvider.overrideWithValue(_smsAccessEnv),
        collectRepositoryProvider.overrideWith((ref) => repository),
        collectNotificationServiceProvider.overrideWithValue(
          _LifecycleNotificationService(enabled: false),
        ),
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

    repository.clearProfile();
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    expect(repository.syncCalls, 1);
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
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final route in <String>['/offline', '/sync']) {
      final router = createAppRouter(initialLocation: route);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appEnvProvider.overrideWithValue(_noSmsAccessEnv)],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      if (route == '/offline') {
        expect(find.text('Connection'), findsOneWidget);
        expect(find.text('Refresh your data'), findsOneWidget);
        expect(find.text('Refresh data'), findsOneWidget);
        expect(find.text('Scan/share'), findsNothing);
      } else {
        expect(find.text('Data sync'), findsOneWidget);
        expect(find.text('Refresh your data'), findsOneWidget);
        expect(find.text('Refresh data'), findsOneWidget);
        expect(find.text('Verified ledger'), findsNothing);
      }
      expect(find.text('Open groups'), findsOneWidget);
      expect(tester.getBottomRight(find.text('Open groups')).dy, lessThan(844));
      expect(find.byTooltip('Back'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/home');
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
        overrides: [
          appEnvProvider.overrideWithValue(_noSmsAccessEnv),
          appRouterProvider.overrideWithValue(router),
        ],
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
    expect(recoveryScreens, contains("label: 'Privacy'"));
    expect(recoveryScreens, isNot(contains('Privacy stays on')));
    expect(
      recoveryScreens,
      contains("label: busy ? 'Refreshing data' : 'Refresh data'"),
    );
    expect(recoveryScreens, isNot(contains("primaryLabel: 'Refresh groups'")));

    final shareScreen = File(
      'lib/features/collections/share_screen.dart',
    ).readAsStringSync();
    expect(shareScreen, isNot(contains('const Spacer()')));
    expect(shareScreen, isNot(contains('Privacy-safe link')));
    expect(shareScreen, contains('collection.title'));
    expect(shareScreen, contains('summaryFor(widget.collectionId)'));
  });

  testWidgets('iOS detail screens use native Cupertino navigation', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final router = createAppRouter(initialLocation: '/groups/qa-private-group');
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appEnvProvider.overrideWithValue(_noSmsAccessEnv),
            appRouterProvider.overrideWithValue(router),
            collectRepositoryProvider.overrideWith(
              (ref) => FixtureCollectRepository(),
            ),
          ],
          child: const CollectApp(),
        ),
      );
      await tester.pumpAndSettle();

      final detailContext = tester.element(find.text('QA private group').first);
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

  test(
    'public runtime uses marketing roles instead of logo-derived colours',
    () {
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
      expect(groupCardMedia, contains('assets/marketing/rwanda/'));
      expect(groupCardMedia, isNot(contains('CollectColors.brandPeriwinkle')));
      expect(groupCardMedia, isNot(contains('_groupCoverPalette')));

      final staticSite = File(
        'scripts/public_static_site_build.rb',
      ).readAsStringSync();
      expect(staticSite, isNot(contains('var(--orange)')));
      final publicCss = <String>[
        'web/public/layout.css',
        'web/public/revolut.css',
      ].map((path) => File(path).readAsStringSync()).join('\n');
      expect(publicCss, contains('--web-action:'));
      expect(publicCss, contains('background: var(--web-action)'));
      expect(publicCss, contains('color: var(--web-ink)'));
      expect(publicCss, isNot(contains('var(--periwinkle)')));
      expect(publicCss, isNot(contains('var(--brand-orange)')));
    },
  );

  _registerAppShellThemeContracts();
}

String _materializeRouteForSmoke(String route) {
  return route
      .replaceAll(':collectionId', 'qa-private-group')
      .replaceAll(':intentId', 'intent-render')
      .replaceAll(':state', 'pending')
      .replaceAll(':publicId', '038491')
      .replaceAll(':slug', 'qa-private-group');
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
  apiUrl: '',
  publicUrl: '',
  adminAppUrl: '',
  enableSmsReader: false,
  enableAndroidSmsAccess: true,
  enableAdminPanel: false,
  enableAdminDevTools: false,
  authCaptchaEnabled: false,
  authCaptchaProvider: '',
  authCaptchaSiteKey: '',
  backend: 'cloudflare',
);

const _noSmsAccessEnv = AppEnv(
  apiUrl: '',
  publicUrl: '',
  adminAppUrl: '',
  enableSmsReader: false,
  enableAndroidSmsAccess: false,
  enableAdminPanel: false,
  enableAdminDevTools: false,
  authCaptchaEnabled: false,
  authCaptchaProvider: '',
  authCaptchaSiteKey: '',
  backend: 'cloudflare',
);

class _LifecycleCollectRepository extends FixtureCollectRepository {
  _LifecycleCollectRepository({
    this.blockFirstSync = false,
    this.failSyncs = 0,
  });

  final bool blockFirstSync;
  final int failSyncs;
  final _firstSyncCompleter = Completer<void>();
  int syncCalls = 0;

  @override
  Future<int> syncPendingSmsAccess() async {
    syncCalls += 1;
    if (blockFirstSync && syncCalls == 1) {
      await _firstSyncCompleter.future;
    }
    if (syncCalls <= failSyncs) throw StateError('Offline SMS retry fixture');
    return 0;
  }

  void releaseFirstSync() {
    if (!_firstSyncCompleter.isCompleted) {
      _firstSyncCompleter.complete();
    }
  }

  void clearProfile() {
    state = state.copyWith(currentProfile: null);
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
