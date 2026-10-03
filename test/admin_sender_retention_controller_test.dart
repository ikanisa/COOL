import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_sender_retention_sdk.dart';
import 'package:collect_app/admin/core/admin_sender_retention_models.dart';
import 'support/retention_fixture.dart';
import 'support/retention_api_fixture.dart';

void main() {
  test(
    'invalid local draft has no original request and remains correctable',
    () async {
      final api = Api(), store = Store(), c = control(api, store);
      await c.refresh();
      await c.apply(
        enabled: false,
        batchLimit: 26,
        byteLimit: 1048576,
        reason: 'Synthetic governed maintenance test',
      );
      expect(
        c.error,
        'Check the maintenance limits and reason before recording a change.',
      );
      expect(c.pending, isNull);
      expect(store.value, isNull);
      expect(store.writes, 0);
      expect(store.clears, 0);
      expect(api.changes, 0);
      expect(c.canApply, isTrue);
      await apply(c);
      expect(api.changes, 1);
      expect(store.writes, 1);
      expect(store.clears, 1);
      expect(c.pending, isNull);
      c.dispose();
    },
  );
  test(
    'SDK rejects drifted v1 protocol authority before any configure call',
    () async {
      final raw = decoded(readInitialRaw), calls = <String>[];
      (raw['retention'] as Map)['protocol_sha256'] = 'a' * 64;
      final sdk = AdminRetentionSdk(
        actorId: actor,
        sessionId: session,
        isCurrent: () => true,
        now: () => fixtureNow,
        rpc: (name, p) async {
          calls.add(name);
          return raw;
        },
      );
      await expectLater(sdk.read(), throwsFormatException);
      expect(calls, ['admin_get_receipt_retention_controls_v1']);
    },
  );
  test(
    'SDK binds real actor/session producer and disables automatic replay by one call seam',
    () async {
      final calls = <String>[];
      final sdk = AdminRetentionSdk(
        actorId: actor,
        sessionId: session,
        isCurrent: () => true,
        now: () => fixtureNow,
        rpc: (name, p) async {
          calls.add(name);
          return decoded(
            name.contains('get_receipt_retention_controls')
                ? readInitialRaw
                : recordedRaw,
          );
        },
      );
      expect((await sdk.read()).revision, initial().revision);
      expect((await sdk.configure(originalIntent())).recorded, isTrue);
      expect((await sdk.recover(originalIntent())).recorded, isTrue);
      expect(calls, [
        'admin_get_receipt_retention_controls_v1',
        'admin_configure_receipt_retention_controls_v1',
        'admin_get_receipt_retention_control_request_v1',
      ]);
    },
  );
  test(
    'durable original checkpoint precedes mutation and clears only after exact recorded receipt',
    () async {
      final api = Api(), store = Store(), c = control(api, store);
      await c.refresh();
      await apply(c);
      expect(api.changes, 1);
      expect(store.writes, 1);
      expect(store.clears, 1);
      expect(c.pending, isNull);
      expect(c.receipt!.row, recorded().row);
      c.dispose();
    },
  );
  test('failed durable storage prevents any server mutation', () async {
    final api = Api(),
        store = Store()..failWrite = true,
        c = control(api, store);
    await c.refresh();
    await apply(c);
    expect(api.changes, 0);
    expect(c.pending, isNotNull);
    expect(c.canApply, isFalse);
    expect(c.error, contains('original request requires recovery'));
    c.dispose();
  });
  test(
    'uncertain response blocks new UUID and recovers only the original',
    () async {
      final api = Api()..changeError = TimeoutException('response unknown'),
          store = Store(),
          c = control(api, store);
      await c.refresh();
      await apply(c);
      await apply(c);
      expect(api.changes, 1);
      expect(c.pending!.fingerprint, originalIntent().fingerprint);
      await c.recover();
      expect(api.lookups, 1);
      expect(api.changes, 1);
      expect(c.pending, isNull);
      c.dispose();
    },
  );
  for (final e in [
    const AdminSessionChanged(),
    const AuthException('expired'),
    const PostgrestException(message: 'denied', code: '42501'),
    const PostgrestException(message: 'expired', code: 'PGRST301'),
  ]) {
    test(
      'authoritative read denial clears protected state ${e.runtimeType} $e',
      () async {
        final api = Api(), c = control(api, Store());
        await c.refresh();
        api.readError = e;
        await c.refresh();
        expect(c.snapshot, isNull);
        expect(c.receipt, isNull);
        expect(c.canApply, isFalse);
        c.dispose();
      },
    );
  }
  test(
    'recovery denial redacts UI but leaves durable original then fresh refresh recovers',
    () async {
      final api = Api()..changeError = TimeoutException('unknown'),
          store = Store(),
          c = control(api, store);
      await c.refresh();
      await apply(c);
      api.lookupError = const PostgrestException(
        message: 'denied',
        code: '42501',
      );
      await c.recover();
      expect(c.pending, isNull);
      expect(store.value, isNotNull);
      expect(c.snapshot, isNull);
      api.lookupError = null;
      await c.refresh();
      expect(c.pending!.fingerprint, originalIntent().fingerprint);
      await c.recover();
      expect(store.value, isNull);
      c.dispose();
    },
  );
  test(
    'departed mutation cannot clear a retained original or publish into new controller',
    () async {
      var current = true;
      final api = Api()..wait = Completer<AdminRetentionRequest>(),
          store = Store(),
          c = control(api, store, current: () => current);
      await c.refresh();
      final work = apply(c);
      await Future<void>.delayed(Duration.zero);
      current = false;
      api.wait!.complete(recorded());
      await work;
      expect(store.value, isNotNull);
      expect(c.receipt, isNull);
      expect(store.clears, 0);
      c.dispose();
    },
  );
  test(
    'delayed predeadline absence remains pending after the client deadline',
    () async {
      final raw = decoded(notRecordedDelayedPredeadlineRaw);
      final i = missingIntent();
      raw['request_id'] = i.requestId;
      raw['fingerprint_sha256'] = i.fingerprint;
      final api = Api()..lookup = AdminRetentionRequest.parse(raw, i),
          store = Store()..value = i,
          c = control(
            api,
            store,
            clock: () => i.expiresAt.add(const Duration(seconds: 5)),
          );
      await c.refresh();
      await c.recover();
      expect(c.pending, isNotNull);
      expect(store.clears, 0);
      expect(api.changes, 0);
      c.dispose();
    },
  );
  test(
    'expired original authoritative lookup permits clear and demands fresh read before replacement',
    () async {
      final i = missingIntent(), raw = decoded(notRecordedAfterDeadlineRaw);
      raw['request_id'] = i.requestId;
      raw['fingerprint_sha256'] = i.fingerprint;
      final api = Api()..lookup = AdminRetentionRequest.parse(raw, i),
          store = Store()..value = i,
          c = control(
            api,
            store,
            clock: () => i.expiresAt.add(const Duration(seconds: 1)),
          );
      await c.refresh();
      await c.recover();
      expect(c.pending, isNull);
      expect(c.snapshot, isNull);
      expect(c.canApply, isFalse);
      expect(api.changes, 0);
      c.dispose();
    },
  );
  test(
    'same actor different session cannot use retained mutation intent',
    () async {
      final sdk = AdminRetentionSdk(
        actorId: actor,
        sessionId: '33333333-3333-4333-8333-333333333333',
        isCurrent: () => true,
        now: () => fixtureNow,
        rpc: (_, _) async => throw StateError('must not invoke'),
      );
      await expectLater(sdk.recover(originalIntent()), throwsFormatException);
    },
  );
}
