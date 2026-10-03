import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/core/admin_exception_models.dart';
import 'package:collect_app/admin/core/admin_receipt_deferral_models.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_action_session_test.dart' as auth;

const fixtureRoot =
    'docs/release/collect-codex-goal-2026-09-30/'
    'receipt-deferral-exceptions-20261001/accepted-sql-attempt5';
Map<String, dynamic> observed(String name) => Map<String, dynamic>.from(
  jsonDecode(File('$fixtureRoot/observed-$name.json').readAsStringSync())
      as Map,
);
Map<String, dynamic> copy(Map<String, dynamic> raw) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(raw)) as Map);
Future<void> settle(WidgetTester tester) async {
  // The actual SDK/container identity Future was created outside widget fake
  // time. Give its real microtasks a bounded turn before checking rendered UI.
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pumpAndSettle();
}

AdminExceptionRow rowFor(Map<String, dynamic> detail) {
  final inbox = observed(
    detail['source_kind'] == 'receipt_event' ? 'event-inbox' : 'backlog-inbox',
  );
  final matches = (inbox['rows'] as List).cast<Map<String, dynamic>>().where(
    (row) => row['id'] == detail['exception_id'],
  );
  // Selected-detail presentation fixture, derived from the accepted SQL DTO.
  // Not all observations were captured in the same inbox sample.
  final raw = {
    'id': detail['exception_id'],
    'source_kind': detail['source_kind'],
    'source_id': detail['source_id'],
    'reason_code': detail['reason_code'],
    'revision': detail['revision'],
    'active': detail['active'],
    'source_sha256': matches.isEmpty
        ? 'c' * 64
        : matches.single['source_sha256'],
    'first_observed_at': detail['checked_at'],
    'last_changed_at': detail['checked_at'],
    'transaction_sms_id': matches.isEmpty
        ? null
        : matches.single['transaction_sms_id'],
    'acknowledged': false,
    'escalation_requested': false,
  };
  return AdminExceptionRow.parse(raw, exceptionInstant(detail['checked_at']));
}

const reviewer = AdminIdentity(
  userId: auth.actor,
  displayName: 'Synthetic receipt reviewer',
  roles: ['admin'],
  permissions: ['payments.read', 'notifications.read', 'system_health.read'],
);
const deniedReviewer = AdminIdentity(
  userId: auth.actor,
  displayName: 'Synthetic denied reviewer',
  roles: ['admin'],
  permissions: ['payments.read', 'notifications.read'],
);

class _SdkProbe {
  late SupabaseClient client;
  late AdminRepository repository;
  final requests = <http.Request>[];
  late Future<http.Response> Function(http.Request) respond;
  Future<void> start() async {
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
        final result = await respond(request);
        return http.Response.bytes(
          result.bodyBytes,
          result.statusCode,
          headers: result.headers,
          request: request,
        );
      }),
    );
    await auth.session(client, 'receipt-deferral-a');
    repository = AdminRepository(client);
    respond = (_) async => auth.response(observed('detail-deferred'));
  }
}

class _EvidenceRepository extends AdminEvidenceRepository {
  Map<String, dynamic> raw = observed('detail-deferred');
  Completer<void>? gate;
  int calls = 0;
  Object? error;
  @override
  Future<Map<String, dynamic>> exceptionInbox({
    bool active = true,
    int limit = 20,
    AdminExceptionSource? source,
    DateTime? beforeChangedAt,
    String? beforeId,
  }) async {
    final inbox = observed('event-inbox');
    final row = copy((inbox['rows'] as List).single as Map<String, dynamic>)
      ..['revision'] = raw['revision']
      ..['active'] = raw['active']
      ..['last_changed_at'] = raw['checked_at'];
    return inbox
      ..['active'] = active
      ..['limit'] = limit
      ..['source_kind'] = source?.wire
      ..['checked_at'] = raw['checked_at']
      ..['sample_valid_until'] = raw['sample_valid_until']
      ..['rows'] =
          active == raw['active'] &&
              (source == null || source.wire == raw['source_kind'])
          ? [row]
          : [];
  }

