import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_exception_followup_v2_models.dart';
import 'package:collect_app/admin/core/admin_exception_workflow_models.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_action_session_test.dart' as auth;

Map<String, dynamic> _sql(String name) => Map<String, dynamic>.from(
  jsonDecode(
        File(
          'scripts/tests/fixtures/exception_followup_v2/observed-$name.json',
        ).readAsStringSync(),
      )
      as Map,
);
AdminExceptionWorkflowIntent _intent() {
  final row = _sql('assignment-binding');
  return AdminExceptionWorkflowIntent.parse({
    'p_request_id': row['request_id'],
    'p_exception_id': row['exception_id'],
    'p_expected_source_revision': row['source_revision'],
    'p_expected_workflow_revision': row['workflow_revision'],
    'p_action': row['action'],
    'p_assignee_id': row['assignee_id'],
    'p_due_at': row['due_at'],
    'p_reason_code': row['reason_code'],
    'p_expires_at': row['expires_at'],
  });
}

void main() {
  late SupabaseClient client;
  late AdminRepository repository;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;
  final intent = _intent();
  final original = AdminExceptionFollowupReference.fromIntent(intent);
  const query = AdminExceptionFollowupDirectoryQuery();
  final directory = _sql('directory-first');
  final receipt = _sql('assignment-receipt');
  final lookup = _sql('recorded-lookup');
  final operations = <String, Future<Map<String, dynamic>> Function()>{
    'directory': () => repository.exceptionFollowupOperators(query),
    'action': () => repository.exceptionFollowupAction(intent),
    'lookup': () => repository.exceptionFollowupRequest(original),
  };
  final responses = {
    'directory': directory,
    'action': receipt,
    'lookup': lookup,
  };
  setUp(() async {
    requests = [];
    respond = (_) async => auth.response(directory);
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
    await auth.session(client, 'followup-a');
    repository = AdminRepository(client);
  });
  tearDown(() => client.dispose());

  test(
    'actual SDK directory uses exact RPC Bearer and paired keyset from SQL',
    () async {
      await operations['directory']!();
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/admin_list_exception_followup_operators_v2',
      );
      expect(jsonDecode(requests.single.body), query.parameters);
      expect(
        requests.single.headers['Authorization'],
        'Bearer ${client.auth.currentSession!.accessToken}',
      );
      final parsed = AdminExceptionFollowupDirectory.parse(
        directory,
        query: query,
      );
      final next = AdminExceptionFollowupDirectoryQuery(
        before: parsed.nextCursor,
      );
      respond = (_) async => auth.response(_sql('directory-last'));
      await repository.exceptionFollowupOperators(next);
      expect(jsonDecode(requests.last.body), next.parameters);
      expect(requests, hasLength(2));
    },
  );
  test('actual SDK v2 mutation submits nine reviewed arguments once', () async {
    respond = (_) async => auth.response(receipt);
    await operations['action']!();
    expect(
      requests.single.url.path,
      '/rest/v1/rpc/admin_act_exception_workflow_v2',
    );
    expect(jsonDecode(requests.single.body), intent.parameters);
    expect(
      requests.single.headers['Authorization'],
      'Bearer ${client.auth.currentSession!.accessToken}',
    );
  });
  test(
    'actual SDK original lookup sends UUID fingerprint expiry without action reconstruction',
    () async {
      respond = (_) async => auth.response(lookup);
      await operations['lookup']!();
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/admin_get_exception_workflow_request_v2',
      );
      expect(jsonDecode(requests.single.body), original.lookupParameters);
      expect(jsonDecode(requests.single.body), hasLength(3));
      expect(requests.single.body, isNot(contains('p_assignee_id')));
      expect(
        requests.single.headers['Authorization'],
        'Bearer ${client.auth.currentSession!.accessToken}',
      );
    },
  );
  for (final name in operations.keys) {
    for (final status in [403, 503]) {
      test(
        '$name HTTP$status makes one attempt with no automatic retry',
        () async {
          respond = (_) async => auth.response({
            'code': '42501',
            'message': 'PRIVATE_CANARY',
          }, status);
          await expectLater(
            operations[name]!(),
            throwsA(isA<PostgrestException>()),
          );
          expect(requests, hasLength(1));
        },
      );
    }
    test(
      '$name malformed or private successful payload fails closed without retry',
      () async {
        for (final bad in [
          <String, dynamic>{'ok': true},
          {...responses[name]!, 'authorization': 'PRIVATE_CANARY'},
        ]) {
          respond = (_) async => auth.response(bad);
          await expectLater(operations[name]!(), throwsFormatException);
        }
        expect(requests, hasLength(2));
      },
    );
    test('$name signed-out caller dispatches no HTTP request', () async {
      await client.auth.signOut();
      await expectLater(
        operations[name]!(),
        throwsA(isA<AdminSessionChanged>()),
      );
      expect(requests, isEmpty);
    });
    testWidgets('$name times out at15seconds with one original HTTP request', (
      tester,
    ) async {
      final held = Completer<http.Response>();
      respond = (_) => held.future;
      final assertion = expectLater(
        operations[name]!(),
        throwsA(isA<TimeoutException>()),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(seconds: 14));
      expect(requests, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      await assertion;
      held.complete(auth.response(responses[name]));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(requests, hasLength(1));
    });
  }
  test(
    'actual SDK binds both mutation ACK and lookup to original fingerprint and expiry',
    () async {
      for (final bad in [
        {...receipt, 'request_fingerprint': 'a' * 64},
        {...receipt, 'request_id': auth.target},
        {...receipt, 'send_action': true},
      ]) {
        respond = (_) async => auth.response(bad);
        await expectLater(operations['action']!(), throwsFormatException);
      }
      for (final bad in [
        {...lookup, 'request_fingerprint': 'a' * 64},
        {...lookup, 'request_id': auth.target},
        {...lookup, 'expires_at': '2026-10-01T14:51:21.686685Z'},
      ]) {
        respond = (_) async => auth.response(bad);
        await expectLater(operations['lookup']!(), throwsFormatException);
      }
      expect(requests, hasLength(6));
    },
  );
  test('out-of-domain full intent fails before actual SDK dispatch', () async {
    for (final invalid in [
      AdminExceptionWorkflowIntent(
        requestId: intent.requestId,
        exceptionId: intent.exceptionId,
        sourceRevision: intent.sourceRevision,
        workflowRevision: 1000000000,
        action: intent.action,
        assigneeId: intent.assigneeId,
        dueAt: intent.dueAt,
        expiresAt: intent.expiresAt,
      ),
      AdminExceptionWorkflowIntent(
        requestId: intent.requestId,
        exceptionId: intent.exceptionId,
        sourceRevision: intent.sourceRevision,
        workflowRevision: intent.workflowRevision,
        action: intent.action,
        assigneeId: intent.assigneeId,
        dueAt: DateTime.utc(0),
        expiresAt: intent.expiresAt,
      ),
    ]) {
      await expectLater(
        repository.exceptionFollowupAction(invalid),
        throwsFormatException,
      );
    }
    expect(requests, isEmpty);
  });
  for (final change in ['replacement', 'logout']) {
    test('$change suppresses late SDK original action response', () async {
      final held = Completer<http.Response>(), started = Completer<void>();
      respond = (_) {
        started.complete();
        return held.future;
      };
      final assertion = expectLater(
        operations['action']!(),
        throwsA(isA<AdminSessionChanged>()),
      );
      await started.future;
      if (change == 'logout') {
        await client.auth.signOut();
      } else {
        await auth.session(client, 'followup-b');
      }
      held.complete(auth.response(receipt));
      await assertion;
      expect(requests, hasLength(1));
    });
  }
  test(
    'sticky opening scope suppresses A-B-A session despite restored identity',
    () async {
      var current = true;
      repository = AdminRepository(client, isCurrent: () => current);
      final held = Completer<http.Response>(), started = Completer<void>();
      respond = (_) {
        started.complete();
        return held.future;
      };
      final assertion = expectLater(
        operations['lookup']!(),
        throwsA(isA<AdminSessionChanged>()),
      );
      await started.future;
      current = false;
      await auth.session(client, 'followup-b');
      await auth.session(client, 'followup-a');
      held.complete(auth.response(lookup));
      await assertion;
      expect(requests, hasLength(1));
    },
  );
}
