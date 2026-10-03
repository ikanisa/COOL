import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_exception_models.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_action_session_test.dart' as auth;
import 'admin_exception_models_test.dart' as fixture;

final _request =
    fixture.exceptionFixture('recorded-lookup')['request_id'] as String;

class _Probe {
  late SupabaseClient client;
  late AdminRepository repository;
  final requests = <http.Request>[];
  late Future<http.Response> Function(http.Request) respond;
  Future<void> start() async {
    client = SupabaseClient(
      'https://synthetic.invalid',
      'synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/verify')) {
          final parts = (jsonDecode(request.body)['token'] as String).split(
            '|',
          );
          return auth.response(auth.authReceipt(parts[0], parts[1]));
        }
        if (request.url.path.endsWith('/logout')) return auth.response({});
        requests.add(request);
        final result = await respond(request);
        return http.Response.bytes(
          result.bodyBytes,
          result.statusCode,
          headers: result.headers,
          request: request,
        );
      }),
    );
    await auth.session(client, 'exception-matrix-a');
    repository = AdminRepository(client);
  }

  Map<String, dynamic> receipt(String operation) => fixture.exceptionFixture(
    operation == 'admin_list_operational_exceptions_v2'
        ? 'populated'
        : 'recorded-lookup',
  );
  Future<Object?> call(String operation) =>
      operation == 'admin_list_operational_exceptions_v2'
      ? repository.exceptionInbox(limit: 50)
      : repository.exceptionActionLookup(_request);
  Map<String, dynamic> body(String operation) =>
      operation == 'admin_list_operational_exceptions_v2'
      ? {
          'p_active': true,
          'p_limit': 50,
          'p_source_kind': null,
          'p_before_changed_at': null,
          'p_before_id': null,
        }
      : {'p_request_id': _request};
}

