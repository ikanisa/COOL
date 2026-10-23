import 'dart:async';

import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/features/status/connection_recovery_screens.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// All records here are synthetic and belong to the isolated test only.
const _empty = CollectState(
  currentProfile: null,
  collections: [],
  paymentIntents: [],
  contributions: [],
);
const _profile = CollectProfile(
  id: 'recovery-test-user',
  publicId: '900001',
  whatsappPhone: '+250700000001',
  countryCode: 'RW',
  currencyCode: 'RWF',
  momoProvider: 'mtn_momo',
  momoNumber: '0700000001',
);
final _oldSync = DateTime.utc(2026, 1, 1, 10);
final _newSync = DateTime.utc(2026, 1, 1, 11);
const _refreshKey = ValueKey('recovery-refresh');

class _Repository extends CollectRepository {
  _Repository(CollectState initialState)
    : super.fixture(initialState: initialState);

  int calls = 0;
  final smsRequests = <bool>[];
  Future<void> Function()? onRefresh;

  void publish(CollectState value) => state = value;

  @override
  Future<void> loadInitial({bool syncPendingSms = false}) async {
    calls++;
    smsRequests.add(syncPendingSms);
    await onRefresh?.call();
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _Repository repository, {
  StateProvider<_Repository>? slot,
  bool sync = false,
  double scale = 1,
  double keyboard = 0,
  Size size = const Size(800, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      collectRepositoryProvider.overrideWith(
        (ref) => slot == null ? repository : ref.watch(slot),
      ),
    ],
  );
  addTearDown(container.dispose);
  final router = GoRouter(
    initialLocation: '/recovery',
    routes: [
      GoRoute(
        path: '/recovery',
        builder: (_, _) =>
            sync ? const SyncRecoveryScreen() : const OfflineRecoveryScreen(),
      ),
      GoRoute(
        path: '/groups',
        builder: (_, _) => const Scaffold(body: Text('Groups destination')),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const Scaffold(body: Text('Settings destination')),
      ),
      GoRoute(
        path: '/settings/legal/privacy',
        builder: (_, _) => const Scaffold(body: Text('Privacy destination')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
            disableAnimations: true,
          ),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _refresh(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(_refreshKey));
  await tester.tap(find.byKey(_refreshKey));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty state makes no cache or connectivity guarantee', (
    tester,
  ) async {
    final repository = _Repository(_empty);
    await _pump(tester, repository);
    expect(find.text('Last data refresh: Not available'), findsOneWidget);
    expect(find.text('Open groups'), findsOneWidget);
    expect(find.text('Saved'), findsNothing);
    expect(find.text('Protected'), findsNothing);
    expect(find.text('Masked'), findsNothing);
    expect(find.text('You are offline'), findsNothing);
    expect(repository.calls, 0); // No automatic retry loop.
  });

  testWidgets('profile alone does not imply that groups were loaded', (
    tester,
  ) async {
    await _pump(tester, _Repository(_empty.copyWith(currentProfile: _profile)));
    expect(find.text('Open groups'), findsOneWidget);
    expect(find.text('View groups'), findsNothing);
    expect(
      find.text('Loaded groups can be opened. Refresh to check for updates.'),
      findsNothing,
    );
  });

  testWidgets(
    'loaded groups are presented without claiming persistent storage',
    (tester) async {
      final group = CollectCollection(
        id: 'recovery-test-group',
        slug: 'recovery-test-group',
        creatorUserId: _profile.id,
        title: 'Synthetic recovery group',
        description: 'Isolated test only',
        collectionType: CollectionType.ikimina,
        receiverMomoNumber: '0700000001',
        receiverDisplayLabel: 'Test receiver',
        receiverNetwork: 'mtn_momo',
        isPublic: false,
        createdAt: _oldSync,
      );
      await _pump(tester, _Repository(_empty.copyWith(collections: [group])));
      expect(find.text('View groups'), findsOneWidget);
      expect(find.text('Saved'), findsNothing);
    },
  );

  testWidgets('no-op Future completion is not a successful refresh', (
    tester,
  ) async {
    await _pump(
      tester,
      _Repository(_empty.copyWith(lastSuccessfulSyncAt: _oldSync)),
    );
    await _refresh(tester);
    expect(find.text('Updates unavailable'), findsOneWidget);
    expect(find.text('Data refreshed'), findsNothing);
  });

  testWidgets('new timestamp without error confirms only a data refresh', (
    tester,
  ) async {
    final repository = _Repository(
      _empty.copyWith(lastSuccessfulSyncAt: _oldSync),
    );
    repository.onRefresh = () async =>
        repository.publish(_empty.copyWith(lastSuccessfulSyncAt: _newSync));
    await _pump(tester, repository);
    await _refresh(tester);
    expect(find.text('Data refreshed'), findsOneWidget);
    expect(
      find.text(
        'The latest data refresh completed. This does not confirm a payment.',
      ),
      findsOneWidget,
    );
    expect(repository.smsRequests, [false]);
  });

  testWidgets('first successful empty data response is still a data refresh', (
    tester,
  ) async {
    final repository = _Repository(_empty);
    repository.onRefresh = () async =>
        repository.publish(_empty.copyWith(lastSuccessfulSyncAt: _newSync));
    await _pump(tester, repository);
    await _refresh(tester);
    expect(find.text('Data refreshed'), findsOneWidget);
    expect(find.text('Open groups'), findsOneWidget);
  });

  testWidgets('a swallowed repository error never becomes success', (
    tester,
  ) async {
    final repository = _Repository(_empty);
    repository.onRefresh = () async => repository.publish(
      _empty.copyWith(
        lastSuccessfulSyncAt: _newSync,
        lastError: 'private-error',
      ),
    );
    await _pump(tester, repository);
    await _refresh(tester);
    expect(find.text('Updates unavailable'), findsOneWidget);
    expect(find.textContaining('private-error'), findsNothing);
    expect(find.text('Data refreshed'), findsNothing);
  });

  testWidgets('an escaping exception is sanitized and retry is re-enabled', (
    tester,
  ) async {
    final repository = _Repository(_empty);
    repository.onRefresh = () async =>
        throw StateError('private-backend-identifier');
    await _pump(tester, repository);
    await _refresh(tester);
    expect(find.textContaining('private-backend-identifier'), findsNothing);
    expect(
      tester.widget<CollectButton>(find.byKey(_refreshKey)).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale cache with a timestamp is not reported as refreshed', (
    tester,
  ) async {
    final repository = _Repository(_empty);
    repository.onRefresh = () async => repository.publish(
      _empty.copyWith(lastSuccessfulSyncAt: _newSync, usingStaleCache: true),
    );
    await _pump(tester, repository);
    await _refresh(tester);
    expect(find.text('Data refreshed'), findsNothing);
    expect(find.text('Updates unavailable'), findsOneWidget);
  });

  testWidgets('backward timestamp is not a fresh success', (tester) async {
    final repository = _Repository(
      _empty.copyWith(lastSuccessfulSyncAt: _newSync),
    );
    repository.onRefresh = () async =>
        repository.publish(_empty.copyWith(lastSuccessfulSyncAt: _oldSync));
    await _pump(tester, repository);
    await _refresh(tester);
    expect(find.text('Data refreshed'), findsNothing);
  });

  testWidgets('callback itself blocks two taps before a rebuild', (
    tester,
  ) async {
    final pending = Completer<void>();
    final repository = _Repository(_empty)..onRefresh = () => pending.future;
    await _pump(tester, repository);
    final action = tester
        .widget<CollectButton>(find.byKey(_refreshKey))
        .onPressed!;
    action();
    action();
    await tester.pump();
    expect(repository.calls, 1);
    expect(
      tester.widget<CollectButton>(find.byKey(_refreshKey)).onPressed,
      isNull,
    );
    pending.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('existing repository load blocks a competing refresh', (
    tester,
  ) async {
    final repository = _Repository(_empty.copyWith(isLoading: true));
    await _pump(tester, repository);
    expect(
      tester.widget<CollectButton>(find.byKey(_refreshKey)).onPressed,
      isNull,
    );
    expect(repository.calls, 0);
  });

  testWidgets('SMS attention survives a successful data refresh', (
    tester,
  ) async {
    final repository = _Repository(_empty.copyWith(smsQueueOverflowed: true));
    repository.onRefresh = () async => repository.publish(
      _empty.copyWith(lastSuccessfulSyncAt: _newSync, smsQueueOverflowed: true),
    );
    await _pump(tester, repository, sync: true);
    await _refresh(tester);
    expect(find.text('Data refreshed'), findsOneWidget);
    expect(
      find.text('SMS sync still needs attention. Review it in Settings.'),
      findsOneWidget,
    );
    expect(repository.smsRequests, [false]);
    await tester.ensureVisible(find.text('Open settings'));
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings destination'), findsOneWidget);
  });

  testWidgets('account change discards in-flight screen confirmation', (
    tester,
  ) async {
    final pending = Completer<void>();
    final repository = _Repository(_empty)..onRefresh = () => pending.future;
    await _pump(tester, repository);
    tester.widget<CollectButton>(find.byKey(_refreshKey)).onPressed!();
    await tester.pump();
    repository.publish(_empty.copyWith(currentProfile: _profile));
    await tester.pumpAndSettle();
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Data refreshed'), findsNothing);
    expect(
      tester.widget<CollectButton>(find.byKey(_refreshKey)).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('repository replacement discards the old attempt result', (
    tester,
  ) async {
    final pending = Completer<void>();
    final oldRepository = _Repository(_empty)..onRefresh = () => pending.future;
    final slot = StateProvider<_Repository>((ref) => oldRepository);
    final container = await _pump(tester, oldRepository, slot: slot);
    tester.widget<CollectButton>(find.byKey(_refreshKey)).onPressed!();
    await tester.pump();
    final newRepository = _Repository(_empty);
    container.read(slot.notifier).state = newRepository;
    await tester.pumpAndSettle();
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Data refreshed'), findsNothing);
    expect(
      tester.widget<CollectButton>(find.byKey(_refreshKey)).onPressed,
      isNotNull,
    );
    expect(newRepository.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'late exception after navigation is handled without using disposed ref',
    (tester) async {
      final pending = Completer<void>();
      final repository = _Repository(_empty)..onRefresh = () => pending.future;
      await _pump(tester, repository);
      tester.widget<CollectButton>(find.byKey(_refreshKey)).onPressed!();
      await tester.pump();
      await tester.ensureVisible(find.text('Open groups'));
      await tester.tap(find.text('Open groups'));
      await tester.pumpAndSettle();
      pending.completeError(StateError('late-private-error'));
      await tester.pumpAndSettle();
      expect(find.text('Groups destination'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new external successful data removes an obsolete failure message',
    (tester) async {
      final repository = _Repository(
        _empty.copyWith(lastSuccessfulSyncAt: _oldSync),
      );
      await _pump(tester, repository);
      await _refresh(tester); // no-op => local failure
      repository.publish(_empty.copyWith(lastSuccessfulSyncAt: _newSync));
      await tester.pumpAndSettle();
      expect(find.text('Updates unavailable'), findsNothing);
      expect(
        find.text('Data refreshed'),
        findsNothing,
      ); // not this screen's attempt
    },
  );

  for (final scale in [2.0, 3.0]) {
    testWidgets(
      'actions remain reachable at 320x568 with keyboard and ${scale}x text',
      (tester) async {
        await _pump(
          tester,
          _Repository(_empty),
          scale: scale,
          size: const Size(320, 568),
          keyboard: 220,
        );
        await tester.ensureVisible(find.byKey(_refreshKey));
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.text('Privacy'), 120);
        await tester.tap(find.text('Privacy'));
        await tester.pumpAndSettle();
        expect(find.text('Privacy destination'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