  @override
  Future<Map<String, dynamic>> receiptDeferralEvidence(String id) async {
    calls++;
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return raw;
  }
}

void main() {
  group('Actual SQL receipt-deferral contracts', () {
    for (final name in [
      'detail-deferred',
      'detail-source-cleared',
      'detail-handled',
      'detail-superseded',
      'detail-backlog-deferred',
      'detail-backlog-handled',
    ]) {
      test('$name retains exact source and business handling meaning', () {
        final raw = observed(name);
        final result = AdminReceiptDeferralEvidence.parse(
          raw,
          raw['exception_id'] as String,
        );
        expect(result.businessHandled, raw['business_handled']);
        expect(result.businessHandled, result.disposition == 'durably_handled');
        expect(result.isFresh(result.checkedAt), isTrue);
        expect(result.isFresh(result.validUntil), isFalse);
        expect(
          result.isFresh(result.checkedAt.subtract(const Duration(seconds: 6))),
          isFalse,
        );
      });
    }
    for (final name in ['event-inbox', 'backlog-inbox']) {
      test('$name new source parses with canonical transaction linkage', () {
        final raw = observed(name);
        final result = AdminExceptionSnapshot.parse(
          raw,
          active: raw['active'] as bool,
          limit: raw['limit'] as int,
          source: AdminExceptionSource.parse(raw['source_kind']),
        );
        expect(result.rows.single.source.isReceiptDeferral, isTrue);
        expect(
          result.rows.single.investigationPath,
          result.rows.single.transactionSmsId == null
              ? null
              : '/admin/transactions/momo:${result.rows.single.transactionSmsId}',
        );
        expect(
          result.rows.single.reasonLabel,
          'Receipt operating limit exhausted',
        );
      });
    }
    test('only the two receipt kinds accept all fifteen prefixed reasons', () {
      final raw = observed('event-inbox');
      for (final code in adminReceiptDeferralLabels.keys) {
        for (final source in AdminExceptionSource.values) {
          final row = copy(
            (raw['rows'] as List).single as Map<String, dynamic>,
          );
          row['source_kind'] = source.wire;
          row['reason_code'] = 'RECEIPT_OPERATION_$code';
          if (source.isReceiptDeferral) {
            expect(
              AdminExceptionRow.parse(
                row,
                exceptionInstant(raw['checked_at']),
              ).reasonLabel,
              adminReceiptDeferralLabels[code],
            );
          } else {
            expect(
              () => AdminExceptionRow.parse(
                row,
                exceptionInstant(raw['checked_at']),
              ),
              throwsFormatException,
            );
          }
        }
      }
    });
    test(
      'a canonical transaction link uses its SMS ID, never an event/snapshot ID',
      () {
        final detail = observed('detail-deferred');
        final original = rowFor(detail);
        final raw = copy(
          (observed('event-inbox')['rows'] as List).single
              as Map<String, dynamic>,
        );
        expect(
          original.investigationPath,
          '/admin/transactions/momo:${original.transactionSmsId}',
        );
        raw['transaction_sms_id'] = '11111111-1111-4111-8111-111111111111';
        final result = AdminExceptionRow.parse(
          raw,
          exceptionInstant(observed('event-inbox')['checked_at']),
        );
        expect(
          result.investigationPath,
          '/admin/transactions/momo:11111111-1111-4111-8111-111111111111',
        );
        expect(result.investigationPath, isNot(contains(result.sourceId)));
      },
    );
    final mutations = <String, void Function(Map<String, dynamic>)>{
      'extra private field': (x) => x['body'] = 'PRIVATE_CANARY',
      'floating contract': (x) => x['contract_version'] = 1.0,
      'wrong exception': (x) =>
          x['exception_id'] = '11111111-1111-4111-8111-111111111111',
      'legacy source': (x) => x['source_kind'] = 'payment',
      'wrong reason category': (x) => x['reason_code'] = 'CONTACT_MISSING',
      'unknown reason': (x) => x['reason_code'] = 'RECEIPT_OPERATION_SEND_NOW',
      'missing event version': (x) => x['source_version'] = null,
      'floating event version': (x) => x['source_version'] = 1.0,
      'unknown event': (x) => x['event_kind'] = 'delivered',
      'backlog contains event': (x) => x['source_kind'] = 'receipt_backlog',
      'invalid source ID': (x) => x['source_id'] = 'PRIVATE_CANARY',
      'fake handling': (x) => x['business_handled'] = true,
      'fake send': (x) => x['send_action'] = true,
      'fake financial action': (x) => x['financial_action'] = true,
      'unknown result': (x) => x['current_code'] = 'DELIVERED',
      'unknown original': (x) => x['original_code'] = 'DELIVERED',
      'floating revision': (x) => x['revision'] = 1.0,
      'wrong TTL': (x) => x['sample_valid_until'] = x['checked_at'],
      'noncanonical timestamp': (x) => x['checked_at'] = '2026-10-01T12:00:00Z',
      'impossible date': (x) => x['checked_at'] = '2026-02-30T12:00:00.123456Z',
    };
    for (final entry in mutations.entries) {
      test('rejects ${entry.key}', () {
        final original = observed('detail-deferred'), raw = copy(original);
        entry.value(raw);
        expect(
          () => AdminReceiptDeferralEvidence.parse(
            raw,
            original['exception_id'] as String,
          ),
          throwsFormatException,
        );
      });
    }
    test('durable receipt handling requires its actual receipt ID', () {
      final raw = observed('detail-handled')..['receipt_id'] = null;
      expect(
        () => AdminReceiptDeferralEvidence.parse(
          raw,
          raw['exception_id'] as String,
        ),
        throwsFormatException,
      );
    });
  });

  group('Actual locked SDK', () {
    late _SdkProbe probe;
    final id = observed('detail-deferred')['exception_id'] as String;
    setUp(() async {
      probe = _SdkProbe();
      await probe.start();
    });
    tearDown(() => probe.client.dispose());
    test(
      'uses only exact evidence RPC with captured session and identifier',
      () async {
        await probe.repository.receiptDeferralEvidence(id);
        final request = probe.requests.single;
        expect(request.method, 'POST');
        expect(
          request.url.path,
          '/rest/v1/rpc/admin_get_receipt_deferral_exception_v1',
        );
        expect(jsonDecode(request.body), {'p_exception_id': id});
        expect(
          request.headers['authorization'],
          'Bearer ${probe.client.auth.currentSession!.accessToken}',
        );
      },
    );
    test('invalid identifier is refused before HTTP', () async {
      await expectLater(
        probe.repository.receiptDeferralEvidence('PRIVATE_CANARY'),
        throwsFormatException,
      );
      expect(probe.requests, isEmpty);
    });
    for (final failure in ['denied', '503', 'lost', 'private', 'mismatch']) {
      test('$failure makes one request without fallback or replay', () async {
        probe.respond = (_) async {
          if (failure == 'lost') throw TimeoutException('PRIVATE_CANARY');
          if (failure == 'denied' || failure == '503') {
            return auth.response({
              'code': '42501',
              'message': 'PRIVATE_CANARY',
            }, failure == 'denied' ? 403 : 503);
          }
          final raw = observed('detail-deferred');
          if (failure == 'private') raw['phone'] = 'PRIVATE_CANARY';
          if (failure == 'mismatch') {
            raw['exception_id'] = '11111111-1111-4111-8111-111111111111';
          }
          return auth.response(raw);
        };
        await expectLater(
          probe.repository.receiptDeferralEvidence(id),
          throwsA(
            failure == 'lost'
                ? isA<TimeoutException>()
                : failure == 'denied' || failure == '503'
                ? isA<PostgrestException>()
                : isA<FormatException>(),
          ),
        );
        expect(probe.requests, hasLength(1));
      });
    }
    test('departed same-user session suppresses late SDK result', () async {
      final entered = Completer<void>(), release = Completer<void>();
      probe.respond = (_) async {
        entered.complete();
        await release.future;
        return auth.response(observed('detail-deferred'));
      };
      final pending = probe.repository.receiptDeferralEvidence(id);
      final check = expectLater(pending, throwsA(isA<AdminSessionChanged>()));
      await entered.future;
      await auth.session(probe.client, 'receipt-deferral-b');
      release.complete();
      await check;
      expect(probe.requests, hasLength(1));
    });
  });

  group('Current-authority receipt evidence view', () {
    late _SdkProbe sdk;
    late _EvidenceRepository repository;
    late ProviderContainer container;
    final authority = StateProvider<Future<AdminIdentity?>>(
      (_) async => reviewer,
    );
    late StateProvider<DateTime> clock;
    setUp(() async {
      sdk = _SdkProbe();
      await sdk.start();
      repository = _EvidenceRepository();
      clock = StateProvider(
        (_) => exceptionInstant(repository.raw['checked_at']),
      );
      container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(sdk.client),
          adminRepositoryProvider.overrideWithValue(repository),
          // Route/modal proof uses controlled reads; realtime has its own
          // actual SDK/loopback acceptance and must not open a network socket.
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
      bool inbox = false,
    }) async {
      await tester.runAsync(() async {
        container.read(adminAuthSessionScopeProvider);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: CollectTheme.light(),
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 900),
                  textScaler: TextScaler.linear(scale),
                ),
                child: inbox
                    ? const AdminExceptionsPage()
                    : SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: AdminReceiptDeferralCard(
                            row: rowFor(repository.raw),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);
    }

    for (final name in [
      'detail-deferred',
      'detail-source-cleared',
      'detail-handled',
      'detail-superseded',
      'detail-backlog-deferred',
      'detail-backlog-handled',
    ]) {
      testWidgets('$name displays handling without claiming delivery', (
        tester,
      ) async {
        repository.raw = observed(name);
        container.read(clock.notifier).state = exceptionInstant(
          repository.raw['checked_at'],
        );
        await mount(tester);
        final handled = repository.raw['business_handled'] == true;
        expect(
          find.text(
            handled
                ? 'Business handling: durably recorded'
                : 'Business handling: not durably recorded',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Open recorded SMS receipt'),
          repository.raw['receipt_id'] == null ? findsNothing : findsOneWidget,
        );
        expect(
          find.textContaining(
            'Message transport and delivery require separate',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets(
      'actual Admin router opens receipt after closing the evidence modal',
      (tester) async {
        repository.raw = observed('detail-source-cleared');
        container.read(clock.notifier).state = exceptionInstant(
          repository.raw['checked_at'],
        );
        await tester.runAsync(() async {
          container.read(adminAuthSessionScopeProvider);
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.binding.setSurfaceSize(const Size(1440, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final router = container.read(adminRouterProvider);
        router.go('/admin/exceptions');
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              theme: CollectTheme.light(),
              routerConfig: router,
            ),
          ),
        );
        await settle(tester);
        await tester.tap(find.byType(DropdownButtonFormField<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cleared').last);
        await settle(tester);
        await tester.ensureVisible(find.text('Review receipt work'));
        await tester.tap(find.text('Review receipt work'));
        await settle(tester);
        expect(find.byType(Dialog), findsOneWidget);
        await tester.ensureVisible(find.text('Open recorded SMS receipt'));
        await tester.tap(find.text('Open recorded SMS receipt'));
        await settle(tester);
        expect(
          router.routeInformationProvider.value.uri.path,
          '/admin/sms-receipts/${repository.raw['receipt_id']}',
        );
        expect(find.byType(Dialog), findsNothing);
        router.go('/admin/exceptions');
        await settle(tester);
        expect(
          router.routeInformationProvider.value.uri.path,
          '/admin/exceptions',
        );
        expect(find.byType(Dialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets('inbox opens source evidence in an authority-bound dialog', (
      tester,
    ) async {
      await mount(tester, inbox: true);
      expect(find.text('Receipt operating limit exhausted'), findsOneWidget);
      await tester.ensureVisible(find.text('Review receipt work'));
      await tester.tap(find.text('Review receipt work'));
      await settle(tester);
      expect(find.byType(Dialog), findsOneWidget);
      expect(
        find.text('Business handling: not durably recorded'),
        findsOneWidget,
      );
      expect(repository.calls, 1);
      container.read(authority.notifier).state = Future.value(deniedReviewer);
      await settle(tester);
      expect(find.textContaining('Business handling:'), findsNothing);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      'narrow layout with twice-size text preserves named refresh action',
      (tester) async {
        await mount(tester, width: 320, scale: 2);
        await tester.ensureVisible(find.text('Refresh receipt evidence'));
        expect(tester.takeException(), isNull);
        expect(repository.calls, 1);
        await tester.tap(find.text('Refresh receipt evidence'));
        await settle(tester);
        expect(repository.calls, 2);
      },
    );
    testWidgets(
      'expired evidence suppresses receipt/source links and current claims',
      (tester) async {
        repository.raw = observed('detail-handled');
        container.read(clock.notifier).state = exceptionInstant(
          repository.raw['sample_valid_until'],
        );
        await mount(tester);
        expect(
          find.textContaining('Receipt evidence expired.'),
          findsOneWidget,
        );
        expect(find.text('Open recorded SMS receipt'), findsNothing);
        expect(find.text('Business handling: durably recorded'), findsNothing);
      },
    );
    testWidgets('permission denial makes no read and hides evidence', (
      tester,
    ) async {
      container.read(authority.notifier).state = Future.value(deniedReviewer);
      await container.read(adminIdentityProvider.future);
      await mount(tester);
      expect(repository.calls, 0);
      expect(
        find.text('Current receipt exception access is required.'),
        findsOneWidget,
      );
    });
    testWidgets(
      'raw failures are redacted and named refresh remains available',
      (tester) async {
        repository.error = StateError('PRIVATE_CANARY phone body');
        await mount(tester);
        expect(find.textContaining('could not be verified'), findsOneWidget);
        expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
        expect(find.text('Refresh receipt evidence'), findsOneWidget);
      },
    );
    testWidgets('forged source association never enters the evidence view', (
      tester,
    ) async {
      final row = rowFor(repository.raw);
      repository.raw['source_id'] = '11111111-1111-4111-8111-111111111111';
      await tester.runAsync(() async {
        container.read(adminAuthSessionScopeProvider);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: AdminReceiptDeferralCard(row: row)),
          ),
        ),
      );
      await settle(tester);
      expect(find.textContaining('could not be verified'), findsOneWidget);
      expect(find.textContaining('Business handling:'), findsNothing);
    });
    testWidgets('an older source revision is refused after inbox selection', (
      tester,
    ) async {
      final row = rowFor(observed('detail-handled'));
      await tester.runAsync(() async {
        container.read(adminAuthSessionScopeProvider);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: AdminReceiptDeferralCard(row: row)),
          ),
        ),
      );
      await settle(tester);
      expect(find.textContaining('could not be verified'), findsOneWidget);
      expect(find.textContaining('Business handling:'), findsNothing);
      expect(repository.calls, 1);
    });
    testWidgets(
      'permission departure and restoration requires a new source read',
      (tester) async {
        repository.gate = Completer<void>();
        await mount(tester);
        container.read(authority.notifier).state = Future.value(deniedReviewer);
        await settle(tester);
        expect(find.textContaining('Business handling:'), findsNothing);
        container.read(authority.notifier).state = Future.value(reviewer);
        await settle(tester);
        expect(repository.calls, 2);
        expect(
          find.text('Checking the current receipt source…'),
          findsOneWidget,
        );
        repository.gate!.complete();
        await settle(tester);
        expect(
          find.text('Business handling: not durably recorded'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets('loading authority departure discards a held result', (
      tester,
    ) async {
      repository.gate = Completer<void>();
      await mount(tester);
      expect(find.text('Checking the current receipt source…'), findsOneWidget);
      final gate = Completer<AdminIdentity?>();
      container.read(authority.notifier).state = gate.future;
      await tester.pump();
      expect(find.text('Checking receipt evidence access…'), findsOneWidget);
      repository.gate!.complete();
      await tester.pump();
      expect(find.textContaining('Business handling:'), findsNothing);
      gate.complete(deniedReviewer);
      await settle(tester);
      expect(
        find.text('Current receipt exception access is required.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
