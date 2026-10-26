import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_automations_page.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_receipt_operational_telemetry.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'admin_action_session_test.dart' as auth;

// Synthetic presentation/HTTP fixtures. Actual SQL contract observations have
// separate producer-bound acceptance and must not be inferred from these cases.
Map<String, dynamic> _sample() => {
  'contract_version': 1,
  'scope': 'receipt_operations_configured_collections',
  'checked_at': '2026-10-02T12:00:00.000000Z',
  'sample_valid_until': '2026-10-02T12:01:00.000000Z',
  'window_start': '2026-10-01T12:00:00.000000Z',
  'window_end': '2026-10-02T12:00:00.000000Z',
  'window_seconds': 86400,
  'policy_revision': 1,
  'mode': 'Paused',
  'emergency_stop': true,
  'configured_collection_count': 1,
  'backlog': {
    'unhandled_events': 1,
    'oldest_unhandled_age_seconds': 300,
    'due_deferrals': 1,
    'source_busy_deferrals': 1,
  },
  'handling': {
    'events_created_24h': 0,
    'events_handled_24h': 1,
    'latency_p50_ms': 120000,
    'latency_p95_ms': 120000,
    'latency_max_ms': 120000,
  },
  'budgets': {
    'scope': 'global_utc_day',
    'utc_day_start': '2026-10-02T00:00:00.000000Z',
    'actions_reserved': 2,
    'actions_cap': 1,
    'sms_segments_reserved': 2,
    'sms_segments_cap': 1,
  },
  'callbacks': {
    'armed_attempts_24h': 1,
    'expected_segments': 2,
    'covered_sent_segments': 2,
    'covered_delivery_segments': 1,
    'complete_delivery_callback_attempts': 0,
    'conflicting_attempts': 0,
  },
  'unknown': {
    'uncertain_attempts': 1,
    'started_without_all_sent_callbacks': 0,
    'observed_sent_without_all_delivery_callbacks': 1,
    'callback_conflict_attempts': 0,
  },
  'alerts': <dynamic>[],
  'evidence_limit_codes': AdminReceiptOperationalTelemetry
      .requiredEvidenceLimitCodes
      .toList(),
  'financial_action': false,
  'send_action': false,
};

const _owner = AdminIdentity(
  userId: auth.actor,
  displayName: 'Synthetic telemetry reviewer',
  roles: ['platform_owner'],
  permissions: ['payments.read', 'notifications.read', 'system_health.read'],
);

