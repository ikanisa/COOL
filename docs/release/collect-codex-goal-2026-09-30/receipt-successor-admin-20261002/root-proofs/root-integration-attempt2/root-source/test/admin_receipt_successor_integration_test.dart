import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_investigation_view.dart';
import 'package:collect_app/admin/core/admin_models.dart';
import 'package:collect_app/admin/core/admin_runtime.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_host.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/successor_fixture.dart';

class _Session extends AdminSessionController {
  _Session(SuccessorFixture f) : super(null) {
    state = (key: f.session!, generation: 1);
  }
}

class _Repository extends AdminRepository {
  _Repository(this.fixture) : super(null);
  final SuccessorFixture fixture;
  int reads = 0;
  Completer<Map<String, dynamic>>? delayed;
  bool wrongTarget = false, missingReceipt = false;

  // This synthetic joined-view fixture tests the real caller's identifier and
  // freshness binding. Successor DTO producer evidence is separately tested
  // against exact retained closure/approval SQL observations.
  Map<String, dynamic> joined(String kind, String id) {
    final row =
        jsonDecode(
              File(
                'test/fixtures/admin_investigation_v1.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    row['kind'] = kind;
    row['target_id'] = wrongTarget
        ? '11111111-1111-4111-8111-111111111111'
        : id;
    row['checked_at'] = stamp(fixture.now);
    row['sample_valid_until'] = stamp(
      fixture.now.add(const Duration(seconds: 60)),
    );
    if (missingReceipt) {
      row['receipt'] = null;
      row['receipt_state'] = 'missing';
    } else {
      (row['receipt'] as Map)['id'] = fixture.outbox;
      (row['receipt'] as Map)['snapshot_id'] = fixture.source;
      (((row['payment'] as Map)['journals'] as List).single
              as Map)['snapshot']['id'] =
          fixture.source;
    }
    return row;
  }

  @override
  Future<Map<String, dynamic>> investigation({
    required String kind,
    required String id,
  }) async {
    reads++;
    if (delayed != null) return delayed!.future;
    return joined(kind, id);
  }

  @override
  Future<Map<String, dynamic>> rpcMap(
    String name, {
    Map<String, dynamic>? params,
    bool automaticRetry = true,
  }) async {
    if (!{
      'admin_inspect_unarmed_receipt_closure_v1',
      'admin_inspect_receipt_successor_v1',
      'admin_list_receipt_successors_v1',
      'admin_approve_receipt_successor_v1',
      'admin_get_receipt_successor_request_v1',
    }.contains(name)) {
      throw UnsupportedError('Unrelated legacy card fixture');
    }
    expect(automaticRetry, isFalse);
    return Map<String, dynamic>.from(
      await fixture.rpc(name, params ?? {}) as Map,
    );
  }
}

Future<ProviderContainer> _mount(
  WidgetTester tester,
  _Repository repository, {
  Size size = const Size(1440, 1200),
}) async {
  final f = repository.fixture;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      adminRepositoryProvider.overrideWithValue(repository),
      adminAuthSessionScopeProvider.overrideWith((_) => _Session(f)),
      adminIdentityProvider.overrideWith(
        (_) async => AdminIdentity(
          userId: f.session!.userId,
          displayName: 'Synthetic owner',
          roles: ['platform_owner'],
          permissions: [
            'payments.read',
            'notifications.read',
            'system_health.read',
            'notifications.manage',
          ],
        ),
      ),
      adminClockProvider.overrideWithValue(() => f.now),
      adminReceiptSuccessorStoreProvider.overrideWithValue(MemoryStore()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: RepaintBoundary(
          key: const Key('root-review-capture'),
          child: Scaffold(
            body: SingleChildScrollView(
              child: AdminInvestigationView(kind: 'receipt', id: f.outbox),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final width in [390.0, 1440.0]) {
    testWidgets('fresh investigation binds actual review SDK at ${width}px', (
      tester,
    ) async {
      final repository = _Repository(SuccessorFixture());
      // One producer fixture owns all route bindings for this case.
      final fixture = repository.fixture;
      await _mount(tester, repository, size: Size(width, 1200));
      expect(find.byType(AdminReceiptSuccessorHost), findsOneWidget);
      expect(find.text('Replacement receipt review'), findsOneWidget);
      final call = fixture.calls.singleWhere(
        (c) => c.name == 'admin_inspect_receipt_successor_v1',
      );
      expect(call.params['p_outbox_id'], fixture.outbox);
      expect(call.params['p_source_snapshot_id'], fixture.source);
      expect(
        call.params.keys,
        unorderedEquals(['p_outbox_id', 'p_action', 'p_source_snapshot_id']),
      );
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('COLLECT_CAPTURE_SUCCESSOR_INTEGRATION')) {
        await tester.ensureVisible(find.text('Replacement receipt review'));
        await tester.pump();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('root-review-capture')),
        );
        await tester.runAsync(() async {
          final captured = await boundary.toImage(pixelRatio: 1);
          final bytes = await captured.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final output = Directory('proof-artifacts')..createSync();
          File(
            '${output.path}/root-review-${width.toInt()}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          captured.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('pending investigation cannot start successor reads', (
    tester,
  ) async {
    final repository = _Repository(SuccessorFixture());
    repository.delayed = Completer<Map<String, dynamic>>();
    await _mount(tester, repository);
    expect(find.byType(AdminReceiptSuccessorHost), findsNothing);
    expect(repository.fixture.calls, isEmpty);
    repository.delayed!.complete(
      repository.joined('receipt', repository.fixture.outbox),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AdminReceiptSuccessorHost), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('stale investigation withdraws successor view and actions', (
    tester,
  ) async {
    final repository = _Repository(SuccessorFixture());
    await _mount(tester, repository);
    expect(find.byType(AdminReceiptSuccessorHost), findsOneWidget);
    final count = repository.fixture.calls.length;
    repository.fixture.now = repository.fixture.now.add(
      const Duration(seconds: 61),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AdminReceiptSuccessorHost), findsNothing);
    expect(find.text('Review replacement'), findsNothing);
    expect(repository.fixture.calls.length, count);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('loading refresh with prior data withdraws successor view', (
    tester,
  ) async {
    final repository = _Repository(SuccessorFixture());
    final container = await _mount(tester, repository);
    expect(find.byType(AdminReceiptSuccessorHost), findsOneWidget);
    final count = repository.fixture.calls.length;
    repository.delayed = Completer<Map<String, dynamic>>();
    container.invalidate(
      adminInvestigationProvider((
        kind: 'receipt',
        id: repository.fixture.outbox,
      )),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.byType(AdminReceiptSuccessorHost), findsNothing);
    expect(repository.fixture.calls.length, count);
    repository.delayed!.complete(
      repository.joined('receipt', repository.fixture.outbox),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AdminReceiptSuccessorHost), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('mismatched target and missing receipt never mount successor', (
    tester,
  ) async {
    for (final mismatch in [true, false]) {
      final repository = _Repository(SuccessorFixture())
        ..wrongTarget = mismatch
        ..missingReceipt = !mismatch;
      await _mount(tester, repository);
      expect(find.byType(AdminReceiptSuccessorHost), findsNothing);
      expect(repository.fixture.calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
    'actual approval records once and refreshes original investigation',
    (tester) async {
      final repository = _Repository(SuccessorFixture());
      await _mount(tester, repository);
      await tester.ensureVisible(find.text('Review replacement'));
      await tester.tap(find.text('Review replacement'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.byType(TextField),
        'Reviewed never-armed evidence',
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Approve replacement receipt'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.reads, 2);
      expect(
        repository.fixture.calls
            .where((c) => c.name == 'admin_approve_receipt_successor_v1')
            .length,
        1,
      );
      expect(
        repository.fixture.recorded?['outbox_id'],
        repository.fixture.outbox,
      );
      expect(
        repository.fixture.recorded?['source_snapshot_id'],
        repository.fixture.source,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
