import 'dart:convert';

import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:collect_app/core/logging/app_logger.dart';
import 'package:collect_app/core/logging/collect_diagnostic_queue.dart';
import 'package:collect_app/core/logging/collect_member_diagnostics.dart';
import 'package:collect_app/core/supabase/collect_supabase_configuration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'supabase_backend_test.dart' as fixtures;

void main() {
  test(
    'member diagnostics uses only the existing configured authenticated transport',
    () async {
      final config = CollectSupabaseConfiguration.fromEnvironment(
        fixtures.environment(),
      );
      final requests = <http.Request>[];
      final client = CollectCloudflareClient(
        config.api.origin,
        supabaseConfiguration: config,
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response('{"contract_version":1,"accepted":true}', 202);
        }),
      );
      final store = _Store(),
          queue = CollectDiagnosticQueue(
            surface: CollectDiagnosticSurface.member,
            store: store,
            initialDelay: const Duration(days: 1),
          );
      final binding = CollectMemberDiagnostics(queue);
      addTearDown(binding.dispose);
      addTearDown(client.dispose);
      binding.bind(client);
      final diagnostics = CollectDiagnostics(
        surface: CollectDiagnosticSurface.member,
        environmentName: 'production',
        sink: queue.add,
      );
      diagnostics.record(CollectDiagnosticCode.frameworkFailure);
      expect(queue.pendingCount, 0);
      final session = fixtures.session();
      await client.auth.recoverSession(jsonEncode(session));
      await Future<void>.delayed(Duration.zero);
      diagnostics.record(CollectDiagnosticCode.frameworkFailure);
      await queue.flush();
      expect(requests, hasLength(1));
      expect(
        requests.single.url.path,
        '/functions/v1/collect-api/v1/diagnostics',
      );
      expect(
        requests.single.headers['authorization'],
        'Bearer ${session['access_token']}',
      );
      expect(requests.single.headers['apikey'], fixtures.publishable);
      expect(requests.single.followRedirects, isFalse);
      final body = requests.single.body;
      for (final forbidden in [
        session['access_token'] as String,
        session['refresh_token'] as String,
        fixtures.principal,
        '+250788000001',
      ]) {
        expect(body, isNot(contains(forbidden)));
        expect(store.value, isNot(contains(forbidden)));
      }
      expect(queue.pendingCount, 0);
    },
  );
}

class _Store implements CollectDiagnosticQueueStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? next) async {
    value = next;
  }
}
