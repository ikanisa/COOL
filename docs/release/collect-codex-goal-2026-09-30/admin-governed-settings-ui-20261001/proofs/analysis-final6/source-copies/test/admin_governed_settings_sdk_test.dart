import 'dart:async';
import 'dart:convert';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_governed_settings_models.dart';
import 'package:collect_app/admin/core/admin_governed_settings_checkpoint.dart';
import 'package:collect_app/admin/core/admin_governed_settings_sdk.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_action_session_test.dart' as auth;
import 'support/settings_fixture.dart' as f;

void main() {
  late SupabaseClient client;
  late AdminRepository repository;
  late AdminGovernedSettingsSdk sdk;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;
  late bool current;
  late DateTime now;
  setUp(() async {
    requests = [];
    current = true;
    now = f.at;
    respond = (_) async => auth.response(f.controlJson());
    client = SupabaseClient(
      'https://synthetic.invalid',
      'synthetic-publishable',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        if (r.url.path.endsWith('/verify')) {
          final values = (jsonDecode(r.body)['token'] as String).split('|');
          return auth.response(auth.authReceipt(values[0], values[1]));
        }
        if (r.url.path.endsWith('/logout')) return auth.response({});
        requests.add(r);
        final result = await respond(r);
        return http.Response.bytes(
          result.bodyBytes,
          result.statusCode,
          headers: result.headers,
          request: r,
        );
      }),
    );
    await auth.session(client, f.sessionA);
    repository = AdminRepository(client, isCurrent: () => current);
    sdk = AdminGovernedSettingsSdk(
      rpc: (name, parameters) =>
          repository.rpcMap(name, params: parameters, automaticRetry: false),
      isCurrent: () => current,
      now: () => now,
      currentSession: () => adminSessionKey(client.auth.currentSession),
    );
  });
  tearDown(() async => client.dispose());
  test(
    'actual pinned SDK carries explicit bearer and exact catalog/detail/history RPC names and parameters',
    () async {
      respond = (r) async {
        final name = r.url.path.split('/').last;
        return auth.response(
          name == 'admin_list_runtime_controls_v2'
              ? f.observed('catalog')
              : name == 'admin_list_runtime_control_history_v2'
              ? {...f.observed('history'), 'limit': 20}
              : f.controlJson(),
        );
      };
      await sdk.catalog(f.family);
      await sdk.control(f.family, f.identity);
      await sdk.history(f.family, f.identity);
      expect(requests.map((r) => r.url.path.split('/').last), [
        'admin_list_runtime_controls_v2',
        'admin_get_runtime_control_v2',
        'admin_list_runtime_control_history_v2',
      ]);
      for (final r in requests) {
        expect(r.headers['Authorization'], startsWith('Bearer '));
      }
      expect(jsonDecode(requests.first.body), {
        'p_family': f.family.key,
        'p_limit': 25,
        'p_after_identity': null,
      });
      expect(jsonDecode(requests.last.body), {
        'p_family': f.family.key,
        'p_identity': f.identity,
        'p_limit': 20,
        'p_before_at': null,
        'p_before_event_id': null,
      });
    },
  );
  test(
    'original mutation and recovery are separate exact calls without replayable recovery parameters',
    () async {
      final prepared = f.intent(),
          bookmark = AdminSettingsBookmark.fromPrepared(
            adminSettingsOwnerDigest(f.actor),
            f.intent(),
          );
      respond = (r) async => auth.response(
        r.url.path.endsWith('admin_update_runtime_control_v2')
            ? f.receiptJson(prepared)
            : f.lookupJson(bookmark, now),
      );
      expect((await sdk.update(prepared)).changed, isTrue);
      expect((await sdk.lookup(bookmark)).status, 'recorded');
      expect(jsonDecode(requests.first.body), prepared.parameters);
      expect(jsonDecode(requests.last.body), bookmark.parameters);
      expect(
        jsonDecode(requests.last.body).toString(),
        isNot(contains('patch_json')),
      );
    },
  );
  test('503 original has one HTTP attempt with SDK retry disabled', () async {
    respond = (_) async =>
        auth.response({'message': 'PRIVATE_503_CANARY'}, 503);
    await expectLater(
      sdk.update(f.intent()),
      throwsA(isA<PostgrestException>()),
    );
    expect(requests.length, 1);
  });
  test('prepared original under replaced session denies before HTTP', () async {
    await auth.session(client, f.sessionB);
    await expectLater(
      sdk.update(f.intent()),
      throwsA(isA<AdminSessionChanged>()),
    );
    expect(requests, isEmpty);
  });
  for (final change in ['logout', 'switch', 'aba', 'provider']) {
    test('late typed read cannot publish after $change', () async {
      final held = Completer<http.Response>();
      respond = (_) => held.future;
      final pending = sdk.control(f.family, f.identity);
      await Future<void>.delayed(Duration.zero);
      if (change == 'logout') await client.auth.signOut();
      if (change == 'switch' || change == 'aba') {
        await auth.session(client, f.sessionB);
      }
      if (change == 'aba') await auth.session(client, f.sessionA, nonce: 1);
      if (change == 'provider') current = false;
      held.complete(auth.response(f.controlJson()));
      await expectLater(pending, throwsA(isA<AdminSessionChanged>()));
      expect(requests.length, 1);
    });
  }
  test(
    'expired prepared request denies before HTTP and stale read DTO is refused',
    () async {
      now = f.intent().expiresAt;
      await expectLater(sdk.update(f.intent()), throwsFormatException);
      expect(requests, isEmpty);
      respond = (_) async => auth.response(f.controlJson(stale: true));
      await expectLater(
        sdk.control(f.family, f.identity),
        throwsFormatException,
      );
      expect(requests.length, 1);
    },
  );
  test('closed malformed acknowledged receipt remains refused', () async {
    respond = (_) async =>
        auth.response({...f.receiptJson(f.intent()), 'session_id': f.sessionA});
    await expectLater(sdk.update(f.intent()), throwsFormatException);
    expect(requests.length, 1);
  });
  test('paired history cursor is forwarded before bounded page read', () async {
    final raw = f.observed('history');
    raw['rows'] = [];
    raw['limit'] = 20;
    final cursor = AdminSettingsHistoryCursor(f.at, f.request);
    respond = (_) async => auth.response(raw);
    await sdk.history(f.family, f.identity, before: cursor);
    expect(jsonDecode(requests.single.body)['p_before_event_id'], f.request);
    expect(jsonDecode(requests.single.body)['p_before_at'], settingsUtc(f.at));
  });
  testWidgets('15-second bounded timeout does not replay original RPC', (
    tester,
  ) async {
    var calls = 0;
    Object? error;
    final never = Completer<Object?>();
    final bounded = AdminGovernedSettingsSdk(
      rpc: (_, _) {
        calls++;
        return never.future;
      },
      isCurrent: () => true,
      now: () => f.at,
      currentSession: () => f.scope.key,
    );
    bounded
        .update(f.intent())
        .then<void>(
          (_) {},
          onError: (Object e) {
            error = e;
          },
        );
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    expect(error, isA<TimeoutException>());
    expect(calls, 1);
  });
  test('foreign operator bookmark cannot make a lookup HTTP call', () async {
    final foreign = AdminSettingsBookmark.fromPrepared('b' * 64, f.intent());
    await expectLater(sdk.lookup(foreign), throwsFormatException);
    expect(requests, isEmpty);
  });
}
