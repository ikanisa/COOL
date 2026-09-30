import '../fixtures/collect_repository_fixture.dart';

import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:collect_app/features/collections/group_link_screen.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/repositories/pending_shared_group_intent_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _firstUser = '11111111-1111-4111-8111-111111111111';
const _secondUser = '22222222-2222-4222-8222-222222222222';
final _testAuthUserProvider = StateProvider<String?>((ref) => _firstUser);

class _RecordingRepository extends FixtureCollectRepository {
  _RecordingRepository()
    : super(
        profileOverride: const CollectProfile(
          id: _firstUser,
          publicId: '038491',
          whatsappPhone: '+250788123456',
          countryCode: 'RW',
          currencyCode: 'RWF',
          momoProvider: 'mtn_momo',
          momoNumber: '0788123456',
        ),
      );

  int joinCalls = 0;

  @override
  Future<CollectCollection> joinGroupBySlug(String slug) async {
    joinCalls++;
    return super.joinGroupBySlug(slug);
  }
}

class _MemoryPreferences implements PendingSharedGroupIntentPreferences {
  final values = <String, String>{};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}

void main() {
  Future<
    ({
      GoRouter router,
      _RecordingRepository repository,
      PendingSharedGroupIntentStore store,
    })
  >
  pumpInvitation(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _RecordingRepository();
    final store = PendingSharedGroupIntentStore(
      preferences: _MemoryPreferences(),
    );
    final router = GoRouter(
      initialLocation: '/c/qa-private-group',
      routes: [
        GoRoute(
          path: '/c/:slug',
          builder: (_, state) =>
              GroupLinkScreen(slug: state.pathParameters['slug']!),
        ),
        GoRoute(
          path: '/groups/:id',
          builder: (_, _) => const Scaffold(body: Text('Opened group')),
        ),
        GoRoute(
          path: '/auth',
          builder: (_, _) => const Scaffold(body: Text('Sign in')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectAuthenticatedUserIdProvider.overrideWith(
            (ref) => ref.watch(_testAuthUserProvider),
          ),
          collectRepositoryProvider.overrideWith((ref) => repository),
          pendingSharedGroupIntentStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (router: router, repository: repository, store: store);
  }

  testWidgets('opening a group link waits for an explicit Join tap', (
    tester,
  ) async {
    final harness = await pumpInvitation(tester);
    expect(find.text('Review this group invitation'), findsOneWidget);
    expect(harness.repository.joinCalls, 0);
    expect((await harness.store.read())?.ownerUserId, _firstUser);

    await tester.tap(find.text('Join group'));
    await tester.pumpAndSettle();
    expect(harness.repository.joinCalls, 1);
    expect(find.text('Opened group'), findsOneWidget);
    expect(await harness.store.read(), isNull);
  });

  testWidgets('an account switch prevents the stored invitation from joining', (
    tester,
  ) async {
    final harness = await pumpInvitation(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GroupLinkScreen)),
    );
    container.read(_testAuthUserProvider.notifier).state = _secondUser;

    await tester.tap(find.text('Join group'));
    await tester.pumpAndSettle();
    expect(harness.repository.joinCalls, 0);
    expect(find.textContaining('another account'), findsOneWidget);
    expect(await harness.store.read(), isNull);
  });

  testWidgets('a replaced same-route invitation requires a fresh Join tap', (
    tester,
  ) async {
    final harness = await pumpInvitation(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GroupLinkScreen)),
    );
    await container
        .read(pendingSharedGroupSlugProvider.notifier)
        .retainRecord('qa-private-group', ownerUserId: _firstUser);

    await tester.tap(find.text('Join group'));
    await tester.pumpAndSettle();
    expect(harness.repository.joinCalls, 0);
    expect(find.textContaining('invitation was refreshed'), findsOneWidget);

    await tester.ensureVisible(find.text('Join group'));
    await tester.tap(find.text('Join group'));
    await tester.pumpAndSettle();
    expect(harness.repository.joinCalls, 1);
    expect(find.text('Opened group'), findsOneWidget);
  });
}
