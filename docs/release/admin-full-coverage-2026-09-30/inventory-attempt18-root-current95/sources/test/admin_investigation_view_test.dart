import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/admin/admin_app.dart';
import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_investigation.dart';
import 'package:collect_app/admin/core/admin_investigation_view.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _sms = '11111111-1111-4111-8111-111111111111';
const _receipt = '44444444-4444-4444-8444-444444444444';
final _now = DateTime.utc(2026, 9, 30, 19, 0, 30);
const _identity = AdminIdentity(
  userId: 'synthetic',
  displayName: 'Synthetic reviewer',
  roles: ['admin'],
  permissions: [
    'payments.read',
    'notifications.read',
    'collections.read',
    'members.read',
  ],
);
Map<String, dynamic> _fixture() =>
    jsonDecode(
          File('test/fixtures/admin_investigation_v1.json').readAsStringSync(),
        )
        as Map<String, dynamic>;

class _Repository extends AdminEvidenceRepository {
  _Repository({Map<String, dynamic>? data, this.error, this.delayed})
    : data = data ?? _fixture();
  final Map<String, dynamic> data;
  final Object? error;
  final Completer<Map<String, dynamic>>? delayed;
  int reads = 0, writes = 0;
  final targets = <(String, String)>[];
  @override
  Future<Map<String, dynamic>> investigation({
    required String kind,
    required String id,
  }) async {
    reads++;
    targets.add((kind, id));
    if (error != null) throw error!;
    if (delayed != null) return delayed!.future;
    return Map<String, dynamic>.from(data)
      ..['kind'] = kind
      ..['target_id'] = id;
  }