void main() {
  late _Probe probe;
  setUp(() async {
    probe = _Probe();
    await probe.start();
  });
  tearDown(() => probe.client.dispose());
  final operations = [
    'admin_list_operational_exceptions_v2',
    'admin_get_operational_exception_action_v2',
  ];
  for (final operation in operations) {
    test(
      '$operation actual SDK exact target body and captured Bearer',
      () async {
        probe.respond = (_) async => auth.response(probe.receipt(operation));
        final token = probe.client.auth.currentSession!.accessToken;
        await probe.call(operation);
        expect(probe.requests, hasLength(1));
        expect(probe.requests.single.method, 'POST');
        expect(probe.requests.single.url.path, '/rest/v1/rpc/$operation');
        expect(jsonDecode(probe.requests.single.body), probe.body(operation));
        expect(probe.requests.single.headers['Authorization'], 'Bearer $token');
      },
    );
    for (final failure in [
      'denied',
      '503',
      'lost response',
      'missing receipt',
      'extra private field',
    ]) {
      test(
        '$operation actual SDK $failure has no fallback or mutation retry',
        () async {
          probe.respond = (_) async {
            if (failure == 'lost response') {
              throw TimeoutException('PRIVATE_CANARY');
            }
            if (failure == 'denied' || failure == '503') {
              return auth.response({
                'code': failure == 'denied' ? '42501' : 'unavailable',
                'message': 'PRIVATE_CANARY',
              }, failure == 'denied' ? 403 : 503);
            }
            final data = failure == 'missing receipt'
                ? <String, dynamic>{}
                : {
                    ...probe.receipt(operation),
                    'private_context': 'PRIVATE_CANARY',
                  };
            return auth.response(data);
          };
          await expectLater(
            probe.call(operation),
            throwsA(
              failure == 'lost response'
                  ? isA<TimeoutException>()
                  : failure == 'denied' || failure == '503'
                  ? isA<PostgrestException>()
                  : isA<FormatException>(),
            ),
          );
          expect(probe.requests, hasLength(1));
          expect(probe.requests.single.url.path, '/rest/v1/rpc/$operation');
        },
      );
    }
    for (final switchBack in [false, true]) {
      test(
        '$operation actual SDK suppresses replaced session switchBack=$switchBack',
        () async {
          final entered = Completer<void>(), release = Completer<void>();
          probe.respond = (_) async {
            entered.complete();
            await release.future;
            return auth.response(probe.receipt(operation));
          };
          final future = probe.call(operation);
          final rejected = expectLater(
            future,
            throwsA(isA<AdminSessionChanged>()),
          );
          await entered.future;
          await auth.session(probe.client, 'exception-matrix-b');
          if (switchBack) {
            await auth.session(probe.client, 'exception-matrix-a', nonce: 2);
          }
          release.complete();
          await rejected;
          expect(probe.requests, hasLength(1));
        },
      );
    }
    test(
      '$operation actual SDK same-session refresh preserves pinned request token',
      () async {
        final entered = Completer<void>(), release = Completer<void>();
        probe.respond = (_) async {
          entered.complete();
          await release.future;
          return auth.response(probe.receipt(operation));
        };
        final token = probe.client.auth.currentSession!.accessToken;
        final future = probe.call(operation);
        await entered.future;
        await auth.session(probe.client, 'exception-matrix-a', nonce: 1);
        release.complete();
        await future;
        expect(probe.requests, hasLength(1));
        expect(probe.requests.single.headers['Authorization'], 'Bearer $token');
      },
    );
    test('$operation actual SDK signed-out caller makes no request', () async {
      await probe.client.auth.signOut();
      await expectLater(
        probe.call(operation),
        throwsA(isA<AdminSessionChanged>()),
      );
      expect(probe.requests, isEmpty);
    });
  }

  for (final requestRead in [false, true]) {
    final operation = requestRead
        ? 'admin_get_operational_exception_action_v2'
        : 'admin_list_operational_exceptions_v2';
    final provider = requestRead
        ? adminExceptionLookupProvider(_request)
        : adminExceptionInboxProvider(const AdminExceptionQuery(limit: 50));
    for (final missing in [
      'payments.read',
      'notifications.read',
      'system_health.read',
    ]) {
      test(
        '$operation production provider denies missing $missing before SDK dispatch',
        () async {
          final container = ProviderContainer(
            overrides: [
              supabaseClientProvider.overrideWithValue(probe.client),
              adminRepositoryProvider.overrideWithValue(probe.repository),
              adminIdentityProvider.overrideWith(
                (ref) async => AdminIdentity(
                  userId: auth.actor,
                  displayName: 'Synthetic owner',
                  roles: ['owner'],
                  permissions: [
                    for (final value in [
                      'payments.read',
                      'notifications.read',
                      'system_health.read',
                    ])
                      if (value != missing) value,
                  ],
                ),
              ),
            ],
          );
          addTearDown(container.dispose);
          await expectLater(
            container.read(provider.future),
            throwsA(isA<AdminExceptionDenied>()),
          );
          expect(probe.requests, isEmpty);
        },
      );
    }
    test(
      '$operation production provider waits for current identity before SDK dispatch',
      () async {
        final identityReady = Completer<AdminIdentity?>();
        probe.respond = (_) async => auth.response(probe.receipt(operation));
        final container = ProviderContainer(
          overrides: [
            supabaseClientProvider.overrideWithValue(probe.client),
            adminRepositoryProvider.overrideWithValue(probe.repository),
            adminIdentityProvider.overrideWith((ref) => identityReady.future),
          ],
        );
        addTearDown(container.dispose);
        final keep = container.listen(provider, (_, _) {});
        addTearDown(keep.close);
        final pending = container.read(provider.future);
        await Future<void>.delayed(Duration.zero);
        expect(probe.requests, isEmpty);
        identityReady.complete(
          const AdminIdentity(
            userId: auth.actor,
            displayName: 'Synthetic owner',
            roles: ['owner'],
            permissions: [
              'payments.read',
              'notifications.read',
              'system_health.read',
            ],
          ),
        );
        final data = await pending;
        expect(
          data,
          requestRead
              ? isA<AdminExceptionLookup>()
              : isA<AdminExceptionSnapshot>(),
        );
        expect(probe.requests.single.url.path, '/rest/v1/rpc/$operation');
      },
    );
    for (final code in ['42501', 'PGRST202']) {
      test(
        '$operation production provider redacts $code service failure',
        () async {
          probe.respond = (_) async => auth.response({
            'code': code,
            'message': 'PRIVATE_CANARY',
          }, code == '42501' ? 403 : 404);
          final container = ProviderContainer(
            overrides: [
              supabaseClientProvider.overrideWithValue(probe.client),
              adminRepositoryProvider.overrideWithValue(probe.repository),
              adminIdentityProvider.overrideWith(
                (ref) async => const AdminIdentity(
                  userId: auth.actor,
                  displayName: 'Synthetic owner',
                  roles: ['owner'],
                  permissions: [
                    'payments.read',
                    'notifications.read',
                    'system_health.read',
                  ],
                ),
              ),
            ],
          );
          addTearDown(container.dispose);
          await expectLater(
            container.read(provider.future),
            throwsA(
              code == '42501'
                  ? isA<AdminExceptionDenied>()
                  : isA<UnsupportedError>(),
            ),
          );
          expect(probe.requests, hasLength(1));
        },
      );
    }
    for (final departure in [
      'permission loss',
      'identity loading',
      'identity error',
    ]) {
      test(
        '$operation production provider suppresses late SDK read after $departure',
        () async {
          final entered = Completer<void>(), release = Completer<void>();
          final unresolved = Completer<AdminIdentity?>();
          const allowed = AdminIdentity(
            userId: auth.actor,
            displayName: 'Synthetic owner',
            roles: ['owner'],
            permissions: [
              'payments.read',
              'notifications.read',
              'system_health.read',
            ],
          );
          final authority = StateProvider<Future<AdminIdentity?>>(
            (ref) async => allowed,
          );
          probe.respond = (_) async {
            if (!entered.isCompleted) {
              entered.complete();
            }
            await release.future;
            return auth.response(probe.receipt(operation));
          };
          final container = ProviderContainer(
            overrides: [
              supabaseClientProvider.overrideWithValue(probe.client),
              adminRepositoryProvider.overrideWithValue(probe.repository),
              adminIdentityProvider.overrideWith((ref) => ref.watch(authority)),
            ],
          );
          addTearDown(container.dispose);
          final observations = <AsyncValue<Object?>>[];
          final listener = container.listen(
            provider,
            (_, next) => observations.add(next),
          );
          addTearDown(listener.close);
          addTearDown(() {
            if (!release.isCompleted) {
              release.complete();
            }
            if (!unresolved.isCompleted) {
              unresolved.complete(null);
            }
          });
          final oldResult = container.read(provider.future);
          // Riverpod's public .future facade follows the replacement build.
          // Observe the actual provider state: no departed SDK value may be
          // emitted even if its old network request finishes successfully.
          final outcome = oldResult.then<Object?>(
            (value) => value,
            onError: (Object error) => error,
          );
          await entered.future;
          container.read(authority.notifier).state = switch (departure) {
            'permission loss' => Future.value(
              const AdminIdentity(
                userId: auth.actor,
                displayName: 'Departed read authority',
                roles: ['owner'],
                permissions: ['notifications.read'],
              ),
            ),
            'identity loading' => unresolved.future,
            _ => unresolved.future,
          };
          await container.pump();
          if (departure == 'identity error') {
            // Install an explicit observer before delivering the injected
            // upstream failure, so the fixture cannot emit an unhandled error
            // before Riverpod has attached to the replacement identity.
            final identityOutcome = container
                .read(adminIdentityProvider.future)
                .then<Object?>(
                  (value) => value,
                  onError: (Object error) => error,
                );
            unresolved.completeError(StateError('PRIVATE_CANARY'));
            expect(await identityOutcome, isA<StateError>());
            await container.pump();
          }
          release.complete();
          await container.pump();
          expect(probe.requests, hasLength(1));
          expect(container.read(provider).asData, isNull);
          expect(observations.where((value) => value.asData != null), isEmpty);
          if (departure == 'identity loading') {
            expect(container.read(provider).isLoading, isTrue);
            unresolved.complete(null);
            await container.pump();
          }
          expect(
            await outcome,
            departure == 'identity error'
                ? isA<StateError>()
                : isA<AdminExceptionDenied>(),
          );
        },
      );
    }
  }
}
