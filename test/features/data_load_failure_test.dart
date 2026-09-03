import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailedInitialReadRepository extends CollectRepository {
  _FailedInitialReadRepository() : super.fixture(seeded: false) {
    state = state.copyWith(lastError: 'private database permission detail');
  }

  int retries = 0;

  @override
  Future<void> loadInitial({bool syncPendingSms = false}) async {
    retries++;
    state = state.copyWith(lastError: 'private database permission detail');
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final route in ['/home', '/groups', '/activity']) {
    testWidgets('$route distinguishes a failed read from an empty account', (
      tester,
    ) async {
      final repository = _FailedInitialReadRepository();
      final router = createAppRouter(initialLocation: route);
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appRouterProvider.overrideWithValue(router),
            collectRepositoryProvider.overrideWith((ref) => repository),
          ],
          child: const CollectApp(),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Could not load data'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('RWF 0'), findsNothing);
      expect(find.text('No groups yet'), findsNothing);
      expect(find.text('No activity yet'), findsNothing);
      expect(find.textContaining('permission detail'), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(repository.retries, 1);
      expect(tester.takeException(), isNull);
    });
  }

  test('an established or cached account is not an initial-load failure', () {
    final repository = _FailedInitialReadRepository();
    addTearDown(repository.dispose);
    expect(repository.state.hasInitialLoadFailure, isTrue);
    expect(
      repository.state.copyWith(isLoading: true).hasInitialLoadFailure,
      isFalse,
    );
    expect(
      repository.state.copyWith(usingStaleCache: true).hasInitialLoadFailure,
      isFalse,
    );
    expect(
      repository.state
          .copyWith(lastSuccessfulSyncAt: DateTime.utc(2026, 9, 2))
          .hasInitialLoadFailure,
      isFalse,
    );
    expect(
      repository.state.copyWith(lastError: null).hasInitialLoadFailure,
      isFalse,
    );
  });
}
