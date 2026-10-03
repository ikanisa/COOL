import 'dart:async';
import 'dart:convert';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_exception_escalation_inbox_v2_models.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/admin_exception_history_v2_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_action_session_test.dart' as auth;
import 'admin_exception_history_v2_models_test.dart' as history;
import 'admin_exception_escalation_inbox_v2_models_test.dart' as inbox;

void main() {
  late SupabaseClient client;
  late AdminRepository repository;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;
  final query = history.historyQuery();
  const inboxQuery = AdminExceptionEscalationInboxQuery();
  final row = inbox.inboxRow(1),
      id = inbox.inboxRow(1)['escalation_id'] as String;
  final historyRaw = history.historyFixture(),
      inboxRaw = inbox.inboxWindow(inbox.inboxFixture(), inboxQuery);
  final ack = {
    'contract_version': 2,
    'escalation_id': id,
    'read_at': '2026-10-01T19:30:00.000000Z',
    'source_resolved': false,
  };
  final operations = <String, Future<Map<String, dynamic>> Function()>{
    'admin_get_exception_entity_audit_v2': () =>
        repository.exceptionEntityAudit(query),
    'admin_list_exception_escalation_inbox_v2': () =>
        repository.exceptionEscalationInboxPage(inboxQuery),
    'admin_read_exception_escalation_v2': () =>
        repository.readExceptionEscalationCurrent(id),
  };
  final responses = {
    'admin_get_exception_entity_audit_v2': historyRaw,
    'admin_list_exception_escalation_inbox_v2': inboxRaw,
    'admin_read_exception_escalation_v2': ack,
  };
  setUp(() async {
    requests = [];
    respond = (_) async => auth.response(historyRaw);
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
        final response = await respond(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
    await auth.session(client, 'history-a');
    repository = AdminRepository(client);
  });
  tearDown(() => client.dispose());
  for (final entry in operations.entries) {
    test('${entry.key} pinned SDK exactRPC currentBearer oneattempt', () async {
      respond = (_) async => auth.response(responses[entry.key]);
      await entry.value();
      expect(requests.single.url.path, '/rest/v1/rpc/${entry.key}');
      expect(
        requests.single.headers['Authorization'],
        'Bearer ${client.auth.currentSession!.accessToken}',
      );
      expect(
        jsonDecode(requests.single.body),
        entry.key == 'admin_get_exception_entity_audit_v2'
            ? {
                'p_exception_id': query.id,
                'p_limit': 20,
                'p_before_at': null,
                'p_before_event_id': null,
              }
            : entry.key == 'admin_list_exception_escalation_inbox_v2'
            ? inboxQuery.parameters
            : {'p_escalation_id': id},
      );
    });
    for (final status in [403, 500, 503]) {
      test(
        '${entry.key} HTTP$status never retries or fabricates empty evidence',
        () async {
          respond = (_) async => auth.response({
            'code': status == 403 ? '42501' : 'XX000',
            'message': 'PRIVATE_CANARY',
          }, status);
          await expectLater(entry.value(), throwsA(isA<PostgrestException>()));
          expect(requests, hasLength(1));
        },
      );
    }
    test(
      '${entry.key} private or wrongcontract successful body is rejected once',
      () async {
        for (final bad in [
          {'ok': true},
          {...responses[entry.key]!, 'destination': 'PRIVATE_CANARY'},
          {...responses[entry.key]!, 'contract_version': 1},
        ]) {
          respond = (_) async => auth.response(bad);
          await expectLater(entry.value(), throwsFormatException);
        }
        expect(requests, hasLength(3));
      },
    );
    for (final back in [false, true]) {
      test(
        '${entry.key} sticky SDK session departure back=$back suppresses oldresponse',
        () async {
          final held = Completer<http.Response>(), started = Completer<void>();
          respond = (_) {
            started.complete();
            return held.future;
          };
          final assertion = expectLater(
            entry.value(),
            throwsA(isA<AdminSessionChanged>()),
          );
          await started.future;
          await auth.session(client, 'history-b');
          if (back) {
            await auth.session(client, 'history-a', nonce: 2);
          }
          held.complete(auth.response(responses[entry.key]));
          await assertion;
          expect(requests, hasLength(1));
        },
      );
    }
    test('${entry.key} signedout caller dispatches zero RPCs', () async {
      await client.auth.signOut();
      await expectLater(entry.value(), throwsA(isA<AdminSessionChanged>()));
      expect(requests, isEmpty);
    });
    testWidgets('${entry.key} bounded15s timeout keeps one original attempt', (
      tester,
    ) async {
      final held = Completer<http.Response>();
      respond = (_) => held.future;
      final assertion = expectLater(
        entry.value(),
        throwsA(isA<TimeoutException>()),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(seconds: 14));
      expect(requests, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      await assertion;
      held.complete(auth.response(responses[entry.key]));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(requests, hasLength(1));
    });
  }
  test(
    'audit and inbox paired cursors are exact independent windows',
    () async {
      final firstQuery = history.historyQuery(limit: 3);
      final first = history.historyWindow(historyRaw, firstQuery);
      final parsed = AdminExceptionHistorySnapshot.parse(
        first,
        query: firstQuery,
      );
      final nextQuery = history.historyQuery(
        limit: 3,
        before: parsed.nextCursor,
      );
      respond = (_) async =>
          auth.response(history.historyWindow(historyRaw, nextQuery));
      await repository.exceptionEntityAudit(nextQuery);
      expect(jsonDecode(requests.single.body), {
        'p_exception_id': query.id,
        'p_limit': 3,
        'p_before_at': '2026-10-01T19:00:00.000000Z',
        'p_before_event_id': parsed.nextCursor!.eventId,
      });
      final firstInbox = AdminExceptionEscalationInboxSnapshot.parse(
        inboxRaw,
        query: inboxQuery,
        recipientId: auth.actor,
      );
      final nextInbox = AdminExceptionEscalationInboxQuery(
        before: firstInbox.nextCursor,
      );
      respond = (_) async =>
          auth.response(inbox.inboxWindow(inbox.inboxFixture(), nextInbox));
      await repository.exceptionEscalationInboxPage(nextInbox);
      expect(jsonDecode(requests.last.body), nextInbox.parameters);
      expect(requests, hasLength(2));
    },
  );
  test(
    'wrong exception recipient or original escalation identity is refused',
    () async {
      for (final name in operations.keys) {
        final bad = {...responses[name]!};
        bad[name == 'admin_get_exception_entity_audit_v2'
                ? 'entity_id'
                : name == 'admin_list_exception_escalation_inbox_v2'
                ? 'recipient_id'
                : 'escalation_id'] =
            history.historyEscalationId;
        respond = (_) async => auth.response(bad);
        await expectLater(operations[name]!(), throwsFormatException);
      }
      expect(requests, hasLength(3));
      expect(row['delivered_at'], '2026-10-01T19:00:00.000000Z');
    },
  );
  test(
    'invalid query kind IDs limit or cursor fails before SDK dispatch',
    () async {
      await expectLater(
        repository.exceptionEntityAudit(history.historyQuery(limit: 26)),
        throwsFormatException,
      );
      await expectLater(
        repository.exceptionEscalationInboxPage(
          const AdminExceptionEscalationInboxQuery(limit: 26),
        ),
        throwsFormatException,
      );
      await expectLater(
        repository.readExceptionEscalationCurrent('PRIVATE_UUID'),
        throwsFormatException,
      );
      expect(requests, isEmpty);
    },
  );
}
