import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actor = '99430000-0000-4000-8000-000000000001';
const target = '99430000-0000-4000-8000-000000000002';
Future<void> session(SupabaseClient client, String id, {int nonce = 0}) async {
  // Drive the pinned SDK's real login path so it emits the signedIn event.
  // recoverSession intentionally emits no event for the same user.
  await client.auth.verifyOTP(
    phone: '+250788943001',
    token: '$id|$nonce',
    type: OtpType.sms,
  );
}

Map<String, dynamic> authReceipt(String id, String nonce) => {
  'access_token':
      'e30.${base64Url.encode(utf8.encode(jsonEncode({'sub': actor, 'session_id': id, 'nonce': nonce, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.synthetic',
  'refresh_token': 'synthetic-refresh',
  'token_type': 'bearer',
  'user': {
    'id': actor,
    'aud': 'authenticated',
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
    'created_at': '2026-09-30T00:00:00Z',
  },
};
http.Response response(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

class _ControlledAuth extends Fake implements GoTrueClient {
  _ControlledAuth(this.currentSession, this.onAuthStateChange);
  @override
  final Session? currentSession;
  @override
  final Stream<AuthState> onAuthStateChange;
}

class _ControlledClient extends Fake implements SupabaseClient {
  _ControlledClient(this.auth);
  @override
  final GoTrueClient auth;
}

void main() {
  late SupabaseClient client;
  late AdminRepository repository;
  late Future<http.Response> Function(http.Request) respond;
  late List<http.Request> requests;
  setUp(() async {
    requests = [];
    respond = (_) async =>
        response({'ok': true, 'status': 'queued', 'delivery_count': 1});
    client = SupabaseClient(
      'https://synthetic.invalid',
      'synthetic-publishable',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/verify')) {
          final values = (jsonDecode(request.body)['token'] as String).split(
            '|',
          );
          return response(authReceipt(values[0], values[1]));
        }
        if (request.url.path.endsWith('/logout')) return response({});
        requests.add(request);
        return respond(request).then(
          (r) => http.Response.bytes(
            r.bodyBytes,
            r.statusCode,
            headers: r.headers,
            request: request,
          ),
        );
      }),
    );
    await session(client, 'session-a');
    repository = AdminRepository(client);
  });
  tearDown(() => client.dispose());

  for (final operation in ['read', 'action', 'identity']) {
    for (final switchBack in [false, true]) {
      test(
        '$operation suppresses same-user session change; switch-back=$switchBack',
        () async {
          final started = Completer<void>(), release = Completer<void>();
          respond = (_) async {
            started.complete();
            await release.future;
            return response(
              operation == 'identity'
                  ? {'user_id': actor, 'roles': [], 'permissions': []}
                  : {'ok': true, 'status': 'queued', 'delivery_count': 1},
            );
          };
          final pending = switch (operation) {
            'read' => repository.rpcMap('admin_get_notification'),
            'identity' => repository.currentIdentity(),
            _ => repository.action('admin_retry_notification', {
              'p_event_id': target,
              'p_reason': 'Confirmed recipient',
            }),
          };
          final assertion = expectLater(
            pending,
            throwsA(isA<AdminSessionChanged>()),
          );
          await started.future;
          final originalToken = requests.single.headers['Authorization'];
          await session(client, 'session-b');
          if (switchBack) await session(client, 'session-a', nonce: 2);
          release.complete();
          await assertion;
          expect(requests, hasLength(1));
          expect(
            originalToken,
            isNot('Bearer ${client.auth.currentSession!.accessToken}'),
          );
        },
      );
    }
  }
  test(
    'same-session token refresh allows completion with pinned request token',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      respond = (_) async {
        started.complete();
        await release.future;
        return response({'ok': true, 'status': 'queued', 'delivery_count': 2});
      };
      final original = client.auth.currentSession!.accessToken;
      final pending = repository.action('admin_retry_notification', {
        'p_event_id': target,
        'p_reason': 'Confirmed recipient',
      });
      await started.future;
      await session(client, 'session-a', nonce: 1);
      release.complete();
      expect((await pending)['delivery_count'], 2);
      expect(requests.single.headers['Authorization'], 'Bearer $original');
    },
  );
  test(
    'old-session backend error is replaced with safe session boundary',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      respond = (_) async {
        started.complete();
        await release.future;
        return response({
          'message': 'old private result',
          'code': '42501',
        }, 403);
      };
      final assertion = expectLater(
        repository.rpcMap('admin_get_user'),
        throwsA(isA<AdminSessionChanged>()),
      );
      await started.future;
      await session(client, 'session-b');
      release.complete();
      await assertion;
    },
  );
  test('signed-out request is denied before HTTP dispatch', () async {
    await client.auth.signOut(scope: SignOutScope.local);
    requests.clear();
    await expectLater(
      repository.rpcMap('admin_get_user'),
      throwsA(isA<AdminSessionChanged>()),
    );
    expect(requests, isEmpty);
  });
  test(
    'nullable identity/detail and explicit absent SLA policy stay supported',
    () async {
      respond = (_) async => response(null);
      expect(await repository.currentIdentity(), isNull);
      expect(await repository.detail('admin_get_collection', target), isEmpty);
      await expectLater(
        repository.queueSla('admin_list_notifications'),
        throwsFormatException,
      );
      await expectLater(repository.runtimeConfig(), throwsFormatException);
      respond = (_) async => response({});
      expect(await repository.queueSla('admin_list_notifications'), isNull);
    },
  );
  for (final body in [
    null,
    {},
    [],
    true,
    {'ok': true},
    {'ok': true, 'status': 'queued', 'delivery_count': '1'},
    {'ok': true, 'status': 'queued', 'delivery_count': 0},
  ]) {
    test('notification action rejects unconfirmed response $body', () async {
      respond = (_) async => response(body);
      await expectLater(
        repository.action('admin_retry_notification', {
          'p_event_id': target,
          'p_reason': 'Reviewed recipient',
        }),
        throwsA(anyOf(isA<FormatException>(), isA<StateError>())),
      );
    });
  }
  test('request parameters are frozen across an awaited response', () async {
    final started = Completer<void>(), release = Completer<void>();
    respond = (_) async {
      started.complete();
      await release.future;
      return response({
        'ok': true,
        'collection_id': target,
        'active': true,
        'status': 'active',
        'visibility': 'private',
      });
    };
    final input = <String, dynamic>{
      'p_collection_id': target,
      'p_active': true,
    };
    final pending = repository.action('admin_set_group_active', input);
    await started.future;
    input['p_collection_id'] = actor;
    input['p_active'] = false;
    release.complete();
    expect((await pending)['collection_id'], target);
    expect(jsonDecode(requests.single.body)['p_collection_id'], target);
  });
  test(
    'provider generation recreates repository and denies previously captured repository',
    () async {
      final container = ProviderContainer(
        overrides: [supabaseClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      final first = container.read(adminRepositoryProvider);
      final a = container.read(adminAuthSessionScopeProvider);
      await session(client, 'session-a', nonce: 1);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(adminAuthSessionScopeProvider), a);
      expect(identical(container.read(adminRepositoryProvider), first), isTrue);
      await session(client, 'session-b');
      await Future<void>.delayed(Duration.zero);
      final second = container.read(adminRepositoryProvider);
      expect(identical(second, first), isFalse);
      final count = requests.length;
      await expectLater(
        first.action('admin_retry_notification', {'p_event_id': target}),
        throwsA(isA<AdminSessionChanged>()),
      );
      expect(requests.length, count);
      await session(client, 'session-a', nonce: 2);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(adminAuthSessionScopeProvider)!.generation,
        greaterThan(a!.generation),
      );
    },
  );

  test('refresh freshness resets on replacement login and logout', () async {
    final container = ProviderContainer(
      overrides: [supabaseClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    final timestamp = DateTime.utc(2026, 9, 30);
    container.read(adminLastSuccessfulRefreshProvider.notifier).state =
        timestamp;
    await session(client, 'session-a', nonce: 1);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(adminLastSuccessfulRefreshProvider), timestamp);
    await session(client, 'session-b');
    await Future<void>.delayed(Duration.zero);
    expect(container.read(adminLastSuccessfulRefreshProvider), isNull);
    container.read(adminLastSuccessfulRefreshProvider.notifier).state =
        timestamp;
    await client.auth.signOut(scope: SignOutScope.local);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(adminLastSuccessfulRefreshProvider), isNull);
  });

  test(
    'reconciliation scope cannot revive after a coalesced A to B to A',
    () async {
      final container = ProviderContainer(
        overrides: [supabaseClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      final first = container.read(adminReconciliationSessionKeyProvider);
      expect(first, isNotNull);
      await session(client, 'session-a', nonce: 1);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(adminReconciliationSessionKeyProvider), first);
      // No provider read or widget rebuild between the two Auth events.
      await session(client, 'session-b');
      await session(client, 'session-a', nonce: 2);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(adminReconciliationSessionKeyProvider),
        isNot(first),
      );
    },
  );

  for (final signal in ['error', 'done']) {
    test(
      'Auth stream $signal denies cached session and in-flight request',
      () async {
        final events = StreamController<AuthState>.broadcast(sync: true);
        final controlled = _ControlledClient(
          _ControlledAuth(client.auth.currentSession, events.stream),
        );
        final controller = AdminSessionController(controlled);
        final fence = AdminRequestSession(controlled);
        final container = ProviderContainer(
          overrides: [supabaseClientProvider.overrideWithValue(controlled)],
        );
        expect(
          container.read(adminReconciliationSessionKeyProvider),
          isNotNull,
        );
        final before = controller.state!;
        expect(before.key.sessionId, 'session-a');
        if (signal == 'error') {
          events.addError(StateError('synthetic private Auth failure'));
        } else {
          await events.close();
        }
        expect(controlled.auth.currentSession, isNotNull);
        expect(controller.state, isNull);
        expect(container.read(adminReconciliationSessionKeyProvider), isNull);
        expect(fence.checkCurrent, throwsA(isA<AdminSessionChanged>()));
        if (signal == 'error') {
          events.add(
            AuthState(AuthChangeEvent.signedIn, client.auth.currentSession),
          );
          expect(controller.state!.generation, greaterThan(before.generation));
          // Recovery can start a new request; an old one remains invalid forever.
          expect(fence.checkCurrent, throwsA(isA<AdminSessionChanged>()));
        }
        await fence.dispose();
        container.dispose();
        controller.dispose();
        if (!events.isClosed) await events.close();
      },
    );
  }

  testWidgets('session expiry clears authorization without an Auth event', (
    tester,
  ) async {
    final events = StreamController<AuthState>.broadcast(sync: true);
    final expiring = Session.fromJson(authReceipt('session-expiry', '0'))!
      ..expiresAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 1;
    final controlled = _ControlledClient(
      _ControlledAuth(expiring, events.stream),
    );
    final controller = AdminSessionController(controlled);
    expect(controller.state, isNotNull);
    await tester.pump(const Duration(seconds: 2));
    expect(controller.state, isNull);
    controller.dispose();
    await events.close();
  });
}
