import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_entity_audit.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_action_session_test.dart' as auth;
import 'support/admin_entity_audit_fixture.dart';

const _identity = AdminIdentity(
  userId: auth.actor,
  displayName: 'Synthetic history reviewer',
  roles: ['platform_owner'],
  permissions: [
    'audit.read',
    'system_health.read',
    'notifications.read',
    'payments.read',
  ],
);

class _Probe {
  _Probe(this.name);
  final String name;
  late SupabaseClient client;
  late ProviderContainer container;
  late Map<String, dynamic> raw;
  late AdminEntityAuditQuery query;
  final requests = <http.Request>[];
  final entered = Completer<void>();
  Completer<void>? release;
  Object? readError;
  late final authority = StateProvider<Future<AdminIdentity?>>(
    (ref) => Future.value(_identity),
  );
  Future<void> start() async {
    raw = auditObserved(name);
    query = auditQuery(raw);
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
        if (request.url.path.endsWith('/logout')) {
          return auth.response({});
        }
        requests.add(request);
        if (!entered.isCompleted) {
          entered.complete();
        }
        if (release != null) {
          await release!.future;
        }
        final error = readError;
        final response = error is String
            ? auth.response({'code': error, 'message': 'PRIVATE_CANARY'}, 403)
            : auth.response(raw);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
    await auth.session(client, 'entity-authority-a');
    container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
        adminIdentityProvider.overrideWith((ref) => ref.watch(authority)),
        adminClockProvider.overrideWithValue(
          () => DateTime.parse(
            raw['checked_at'] as String,
          ).add(const Duration(seconds: 20)),
        ),
      ],
    );
  }

  Future<void> finish() async {
    if (release != null && !release!.isCompleted) {
      release!.complete();
    }
    container.dispose();
    await client.dispose();
  }

  Future<AdminEntityAuditSnapshot> read() =>
      container.read(adminEntityAuditProvider(query).future);
  AdminIdentity denied(String value) => AdminIdentity(
    userId: auth.actor,
    displayName: 'Synthetic denied reviewer',
    roles: value == 'role loss' ? ['admin'] : _identity.roles,
    permissions: _identity.permissions.where((v) => v != value).toList(),
  );
}

