import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/pending_shared_group_intent_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 28, 12);

  test(
    'pending group intent survives a store and controller recreation',
    () async {
      final preferences = _MemoryPreferences();
      final firstStore = PendingSharedGroupIntentStore(
        preferences: preferences,
        clock: () => now,
      );
      final firstController = PendingSharedGroupIntentController(firstStore);
      addTearDown(firstController.dispose);

      expect(
        await firstController.retain(' St-Michel-Building-Fund '),
        'st-michel-building-fund',
      );

      final restartedStore = PendingSharedGroupIntentStore(
        preferences: preferences,
        clock: () => now.add(const Duration(minutes: 2)),
      );
      final restartedController = PendingSharedGroupIntentController(
        restartedStore,
      );
      addTearDown(restartedController.dispose);

      expect(await restartedController.current(), 'st-michel-building-fund');
    },
  );

  test('stale, malformed, and oversized pending intents fail closed', () async {
    final preferences = _MemoryPreferences();
    final staleStore = PendingSharedGroupIntentStore(
      preferences: preferences,
      clock: () => now,
    );
    await staleStore.saveSlug('st-michel-building-fund');

    final expiredStore = PendingSharedGroupIntentStore(
      preferences: preferences,
      clock: () => now.add(const Duration(hours: 25)),
    );
    expect(await expiredStore.readSlug(), isNull);
    expect(preferences.values, isEmpty);

    preferences.values[PendingSharedGroupIntentStore.defaultPreferencesKey] =
        '{"version":1,"slug":"../../settings","captured_at":"${now.toIso8601String()}"}';
    expect(await staleStore.readSlug(), isNull);
    expect(preferences.values, isEmpty);

    expect(
      () => staleStore.saveSlug(
        List.filled(
          PendingSharedGroupIntentStore.maxSlugLength + 1,
          'a',
        ).join(),
      ),
      throwsFormatException,
    );
  });

  test(
    'only the matching completed intent can clear persisted recovery',
    () async {
      final preferences = _MemoryPreferences();
      final store = PendingSharedGroupIntentStore(
        preferences: preferences,
        clock: () => now,
      );
      final controller = PendingSharedGroupIntentController(store);
      addTearDown(controller.dispose);

      await controller.retain('st-michel-building-fund');
      await controller.retain('kigali-lions-away-kit');

      expect(
        await controller.clearIfMatches('st-michel-building-fund'),
        isFalse,
      );
      expect(await controller.current(), 'kigali-lions-away-kit');
      expect(await store.readSlug(), 'kigali-lions-away-kit');

      expect(await controller.clearIfMatches('kigali-lions-away-kit'), isTrue);
      expect(await controller.current(), isNull);
      expect(await store.readSlug(), isNull);
    },
  );

  test(
    'a persistence failure does not expose an in-memory-only intent',
    () async {
      final preferences = _MemoryPreferences(failWrites: true);
      final store = PendingSharedGroupIntentStore(
        preferences: preferences,
        clock: () => now,
      );
      final controller = PendingSharedGroupIntentController(store);
      addTearDown(controller.dispose);

      await expectLater(
        controller.retain('st-michel-building-fund'),
        throwsA(isA<StateError>()),
      );
      expect(await controller.current(), isNull);
    },
  );

  test('slug normalization accepts only bounded canonical URL segments', () {
    expect(
      normalizePendingSharedGroupSlug(' St-Michel-Building-Fund '),
      'st-michel-building-fund',
    );
    expect(normalizePendingSharedGroupSlug('group/path'), isNull);
    expect(normalizePendingSharedGroupSlug('../group'), isNull);
    expect(normalizePendingSharedGroupSlug('group--name'), isNull);
    expect(normalizePendingSharedGroupSlug(''), isNull);
    expect(PendingSharedGroupIntentStore.maxSlugLength, 140);
    final maximumCode = List.filled(140, 'a').join();
    expect(normalizePendingSharedGroupSlug(maximumCode), maximumCode);
    expect(normalizePendingSharedGroupSlug('${maximumCode}a'), isNull);
  });

  test('external app links accept only the canonical Collect group origin', () {
    expect(
      pendingSharedGroupSlugFromAppLink(
        Uri.parse('https://collect.ikanisa.com/c/St-Michel-Building-Fund'),
      ),
      'st-michel-building-fund',
    );
    expect(
      pendingSharedGroupSlugFromAppLink(
        Uri.parse('http://collect.ikanisa.com/c/st-michel-building-fund'),
      ),
      isNull,
    );
    expect(
      pendingSharedGroupSlugFromAppLink(
        Uri.parse('https://example.com/c/st-michel-building-fund'),
      ),
      isNull,
    );
    expect(
      pendingSharedGroupSlugFromAppLink(
        Uri.parse(
          'https://collect.ikanisa.com/c/st-michel-building-fund/extra',
        ),
      ),
      isNull,
    );
    expect(
      pendingSharedGroupSlugFromAppLink(
        Uri.parse('collect://group/St-Michel-Building-Fund'),
      ),
      'st-michel-building-fund',
    );
  });

  test('app sharing links route only canonical app and invite targets', () {
    expect(
      collectAppLinkTargetFromUri(
        Uri.parse('https://collect.ikanisa.com/app'),
      )?.kind,
      CollectAppLinkKind.app,
    );
    final invite = collectAppLinkTargetFromUri(
      Uri.parse('https://collect.ikanisa.com/invite/038491'),
    );
    expect(invite?.kind, CollectAppLinkKind.invite);
    expect(invite?.value, '038491');
    expect(
      collectAppLinkTargetFromUri(Uri.parse('collect://invite/038491'))?.kind,
      CollectAppLinkKind.invite,
    );
    expect(
      collectAppLinkTargetFromUri(Uri.parse('collect://app'))?.kind,
      CollectAppLinkKind.app,
    );
    expect(
      collectAppLinkTargetFromUri(
        Uri.parse('https://evil.example/invite/038491'),
      ),
      isNull,
    );
    expect(
      collectAppLinkTargetFromUri(Uri.parse('collect://invite/038491/extra')),
      isNull,
    );
  });
}

class _MemoryPreferences implements PendingSharedGroupIntentPreferences {
  _MemoryPreferences({this.failWrites = false});

  final bool failWrites;
  final Map<String, String> values = {};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    if (failWrites) throw StateError('storage unavailable');
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}
