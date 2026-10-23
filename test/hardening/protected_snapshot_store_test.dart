import 'dart:convert';
import 'package:collect_app/core/security/protected_snapshot_store.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const owner = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const other = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const channel = MethodChannel('collect/secure_snapshot');
Map<String, dynamic> payload({String id = owner}) => {
  'version': 4,
  'saved_at': '2026-09-27T12:00:00Z',
  'collections': [],
  'payment_intents': [],
  'contributions': [],
  'collection_summaries': {},
  'current_profile': {
    'id': id,
    'public_id': '123456',
    'whatsapp_phone': '+250788000001',
    'country_code': 'RW',
    'currency_code': 'RWF',
    'momo_provider': 'mtn_momo',
    'momo_number': '0788000001',
  },
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  void host(Future<Object?> Function(MethodCall) handler) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, handler);
  test(
    'write passes owner and plaintext only across the native method boundary',
    () async {
      host((call) async {
        expect(call.method, 'write');
        expect(call.arguments['owner_id'], owner);
        expect(call.arguments['value'], '{}');
        return true;
      });
      expect(await const ProtectedSnapshotStore().write(owner, '{}'), isTrue);
    },
  );
  test('invalid owner blocks a host call', () async {
    host((_) async => throw StateError('must not invoke'));
    expect(
      () => const ProtectedSnapshotStore().write('../owner', '{}'),
      throwsFormatException,
    );
  });
  test('UTF8 byte size is bounded', () async {
    expect(
      () => const ProtectedSnapshotStore().write(
        owner,
        List.filled(300000, '💚').join(),
      ),
      throwsFormatException,
    );
  });
  test('missing platform has no plaintext fallback', () async {
    host((_) async => throw MissingPluginException());
    expect(await const ProtectedSnapshotStore().write(owner, '{}'), isFalse);
    expect(await const ProtectedSnapshotStore().read(owner), isNull);
  });
  test('key failure surfaces instead of returning an empty success', () async {
    host((_) async => throw PlatformException(code: 'key_locked'));
    expect(
      () => const ProtectedSnapshotStore().read(owner),
      throwsA(isA<PlatformException>()),
    );
  });
  test('negative clear acknowledgement is not ignored', () async {
    host((_) async => false);
    expect(() => const ProtectedSnapshotStore().clear(), throwsStateError);
  });
  test(
    'protected cache will not read before authenticated identity is known',
    () async {
      host((_) async => throw StateError('must not invoke'));
      expect(await const CollectOfflineCache.protected().read(), isNull);
    },
  );
  test('matching protected snapshot is restored', () async {
    host((_) async => jsonEncode(payload()));
    final restored = await const CollectOfflineCache.protected().read(
      ownerUserId: owner,
    );
    expect(restored?.currentProfile?.id, owner);
    expect(restored?.savedAt, DateTime.utc(2026, 9, 27, 12));
  });
  test('misbound native response is never displayed', () async {
    host((_) async => jsonEncode(payload(id: other)));
    expect(
      await const CollectOfflineCache.protected().read(ownerUserId: owner),
      isNull,
    );
  });
  test('missing saved timestamp is not replaced by now', () async {
    final p = payload()..remove('saved_at');
    host((_) async => jsonEncode(p));
    expect(
      await const CollectOfflineCache.protected().read(ownerUserId: owner),
      isNull,
    );
  });
  test('unknown snapshot version rejected', () async {
    final p = payload()..['version'] = 99;
    host((_) async => jsonEncode(p));
    expect(
      await const CollectOfflineCache.protected().read(ownerUserId: owner),
      isNull,
    );
  });
  test('legacy financial payloads are removed rather than imported', () async {
    SharedPreferences.setMockInitialValues({
      'collect.offline_snapshot.v4': 'PRIVATE',
      'collect.offline_snapshot.v3': 'PRIVATE',
      'unrelated': 'keep',
    });
    host((_) async => null);
    expect(
      await const CollectOfflineCache.protected().read(ownerUserId: owner),
      isNull,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('collect.offline_snapshot.v4'), isFalse);
    expect(prefs.containsKey('collect.offline_snapshot.v3'), isFalse);
    expect(prefs.getString('unrelated'), 'keep');
  });
}
