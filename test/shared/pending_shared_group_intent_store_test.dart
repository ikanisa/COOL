import 'dart:convert';

import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/pending_shared_group_intent_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 28, 12);
  const firstUser = '11111111-1111-4111-8111-111111111111';
  const secondUser = '22222222-2222-4222-8222-222222222222';

  for (final time in [
    '2026-02-30T12:00:00Z',
    '2026-07-28T11:00:00',
    '2026-07-28',
    '0000-07-28T11:00:00Z',
    '2026-07-28T11:00:00+24:00',
  ]) {
    test(
      'invalid invitation timestamp $time cannot acquire a fresh TTL',
      () async {
        final preferences = _MemoryPreferences();
        preferences.values[PendingSharedGroupIntentStore
            .defaultPreferencesKey] = jsonEncode({
          'version': 2,
          'slug': 'qa-private-group',
          'intent_id': '33333333-3333-4333-8333-333333333333',
          'owner_user_id': firstUser,
          'captured_at': time,
        });
        final store = PendingSharedGroupIntentStore(
          preferences: preferences,
          clock: () => now,
        );
        expect(await store.read(), isNull);
        expect(preferences.values, isEmpty);
      },
    );
  }
  test(
    'impossible calendar date cannot normalize into the current TTL window',
    () async {
      final preferences = _MemoryPreferences();
      preferences.values[PendingSharedGroupIntentStore.defaultPreferencesKey] =
          jsonEncode({
            'version': 2,
            'slug': 'qa-private-group',
            'intent_id': '33333333-3333-4333-8333-333333333333',
            'owner_user_id': firstUser,
            'captured_at': '2026-02-30T11:00:00Z',
          });
      final store = PendingSharedGroupIntentStore(
        preferences: preferences,
        clock: () => DateTime.utc(2026, 3, 2, 12),
      );
      expect(await store.read(), isNull);
      expect(preferences.values, isEmpty);
    },
  );
  test(
    'writing a DateTime instant serializes UTC and preserves exact TTL',
    () async {
      final preferences = _MemoryPreferences();
      final store = PendingSharedGroupIntentStore(
        preferences: preferences,
        clock: () => now,
      );
      final instant = DateTime.fromMillisecondsSinceEpoch(
        now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
      );
      await store.write(
        PendingSharedGroupIntent(
          slug: 'qa-private-group',
          intentId: '33333333-3333-4333-8333-333333333333',
          ownerUserId: firstUser,
          capturedAt: instant,
        ),
      );
      final payload = jsonDecode(preferences.values.values.single) as Map;
      expect(payload['captured_at'], instant.toUtc().toIso8601String());
      expect((await store.read())!.capturedAt, instant.toUtc());
    },
  );

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
        await firstController.retain(' QA-Private-Group '),
        'qa-private-group',
      );

      final restartedStore = PendingSharedGroupIntentStore(
        preferences: preferences,
        clock: () => now.add(const Duration(minutes: 2)),
      );
      final restartedController = PendingSharedGroupIntentController(
        restartedStore,
      );
      addTearDown(restartedController.dispose);

      expect(await restartedController.current(), 'qa-private-group');
      final bound = await restartedController.currentRecordForOwner(firstUser);
      expect(bound?.ownerUserId, firstUser);
      expect((await restartedStore.read())?.ownerUserId, firstUser);
    },
  );

  test(
    'a signed-out invitation binds once and rejects another account',
    () async {
      final preferences = _MemoryPreferences();
      final store = PendingSharedGroupIntentStore(
        preferences: preferences,
        clock: () => now,
      );
      final controller = PendingSharedGroupIntentController(store);
      addTearDown(controller.dispose);

      final captured = await controller.retainRecord('qa-private-group');
      expect(captured.ownerUserId, isNull);
      final bound = await controller.currentRecordForOwner(firstUser);
      expect(bound?.intentId, captured.intentId);
      expect(bound?.ownerUserId, firstUser);
      expect((await store.read())?.ownerUserId, firstUser);

      expect(await controller.currentRecordForOwner(secondUser), isNull);
      expect(await store.read(), isNull);
      expect(await controller.current(), isNull);
    },
  );

  test(
    'a stale same-slug completion cannot clear a later invitation',
    () async {
      final store = PendingSharedGroupIntentStore(
        preferences: _MemoryPreferences(),
        clock: () => now,
      );
      final controller = PendingSharedGroupIntentController(store);
      addTearDown(controller.dispose);

      final first = await controller.retainRecord(
        'qa-private-group',
        ownerUserId: firstUser,
      );
      final second = await controller.retainRecord(
        'qa-private-group',
        ownerUserId: firstUser,
      );
      expect(second.intentId, isNot(first.intentId));
      expect(await controller.clearIfMatchesRecord(first), isFalse);
      expect((await store.read())?.intentId, second.intentId);
      expect(await controller.clearIfMatchesRecord(second), isTrue);
      expect(await store.read(), isNull);
    },
  );

  test('duplicate warm App Links keep the visible intent generation', () async {
    final store = PendingSharedGroupIntentStore(
      preferences: _MemoryPreferences(),
      clock: () => now,
    );
    final controller = PendingSharedGroupIntentController(store);
    addTearDown(controller.dispose);

    final first = await controller.retainIncomingRecord(
      'qa-private-group',
      ownerUserId: firstUser,
    );
    final duplicate = await controller.retainIncomingRecord(
      'qa-private-group',
      ownerUserId: firstUser,
    );
    expect(duplicate.intentId, first.intentId);
    expect((await store.read())?.intentId, first.intentId);

    final switched = await controller.retainIncomingRecord(
      'qa-private-group',
      ownerUserId: secondUser,
    );
    expect(switched.intentId, isNot(first.intentId));
    expect(switched.ownerUserId, secondUser);
  });

  test('stale, malformed, and oversized pending intents fail closed', () async {
    final preferences = _MemoryPreferences();
    final staleStore = PendingSharedGroupIntentStore(
      preferences: preferences,
      clock: () => now,
    );
    await staleStore.saveSlug('qa-private-group');

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

    preferences.values[PendingSharedGroupIntentStore.defaultPreferencesKey] =
        '{"version":1,"slug":"qa-private-group","captured_at":"${now.toIso8601String()}"}';
    expect(await staleStore.read(), isNull);
    expect(preferences.values, isEmpty);

    await expectLater(
      staleStore.save('qa-private-group', ownerUserId: 'local-user'),
      throwsFormatException,
    );

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

      await controller.retain('qa-private-group');
      await controller.retain('kigali-lions-away-kit');

      expect(await controller.clearIfMatches('qa-private-group'), isFalse);
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
        controller.retain('qa-private-group'),
        throwsA(isA<StateError>()),
      );
      expect(await controller.current(), isNull);
    },
  );

  test('slug normalization accepts only bounded canonical URL segments', () {
    expect(
      normalizePendingSharedGroupSlug(' QA-Private-Group '),
      'qa-private-group',
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
        Uri.parse('https://collect.ikanisa.com/c/QA-Private-Group'),
      ),
      'qa-private-group',
    );
    expect(
      pendingSharedGroupSlugFromAppLink(
        Uri.parse('http://collect.ikanisa.com/c/qa-private-group'),
      ),
      isNull,
    );
    expect(
      pendingSharedGroupSlugFromAppLink(
        Uri.parse('https://example.com/c/qa-private-group'),
      ),
      isNull,
    );
    expect(
      pendingSharedGroupSlugFromAppLink(
        Uri.parse('https://collect.ikanisa.com/c/qa-private-group/extra'),
      ),
      isNull,
    );
    expect(
      pendingSharedGroupSlugFromAppLink(
        Uri.parse('collect://group/QA-Private-Group'),
      ),
      'qa-private-group',
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
