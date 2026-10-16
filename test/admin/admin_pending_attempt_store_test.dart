import 'dart:convert';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:flutter_test/flutter_test.dart';

final instant = DateTime.utc(2026, 10, 5, 13);
CloudflareAdminUser actor({
  String id = 'actor-1',
  String session = 'public-session-1',
  List<String> permissions = const [
    'reconciliations.propose',
    'transactions.read',
  ],
  DateTime? expires,
}) => CloudflareAdminUser(
  id: id,
  email: 'operator@example.test',
  role: AdminAccountRole.staff,
  sessionId: session,
  expiresAt: expires ?? instant.add(const Duration(hours: 1)),
  permissions: permissions,
);
const schema = AdminPendingAttemptSchema(
  fields: {'amount', 'receiver', 'entries'},
  nestedFields: {
    'receiver': {'id', 'code'},
    'entries[]': {'account_id', 'amount'},
  },
);
Map<String, dynamic> get intent => {
  'amount': 400,
  'receiver': {'id': 'recorded-receiver', 'code': '008001'},
  'entries': [
    {'account_id': 'account-1', 'amount': 400},
  ],
};
AdminPendingAttemptCheckpoint save(
  AdminPendingAttemptStore store, {
  String key = 'original-request-123',
  String resource = 'transaction-1',
}) => store.retain(
  family: 'reconciliation',
  resourceId: resource,
  requestKey: key,
  permission: 'reconciliations.propose',
  intent: intent,
  schema: schema,
);
AdminPendingAttemptCheckpoint? restore(
  AdminPendingAttemptStore store, {
  String resource = 'transaction-1',
}) => store.restore(
  family: 'reconciliation',
  resourceId: resource,
  schema: schema,
);

class DeniedStorage implements AdminPendingAttemptStorage {
  @override
  String? read(String key) => throw StateError('blocked');
  @override
  void write(String key, String value) => throw StateError('blocked');
  @override
  void remove(String key) => throw StateError('blocked');
}

