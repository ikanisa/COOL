import 'dart:async';
import 'dart:convert';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_exception_workflow_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_action_session_test.dart' as auth;
import 'admin_exception_workflow_test.dart' as evidence;

void main() {
  late SupabaseClient client;
  late AdminRepository repository;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;
  final raw = evidence.observed('workflow');
  final id = raw['exception_id'] as String;
  final now = DateTime.parse(raw['checked_at'] as String);
  final intent = AdminExceptionWorkflowIntent(
    requestId: '11111111-1111-4111-8111-111111111111',
    exceptionId: id,
    sourceRevision: raw['source_revision'] as int,
    workflowRevision: raw['workflow_revision'] as int,
    action: 'resolve',
    expiresAt: now.add(const Duration(seconds: 90)),
  );
  final receipt = {
    'contract_version': 1,
    'request_id': intent.requestId,
    'exception_id': id,
    'source_revision': intent.sourceRevision,
    'workflow_revision': intent.workflowRevision + 1,
    'action': 'resolve',
    'escalation_id': null,
    'source_resolved': true,
    'financial_action': false,
    'send_action': false,
    'recorded_at': evidence.wire(now),
  };
  setUp(() async {
    requests = [];
    respond = (_) async => auth.response(raw);
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
    await auth.session(client, 'workflow-a');
    repository = AdminRepository(client);
  });
  tearDown(() => client.dispose());
  test(
    'actual SDK reads strict workflow with current session header',
    () async {
      await repository.exceptionWorkflow(id);
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/admin_get_exception_workflow_v1',
      );
      expect(jsonDecode(requests.single.body), {'p_exception_id': id});
      expect(
        requests.single.headers['Authorization'],
        'Bearer ${client.auth.currentSession!.accessToken}',
      );
    },
  );
  test(
    'actual SDK binds expiring action to exact source and workflow revisions',
    () async {
      respond = (_) async => auth.response(receipt);
      await repository.exceptionWorkflowAction(intent);
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/admin_act_exception_workflow_v1',
      );
      expect(jsonDecode(requests.single.body), intent.parameters);
    },
  );
  test(
    'denial and uncertain server response each perform one mutation attempt',
    () async {
      for (final status in [403, 503]) {
        respond = (_) async => auth.response({
          'code': status == 403 ? '42501' : 'unavailable',
          'message': 'PRIVATE_CANARY',
        }, status);
        await expectLater(
          repository.exceptionWorkflowAction(intent),
          throwsA(isA<PostgrestException>()),
        );
      }
      expect(requests.length, 2);
    },
  );
  test(
    'false send and mismatched receipt claims reject without retry',
    () async {
      for (final invalid in [
        {...receipt, 'send_action': true},
        {...receipt, 'source_revision': 1},
        {'ok': true},
      ]) {
        respond = (_) async => auth.response(invalid);
        await expectLater(
          repository.exceptionWorkflowAction(intent),
          throwsFormatException,
        );
      }
      expect(requests.length, 3);
    },
  );
  test(
    'session replacement suppresses a pending old action response',
    () async {
      final held = Completer<http.Response>();
      final started = Completer<void>();
      respond = (_) {
        started.complete();
        return held.future;
      };
      final pending = repository.exceptionWorkflowAction(intent);
      final assertion = expectLater(
        pending,
        throwsA(isA<AdminSessionChanged>()),
      );
      await started.future;
      await auth.session(client, 'workflow-b');
      held.complete(auth.response(receipt));
      await assertion;
      expect(requests.length, 1);
    },
  );
  test(
    'request lookup is a single read and never replays original action',
    () async {
      respond = (_) async => auth.response({
        'contract_version': 1,
        'request_id': intent.requestId,
        'checked_at': evidence.wire(now),
        'sample_valid_until': evidence.wire(
          now.add(const Duration(seconds: 60)),
        ),
        'status': 'recorded',
        'receipt': receipt,
      });
      final result = await repository.exceptionWorkflowRequest(
        intent.requestId,
      );
      expect(
        AdminExceptionWorkflowLookup.parse(result, intent).status,
        'recorded',
      );
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/admin_get_exception_workflow_request_v1',
      );
      expect(jsonDecode(requests.single.body), {
        'p_request_id': intent.requestId,
      });
    },
  );
}