class _Sdk {
  late CollectCloudflareClient client;
  late AdminRepository repository;
  final requests = <http.Request>[];
  late Future<http.Response> Function(http.Request) respond;
  Future<void> start() async {
    respond = (_) async => auth.response(_sample());
    client = CollectCloudflareClient(
      'https://synthetic.invalid',
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
    await auth.session(client, 'telemetry-a');
    repository = AdminRepository(client);
  }
}

class _Repository extends AdminEvidenceRepository {
  Map<String, dynamic> raw = _sample();
  Completer<void>? gate;
  Object? error;
  int reads = 0;
  @override
  Future<Map<String, dynamic>> receiptOperationalTelemetry() async {
    reads++;
    final captured = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(raw)) as Map,
    );
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return captured;
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  group('Pinned telemetry SDK', () {
    late _Sdk sdk;
    setUp(() async {
      sdk = _Sdk();
      await sdk.start();
    });
    tearDown(() => sdk.client.dispose());
    test('exact read RPC, empty arguments and captured token', () async {
      await sdk.repository.receiptOperationalTelemetry();
      final request = sdk.requests.single;
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/v1/rpc/admin_get_receipt_operational_telemetry_v1',
      );
      expect(jsonDecode(request.body), {});
      expect(
        request.headers['authorization'],
        'Bearer ${sdk.client.auth.currentSession!.accessToken}',
      );
    });
    for (final failure in ['403', '503', 'lost', 'private', 'malformed']) {
      test(
        '$failure makes one attempt and never exposes an open DTO',
        () async {
          sdk.respond = (_) async {
            if (failure == 'lost') throw TimeoutException('PRIVATE_CANARY');
            if (failure == '403' || failure == '503') {
              return auth.response({
                'code': '42501',
                'message': 'PRIVATE_CANARY',
              }, int.parse(failure));
            }
            final raw = _sample();
            if (failure == 'private') raw['destination'] = 'PRIVATE_CANARY';
            if (failure == 'malformed') raw['send_action'] = true;
            return auth.response(raw);
          };
          await expectLater(
            sdk.repository.receiptOperationalTelemetry(),
            throwsA(
              failure == 'lost'
                  ? isA<TimeoutException>()
                  : failure == '403' || failure == '503'
                  ? isA<CollectApiException>()
                  : isA<FormatException>(),
            ),
          );
          expect(sdk.requests, hasLength(1));
        },
      );
    }
    test(
      'delayed result cannot survive same-user replacement sign-in',
      () async {
        final entered = Completer<void>(), release = Completer<void>();
        sdk.respond = (_) async {
          entered.complete();
          await release.future;
          return auth.response(_sample());
        };
        final checked = expectLater(
          sdk.repository.receiptOperationalTelemetry(),
          throwsA(isA<AdminSessionChanged>()),
        );
        await entered.future;
        await auth.session(sdk.client, 'telemetry-b');
        release.complete();
        await checked;
        expect(sdk.requests, hasLength(1));
      },
    );
    test('unresolved read expires without automatic replay', () async {
      final release = Completer<http.Response>();
      sdk.respond = (_) => release.future;
      await expectLater(
        sdk.repository.receiptOperationalTelemetry(),
        throwsA(isA<TimeoutException>()),
      );
      expect(sdk.requests, hasLength(1));
      release.complete(auth.response(_sample()));
    });
  });

  group('Current telemetry view', () {
    late _Sdk sdk;
    late _Repository repository;
    late ProviderContainer container;
    final authority = StateProvider<Future<AdminIdentity?>>(
      (_) async => _owner,
    );
    final clock = StateProvider((_) => DateTime.utc(2026, 10, 2, 12));
    setUp(() async {
      sdk = _Sdk();
      await sdk.start();
      repository = _Repository();
      container = ProviderContainer(
        overrides: [
          collectBackendClientProvider.overrideWithValue(sdk.client),
          adminRepositoryProvider.overrideWithValue(repository),
          adminRealtimeSubscriptionProvider.overrideWith((ref) {}),
          adminIdentityProvider.overrideWith((ref) => ref.watch(authority)),
          adminClockProvider.overrideWith((ref) {
            final now = ref.watch(clock);
            return () => now;
          }),
        ],
      );
      await container.read(adminIdentityProvider.future);
    });
    tearDown(() async {
      container.dispose();
      await sdk.client.dispose();
    });
    Future<void> mount(
      WidgetTester tester, {
      double width = 640,
      double scale = 1,
      bool compact = false,
      Widget? child,
    }) async {
      await tester.runAsync(() async {
        container.read(adminAuthSessionScopeProvider);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.binding.setSurfaceSize(Size(width, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: CollectTheme.dark(),
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 1400),
                  textScaler: TextScaler.linear(scale),
                ),
                child:
                    child ??
                    SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: RepaintBoundary(
                          key: const Key('telemetry-capture'),
                          child: AdminReceiptTelemetryCard(compact: compact),
                        ),
                      ),
                    ),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
    }

    for (final width in [320.0, 1440.0]) {
      testWidgets(
        '$width layout labels budgets, handling and callback limits',
        (tester) async {
          await mount(tester, width: width, scale: width == 320 ? 2 : 1);
          expect(find.text('Global UTC-day budget limits'), findsOneWidget);
          expect(
            find.text('Authenticated callback observations'),
            findsOneWidget,
          );
          expect(
            find.textContaining('does not confirm carrier delivery'),
            findsOneWidget,
          );
          expect(
            find.text('No retained alert observations in this sample.'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      'compact mode retains measured age and unknown outcome counts',
      (tester) async {
        await mount(tester, compact: true);
        expect(find.text('300 seconds'), findsOneWidget);
        expect(
          find.text('Attempts with an uncertain recorded outcome'),
          findsOneWidget,
        );
        expect(find.text('View receipt operations'), findsOneWidget);
        expect(find.text('Global UTC-day budget limits'), findsNothing);
      },
    );
    testWidgets('Automations mounts the actual measurements section', (
      tester,
    ) async {
      await mount(tester, child: const AdminAutomationsPage(), width: 1440);
      expect(find.text('Receipt operations measurements'), findsOneWidget);
      expect(find.text('Durable event handling'), findsOneWidget);
      expect(repository.reads, greaterThanOrEqualTo(1));
      expect(tester.takeException(), isNull);
    });
    testWidgets('Overview mounts compact measurements independently', (
      tester,
    ) async {
      await mount(tester, child: const AdminOverviewContent(), width: 390);
      await tester.scrollUntilVisible(
        find.text('Receipt operations'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await _settle(tester);
      expect(find.text('Receipt operations'), findsOneWidget);
      expect(find.text('300 seconds'), findsOneWidget);
      expect(find.text('View receipt operations'), findsOneWidget);
      expect(repository.reads, greaterThanOrEqualTo(1));
      expect(tester.takeException(), isNull);
    });
    testWidgets('keyboard activates the named operations route link', (
      tester,
    ) async {
      await mount(tester, compact: true);
      final router = GoRouter(
        initialLocation: '/admin',
        routes: [
          GoRoute(
            path: '/admin',
            builder: (_, _) => const Scaffold(
              body: SingleChildScrollView(
                child: AdminReceiptTelemetryCard(compact: true),
              ),
            ),
          ),
          GoRoute(
            path: '/admin/automations',
            builder: (_, _) =>
                const Scaffold(body: Text('Synthetic operations destination')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: CollectTheme.dark(),
            routerConfig: router,
          ),
        ),
      );
      await _settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settle(tester);
      expect(
        router.routeInformationProvider.value.uri.path,
        '/admin/automations',
      );
      expect(find.text('Synthetic operations destination'), findsOneWidget);
    });
    for (final width in [390.0, 1440.0]) {
      testWidgets('capture compact dark measurements at $width', (
        tester,
      ) async {
        await mount(tester, width: width, compact: true);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('telemetry-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            if (bytes == null) throw StateError('Capture unavailable');
            final directory = Directory('build/telemetry-captures')
              ..createSync(recursive: true);
            await File(
              '${directory.path}/compact-dark-${width.toInt()}.png',
            ).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
          } finally {
            image.dispose();
          }
        });
        expect(tester.takeException(), isNull);
      });
    }
    for (final absent in [
      'platform_owner',
      'payments.read',
      'notifications.read',
      'system_health.read',
    ]) {
      testWidgets('missing $absent denies before telemetry read', (
        tester,
      ) async {
        container.read(authority.notifier).state = Future.value(
          AdminIdentity(
            userId: auth.actor,
            displayName: 'Synthetic limited reviewer',
            roles: _owner.roles.where((v) => v != absent).toList(),
            permissions: _owner.permissions.where((v) => v != absent).toList(),
          ),
        );
        await mount(tester);
        expect(repository.reads, 0);
        expect(find.textContaining('current platform owner'), findsOneWidget);
        expect(find.text('Refresh receipt operations'), findsNothing);
      });
    }
    testWidgets('expiry withdraws counts and investigation buttons', (
      tester,
    ) async {
      await mount(tester, compact: true);
      container.read(clock.notifier).state = DateTime.utc(2026, 10, 2, 12, 1);
      await _settle(tester);
      expect(find.textContaining('measurements expired'), findsOneWidget);
      expect(find.text('300 seconds'), findsNothing);
      expect(find.text('Investigate retained exception'), findsNothing);
    });
    testWidgets(
      'unavailable metrics stay unavailable and preserve retained alerts',
      (tester) async {
        for (final key in [
          'backlog',
          'handling',
          'budgets',
          'callbacks',
          'unknown',
        ]) {
          repository.raw[key] = null;
        }
        (repository.raw['evidence_limit_codes'] as List).add(
          'measurement_timeout',
        );
        repository.raw['alerts'] = [
          {
            'id': auth.target,
            'rule_code': 'BACKLOG_AGED',
            'status': 'superseded',
            'episode': 1,
            'revision': 2,
            'source_kind': 'business_event',
            'source_id': auth.target,
            'exception_id': auth.target,
            'response_code': 'investigate_backlog',
            'observed_at': repository.raw['checked_at'],
          },
        ];
        await mount(tester);
        expect(
          find.text('Legacy measurements unavailable. Measurement timed out.'),
          findsOneWidget,
        );
        expect(find.text('Receipt backlog age · Superseded'), findsOneWidget);
        expect(find.text('Investigate retained exception'), findsOneWidget);
        expect(find.text('300 seconds'), findsNothing);
        expect(find.text('Global UTC-day budget limits'), findsNothing);
      },
    );
    testWidgets('private service errors render only safe refresh guidance', (
      tester,
    ) async {
      repository.error = StateError('PRIVATE_CANARY');
      await mount(tester);
      expect(find.textContaining('could not be verified'), findsOneWidget);
      expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
      expect(find.text('300 seconds'), findsNothing);
    });
    testWidgets(
      'delayed old authority is hidden through role loss and restoration',
      (tester) async {
        repository.gate = Completer<void>();
        await mount(tester);
        expect(find.textContaining('Loading legacy receipt'), findsOneWidget);
        container.read(authority.notifier).state = Future.value(
          const AdminIdentity(
            userId: auth.actor,
            displayName: 'Synthetic denied reviewer',
            roles: [],
            permissions: [],
          ),
        );
        await _settle(tester);
        expect(find.textContaining('current platform owner'), findsOneWidget);
        repository.gate!.complete();
        await _settle(tester);
        expect(find.text('300 seconds'), findsNothing);
        repository.gate = null;
        container.read(authority.notifier).state = Future.value(_owner);
        await _settle(tester);
        expect(find.text('300 seconds'), findsOneWidget);
        expect(repository.reads, greaterThanOrEqualTo(2));
      },
    );
  });
}
