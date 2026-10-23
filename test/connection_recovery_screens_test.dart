import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/features/status/connection_recovery_screens.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// These eight cases preserve the Lists branch's availability/navigation coverage
// against the reconciled recovery behavior. No production records are used.
class _RecoveryRepository extends CollectRepository {
  _RecoveryRepository({required bool hasLoadedGroups})
    : super.fixture(
        initialState: CollectState(
          currentProfile: null,
          collections: hasLoadedGroups
              ? [
                  CollectCollection(
                    id: 'synthetic-recovery-group',
                    slug: 'synthetic-recovery-group',
                    creatorUserId: 'synthetic-owner',
                    title: 'Synthetic recovery group',
                    description: 'Isolated widget fixture',
                    collectionType: CollectionType.ikimina,
                    receiverMomoNumber: '0700000001',
                    receiverDisplayLabel: 'Test receiver',
                    receiverNetwork: 'mtn_momo',
                    isPublic: true,
                    createdAt: DateTime.utc(2026, 1, 1),
                  ),
                ]
              : const [],
          paymentIntents: const [],
          contributions: const [],
          usingStaleCache: hasLoadedGroups,
        ),
      );

  @override
  Future<void> loadInitial({bool syncPendingSms = false}) async {}
}

Future<void> _pumpRecovery(
  WidgetTester tester,
  Widget screen, {
  bool hasLoadedGroups = false,
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: '/recovery',
    routes: [
      GoRoute(path: '/recovery', builder: (_, state) => screen),
      GoRoute(
        path: '/groups',
        builder: (_, state) => const Scaffold(body: Text('Groups destination')),
      ),
      GoRoute(
        path: '/settings/legal/privacy',
        builder: (_, state) =>
            const Scaffold(body: Text('Privacy destination')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collectRepositoryProvider.overrideWith(
          (_) => _RecoveryRepository(hasLoadedGroups: hasLoadedGroups),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final screen in const [OfflineRecoveryScreen(), SyncRecoveryScreen()]) {
    final name = screen.runtimeType.toString();
    testWidgets('$name does not invent a saved snapshot or protected queue', (
      tester,
    ) async {
      await _pumpRecovery(tester, screen);
      expect(find.byType(MinimalStatePanel), findsOneWidget);
      expect(
        find.text('Refresh to load groups and recorded activity.'),
        findsOneWidget,
      );
      expect(
        find.text('Previously loaded data may be out of date.'),
        findsNothing,
      );
      expect(find.text('Protected'), findsNothing);
      expect(find.text('Masked'), findsNothing);
      expect(find.text('Queued updates'), findsNothing);
      expect(tester.takeException(), isNull);
    });
    testWidgets('$name acknowledges stale groups without promising freshness', (
      tester,
    ) async {
      await _pumpRecovery(tester, screen, hasLoadedGroups: true);
      expect(
        find.text('Previously loaded data may be out of date.'),
        findsOneWidget,
      );
      expect(find.text('View groups'), findsOneWidget);
      expect(find.byType(MinimalStatePanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('$name group navigation is reachable at 2x text', (
      tester,
    ) async {
      await _pumpRecovery(tester, screen, scale: 2);
      await tester.ensureVisible(find.text('Open groups'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open groups'));
      await tester.pumpAndSettle();
      expect(find.text('Groups destination'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('$name privacy navigation is reachable at 3x text', (
      tester,
    ) async {
      await _pumpRecovery(tester, screen, scale: 3);
      await tester.scrollUntilVisible(find.text('Privacy'), 120);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Privacy'));
      await tester.pumpAndSettle();
      expect(find.text('Privacy destination'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