void main() {
  test(
    'family restoration is bounded, schema-validated and permission-scoped',
    () {
      final storage = MemoryAdminPendingAttemptStorage();
      final store = AdminPendingAttemptStore(
        storage: storage,
        now: () => instant,
      )..bind(actor(permissions: ['reconciliations.propose', 'users.manage']));
      addTearDown(store.dispose);
      for (var index = 0; index < 19; index++) {
        save(
          store,
          resource: 'transaction-$index',
          key: 'request-$index-original',
        );
      }
      store.retain(
        family: 'operating-updatemembership',
        resourceId: 'group:user',
        requestKey: 'membership-request-original',
        permission: 'users.manage',
        intent: {'expected_version': 1},
        schema: const AdminPendingAttemptSchema(fields: {'expected_version'}),
      );
      final restored = store.restoreFamily(
        family: 'reconciliation',
        permission: 'reconciliations.propose',
        schema: schema,
      );
      expect(restored, hasLength(19));
      expect(restored.every((entry) => entry.restored), isTrue);
      expect(() => restored.clear(), throwsUnsupportedError);
      expect(
        store.restoreFamily(
          family: 'reconciliation',
          permission: 'users.manage',
          schema: schema,
        ),
        isEmpty,
      );
      expect(
        store.restoreFamily(
          family: 'reconciliation',
          permission: 'reconciliations.propose',
          schema: const AdminPendingAttemptSchema(fields: {}),
        ),
        isEmpty,
      );
      expect(store.storageAvailable, isFalse);
      final unrelated = store.restoreFamily(
        family: 'operating-updatemembership',
        permission: 'users.manage',
        schema: const AdminPendingAttemptSchema(fields: {'expected_version'}),
      );
      expect(unrelated.single.requestKey, 'membership-request-original');
    },
  );

  test('family restoration cannot outlive permission or session expiry', () {
    var now = instant;
    final store = AdminPendingAttemptStore(
      storage: MemoryAdminPendingAttemptStorage(),
      now: () => now,
    )..bind(actor());
    addTearDown(store.dispose);
    save(store);
    now = instant.add(const Duration(hours: 1));
    expect(
      () => store.restoreFamily(
        family: 'reconciliation',
        permission: 'reconciliations.propose',
        schema: schema,
      ),
      throwsA(isA<AdminAccountException>()),
    );
    now = instant;
    store.bind(actor());
    save(store);
    store.bind(actor(permissions: ['transactions.read']));
    expect(
      () => store.restoreFamily(
        family: 'reconciliation',
        permission: 'reconciliations.propose',
        schema: schema,
      ),
      throwsA(isA<AdminAccountException>()),
    );
  });

  test(
    'reload keeps canonical immutable original intent, per-tab scope and exact key',
    () {
      final storage = MemoryAdminPendingAttemptStorage();
      final store = AdminPendingAttemptStore(
        storage: storage,
        now: () => instant,
      )..bind(actor());
      final checkpoint = save(store);
      expect(checkpoint.restored, isFalse);
      expect(checkpoint.expiresAt, actor().expiresAt);
      final encoded = storage.values.values.single;
      expect(encoded, isNot(contains('public-session-1')));
      expect(encoded, isNot(contains('operator@example.test')));
      store.dispose();
      expect(storage.values, isNotEmpty);
      final reloaded =
          AdminPendingAttemptStore(storage: storage, now: () => instant)..bind(
            actor(
              permissions: [
                'transactions.read',
                'reconciliations.propose',
                'transactions.read',
              ],
            ),
          );
      addTearDown(reloaded.dispose);
      final recovered = restore(reloaded)!;
      expect(recovered.restored, isTrue);
      expect(recovered.requestKey, checkpoint.requestKey);
      expect(jsonEncode(recovered.intent), jsonEncode(checkpoint.intent));
      expect(
        () => (recovered.intent['receiver'] as Map)['code'] = '1',
        throwsUnsupportedError,
      );
      expect(
        () => (recovered.intent['entries'] as List).clear(),
        throwsUnsupportedError,
      );
      expect(
        () => save(reloaded, key: 'different-request-123'),
        throwsA(isA<AdminAccountException>()),
      );
      expect(save(reloaded).expiresAt, checkpoint.expiresAt);
      reloaded.clear(family: 'reconciliation', resourceId: 'transaction-1');
      expect(storage.values, isEmpty);
    },
  );

  test(
    'actor, session, permissions and logout boundaries clear stale recovery references',
    () {
      for (final changed in [
        actor(id: 'actor-2'),
        actor(session: 'session-2'),
        actor(permissions: ['transactions.read']),
      ]) {
        final storage = MemoryAdminPendingAttemptStorage();
        final first = AdminPendingAttemptStore(
          storage: storage,
          now: () => instant,
        )..bind(actor());
        save(first);
        first.dispose();
        final next = AdminPendingAttemptStore(
          storage: storage,
          now: () => instant,
        )..bind(changed);
        expect(restore(next), isNull);
        expect(storage.values, isEmpty);
        next.dispose();
      }
      final storage = MemoryAdminPendingAttemptStorage();
      final store = AdminPendingAttemptStore(
        storage: storage,
        now: () => instant,
      )..bind(actor());
      addTearDown(store.dispose);
      save(store);
      store.bind(null);
      expect(storage.values, isEmpty);
      expect(() => save(store), throwsA(isA<AdminAccountException>()));
    },
  );

  test(
    'checkpoints follow the live session without extending their eight-hour age bound',
    () {
      var now = instant;
      final storage = MemoryAdminPendingAttemptStorage();
      final store = AdminPendingAttemptStore(storage: storage, now: () => now)
        ..bind(actor());
      addTearDown(store.dispose);
      save(store);
      store.bind(actor(expires: instant.add(const Duration(minutes: 2))));
      expect(
        restore(store)!.expiresAt,
        instant.add(const Duration(minutes: 2)),
      );
      store.bind(actor(expires: instant.add(const Duration(hours: 2))));
      expect(save(store).expiresAt, instant.add(const Duration(hours: 2)));
      now = instant.add(const Duration(minutes: 30));
      expect(restore(store)!.requestKey, 'original-request-123');
      store.bind(actor(expires: instant.add(const Duration(hours: 12))));
      expect(save(store).expiresAt, instant.add(const Duration(hours: 8)));
      now = instant.add(const Duration(hours: 8));
      expect(restore(store), isNull);
      expect(storage.values, isEmpty);
      final short = AdminPendingAttemptStore(
        storage: storage,
        now: () => instant,
      )..bind(actor(expires: instant.add(const Duration(seconds: 30))));
      addTearDown(short.dispose);
      expect(save(short).expiresAt, instant.add(const Duration(seconds: 30)));
    },
  );

  test(
    'allowlists cover nested maps and journal lists and reject secrets or arbitrary payloads',
    () {
      final store = AdminPendingAttemptStore(
        storage: MemoryAdminPendingAttemptStorage(),
        now: () => instant,
      )..bind(actor());
      addTearDown(store.dispose);
      for (final body in [
        {...intent, 'password': 'must-not-store'},
        {
          ...intent,
          'receiver': {'id': 'receiver', 'token': 'secret'},
        },
        {
          ...intent,
          'entries': [
            {'account_id': '1', 'authorization': 'secret'},
          ],
        },
        {...intent, 'amount': 1.5},
        {...intent, 'amount': 9007199254740992},
      ]) {
        expect(
          () => store.retain(
            family: 'reconciliation',
            resourceId: '1',
            requestKey: 'request-key-123',
            permission: 'reconciliations.propose',
            intent: body,
            schema: schema,
          ),
          throwsFormatException,
        );
      }
      expect(
        () => const AdminPendingAttemptSchema(
          fields: {'password'},
        ).canonical({'password': 'secret'}),
        throwsFormatException,
      );
      expect(
        () => const AdminPendingAttemptSchema(fields: {'receiver'}).canonical({
          'receiver': {'id': '1'},
        }),
        throwsFormatException,
      );
      expect(
        () => store.retain(
          family: 'reconciliation',
          resourceId: '1',
          requestKey: 'request-key-123',
          permission: 'users.manage',
          intent: intent,
          schema: schema,
        ),
        throwsA(isA<AdminAccountException>()),
      );
    },
  );

  test(
    'corrupt, credential-bearing, oversized or extended-expiry browser data cannot restore',
    () {
      for (final mutate in <String Function(String)>[
        (_) => 'not-json',
        (_) => 'x' * 65537,
        (raw) {
          final data = jsonDecode(raw) as Map;
          (data['entries'] as List).single['intent']['password'] = 'secret';
          return jsonEncode(data);
        },
        (raw) {
          final data = jsonDecode(raw) as Map;
          (data['entries'] as List).single['expires_at'] = instant
              .add(const Duration(hours: 9))
              .millisecondsSinceEpoch;
          return jsonEncode(data);
        },
      ]) {
        final storage = MemoryAdminPendingAttemptStorage();
        final first = AdminPendingAttemptStore(
          storage: storage,
          now: () => instant,
        )..bind(actor());
        save(first);
        first.dispose();
        final key = storage.values.keys.single;
        storage.values[key] = mutate(storage.values[key]!);
        final next = AdminPendingAttemptStore(
          storage: storage,
          now: () => instant,
        )..bind(actor());
        expect(restore(next), isNull);
        expect(next.storageAvailable, isFalse);
        expect(next.storageMessage, isNotEmpty);
        expect(storage.values, isEmpty);
        next.dispose();
      }
    },
  );

  test(
    'blocked sessionStorage is explicit and retains only in-memory recovery',
    () {
      final store = AdminPendingAttemptStore(
        storage: DeniedStorage(),
        now: () => instant,
      )..bind(actor());
      addTearDown(store.dispose);
      final checkpoint = save(store);
      expect(store.storageAvailable, isFalse);
      expect(store.storageMessage, contains('hard reload'));
      expect(restore(store)!.requestKey, checkpoint.requestKey);
      final reload = AdminPendingAttemptStore(
        storage: DeniedStorage(),
        now: () => instant,
      )..bind(actor());
      addTearDown(reload.dispose);
      expect(restore(reload), isNull);
      expect(reload.storageAvailable, isFalse);
    },
  );
}
