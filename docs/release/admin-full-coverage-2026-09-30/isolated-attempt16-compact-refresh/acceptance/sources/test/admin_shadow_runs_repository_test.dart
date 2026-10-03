import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_action_session_test.dart' as auth;

Map<String, dynamic> _history() =>
    jsonDecode(
          File(
            'contracts/collect-shadow-supervisor-v1.fixture.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

void main() {
  late SupabaseClient client;
  late AdminRepository repository;
  late Future<http.Response> Function(http.Request) respond;
  late List<http.Request> requests;
  setUp(() async {
    requests = [];
    respond = (_) async => auth.response(_history());
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
        return respond(request).then(
          (response) => http.Response.bytes(
            response.bodyBytes,
            response.statusCode,
            headers: response.headers,
            request: request,
          ),
        );
      }),
    );
    await auth.session(client, 'session-a');
    repository = AdminRepository(client);
  });
  tearDown(() => client.dispose());

  test(
    'history calls only the pinned authenticated read with paired cursor',
    () async {
      final before = DateTime.utc(2026, 10, 1);
      const id = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
      final data = await repository.shadowRuns(
        limit: 10,
        beforeStartedAt: before,
        beforeRunId: id,
      );
      expect(data['scope'], 'collect_platform');
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/list_collect_shadow_runs_v1',
      );
      expect(jsonDecode(requests.single.body), {
        'p_limit': 10,
        'p_before_started_at': before.toIso8601String(),
        'p_before_run_id': id,
      });
      expect(
        requests.single.headers['Authorization'],
        'Bearer ${client.auth.currentSession!.accessToken}',
      );
    },
  );

  test(
    'invalid window or unmatched cursor never reaches the service',
    () async {
      for (final limit in [0, 51]) {
        await expectLater(
          repository.shadowRuns(limit: limit),
          throwsRangeError,
        );
      }
      await expectLater(
        repository.shadowRuns(beforeStartedAt: DateTime.utc(2026)),
        throwsFormatException,
      );
      await expectLater(
        repository.shadowRuns(
          beforeRunId: '11111111-1111-4111-8111-111111111111',
        ),
        throwsFormatException,
      );
      await expectLater(
        repository.shadowRuns(
          beforeStartedAt: DateTime.utc(2026),
          beforeRunId: 'bad',
        ),
        throwsFormatException,
      );
      expect(requests, isEmpty);
    },
  );

  for (final corruption in ['extra', 'mutation', 'checks', 'completion']) {
    test(
      'corrupt $corruption history fails without retry or synthetic fallback',
      () async {
        final data = _history();
        final row = (data['rows'] as List).single as Map<String, dynamic>;
        final summary = row['summary'] as Map<String, dynamic>;
        switch (corruption) {
          case 'extra':
            data['private_diagnostic'] = 'PRIVATE_CANARY';
          case 'mutation':
            summary['business_mutations'] = 1;
          case 'checks':
            summary['checks_recorded'] = 12;
          case 'completion':
            row['completed_at'] = null;
        }
        respond = (_) async => auth.response(data);
        await expectLater(repository.shadowRuns(), throwsFormatException);
        expect(requests, hasLength(1));
      },
    );
  }

  test(
    'replacement same-user session suppresses an old history response',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      respond = (_) async {
        started.complete();
        await release.future;
        return auth.response(_history());
      };
      final result = repository.shadowRuns();
      final check = expectLater(result, throwsA(isA<AdminSessionChanged>()));
      await started.future;
      await auth.session(client, 'session-b');
      release.complete();
      await check;
      expect(requests, hasLength(1));
    },
  );

  test(
    'serialization rejection is propagated without fallback or retry',
    () async {
      respond = (_) async => http.Response(
        jsonEncode({'code': '40001', 'message': 'shadow_snapshot_retry'}),
        409,
        headers: {'Content-Type': 'application/json'},
      );
      await expectLater(
        repository.shadowRuns(),
        throwsA(isA<PostgrestException>()),
      );
      expect(requests, hasLength(1));
    },
  );
}