  @override
  Future<Map<String, dynamic>> detail(String rpcName, String id) async => {
    'id': id,
    'raw_sms_id': _sms,
    'state': 'uncertain',
  };
  @override
  Future<Map<String, dynamic>> action(
    String rpcName,
    Map<String, dynamic> params,
  ) async {
    writes++;
    return {};
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Repository repository, {
  AdminIdentity? identity = _identity,
  Size size = const Size(1440, 3000),
  double scale = 1,
  Brightness brightness = Brightness.dark,
  DateTime Function()? clock,
  String kind = 'transaction',
  String id = _sms,
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
        supabaseClientProvider.overrideWithValue(null),
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
        home: Scaffold(
          body: RepaintBoundary(
            key: const Key('investigation-capture'),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: AdminInvestigationView(kind: kind, id: id),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final name in [
    'observed-posted-transaction',
    'observed-posted-receipt',
    'observed-reversed-transaction',
    'observed-bounded-history',
  ]) {
    test(
      'isolated SQL observation $name satisfies current investigation DTO',
      () {
        final data =
            jsonDecode(
                  File(
                    'docs/release/collect-codex-goal-2026-09-30/investigation-backend/$name.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        final parsed = AdminInvestigationSnapshot.parse(data);
        expect(parsed.scope, 'rwanda_momo');
        expect(parsed.kind, data['kind']);
        expect(parsed.targetId, data['target_id']);
        expect(parsed.checkedAt.toIso8601String(), isNotEmpty);
      },
    );
  }
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
    'typed posting evidence retains distinct source timestamps and bigint balances',
    () {
      final data = AdminInvestigationSnapshot.parse(_fixture());
      expect(data.payment!.journals.single.snapshot!.memberRwf, '6700');
      expect(data.payment!.currentBalances.memberRwf, '7900');
      expect(
        data.payment!.times['provider_confirmed_at'],
        DateTime.utc(2026, 9, 30, 18, 59, 55),
      );
      expect(
        data.payment!.times['confirmation_recorded_at'],
        DateTime.utc(2026, 9, 30, 19, 0, 3),
      );
      expect(data.receipt!.attempts.single.state, 'uncertain');
      expect(data.isFresh(_now), isTrue);
      expect(data.isFresh(_now.add(const Duration(seconds: 60))), isFalse);
      final raw = _fixture();
      raw['receipt']['group_balance_rwf'] = '9223372036854775807';
      raw['payment']['journals'][0]['snapshot']['group_balance_rwf'] =
          '9223372036854775807';
      expect(
        AdminInvestigationSnapshot.parse(raw).receipt!.groupRwf,
        '9223372036854775807',
      );
    },
  );
  test(
    'strict projection rejects extra private fields invalid enums scalars dates and inconsistent evidence',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (d) => d['body_sha256'] = 'private',
        (d) => d['history_limit'] = 50.0,
        (d) => d['scope'] = 'all_money',
        (d) => d['checked_at'] = '2026-02-30T19:00:30Z',
        (d) => d['target_id'] = _receipt,
        (d) => d['receipt']['state'] = 'delivered',
        (d) => d['receipt']['amount_rwf'] = 1200,
        (d) => d['receipt']['amount_rwf'] = '9223372036854775808',
        (d) => d['receipt']['masked_destination'] = '+250723456123',
        (d) => d['receipt']['masked_snapshot_preview'] = '+250723456123',
        (d) => d['receipt']['attempts'][0]['outcome_at'] = null,
        (d) => d['payment']['current_balances']['member_updated_at'] = null,
        (d) => d['payment']['journals'][0]['snapshot']['delta_rwf'] = '-1200',
      ]) {
        final raw = _fixture();
        mutate(raw);
        expect(
          () => AdminInvestigationSnapshot.parse(raw),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'partial history is explicit and duplicate attempt identities are rejected',
    () {
      final raw = _fixture();
      final rows = <Map<String, dynamic>>[];
      for (var i = 50; i >= 1; i--) {
        rows.add(
          Map<String, dynamic>.from(raw['receipt']['attempts'][0] as Map)
            ..['id'] =
                'aaaaaaaa-aaaa-4aaa-8aaa-${i.toString().padLeft(12, '0')}'
            ..['attempt_number'] = i,
        );
      }
      raw['receipt']['attempts'] = rows;
      raw['receipt']['attempt_total'] = 52;
      expect(
        AdminInvestigationSnapshot.parse(raw).receipt!.partialHistory,
        isTrue,
      );
      rows[1]['id'] = rows[0]['id'];
      expect(
        () => AdminInvestigationSnapshot.parse(raw),
        throwsFormatException,
      );
    },
  );
  testWidgets(
    'read-only evidence labels snapshot vs current values and refresh performs only reads',
    (tester) async {
      final repository = _Repository();
      await _pump(tester, repository);
      expect(
        find.text('Member balance at this posting: RWF 6,700'),
        findsOneWidget,
      );
      expect(find.textContaining('Member: RWF 7,900'), findsOneWidget);
      expect(find.text('Masked snapshot reconstruction'), findsOneWidget);
      expect(find.textContaining('original sent message'), findsOneWidget);
      expect(
        find.textContaining('Carrier delivery, provider callback'),
        findsOneWidget,
      );
      expect(find.textContaining('Parsed event recorded'), findsOneWidget);
      expect(find.text('Send'), findsNothing);
      await tester.ensureVisible(find.text('Refresh investigation'));
      await tester.tap(find.text('Refresh investigation'));
      await tester.pumpAndSettle();
      expect(repository.reads, 2);
      expect(repository.writes, 0);
    },
  );
  testWidgets('missing permission makes no protected read', (tester) async {
    final repository = _Repository();
    await _pump(
      tester,
      repository,
      identity: const AdminIdentity(
        userId: 's',
        displayName: 's',
        roles: [],
        permissions: [],
      ),
    );
    expect(repository.reads, 0);
    expect(find.text('Investigation access denied'), findsOneWidget);
  });
  testWidgets(
    'denial unsupported and malformed service states remain distinct and redacted',
    (tester) async {
      for (final pair in <(Object, String)>[
        (
          const PostgrestException(message: 'private-canary', code: '42501'),
          'Investigation access denied',
        ),
        (
          const PostgrestException(message: 'private-canary', code: 'PGRST202'),
          'Investigation unavailable',
        ),
        (const FormatException('private-canary'), 'Investigation read failed'),
      ]) {
        await _pump(tester, _Repository(error: pair.$1));
        expect(find.text(pair.$2), findsOneWidget);
        expect(find.textContaining('private-canary'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );
  testWidgets(
    'stale hides current balances and reconstruction while refresh remains available',
    (tester) async {
      var now = _now;
      await _pump(tester, _Repository(), clock: () => now);
      now = now.add(const Duration(seconds: 60));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Investigation stale'), findsOneWidget);
      expect(find.textContaining('Member: RWF 7,900'), findsNothing);
      expect(find.byKey(const Key('masked-snapshot-preview')), findsNothing);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNotNull,
      );
    },
  );
  testWidgets(
    'payment survives notification denial; receipt-only permission hides current balance',
    (tester) async {
      final raw = _fixture()
        ..['receipt_state'] = 'denied'
        ..['receipt'] = null;
      await _pump(tester, _Repository(data: raw));
      expect(find.text('Receipt evidence access required'), findsOneWidget);
      expect(
        find.text('Member balance at this posting: RWF 6,700'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      final receipt = _fixture()
        ..['kind'] = 'receipt'
        ..['target_id'] = _receipt
        ..['payment_state'] = 'denied'
        ..['payment'] = null;
      await _pump(
        tester,
        _Repository(data: receipt),
        kind: 'receipt',
        id: _receipt,
        identity: const AdminIdentity(
          userId: 's',
          displayName: 's',
          roles: [],
          permissions: ['notifications.read'],
        ),
      );
      expect(find.text('Payment evidence access required'), findsOneWidget);
      expect(find.text('Current recorded balances'), findsNothing);
      expect(find.byKey(const Key('masked-snapshot-preview')), findsOneWidget);
      expect(find.text('Open transaction'), findsNothing);
    },
  );
  testWidgets(
    'unclassified targets show unsupported scope without inferred Rwanda evidence',
    (tester) async {
      final raw = _fixture()
        ..['scope'] = 'unclassified'
        ..['payment_state'] = 'unsupported'
        ..['payment'] = null
        ..['receipt_state'] = 'unsupported'
        ..['receipt'] = null;
      await _pump(tester, _Repository(data: raw));
      expect(find.text('Scope: unclassified'), findsOneWidget);
      expect(find.text('Scope: Rwanda MoMo'), findsNothing);
      expect(find.text('Payment evidence unsupported'), findsOneWidget);
      expect(find.text('Receipt evidence unsupported'), findsOneWidget);
      expect(find.byKey(const Key('masked-snapshot-preview')), findsNothing);
      expect(find.text('Current recorded balances'), findsNothing);
    },
  );
  testWidgets('pending disposed read never publishes evidence', (tester) async {
    final delayed = Completer<Map<String, dynamic>>();
    final repository = _Repository(delayed: delayed);
    await _pump(tester, repository);
    expect(repository.reads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    delayed.complete(_fixture());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('masked-snapshot-preview')), findsNothing);
  });
  testWidgets(
    'registered detail cross-link opens actual receipt route and refreshes its target',
    (tester) async {
      final repository = _Repository();
      tester.view.physicalSize = const Size(1440, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(
        overrides: [
          adminAuthGuardProvider.overrideWithValue(
            const AdminAuthGuard(isAuthorized: true),
          ),
          adminRepositoryProvider.overrideWithValue(repository),
          adminIdentityProvider.overrideWith((_) async => _identity),
          adminClockProvider.overrideWithValue(() => _now),
          supabaseClientProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(adminRouterProvider)
        ..go('/admin/transactions/momo:$_sms');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CollectAdminApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.targets, contains(('transaction', _sms)));
      await tester.ensureVisible(find.text('Open SMS receipt'));
      await tester.tap(find.text('Open SMS receipt'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/admin/sms-receipts/$_receipt',
      );
      expect(repository.targets, contains(('receipt', _receipt)));
      expect(tester.takeException(), isNull);
    },
  );
  for (final brightness in [Brightness.dark, Brightness.light]) {
    testWidgets(
      '${brightness.name} 320px 2x text scrolls to accessible timeline',
      (tester) async {
        await _pump(
          tester,
          _Repository(),
          size: const Size(320, 900),
          scale: 2,
          brightness: brightness,
        );
        await tester.ensureVisible(find.text('Recorded timeline'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final handle = tester.ensureSemantics();
        expect(find.bySemanticsLabel('Recorded timeline'), findsOneWidget);
        handle.dispose();
      },
    );
    testWidgets('${brightness.name} desktop synthetic capture', (tester) async {
      await _pump(tester, _Repository(), brightness: brightness);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('COLLECT_CAPTURE_OPERATIONS')) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('investigation-capture')),
          );
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'docs/release/collect-codex-goal-2026-09-30/admin-investigation/investigation-${brightness.name}-synthetic.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}
