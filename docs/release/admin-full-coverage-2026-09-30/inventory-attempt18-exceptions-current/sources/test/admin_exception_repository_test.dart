import 'dart:async';
import 'dart:convert';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/admin_exception_models.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_action_session_test.dart' as auth;
import 'admin_exception_models_test.dart' as fixture;

void main() {
  late SupabaseClient client;
  late AdminRepository repository;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;
  setUp(() async {
    requests = [];
    respond = (_) async => auth.response(fixture.exceptionFixture());
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
        final response = await respond(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
    await auth.session(client, 'exception-a');
    repository = AdminRepository(client);
  });
  tearDown(() => client.dispose());
  test(
    'actual SDK list uses current token exact filters paired UTC cursor and strict wire',
    () async {
      final raw = fixture.exceptionFixture('filtered');
      final source = AdminExceptionSource.parse(raw['source_kind']);
      final before = DateTime.utc(2026, 10, 2);
      respond = (_) async => auth.response(raw);
      await repository.exceptionInbox(
        limit: raw['limit'] as int,
        source: source,
        beforeChangedAt: before,
        beforeId: 'ffffffff-ffff-ffff-ffff-ffffffffffff',
      );
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/admin_list_operational_exceptions_v2',
      );
      expect(jsonDecode(requests.single.body), {
        'p_active': true,
        'p_limit': raw['limit'],
        'p_source_kind': source.wire,
        'p_before_changed_at': before.toIso8601String(),
        'p_before_id': 'ffffffff-ffff-ffff-ffff-ffffffffffff',
      });
      expect(
        requests.single.headers['Authorization'],
        'Bearer ${client.auth.currentSession!.accessToken}',
      );
    },
  );
  test('invalid limits cursor UUID and date avoid network', () async {
    for (final limit in [0, 51])
      await expectLater(
        repository.exceptionInbox(limit: limit),
        throwsFormatException,
      );
    await expectLater(
      repository.exceptionInbox(beforeChangedAt: DateTime.utc(2026)),
      throwsFormatException,
    );
    await expectLater(
      repository.exceptionInbox(beforeId: 'not-id'),
      throwsFormatException,
    );
    await expectLater(
      repository.exceptionInbox(
        beforeChangedAt: DateTime.utc(10000),
        beforeId: 'ffffffff-ffff-ffff-ffff-ffffffffffff',
      ),
      throwsFormatException,
    );
    await expectLater(
      repository.exceptionActionLookup('not-id'),
      throwsFormatException,
    );
    expect(requests, isEmpty);
  });
  test(
    'actual v1 action uses one exact nonretrying RPC and immutable receipt',
    () async {
      final raw = fixture.exceptionFixture('action-receipt');
      final intent = fixture.receiptIntent(raw);
      respond = (_) async => auth.response(raw);
      final receipt = await repository.exceptionAction(intent);
      expect(receipt.matches(intent), isTrue);
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/admin_act_operational_exception_v1',
      );
      expect(jsonDecode(requests.single.body), intent.parameters);
    },
  );
  test(
    'mismatched target and false source/delivery claims reject without retry',
    () async {
      final good = fixture.exceptionFixture('action-receipt');
      for (final raw in [
        {...good, 'revision': 2},
        {...good, 'send_action': true},
        {'ok': true},
      ]) {
        respond = (_) async => auth.response(raw);
        await expectLater(
          repository.exceptionAction(fixture.receiptIntent(good)),
          throwsFormatException,
        );
      }
      expect(requests, hasLength(3));
    },
  );
  test(
    '403 and uncertain503 mutations perform one call each without retry',
    () async {
      for (final code in [403, 503]) {
        respond = (_) async => auth.response({
          'code': code == 403 ? '42501' : 'unavailable',
          'message': 'PRIVATE_CANARY',
        }, code);
        await expectLater(
          repository.exceptionAction(
            fixture.receiptIntent(fixture.exceptionFixture('action-receipt')),
          ),
          throwsA(isA<PostgrestException>()),
        );
      }
      expect(requests, hasLength(2));
    },
  );
  test(
    'bounded authority_busy lookup stays distinct and is not retried',
    () async {
      respond = (_) async => auth.response({
        'code': '55P03',
        'message': 'operational_exception_authority_busy',
      }, 409);
      await expectLater(
        repository.exceptionActionLookup(
          fixture.exceptionFixture('action-receipt')['request_id'] as String,
        ),
        throwsA(
          isA<PostgrestException>().having(
            (error) => error.code,
            'code',
            '55P03',
          ),
        ),
      );
      expect(requests, hasLength(1));
    },
  );
  test(
    'lookup exact requested UUID is read-only and wrong target is rejected',
    () async {
      final raw = fixture.exceptionFixture('recorded-lookup');
      final id = raw['request_id'] as String;
      respond = (_) async => auth.response(raw);
      await repository.exceptionActionLookup(id);
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/admin_get_operational_exception_action_v2',
      );
      expect(jsonDecode(requests.single.body), {'p_request_id': id});
      raw['request_id'] = '00000000-0000-0000-0000-000000000000';
      await expectLater(
        repository.exceptionActionLookup(id),
        throwsFormatException,
      );
    },
  );
  for (final returnToOwner in [false, true]) {
    test(
      'pending old-session receipt suppressed through owner switch return=$returnToOwner',
      () async {
        final started = Completer<void>(), release = Completer<void>();
        final raw = fixture.exceptionFixture('action-receipt');
        respond = (_) async {
          started.complete();
          await release.future;
          return auth.response(raw);
        };
        final future = repository.exceptionAction(fixture.receiptIntent(raw));
        final expectation = expectLater(
          future,
          throwsA(isA<AdminSessionChanged>()),
        );
        await started.future;
        await auth.session(client, 'exception-b');
        if (returnToOwner) await auth.session(client, 'exception-a');
        release.complete();
        await expectation;
        expect(requests, hasLength(1));
      },
    );
  }
}
