import 'dart:async';
import 'dart:convert';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_action_session_test.dart' as auth;
import 'admin_receipt_cancel_models_test.dart' as fixture;

void main() {
  late SupabaseClient client;
  late AdminRepository repository;
  final requests = <http.Request>[];
  late Future<http.Response> Function(http.Request) respond;
  setUp(() async {
    requests.clear();
    respond = (_) async =>
        auth.response(fixture.cancelFixture('cancelled-action'));
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
    await auth.session(client, 'cancel-a');
    repository = AdminRepository(client);
  });
  tearDown(() => client.dispose());
  test(
    'actual SDK sends exact authenticated cancellation once and validates immutable receipt',
    () async {
      final intent = fixture.cancelIntent();
      await repository.cancelUnstartedReceipt(intent);
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/admin_cancel_unstarted_receipt_v1',
      );
      expect(jsonDecode(requests.single.body), intent.parameters);
      expect(
        requests.single.headers['Authorization'],
        'Bearer ${client.auth.currentSession!.accessToken}',
      );
    },
  );
  test(
    'actual SDK inspection and original lookup bind exact UUID without broad data fetch',
    () async {
      final inspection = fixture.cancelFixture(
        'preexisting-eligible-inspection',
      );
      respond = (_) async => auth.response(inspection);
      await repository.inspectUnstartedReceipt(
        inspection['outbox_id'] as String,
      );
      final lookup = fixture.cancelFixture('recorded-lookup');
      respond = (_) async => auth.response(lookup);
      await repository.unstartedReceiptAction(lookup['request_id'] as String);
      expect(jsonDecode(requests[0].body), {
        'p_outbox_id': inspection['outbox_id'],
      });
      expect(jsonDecode(requests[1].body), {
        'p_request_id': lookup['request_id'],
      });
    },
  );
  test('invalid UUID avoids all HTTP requests', () async {
    await expectLater(
      repository.inspectUnstartedReceipt('invalid'),
      throwsFormatException,
    );
    await expectLater(
      repository.unstartedReceiptAction('invalid'),
      throwsFormatException,
    );
    expect(requests, isEmpty);
  });
  for (final code in [403, 503]) {
    test('actual mutation HTTP $code performs no retry or fallback', () async {
      respond = (_) async => auth.response({
        'code': code == 403 ? '42501' : 'unavailable',
        'message': 'PRIVATE_CANARY',
      }, code);
      await expectLater(
        repository.cancelUnstartedReceipt(fixture.cancelIntent()),
        throwsA(isA<PostgrestException>()),
      );
      expect(requests, hasLength(1));
    });
  }
  test(
    'bounded busy original lookup discloses no receipt and does not retry',
    () async {
      respond = (_) async => auth.response({
        'code': '55P03',
        'message': 'receipt_action_authority_busy',
      }, 409);
      await expectLater(
        repository.unstartedReceiptAction(fixture.cancelIntent().requestId),
        throwsA(isA<PostgrestException>()),
      );
      expect(requests, hasLength(1));
    },
  );
  test(
    'malformed or mismatched action evidence stays unconfirmed after one request',
    () async {
      for (final raw in [
        <String, dynamic>{'ok': true},
        fixture.cancelFixture('cancelled-action')
          ..['reason_code'] = 'content_review_required',
      ]) {
        respond = (_) async => auth.response(raw);
        await expectLater(
          repository.cancelUnstartedReceipt(fixture.cancelIntent()),
          throwsFormatException,
        );
      }
      expect(requests, hasLength(2));
    },
  );
  for (final switchBack in [false, true]) {
    test(
      'departed real SDK session suppresses pending cancellation evidence switchBack=$switchBack',
      () async {
        final started = Completer<void>(), release = Completer<void>();
        respond = (_) async {
          started.complete();
          await release.future;
          return auth.response(fixture.cancelFixture('cancelled-action'));
        };
        final result = repository.cancelUnstartedReceipt(
          fixture.cancelIntent(),
        );
        final rejection = expectLater(
          result,
          throwsA(isA<AdminSessionChanged>()),
        );
        await started.future;
        await auth.session(client, 'cancel-b');
        if (switchBack) await auth.session(client, 'cancel-a', nonce: 2);
        release.complete();
        await rejection;
        expect(requests, hasLength(1));
      },
    );
  }
}