void main() {
  for (final name in [
    'shadow',
    'gateway',
    'supervisor',
    'exception',
    'receipt',
  ]) {
    group(name, () {
      late _Probe probe;
      setUp(() async {
        probe = _Probe(name);
        await probe.start();
      });
      tearDown(() => probe.finish());
      test(
        'entity history provider binds kind target and pinned SDK bearer',
        () async {
          final keep = probe.container.listen(
            adminEntityAuditProvider(probe.query),
            (_, _) {},
          );
          addTearDown(keep.close);
          final result = await probe.read();
          expect(result.query, probe.query);
          expect(result.rows, isNotEmpty);
          expect(probe.requests, hasLength(1));
          final request = probe.requests.single;
          expect(request.method, 'POST');
          expect(
            request.url.path,
            '/rest/v1/rpc/admin_get_operator_entity_audit_v1',
          );
          expect(
            request.headers['Authorization'],
            'Bearer ${probe.client.auth.currentSession!.accessToken}',
          );
          expect(jsonDecode(request.body), {
            'p_entity_kind': probe.query.kind.wire,
            'p_entity_id': probe.query.id,
            'p_limit': probe.query.limit,
            'p_before_at': null,
            'p_before_event_id': null,
          });
        },
      );
      for (final missing in [
        'role loss',
        'absent identity',
        'audit.read',
        'system_health.read',
        'notifications.read',
        if (name == 'exception' || name == 'receipt') 'payments.read',
      ]) {
        test(
          'entity history provider denies $missing before private SDK read',
          () async {
            probe.container.read(probe.authority.notifier).state = Future.value(
              missing == 'absent identity' ? null : probe.denied(missing),
            );
            await expectLater(
              probe.read(),
              throwsA(isA<AdminEntityAuditDenied>()),
            );
            expect(probe.requests, isEmpty);
          },
        );
      }
      test(
        'entity history provider waits for current identity before SDK dispatch',
        () async {
          final ready = Completer<AdminIdentity?>();
          addTearDown(() {
            if (!ready.isCompleted) {
              ready.complete(null);
            }
          });
          probe.container.read(probe.authority.notifier).state = ready.future;
          final keep = probe.container.listen(
            adminEntityAuditProvider(probe.query),
            (_, _) {},
          );
          addTearDown(keep.close);
          final future = probe.read();
          await probe.container.pump();
          expect(probe.requests, isEmpty);
          ready.complete(_identity);
          expect((await future).rows, isNotEmpty);
          expect(probe.requests, hasLength(1));
        },
      );
      for (final departure in [
        'permission loss',
        'role loss',
        'identity loading',
        'identity error',
      ]) {
        test(
          'entity history provider suppresses late SDK read after $departure',
          () async {
            probe.release = Completer<void>();
            final ready = Completer<AdminIdentity?>();
            addTearDown(() {
              if (!ready.isCompleted) {
                ready.complete(null);
              }
            });
            final emissions = <AsyncValue<AdminEntityAuditSnapshot>>[];
            final provider = adminEntityAuditProvider(probe.query);
            final keep = probe.container.listen(
              provider,
              (_, next) => emissions.add(next),
            );
            addTearDown(keep.close);
            final outcome = probe.read().then<Object?>(
              (v) => v,
              onError: (Object error) => error,
            );
            await probe.entered.future;
            probe.container.read(probe.authority.notifier).state =
                departure == 'permission loss' || departure == 'role loss'
                ? Future.value(
                    probe.denied(
                      departure == 'permission loss' ? 'audit.read' : departure,
                    ),
                  )
                : ready.future;
            await probe.container.pump();
            if (departure == 'identity error') {
              final denied = probe.container
                  .read(adminIdentityProvider.future)
                  .then<Object?>((v) => v, onError: (Object error) => error);
              ready.completeError(StateError('PRIVATE_CANARY'));
              expect(await denied, isA<StateError>());
              await probe.container.pump();
            }
            probe.release!.complete();
            await probe.container.pump();
            expect(probe.requests, hasLength(1));
            expect(emissions.where((v) => v.asData != null), isEmpty);
            if (departure == 'identity loading') {
              expect(probe.container.read(provider).isLoading, isTrue);
              ready.complete(null);
              await probe.container.pump();
            }
            expect(await outcome, anyOf(isA<Exception>(), isA<StateError>()));
          },
        );
      }
      for (final switchBack in [false, true]) {
        test(
          'entity history provider suppresses departed session A-B-A=$switchBack',
          () async {
            probe.release = Completer<void>();
            final ready = Completer<AdminIdentity?>();
            addTearDown(() {
              if (!ready.isCompleted) {
                ready.complete(null);
              }
            });
            final provider = adminEntityAuditProvider(probe.query);
            final emissions = <AsyncValue<AdminEntityAuditSnapshot>>[];
            final keep = probe.container.listen(
              provider,
              (_, next) => emissions.add(next),
            );
            addTearDown(keep.close);
            final outcome = probe.read().then<Object?>(
              (v) => v,
              onError: (Object error) => error,
            );
            await probe.entered.future;
            // A replacement login requires a new identity proof before dispatch.
            probe.container.read(probe.authority.notifier).state = ready.future;
            await probe.container.pump();
            await auth.session(probe.client, 'entity-authority-b');
            if (switchBack) {
              await auth.session(probe.client, 'entity-authority-a', nonce: 2);
            }
            probe.release!.complete();
            await probe.container.pump();
            ready.complete(null);
            await probe.container.pump();
            expect(probe.requests, hasLength(1));
            expect(emissions.where((v) => v.asData != null), isEmpty);
            expect(await outcome, anyOf(isA<Exception>(), isA<StateError>()));
          },
        );
      }
      for (final departure in [
        'permission loss',
        'role loss',
        'identity loading',
        'identity error',
        'session replacement',
      ]) {
        testWidgets(
          'entity history production page hides loaded actions after $departure',
          (tester) async {
            final provider = adminEntityAuditProvider(probe.query);
            late ProviderSubscription<AsyncValue<AdminEntityAuditSnapshot>>
            keep;
            await tester.runAsync(() async {
              keep = probe.container.listen(provider, (_, _) {});
              await probe.read();
            });
            addTearDown(keep.close);
            tester.view.physicalSize = const Size(1440, 1600);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: probe.container,
                child: MaterialApp(
                  theme: AppTheme.light(),
                  home: Scaffold(
                    body: AdminEntityAuditPage(
                      entityKind: probe.query.kind.wire,
                      entityId: probe.query.id,
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final marker =
                (probe.raw['rows'] as List).first['request_id'] as String;
            for (
              var i = 0;
              i < 20 && find.text(marker).evaluate().isEmpty;
              i++
            ) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 10)),
              );
              await tester.pump(const Duration(milliseconds: 10));
            }
            expect(find.text(marker), findsWidgets);
            final count = probe.requests.length;
            final waiting = Completer<AdminIdentity?>();
            addTearDown(() {
              if (!waiting.isCompleted) {
                waiting.complete(null);
              }
            });
            await tester.runAsync(() async {
              probe.container.read(probe.authority.notifier).state =
                  departure == 'permission loss' || departure == 'role loss'
                  ? Future.value(
                      probe.denied(
                        departure == 'permission loss'
                            ? 'audit.read'
                            : departure,
                      ),
                    )
                  : waiting.future;
              await probe.container.pump();
              if (departure == 'session replacement') {
                await auth.session(probe.client, 'entity-authority-b');
              }
              if (departure == 'identity error') {
                waiting.completeError(StateError('PRIVATE_CANARY'));
                await probe.container.pump();
              }
            });
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 100));
            if (departure == 'identity error') {
              expect(
                probe.container.read(adminIdentityProvider).asError?.error,
                isA<StateError>(),
              );
            }
            expect(find.text(marker), findsNothing);
            expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
            expect(probe.requests, hasLength(count));
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    });
  }
}
