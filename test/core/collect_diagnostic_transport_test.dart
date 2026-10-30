import 'dart:async';
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
import '../admin/cloudflare_canonical_reconciliation_support.dart';

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

  test(
    'Admin telemetry uses BFF CSRF and an unauthorized reply does not clear app authentication',
    () async {
      final requests = <http.Request>[];
      var status = 202;
      final h = await FinancialHarness.create(
        auth: canonicalSupabaseFinancialSession(),
        environment: fixtures.environment(),
        origin: Uri.parse('https://admin.collect.ikanisa.com'),
        reply: (request) async {
          requests.add(request);
          return http.Response(
            status == 202
                ? '{"contract_version":1,"accepted":true}'
                : '{"error":"PRIVATE SYNTHETIC DETAIL"}',
            status,
          );
        },
      );
      final before = h.session.authorityFence;
      final body = <String, Object?>{
        'contract_version': 1,
        'reports': <Object?>[],
      };
      expect(
        await h.session.sendDiagnosticBatch(body, current: () => true),
        CollectDiagnosticDelivery.accepted,
      );
      expect(
        requests.single.url.path,
        '/functions/v1/admin-api/api/admin/diagnostics',
      );
      expect(requests.single.headers['x-collect-csrf'], 'a' * 64);
      expect(
        requests.single.headers['x-collect-requested-with'],
        'collect-admin',
      );
      expect(requests.single.headers.containsKey('authorization'), isFalse);
      status = 401;
      expect(
        await h.session.sendDiagnosticBatch(body, current: () => true),
        CollectDiagnosticDelivery.retry,
      );
      expect(h.session.authorityFence, before);
      expect(h.session.user, isNotNull);
    },
  );

  test(
    'Admin diagnostics rejects late acknowledgements after a session switch',
    () async {
      final gate = Completer<http.Response>(), started = Completer<void>();
      final h = await FinancialHarness.create(
        auth: canonicalSupabaseFinancialSession(),
        environment: fixtures.environment(),
        origin: Uri.parse('https://admin.collect.ikanisa.com'),
        reply: (request) {
          started.complete();
          return gate.future;
        },
      );
      final pending = h.session.sendDiagnosticBatch({
        'contract_version': 1,
        'reports': <Object?>[],
      }, current: () => true);
      await started.future;
      h.session.clear();
      gate.complete(
        http.Response('{"contract_version":1,"accepted":true}', 202),
      );
      expect(await pending, CollectDiagnosticDelivery.retry);
      expect(h.session.user, isNull);
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
