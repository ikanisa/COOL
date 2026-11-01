import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/core/cloudflare_sms_oversight.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/legacy_backend_fixture.dart';

Map<String, dynamic> receipt({String? checked}) => {
  'contract_version': 1,
  'scope': 'admin_operational_health',
  'metrics_scope': 'all_retained_rows',
  'worker_heartbeat': 'not_recorded',
  'external_services_checked': false,
  'checked_at': checked ?? DateTime.now().toUtc().toIso8601String(),
  'queues': {
    'assisted_sms': {
      'queued': 3,
      'claimed': 2,
      'expired_claim': 0,
      'send_started': 1,
      'observed_sent': 4,
      'failed_no_send': 0,
      'uncertain': 1,
      'oldest_queued_seconds': 15,
      'oldest_unobserved_send_seconds': 4,
      'last_created_at': null,
      'automatic_retry': false,
    },
  },
};

Map<String, dynamic> sessionBody({
  List<String> permissions = const ['system_health.read'],
}) => {
  'user': {
    'id': '00000000-0000-4000-8000-000000000001',
    'email': 'owner@example.test',
    'role': 'owner',
    'sessionId': 'public-session-one',
    'permissions': permissions,
  },
  'expiresAt': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
};

void main() {
  test('accepts measured counts and never infers a heartbeat or gate', () {
    final sample = CloudflareSmsOversight.parse(receipt());
    expect(sample.counts, {
      'queued': 3,
      'claimed': 2,
      'send_started': 1,
      'uncertain': 1,
    });
    expect(sample.isFresh(DateTime.now()), isTrue);
    expect(
      sample.isFresh(DateTime.now().add(const Duration(minutes: 2))),
      isFalse,
    );
  });

  test('malformed or unsupported observations fail closed', () {
    for (final candidate in [
      {...receipt(), 'worker_heartbeat': 'active'},
      {...receipt(), 'external_services_checked': true},
      {...receipt(), 'checked_at': '2026-02-30T12:00:00Z'},
      {
        ...receipt(),
        'queues': {
          'assisted_sms': {'queued': 0},
        },
      },
      {
        ...receipt(),
        'queues': {
          'assisted_sms': {
            'queued': -1,
            'claimed': 0,
            'send_started': 0,
            'uncertain': 0,
            'automatic_retry': false,
          },
        },
      },
      {
        ...receipt(),
        'queues': {
          'assisted_sms': {
            'queued': 0,
            'claimed': 0,
            'send_started': 0,
            'uncertain': 0,
            'automatic_retry': true,
          },
        },
      },
    ]) {
      expect(
        () => CloudflareSmsOversight.parse(candidate),
        throwsFormatException,
      );
    }
  });

  test(
    'reads only through authenticated account oversight and fails on denial',
    () async {
      var status = 200;
      final requests = <http.Request>[];
      final session = CloudflareAdminSession(
        MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/auth/session')) {
            return http.Response(jsonEncode(sessionBody()), 200);
          }
          return status == 200
              ? http.Response(jsonEncode(receipt()), status)
              : http.Response(
                  '{"error":{"code":"permission_required"}}',
                  status,
                );
        }),
        origin: Uri.parse('https://admin.example.test/'),
        environment: legacyBackendFixtureEnvironment,
      );
      addTearDown(session.dispose);
      await session.refresh();
      expect((await readCloudflareSmsOversight(session)).counts['queued'], 3);
      expect(requests.last.method, 'GET');
      expect(requests.last.url.path, '/api/admin/oversight/health');
      status = 403;
      await expectLater(
        readCloudflareSmsOversight(session),
        throwsA(isA<CloudflareAdminRequestException>()),
      );
      status = 501;
      await expectLater(
        readCloudflareSmsOversight(session),
        throwsA(isA<CloudflareAdminRequestException>()),
      );
      status = 401;
      await expectLater(
        readCloudflareSmsOversight(session),
        throwsA(isA<CloudflareAdminRequestException>()),
      );
      expect(session.user, isNull);
    },
  );

  test('managed Supabase uses the configured account API route', () async {
    final requests = <http.Request>[];
    const environment = AppEnv(
      apiUrl: '',
      publicUrl: '',
      adminAppUrl: '',
      enableSmsReader: false,
      enableAndroidSmsAccess: true,
      enableAdminPanel: true,
      enableAdminDevTools: false,
      authCaptchaEnabled: false,
      authCaptchaProvider: '',
      authCaptchaSiteKey: '',
      backend: 'supabase',
      supabaseUrl: 'https://project.example.test',
      supabaseAdminApiUrl: 'https://admin.example.test',
      supabasePublishableKey: 'sb_publishable_syntheticfixture',
    );
    final session = CloudflareAdminSession(
      MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/auth/session')) {
          return http.Response(jsonEncode(sessionBody()), 200);
        }
        if (request.url.path.endsWith('/auth/email-verification')) {
          return http.Response('{"error":{"code":"unavailable"}}', 503);
        }
        return http.Response(jsonEncode(receipt()), 200);
      }),
      origin: Uri.parse('https://admin.example.test/'),
      environment: environment,
    );
    addTearDown(session.dispose);
    await session.refresh();
    expect((await readCloudflareSmsOversight(session)).counts['queued'], 3);
    expect(
      requests.last.url.path,
      '/functions/v1/admin-api/api/admin/oversight/health',
    );
    expect(requests.last.headers['apikey'], 'sb_publishable_syntheticfixture');
  });

  test('local permission denial avoids the health request', () async {
    var calls = 0;
    final session = CloudflareAdminSession(
      MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode(sessionBody(permissions: ['notifications.read'])),
          200,
        );
      }),
      origin: Uri.parse('https://admin.example.test/'),
      environment: legacyBackendFixtureEnvironment,
    );
    addTearDown(session.dispose);
    await session.refresh();
    await expectLater(
      readCloudflareSmsOversight(session),
      throwsA(isA<AdminAccountException>()),
    );
    expect(calls, 1);
  });

  test('session change rejects a late oversight response', () async {
    final pending = Completer<http.Response>();
    final session = CloudflareAdminSession(
      MockClient(
        (request) async => request.url.path.endsWith('/auth/session')
            ? http.Response(jsonEncode(sessionBody()), 200)
            : pending.future,
      ),
      origin: Uri.parse('https://admin.example.test/'),
      environment: legacyBackendFixtureEnvironment,
    );
    addTearDown(session.dispose);
    await session.refresh();
    final read = readCloudflareSmsOversight(session);
    final expectation = expectLater(
      read,
      throwsA(isA<AdminAccountException>()),
    );
    session.clear();
    pending.complete(http.Response(jsonEncode(receipt()), 200));
    await expectation;
  });

  testWidgets('workspace reports measured counts and unknown heartbeat', (
    tester,
  ) async {
    final session = CloudflareAdminSession(
      MockClient(
        (request) async => request.url.path.endsWith('/auth/session')
            ? http.Response(jsonEncode(sessionBody()), 200)
            : http.Response(jsonEncode(receipt()), 200),
      ),
      origin: Uri.parse('https://admin.example.test/'),
      environment: legacyBackendFixtureEnvironment,
    );
    await session.refresh();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cloudflareAdminSessionProvider.overrideWith((ref) => session),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CloudflareSmsOversightPanel()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Queued receipts: 3'), findsOneWidget);
    expect(
      find.text('Operator heartbeat and receipt gate status are not recorded.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'These records do not confirm provider availability or handset delivery.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('an expired sample does not show old queue totals', (
    tester,
  ) async {
    final session = CloudflareAdminSession(
      MockClient(
        (request) async => request.url.path.endsWith('/auth/session')
            ? http.Response(jsonEncode(sessionBody()), 200)
            : http.Response(
                jsonEncode(receipt(checked: '2020-01-01T00:00:00Z')),
                200,
              ),
      ),
      origin: Uri.parse('https://admin.example.test/'),
      environment: legacyBackendFixtureEnvironment,
    );
    await session.refresh();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cloudflareAdminSessionProvider.overrideWith((ref) => session),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CloudflareSmsOversightPanel()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Sample expired. Refresh for current counts.'),
      findsOneWidget,
    );
    expect(find.text('Queued receipts: 3'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
