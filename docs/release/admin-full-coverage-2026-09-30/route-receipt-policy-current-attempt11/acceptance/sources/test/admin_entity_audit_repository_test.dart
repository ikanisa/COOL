import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_entity_audit.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_action_session_test.dart' as auth;
import 'support/admin_entity_audit_fixture.dart';

void main() {
  late SupabaseClient client;
  late AdminRepository repository;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;
  setUp(() async {
    requests = [];
    respond = (_) async => auth.response(auditObserved());
    client = SupabaseClient(
      'https://synthetic.invalid',
      'synthetic-publishable',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/verify')) {
          final token = (jsonDecode(request.body)['token'] as String).split(
            '|',
          );
          return auth.response(auth.authReceipt(token[0], token[1]));
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
    await auth.session(client, 'audit-session-a');
    repository = AdminRepository(client);
  });
  tearDown(() => client.dispose());

  for (final name in [
    'shadow',
    'expiry',
    'gateway',
    'supervisor',
    'exception',
    'receipt',
  ]) {
    test(
      'real pinned SDK reads actual $name observation through one fixed RPC',
      () async {
        final raw = auditObserved(name),
            query = auditQuery(auditObserved(name));
        respond = (_) async => auth.response(raw);
        expect(await repository.operatorEntityAudit(query), raw);
        expect(requests, hasLength(1));
        expect(
          requests.single.url.path,
          '/rest/v1/rpc/admin_get_operator_entity_audit_v1',
        );
        expect(jsonDecode(requests.single.body), {
          'p_entity_kind': query.kind.wire,
          'p_entity_id': query.id,
          'p_limit': 20,
          'p_before_at': null,
          'p_before_event_id': null,
        });
        expect(
          requests.single.headers['Authorization'],
          'Bearer ${client.auth.currentSession!.accessToken}',
        );
      },
    );
  }
  test(
    'real SDK preserves paired cursor binding and does not scan another entity',
    () async {
      final raw = auditObserved(),
          firstQuery = auditQuery(auditObserved(), limit: 1);
      final first = AdminEntityAuditSnapshot.parse(
        auditWindow(raw, firstQuery),
        query: firstQuery,
      );
      final query = auditQuery(raw, limit: 1, before: first.nextCursor);
      respond = (_) async => auth.response(auditWindow(raw, query));
      await repository.operatorEntityAudit(query);
      expect(jsonDecode(requests.single.body), {
        'p_entity_kind': query.kind.wire,
        'p_entity_id': query.id,
        'p_limit': 1,
        'p_before_at': first.nextCursor!.recordedAt.toIso8601String(),
        'p_before_event_id': first.nextCursor!.eventId,
      });
    },
  );
  test(
    'invalid query bounds IDs and cursor fail before any HTTP request',
    () async {
      final query = auditQuery(auditObserved());
      final invalid = [
        AdminEntityAuditQuery(kind: query.kind, id: query.id, limit: 0),
        AdminEntityAuditQuery(kind: query.kind, id: query.id, limit: 51),
        AdminEntityAuditQuery(kind: query.kind, id: 'bad'),
        AdminEntityAuditQuery(
          kind: query.kind,
          id: query.id,
          before: AdminEntityAuditCursor(
            recordedAt: DateTime.utc(10000),
            eventId: query.id,
          ),
        ),
        AdminEntityAuditQuery(
          kind: query.kind,
          id: query.id,
          before: AdminEntityAuditCursor(
            recordedAt: DateTime.utc(2026),
            eventId: 'bad',
          ),
        ),
      ];
      for (final value in invalid) {
        await expectLater(
          repository.operatorEntityAudit(value),
          throwsFormatException,
        );
      }
      expect(requests, isEmpty);
    },
  );
  for (final status in [403, 500, 503]) {
    test(
      'HTTP$status is never automatically retried or turned into empty history',
      () async {
        respond = (_) async => auth.response({
          'code': status == 403 ? '42501' : 'XX000',
          'message': 'PRIVATE_CANARY +250788000000',
        }, status);
        await expectLater(
          repository.operatorEntityAudit(auditQuery(auditObserved())),
          throwsA(isA<PostgrestException>()),
        );
        expect(requests, hasLength(1));
      },
    );
  }
  test(
    'malformed successful server evidence fails without fallback or another read',
    () async {
      final raw = auditObserved()..['history_complete'] = true;
      respond = (_) async => auth.response(raw);
      await expectLater(
        repository.operatorEntityAudit(auditQuery(auditObserved())),
        throwsFormatException,
      );
      expect(requests, hasLength(1));
    },
  );
  for (final switchBack in [false, true]) {
    test(
      'sticky real SDK session fence suppresses old audit result; switchBack=$switchBack',
      () async {
        final started = Completer<void>(), release = Completer<void>();
        respond = (_) async {
          started.complete();
          await release.future;
          return auth.response(auditObserved());
        };
        final pending = repository.operatorEntityAudit(
          auditQuery(auditObserved()),
        );
        final assertion = expectLater(
          pending,
          throwsA(isA<AdminSessionChanged>()),
        );
        await started.future;
        final token = requests.single.headers['Authorization'];
        await auth.session(client, 'audit-session-b');
        if (switchBack) await auth.session(client, 'audit-session-a', nonce: 1);
        release.complete();
        await assertion;
        expect(requests, hasLength(1));
        expect(requests.single.headers['Authorization'], token);
      },
    );
  }
  test(
    'same-session token refresh preserves the exact token of the original read',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      respond = (_) async {
        started.complete();
        await release.future;
        return auth.response(auditObserved());
      };
      final pending = repository.operatorEntityAudit(
        auditQuery(auditObserved()),
      );
      await started.future;
      final token = requests.single.headers['Authorization'];
      await auth.session(client, 'audit-session-a', nonce: 1);
      release.complete();
      await pending;
      expect(requests, hasLength(1));
      expect(requests.single.headers['Authorization'], token);
      expect(token, isNot('Bearer ${client.auth.currentSession!.accessToken}'));
    },
  );
  test(
    'departed provider or missing session cannot expose data or start HTTP',
    () async {
      repository = AdminRepository(client, isCurrent: () => false);
      await expectLater(
        repository.operatorEntityAudit(auditQuery(auditObserved())),
        throwsA(isA<AdminSessionChanged>()),
      );
      expect(requests, isEmpty);
      await client.auth.signOut();
      repository = AdminRepository(client);
      await expectLater(
        repository.operatorEntityAudit(auditQuery(auditObserved())),
        throwsA(isA<AdminSessionChanged>()),
      );
      expect(requests, isEmpty);
    },
  );
}
