import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_action_session_test.dart' as auth;
import 'support/admin_read_fixture.dart';

const _identity = AdminIdentity(
  userId: auth.actor,
  displayName: 'Synthetic provider reviewer',
  roles: ['admin'],
  permissions: [
    'overview.read',
    'users.read',
    'collections.read',
    'payments.read',
    'notifications.read',
    'admin_users.read',
    'system_health.read',
  ],
);

class _Read {
  const _Read(this.rpc, this.permission);
  final String rpc, permission;
  String get id => rpc == 'admin_system_health'
      ? 'system'
      : rpc == 'admin_get_collect_transaction'
      ? 'momo:$adminReadTarget'
      : adminReadTarget;
  ProviderListenable<AsyncValue<Object?>> get provider =>
      rpc == 'admin_runtime_config'
      ? adminRuntimeConfigProvider
      : adminDetailRecordProvider((rpc: rpc, id: id));
  Future<Object?> future(ProviderContainer container) =>
      rpc == 'admin_runtime_config'
      ? container.read(adminRuntimeConfigProvider.future)
      : container.read(adminDetailRecordProvider((rpc: rpc, id: id)).future);
  Object? get data {
    if (rpc == 'admin_runtime_config') return adminRuntimeFixture();
    if (rpc == 'admin_system_health') {
      return (jsonDecode(
            File(
              'test/fixtures/admin_operational_health148.json',
            ).readAsStringSync(),
          )
          as Map)['receipt'];
    }
    return adminDetailFixture(rpc);
  }
}

class _Probe {
  late SupabaseClient client;
  late ProviderContainer container;
  late _Read read;
  late final authority = StateProvider<Future<AdminIdentity?>>(
    (_) async => _identity,
  );
  final requests = <http.Request>[];
  final entered = Completer<void>();
  Completer<void>? release;
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
        if (!entered.isCompleted) entered.complete();
        if (release != null) await release!.future;
        final response = auth.response(read.data);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
    await auth.session(client, 'private-provider-a');
    container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
        adminIdentityProvider.overrideWith((ref) => ref.watch(authority)),
      ],
    );
  }

  Future<void> finish() async {
    if (release != null && !release!.isCompleted) release!.complete();
    container.dispose();
    await client.dispose();
  }
}

void main() {
  for (final read in const [
    _Read('admin_runtime_config', ''),
    _Read('admin_get_collection', 'collections.read'),
    _Read('admin_get_user', 'users.read'),
    _Read('admin_get_member_record', 'users.read'),
    _Read('admin_get_collect_transaction', 'payments.read'),
    _Read('admin_get_hybrid_sms_receipt', 'notifications.read'),
    _Read('admin_get_notification', 'notifications.read'),
    _Read('admin_get_admin_user', 'admin_users.read'),
    _Read('admin_system_health', 'system_health.read'),
  ]) {
    group(read.rpc, () {
      late _Probe probe;
      setUp(() async {
        probe = _Probe()..read = read;
        await probe.start();
      });
      tearDown(() => probe.finish());
      test(
        'current authority provider pins exact target and SDK bearer',
        () async {
          final keep = probe.container.listen(read.provider, (_, _) {});
          addTearDown(keep.close);
          final result = await read.future(probe.container);
          expect(
            result,
            read.rpc == 'admin_runtime_config'
                ? isA<AdminRuntimeConfig>()
                : isA<Map<String, dynamic>>(),
          );
          expect(probe.requests, hasLength(1));
          final request = probe.requests.single;
          expect(request.url.path, '/rest/v1/rpc/${read.rpc}');
          expect(
            request.headers['Authorization'],
            'Bearer ${probe.client.auth.currentSession!.accessToken}',
          );
          expect(
            jsonDecode(request.body),
            read.rpc == 'admin_runtime_config' ? isNull : {'p_id': read.id},
          );
        },
      );
      for (final denied in [
        'absent identity',
        if (read.permission.isNotEmpty) 'missing permission',
      ]) {
        test(
          'current authority provider denies $denied before private SDK read',
          () async {
            probe.container.read(probe.authority.notifier).state = Future.value(
              denied == 'absent identity'
                  ? null
                  : AdminIdentity(
                      userId: auth.actor,
                      displayName: 'Synthetic denied',
                      roles: ['admin'],
                      permissions: _identity.permissions
                          .where((v) => v != read.permission)
                          .toList(),
                    ),
            );
            await expectLater(
              read.future(probe.container),
              throwsA(anyOf(isA<Exception>(), isA<StateError>())),
            );
            expect(probe.requests, isEmpty);
          },
        );
      }
      test(
        'current authority provider waits for identity before private SDK read',
        () async {
          final ready = Completer<AdminIdentity?>();
          addTearDown(() {
            if (!ready.isCompleted) ready.complete(null);
          });
          probe.container.read(probe.authority.notifier).state = ready.future;
          final keep = probe.container.listen(read.provider, (_, _) {});
          addTearDown(keep.close);
          final result = read.future(probe.container);
          await probe.container.pump();
          expect(probe.requests, isEmpty);
          ready.complete(_identity);
          expect(await result, isNotNull);
          expect(probe.requests, hasLength(1));
        },
      );
      for (final departure in [
        'absent identity',
        'identity loading',
        'identity error',
        if (read.permission.isNotEmpty) 'permission loss',
      ]) {
        test(
          'current authority provider suppresses late private SDK read after $departure',
          () async {
            probe.release = Completer<void>();
            final ready = Completer<AdminIdentity?>();
            addTearDown(() {
              if (!ready.isCompleted) ready.complete(null);
            });
            final emissions = <AsyncValue<Object?>>[];
            final keep = probe.container.listen(
              read.provider,
              (_, next) => emissions.add(next),
            );
            addTearDown(keep.close);
            final outcome = read
                .future(probe.container)
                .then<Object?>((v) => v, onError: (Object e) => e);
            await probe.entered.future;
            probe.container
                .read(probe.authority.notifier)
                .state = departure == 'absent identity'
                ? Future.value(null)
                : departure == 'permission loss'
                ? Future.value(
                    AdminIdentity(
                      userId: auth.actor,
                      displayName: 'Synthetic denied',
                      roles: ['admin'],
                      permissions: _identity.permissions
                          .where((v) => v != read.permission)
                          .toList(),
                    ),
                  )
                : ready.future;
            await probe.container.pump();
            if (departure == 'identity error') {
              final authorityOutcome = probe.container
                  .read(adminIdentityProvider.future)
                  .then<Object?>((v) => v, onError: (Object e) => e);
              ready.completeError(StateError('PRIVATE_CANARY'));
              expect(await authorityOutcome, isA<StateError>());
              await probe.container.pump();
            }
            probe.release!.complete();
            await probe.container.pump();
            expect(probe.requests, hasLength(1));
            expect(probe.container.read(read.provider).asData, isNull);
            expect(emissions.where((v) => v.asData != null), isEmpty);
            if (departure == 'identity loading') {
              expect(probe.container.read(read.provider).isLoading, isTrue);
              ready.complete(null);
              await probe.container.pump();
            }
            expect(await outcome, anyOf(isA<Exception>(), isA<StateError>()));
          },
        );
      }
    });
  }
}
