import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Reuse the suite's real pinned SDK login fixtures; its main is not invoked.
import 'admin_action_session_test.dart' as auth;

Map<String, dynamic> _receipt() => {
  'ok': true,
  'action': 'health',
  'result': {
    'enabled': false,
    'queued': 0,
    'awaiting_confirmation': 0,
    'send_started': 0,
    'uncertain': 0,
    'suppressed': 0,
    'active_workers': 0,
    'oldest_queued_at': null,
    'observed_at': '2026-09-30T10:00:00Z',
  },
};

void main() {
  late SupabaseClient client;
  late AdminRepository repository;
  late Future<http.Response> Function(http.Request) respond;
  late List<http.Request> requests;
  setUp(() async {
    requests = [];
    respond = (_) async => auth.response(_receipt());
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
        return respond(request);
      }),
    );
    await auth.session(client, 'session-a');
    repository = AdminRepository(client);
  });
  tearDown(() => client.dispose());

  test(
    'queue health uses authenticated Edge health only and validates its envelope',
    () async {
      final data = await repository.smsQueueHealth();
      expect(data['enabled'], isFalse);
      expect(
        requests.single.url.path,
        '/functions/v1/collect-notification-operator',
      );
      expect(jsonDecode(requests.single.body), {'action': 'health'});
      expect(
        requests.single.headers['Authorization'],
        'Bearer ${client.auth.currentSession!.accessToken}',
      );
    },
  );

  for (final response in [
    {'ok': false, 'action': 'health', 'result': _receipt()['result']},
    {'ok': true, 'action': 'claim', 'result': _receipt()['result']},
    {..._receipt(), 'private': 'PRIVATE_CANARY'},
    {
      ..._receipt(),
      'result': {...(_receipt()['result'] as Map), 'uncertain': '0'},
    },
  ]) {
    test(
      'malformed queue response cannot become a healthy empty sample ${response['action']}/${response.keys.length}',
      () async {
        respond = (_) async => auth.response(response);
        await expectLater(repository.smsQueueHealth(), throwsFormatException);
      },
    );
  }

  test(
    'replacement same-user session suppresses a late valid queue response',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      respond = (_) async {
        started.complete();
        await release.future;
        return auth.response(_receipt());
      };
      final pending = repository.smsQueueHealth();
      final assertion = expectLater(
        pending,
        throwsA(isA<AdminSessionChanged>()),
      );
      await started.future;
      await auth.session(client, 'session-b');
      release.complete();
      await assertion;
    },
  );
}
