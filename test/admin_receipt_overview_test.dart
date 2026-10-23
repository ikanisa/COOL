import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/admin/admin_app.dart';
import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_receipt_overview.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/app/theme/collect_colors.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'admin_action_session_test.dart' as auth;
import 'support/test_capture_paths.dart';

final _now = DateTime.utc(2026, 9, 30, 10, 30);
const _identity = AdminIdentity(
  userId: '00000000-0000-4000-8000-000000000001',
  displayName: 'Synthetic reviewer',
  roles: ['admin'],
  permissions: ['overview.read', 'notifications.read', 'system_health.read'],
);
Map<String, dynamic> _fixture() => {
  'contract_version': 1,
  'scope': 'rwanda_momo',
  'country_code': 'RW',
  'timezone': 'Africa/Kigali',
  'checked_at': _now.toIso8601String(),
  'sample_valid_until': _now.add(const Duration(seconds: 60)).toIso8601String(),
  'day_start': DateTime.utc(2026, 9, 29, 22).toIso8601String(),
  'day_end': DateTime.utc(2026, 9, 30, 22).toIso8601String(),
  'posted': {'count': 7, 'value_rwf': '1234500'},
  'receipts_state': 'available',
  'receipts': <String, dynamic>{
    'queued': 4,
    'awaiting_confirmation': 2,
    'oldest_pending_at': _now
        .subtract(const Duration(minutes: 15))
        .toIso8601String(),
    'failed_no_send': 1,
    'uncertain': 2,
    'send_started': 3,
  },
};
Map<String, dynamic> _health() {
  final source =
      jsonDecode(
            File(
              'test/fixtures/admin_operational_health148.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final data = Map<String, dynamic>.from(source['receipt'] as Map);
  data['checked_at'] = _now.toIso8601String();
  data['sample_valid_until'] = _now
      .add(const Duration(seconds: 60))
      .toIso8601String();
  return data;
}

class _Repository extends AdminEvidenceRepository {
  _Repository({
    this.failure,
    this.healthFailure,
    this.queueFailure,
    this.delayed,
    this.failMetrics = false,
    Map<String, dynamic>? data,
  }) : data = data ?? _fixture();
  final Object? failure, healthFailure, queueFailure;
  final bool failMetrics;
  final Completer<Map<String, dynamic>>? delayed;
  final Map<String, dynamic> data;
  final called = Completer<void>();
  int receiptReads = 0, healthReads = 0, smsReads = 0, writes = 0;
  final filters = <String?>[];
  @override
  Future<Map<String, dynamic>> receiptOverview({String? countryCode}) async {
    receiptReads++;
    if (!called.isCompleted) called.complete();
    if (failure != null) throw failure!;
    return delayed?.future ?? data;
  }

  @override
  Future<Map<String, dynamic>> detail(String rpcName, String id) async {
    if (rpcName == 'admin_system_health') {
      healthReads++;
      if (healthFailure != null) throw healthFailure!;
      return _health();
    }
    return super.detail(rpcName, id);
  }

  @override
  Future<Map<String, dynamic>> smsQueueHealth() async {
    smsReads++;
    if (queueFailure != null) throw queueFailure!;
    return {
      'enabled': false,
      'queued': 4,
      'awaiting_confirmation': 2,
      'send_started': 3,
      'uncertain': 2,
      'suppressed': 0,
      'active_workers': 1,
      'observed_at': _now.toIso8601String(),
      'oldest_queued_at': _now
          .subtract(const Duration(minutes: 15))
          .toIso8601String(),
    };
  }

  @override
  Future<List<AdminMetric>> overviewMetrics() {
    if (failMetrics) throw StateError('synthetic independent failure');
    return super.overviewMetrics().then(
      (metrics) => [
        for (final metric in metrics)
          if (metric.label != 'Balanced ledgers') metric,
        const AdminMetric(
          label: 'Ledger entries',
          value: '10',
          status: 'active',
        ),
      ],
    );
  }

  @override
  Future<AdminListResult> list(
    String rpcName, {
    String? search,
    String? status,
    int? limit,
    int? offset,
    String? sortBy,
    String? countryCode,
  }) {
    if (rpcName == 'admin_list_hybrid_sms_receipts') filters.add(status);
    return super.list(
      rpcName,
      search: search,
      status: status,
      limit: limit,
      offset: offset,
      sortBy: sortBy,
      countryCode: countryCode,
    );
  }

  @override
  Future<Map<String, dynamic>> action(
    String rpcName,
    Map<String, dynamic> params,
  ) {
    writes++;
    return super.action(rpcName, params);
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Repository repository, {
  Size size = const Size(1440, 1400),
  double scale = 1,
  Brightness brightness = Brightness.dark,
  DateTime Function()? clock,
  AdminIdentity? identity = _identity,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminRepositoryProvider.overrideWithValue(repository),
        adminIdentityProvider.overrideWith((_) async => identity),
        adminClockProvider.overrideWithValue(clock ?? () => _now),
        collectBackendClientProvider.overrideWithValue(null),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.dark
            ? AppTheme.dark()
            : AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const Scaffold(
          body: RepaintBoundary(
            key: Key('overview-capture'),
            child: AdminOverviewContent(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    450,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('admin-overview-workspace')),
          matching: find.byType(Scrollable),
        )
        .first,
    maxScrolls: 30,
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  setUpAll(() async {
    if (const bool.fromEnvironment('COLLECT_CAPTURE_OPERATIONS')) {
      await (FontLoader('Inter')
            ..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf')))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  test(
    'exact aggregate contract preserves bigint value and Kigali interval',
    () {
      final raw = _fixture();
      raw['posted'] = {'count': 7, 'value_rwf': '900719925474099312345'};
      final data = AdminReceiptOverview.parse(raw);
      expect(data.postedValueRwf, '900719925474099312345');
      expect(data.dayStart.hour, 22);
      expect(data.receipts!.pending, 6);
      expect(data.isFresh(_now), isTrue);
      expect(data.isFresh(_now.add(const Duration(seconds: 60))), isFalse);
      expect(data.isFresh(_now.subtract(const Duration(seconds: 6))), isFalse);
    },
  );
  test('midnight Kigali follows next day while UTC remains previous date', () {
    final raw = _fixture();
    final checked = DateTime.utc(2026, 9, 30, 22, 1);
    raw['checked_at'] = checked.toIso8601String();
    raw['sample_valid_until'] = checked
        .add(const Duration(seconds: 60))
        .toIso8601String();
    raw['day_start'] = DateTime.utc(2026, 9, 30, 22).toIso8601String();
    raw['day_end'] = DateTime.utc(2026, 10, 1, 22).toIso8601String();
    expect(
      AdminReceiptOverview.parse(raw).dayStart,
      DateTime.utc(2026, 9, 30, 22),
    );
  });
  test(
    'missing, surplus, permissive scalar and fabricated zero responses fail closed',
    () {
      final invalid = <Map<String, dynamic>>[
        _fixture()..remove('receipts'),
        _fixture()..['phone'] = 'forbidden',
        _fixture()..['contract_version'] = 1.0,
        _fixture()..['scope'] = 'collect_platform',
        _fixture()..['day_start'] = DateTime.utc(2026, 9, 30).toIso8601String(),
        _fixture()..['posted'] = {'count': 1.0, 'value_rwf': '10'},
        _fixture()..['posted'] = {'count': 1, 'value_rwf': '0'},
        _fixture()..['posted'] = {'count': 0, 'value_rwf': '1'},
        _fixture()..['posted'] = {'count': 2, 'value_rwf': '1'},
        _fixture()..['posted'] = {'count': 2, 'value_rwf': 2},
      ];
      for (final value in invalid) {
        expect(() => AdminReceiptOverview.parse(value), throwsFormatException);
      }
    },
  );
  test('pending oldest/count and receipt authorization remain consistent', () {
    final denied = _fixture()
      ..['receipts_state'] = 'denied'
      ..['receipts'] = null;
    expect(AdminReceiptOverview.parse(denied).receipts, isNull);
    expect(
      () =>
          AdminReceiptOverview.parse(_fixture()..['receipts_state'] = 'denied'),
      throwsFormatException,
    );
    final raw = _fixture();
    (raw['receipts'] as Map)['oldest_pending_at'] = null;
    expect(() => AdminReceiptOverview.parse(raw), throwsFormatException);
    (raw['receipts'] as Map)['oldest_pending_at'] = _now
        .add(const Duration(seconds: 1))
        .toIso8601String();
    expect(() => AdminReceiptOverview.parse(raw), throwsFormatException);
  });
  test('zero financial and empty queue are real available observations', () {
    final raw = _fixture()..['posted'] = {'count': 0, 'value_rwf': '0'};
    raw['receipts'] = {
      'queued': 0,
      'awaiting_confirmation': 0,
      'oldest_pending_at': null,
      'failed_no_send': 0,
      'uncertain': 0,
      'send_started': 0,
    };
    expect(AdminReceiptOverview.parse(raw).postedCount, 0);
    expect(AdminReceiptOverview.parse(raw).receipts!.oldestPendingAt, isNull);
  });
  testWidgets(
    'real-shaped measures distinguish posting, pending, failure and unknown sends',
    (tester) async {
      final repository = _Repository();
      await _pump(tester, repository);
      expect(find.text('Posted payments today'), findsOneWidget);
      expect(find.text('RWF 1,234,500'), findsOneWidget);
      expect(find.text('Today · 30 Sep 2026'), findsOneWidget);
      expect(find.text('15m 0s'), findsOneWidget);
      expect(find.text('Definite no-send failures'), findsOneWidget);
      expect(find.text('Unknown send outcome'), findsOneWidget);
      expect(find.text('Send started, unresolved'), findsOneWidget);
      await _reveal(
        tester,
        find.textContaining(
          'sender/device/network diagnostics are not connected',
        ),
      );
      expect(
        find.textContaining(
          'sender/device/network diagnostics are not connected',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Gate closed'), findsOneWidget);
      expect(repository.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'specialized Overview table headings have visible text and stable semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, _Repository());
      await _reveal(
        tester,
        find.descendant(
          of: find.bySemanticsLabel(RegExp(r'^Needs attention queue,')),
          matching: find.text('Record'),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in [
        'Record',
        'MoMo number',
        'Amount',
        'Status',
        'Age',
        'Action',
      ]) {
        expect(find.text(label), findsWidgets);
        expect(find.bySemanticsLabel(label), findsWidgets);
      }
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
  testWidgets('light queue metrics use readable surface foregrounds', (
    tester,
  ) async {
    await _pump(tester, _Repository(), brightness: Brightness.light);
    final heading = tester.widget<Text>(find.text('Ledger entries'));
    final value = tester.widget<Text>(find.text('10'));
    expect(heading.style!.color, CollectColors.light.textSecondary);
    expect(value.style!.color, CollectColors.light.textPrimary);
    expect(value.style!.color, isNot(CollectColors.light.surfaceReadable));
  });
  testWidgets(
    'backend permission denial remains distinct from unavailable service',
    (tester) async {
      await _pump(
        tester,
        _Repository(
          failure: const CollectApiException(
            message: 'redacted',
            code: '42501',
          ),
        ),
      );
      expect(
        find.text('Payments and receipts · Access denied'),
        findsOneWidget,
      );
      expect(find.text('Posted value today'), findsNothing);
      expect(find.textContaining('Observed queue checks:'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'missing permission avoids service reads and does not fabricate measurements',
    (tester) async {
      final repository = _Repository();
      await _pump(tester, repository, identity: null);
      expect(repository.receiptReads, 0);
      expect(repository.healthReads, 0);
      expect(repository.smsReads, 0);
      expect(find.text('RWF 1,234,500'), findsNothing);
      expect(find.textContaining('Access denied'), findsWidgets);
    },
  );
  testWidgets('financial section survives receipt permission denial', (
    tester,
  ) async {
    final raw = _fixture()
      ..['receipts_state'] = 'denied'
      ..['receipts'] = null;
    await _pump(tester, _Repository(data: raw));
    expect(find.text('RWF 1,234,500'), findsOneWidget);
    expect(
      find.textContaining('Receipt measurements · Access denied'),
      findsOneWidget,
    );
    expect(find.text('Unknown send outcome'), findsNothing);
  });
  testWidgets(
    'health failure leaves financial and SMS gate measurements readable',
    (tester) async {
      await _pump(
        tester,
        _Repository(
          healthFailure: UnsupportedError('synthetic health unavailable'),
        ),
      );
      expect(find.text('RWF 1,234,500'), findsOneWidget);
      await _reveal(tester, find.textContaining('Gate closed'));
      expect(find.textContaining('Gate closed'), findsOneWidget);
      expect(find.text('Unavailable'), findsNWidgets(2));
      expect(find.textContaining('Observed queue checks:'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'partial metrics and SMS errors preserve allocations and independent health',
    (tester) async {
      await _pump(
        tester,
        _Repository(
          failMetrics: true,
          queueFailure: UnsupportedError('synthetic'),
        ),
      );
      expect(find.text('RWF 1,234,500'), findsOneWidget);
      expect(find.text('Queue totals · Unavailable'), findsOneWidget);
      expect(find.text('Needs attention'), findsOneWidget);
      final scroll = find.byKey(const Key('admin-overview-workspace'));
      await tester.drag(scroll, const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(find.text('Recent allocations'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'stale observations hide values and show a usable refresh action',
    (tester) async {
      var clock = _now;
      final repository = _Repository();
      await _pump(tester, repository, clock: () => clock);
      clock = _now.add(const Duration(seconds: 60));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('RWF 1,234,500'), findsNothing);
      expect(
        find.textContaining('Payments and receipts · Stale'),
        findsOneWidget,
      );
      expect(find.textContaining('Stale · refresh required'), findsWidgets);
      final button = find
          .widgetWithText(TextButton, 'Refresh measurement')
          .first;
      expect(tester.widget<TextButton>(button).onPressed, isNotNull);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(repository.receiptReads, 2);
      expect(repository.writes, 0);
    },
  );
  testWidgets(
    'all three resolved measurement refresh actions only reread services',
    (tester) async {
      final repository = _Repository();
      await _pump(tester, repository);
      await _reveal(
        tester,
        find.widgetWithText(OutlinedButton, 'Refresh payments and receipts'),
      );
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Refresh payments and receipts'),
      );
      await tester.pumpAndSettle();
      await _reveal(
        tester,
        find.widgetWithText(OutlinedButton, 'Refresh operational status'),
      );
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Refresh operational status'),
      );
      await tester.pumpAndSettle();
      expect(repository.receiptReads, 2);
      expect(repository.healthReads, 2);
      expect(repository.smsReads, 2);
      expect(repository.writes, 0);
    },
  );
  testWidgets(
    'disposed pending measurement cannot publish a prior workspace value',
    (tester) async {
      final release = Completer<Map<String, dynamic>>();
      final repository = _Repository(delayed: release);
      await _pump(tester, repository);
      await repository.called.future;
      expect(
        find.text('Loading today’s payments and receipts'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      release.complete(_fixture());
      await tester.pumpAndSettle();
      expect(find.text('RWF 1,234,500'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('receipt alert navigates to an applied, validated queue filter', (
    tester,
  ) async {
    final repository = _Repository();
    final container = ProviderContainer(
      overrides: [
        adminAuthGuardProvider.overrideWithValue(
          const AdminAuthGuard(isAuthorized: true),
        ),
        adminRepositoryProvider.overrideWithValue(repository),
        adminIdentityProvider.overrideWith((_) async => _identity),
        adminClockProvider.overrideWithValue(() => _now),
        collectBackendClientProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(adminRouterProvider)..go('/admin');
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CollectAdminApp(),
      ),
    );
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Investigate unknown outcomes'));
    await tester.tap(find.text('Investigate unknown outcomes'));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/admin/sms-receipts?status=uncertain',
    );
    expect(repository.filters.last, 'uncertain');
    router.go('/admin/sms-receipts?status=not_a_real_state');
    await tester.pumpAndSettle();
    expect(repository.filters.last, '');
    expect(repository.writes, 0);
    expect(tester.takeException(), isNull);
  });
  for (final brightness in [Brightness.dark, Brightness.light]) {
    testWidgets(
      'synthetic ${brightness.name} Overview at320px enlarged text remains scrollable',
      (tester) async {
        await _pump(
          tester,
          _Repository(),
          size: const Size(320, 1000),
          scale: 2,
          brightness: brightness,
        );
        expect(tester.takeException(), isNull);
        final scroll = find.byKey(const Key('admin-overview-workspace'));
        await tester.scrollUntilVisible(
          find.text('Recent allocations'),
          700,
          scrollable: find
              .descendant(of: scroll, matching: find.byType(Scrollable))
              .first,
          maxScrolls: 30,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Recent allocations'), findsOneWidget);
      },
    );
    testWidgets('synthetic ${brightness.name} Overview capture', (
      tester,
    ) async {
      await _pump(
        tester,
        _Repository(),
        size: const Size(1440, 1400),
        brightness: brightness,
      );
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('COLLECT_CAPTURE_OPERATIONS')) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('overview-capture')),
          );
          final picture = await boundary.toImage(pixelRatio: 1);
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          collectTestCaptureFile(
            'overview-${brightness.name}-synthetic.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }
    });
  }
  group('SDK request and session fence', () {
    late CollectCloudflareClient client;
    late AdminRepository repository;
    final requests = <http.Request>[];
    late Future<http.Response> Function(http.Request) respond;
    setUp(() async {
      requests.clear();
      respond = (_) async => auth.response(_fixture());
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
          final response = await respond(request);
          return http.Response.bytes(
            response.bodyBytes,
            response.statusCode,
            headers: response.headers,
            request: request,
          );
        }),
      );
      await auth.session(client, 'session-a');
      repository = AdminRepository(client);
    });
    tearDown(() => client.dispose());
    test(
      'uses exact authenticated read and validates redacted response',
      () async {
        final data = await repository.receiptOverview(countryCode: 'RW');
        expect(data['scope'], 'rwanda_momo');
        expect(requests.single.url.path, '/v1/rpc/admin_receipt_overview_v1');
        expect(jsonDecode(requests.single.body), {'p_country': 'RW'});
        expect(
          requests.single.headers['Authorization'],
          'Bearer ${client.auth.currentSession!.accessToken}',
        );
      },
    );
    test(
      'unsupported country and signed-out request never reach service',
      () async {
        await expectLater(
          repository.receiptOverview(countryCode: 'MT'),
          throwsFormatException,
        );
        await client.auth.signOut();
        await expectLater(
          repository.receiptOverview(),
          throwsA(isA<AdminSessionChanged>()),
        );
        expect(requests, isEmpty);
      },
    );
    test('malformed response is not empty or healthy data', () async {
      respond = (_) async => auth.response({'contract_version': 1});
      await expectLater(repository.receiptOverview(), throwsFormatException);
    });
    test('same-owner session replacement suppresses delayed read', () async {
      final started = Completer<void>(), release = Completer<void>();
      respond = (_) async {
        started.complete();
        await release.future;
        return auth.response(_fixture());
      };
      final pending = repository.receiptOverview();
      final assertion = expectLater(
        pending,
        throwsA(isA<AdminSessionChanged>()),
      );
      await started.future;
      await auth.session(client, 'session-b');
      release.complete();
      await assertion;
    });
  });
}
