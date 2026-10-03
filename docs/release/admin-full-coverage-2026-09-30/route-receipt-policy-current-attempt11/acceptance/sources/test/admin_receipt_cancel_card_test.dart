import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:collect_app/admin/admin_shell.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_investigation_view.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/admin_receipt_cancel_models.dart';
import 'package:collect_app/admin/core/admin_receipt_cancel_checkpoint.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/app/theme/collect_runtime_assets.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_receipt_cancel_models_test.dart' as wire;

const _actor = AdminIdentity(
  userId: '99710000-0000-4000-8000-000000000001',
  displayName: 'Synthetic cancellation reviewer',
  roles: ['platform_owner'],
  permissions: [
    'payments.read',
    'notifications.read',
    'system_health.read',
    'notifications.manage',
  ],
);
final _id = wire.cancelIntent().outboxId;
final _now = DateTime.parse(
  wire.cancelFixture('recorded-lookup')['checked_at'] as String,
);
String _iso(DateTime time) =>
    '${time.toUtc().toIso8601String().split('.').first}.${time.millisecond.toString().padLeft(3, '0')}${time.microsecond.toString().padLeft(3, '0')}Z';

class _Sessions extends AdminSessionController {
  _Sessions({String userId = _actorId, int generation = 1}) : super(null) {
    change(generation, userId: userId);
  }
  static const _actorId = '99710000-0000-4000-8000-000000000001';
  void change(int generation, {String userId = _actorId}) => state = (
    key: (userId: userId, sessionId: 'synthetic-$generation'),
    generation: generation,
  );
}

class _Store implements AdminReceiptCancelCheckpointStore {
  final values = <String, String>{};
  bool failWrite = false, corrupt = false, failClear = false;
  @override
  String? read(String owner) =>
      corrupt && values.containsKey(owner) ? '{}' : values[owner];
  @override
  void write(String owner, String encoded) {
    if (failWrite) throw StateError('PRIVATE_STORAGE_CANARY');
    values[owner] = encoded;
  }

  @override
  void clear(String owner) {
    if (failClear) throw StateError('PRIVATE_STORAGE_CANARY');
    values.remove(owner);
  }
}

class _Repository extends AdminEvidenceRepository {
  _Repository(this.store);
  final _Store store;
  AdminIdentity? actor = _actor;
  Map<String, dynamic> inspection = wire.cancelFixture(
    'preexisting-eligible-inspection',
  );
  Object? inspectError, writeError, lookupError;
  Completer<Map<String, dynamic>>? inspectGate;
  Completer<AdminReceiptCancelReceipt>? writeGate;
  Completer<Map<String, dynamic>>? lookupGate;
  DateTime serverNow = _now;
  final inspectionIds = <String>[], lookupIds = <String>[];
  final intents = <AdminReceiptCancelIntent>[];
  String lookupStatus = 'recorded';
  bool mismatch = false, inspectionUnavailable = false;
  @override
  Future<AdminIdentity?> currentIdentity() async => actor;
  @override
  Future<Map<String, dynamic>> inspectUnstartedReceipt(String id) async {
    inspectionIds.add(id);
    if (inspectError != null) throw inspectError!;
    if (inspectGate != null) return inspectGate!.future;
    return wire.cancelCopy(inspection)
      ..['outbox_id'] = id
      ..['receipt'] = inspectionUnavailable
          ? null
          : {...inspection['receipt'] as Map, 'outbox_id': id}
      ..['status'] = inspectionUnavailable ? 'unavailable' : 'available';
  }

  Map<String, dynamic> receipt(AdminReceiptCancelIntent intent) =>
      wire.cancelFixture('cancelled-action')
        ..['request_id'] = intent.requestId
        ..['outbox_id'] = intent.outboxId
        ..['expected_revision'] = intent.revision
        ..['revision'] = intent.revision + 1
        ..['reason_code'] = intent.reason.wire
        ..['recorded_at'] = _iso(_now);
  @override
  Future<AdminReceiptCancelReceipt> cancelUnstartedReceipt(
    AdminReceiptCancelIntent intent,
  ) async {
    final saved = AdminReceiptCancelCheckpoint.parse(
      store.values[adminReceiptCancelOwnerDigest(_actor.userId)]!,
      adminReceiptCancelOwnerDigest(_actor.userId),
    );
    expect(saved.intent.parameters, intent.parameters);
    intents.add(intent);
    if (writeGate != null) return writeGate!.future;
    if (writeError != null) throw writeError!;
    inspection = wire.cancelFixture('cancelled-inspection');
    return AdminReceiptCancelReceipt.parse(receipt(intent), intent: intent);
  }

  @override
  Future<Map<String, dynamic>> unstartedReceiptAction(String id) async {
    lookupIds.add(id);
    if (lookupError != null) throw lookupError!;
    if (lookupGate != null) return lookupGate!.future;
    final intent = intents.isEmpty ? wire.cancelIntent() : intents.last;
    final result = wire.cancelFixture('recorded-lookup')
      ..['request_id'] = id
      ..['checked_at'] = _iso(serverNow)
      ..['sample_valid_until'] = _iso(
        serverNow.add(const Duration(seconds: 60)),
      )
      ..['status'] = lookupStatus;
    result['receipt'] = lookupStatus == 'recorded' ? receipt(intent) : null;
    if (mismatch) {
      (result['receipt'] as Map)['reason_code'] = 'content_review_required';
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> investigation({
    required String kind,
    required String id,
  }) async =>
      throw UnsupportedError('synthetic joined investigation unavailable');
}

Future<ProviderContainer> _mount(
  WidgetTester tester,
  _Repository repo,
  _Store store, {
  AdminIdentity identity = _actor,
  _Sessions? sessions,
  DateTime Function()? clock,
  bool integrated = false,
  bool shell = false,
  bool dark = true,
  double width = 1440,
  double scale = 1,
  GlobalKey? capture,
  String? outboxId,
}) async {
  tester.view.physicalSize = Size(width, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      supabaseClientProvider.overrideWithValue(null),
      adminIdentityProvider.overrideWith((ref) async => identity),
      adminRepositoryProvider.overrideWithValue(repo),
      adminClockProvider.overrideWithValue(clock ?? () => _now),
      adminAuthSessionScopeProvider.overrideWith(
        (ref) => sessions ?? _Sessions(userId: identity.userId),
      ),
      adminReceiptCancelCheckpointStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(container.dispose);
  final content = SingleChildScrollView(
    child: integrated
        ? AdminInvestigationView(kind: 'receipt', id: outboxId ?? _id)
        : AdminReceiptCancelCard(outboxId: outboxId ?? _id),
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: dark ? CollectTheme.dark() : CollectTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: RepaintBoundary(
            key: capture,
            child: shell
                ? AdminShell(
                    location: '/admin/sms-receipts/${outboxId ?? _id}',
                    child: content,
                  )
                : content,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (capture != null) {
    await tester.runAsync(
      () => precacheImage(
        const AssetImage(CollectRuntimeAssets.officialLogo),
        capture.currentContext!,
      ),
    );
    await tester.pumpAndSettle();
  }
  return container;
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  expect(tester.takeException(), isNull);
}

Future<void> _show(WidgetTester tester, Finder find) async {
  await tester.ensureVisible(find);
  await tester.pumpAndSettle();
}

Future<void> _review(WidgetTester tester, {bool submit = true}) async {
  await _show(tester, find.text('Review cancellation'));
  await tester.tap(find.text('Review cancellation'));
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Confirm cancellation'),
        )
        .onPressed,
    isNull,
  );
  await tester.tap(find.byKey(const Key('receipt-cancel-reason')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Operator cancellation').last);
  await tester.pumpAndSettle();
  if (submit) {
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm cancellation'));
    await tester.pumpAndSettle();
  }
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final missing in [
    'platform_owner',
    'payments.read',
    'notifications.read',
    'system_health.read',
  ]) {
    testWidgets('missing $missing prevents all cancellation reads and writes', (
      tester,
    ) async {
      final store = _Store(), repo = _Repository(store);
      final denied = AdminIdentity(
        userId: _actor.userId,
        displayName: 'Synthetic denied',
        roles: missing == 'platform_owner' ? ['admin'] : _actor.roles,
        permissions: _actor.permissions.where((v) => v != missing).toList(),
      );
      await _mount(tester, repo, store, identity: denied);
      expect(repo.inspectionIds, isEmpty);
      expect(repo.intents, isEmpty);
      expect(find.text('Cancellation access required'), findsOneWidget);
      await _finish(tester);
    });
  }
  testWidgets('read-only operator sees eligibility without mutation control', (
    tester,
  ) async {
    final store = _Store(), repo = _Repository(store);
    final actor = AdminIdentity(
      userId: _actor.userId,
      displayName: 'Synthetic readonly',
      roles: _actor.roles,
      permissions: _actor.permissions
          .where((v) => v != 'notifications.manage')
          .toList(),
    );
    await _mount(tester, repo, store, identity: actor);
    expect(find.text('Eligible for cancellation'), findsOneWidget);
    expect(find.text('Review cancellation'), findsNothing);
    await _finish(tester);
  });
  testWidgets(
    'receipt investigation remains separate when joined evidence unavailable',
    (tester) async {
      final store = _Store(), repo = _Repository(store);
      await _mount(tester, repo, store, integrated: true);
      expect(find.text('Investigation unavailable'), findsOneWidget);
      expect(find.text('Cancel an unstarted receipt'), findsOneWidget);
      expect(repo.inspectionIds, [_id]);
      await _finish(tester);
    },
  );
  testWidgets(
    'explicit reason and verified exact checkpoint precede one action; confirmed receipt refreshes source',
    (tester) async {
      final store = _Store(), repo = _Repository(store);
      await _mount(tester, repo, store);
      await _review(tester);
      expect(repo.intents, hasLength(1));
      expect(store.values, isEmpty);
      expect(find.text('Cancellation recorded'), findsOneWidget);
      expect(
        find.text('Blocked: this receipt was already cancelled'),
        findsOneWidget,
      );
      expect(repo.inspectionIds, [_id, _id]);
      await _finish(tester);
    },
  );
  for (final corruption in [false, true]) {
    testWidgets(
      'storage ${corruption ? 'readback corruption' : 'write failure'} prevents action',
      (tester) async {
        final store = _Store()
          ..failWrite = !corruption
          ..corrupt = corruption;
        final repo = _Repository(store);
        await _mount(tester, repo, store);
        await _review(tester);
        expect(repo.intents, isEmpty);
        expect(find.textContaining('PRIVATE_STORAGE_CANARY'), findsNothing);
        await _finish(tester);
      },
    );
  }
  testWidgets(
    'inspection TTL hides source and prevents reviewed stale submission',
    (tester) async {
      final store = _Store(), repo = _Repository(store);
      var now = _now;
      await _mount(tester, repo, store, clock: () => now);
      await _review(tester, submit: false);
      now = now.add(const Duration(minutes: 2));
      await tester.tap(
        find.widgetWithText(FilledButton, 'Confirm cancellation'),
      );
      await tester.pumpAndSettle();
      expect(repo.intents, isEmpty);
      expect(store.values, isEmpty);
      expect(find.text('Cancellation inspection expired'), findsOneWidget);
      await _finish(tester);
    },
  );
  testWidgets('current authority loss after dialog blocks mutation', (
    tester,
  ) async {
    final store = _Store(), repo = _Repository(store);
    await _mount(tester, repo, store);
    await _review(tester, submit: false);
    repo.actor = AdminIdentity(
      userId: _actor.userId,
      displayName: 'Revoked',
      roles: ['admin'],
      permissions: _actor.permissions,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm cancellation'));
    await tester.pumpAndSettle();
    expect(repo.intents, isEmpty);
    await _finish(tester);
  });
  testWidgets(
    'session replacement closes reviewed dialog without saving or submitting',
    (tester) async {
      final store = _Store(), repo = _Repository(store), sessions = _Sessions();
      await _mount(tester, repo, store, sessions: sessions);
      await _review(tester, submit: false);
      sessions.change(2);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(repo.intents, isEmpty);
      expect(store.values, isEmpty);
      await _finish(tester);
    },
  );
  for (final status in [
    'not_recorded',
    'in_progress',
    'busy',
    'mismatch',
    'missing',
    'stale',
  ]) {
    testWidgets(
      '$status recovery retains original UUID and blocks a new cancellation',
      (tester) async {
        final store = _Store(),
            repo = _Repository(store)
              ..writeError = TimeoutException('PRIVATE_CANARY');
        var now = _now;
        await _mount(tester, repo, store, clock: () => now);
        await _review(tester);
        final request = repo.intents.single.requestId;
        await _finish(tester);
        await _mount(
          tester,
          repo,
          store,
          sessions: _Sessions(generation: 2),
          clock: () => now,
        );
        expect(repo.lookupIds, isEmpty);
        expect(repo.intents, hasLength(1));
        if (status == 'busy') {
          repo.lookupError = const PostgrestException(
            message: 'PRIVATE_CANARY',
            code: '55P03',
          );
        }
        if (status == 'missing') {
          repo.lookupError = StateError('PRIVATE_CANARY');
        }
        if (status == 'mismatch') repo.mismatch = true;
        if ({'not_recorded', 'in_progress'}.contains(status)) {
          repo.lookupStatus = status;
        }
        await _show(tester, find.text('Check original request'));
        await tester.tap(find.text('Check original request'));
        await tester.pumpAndSettle();
        if (status == 'stale') {
          now = now.add(const Duration(minutes: 2));
          await tester.pump(const Duration(seconds: 1));
        }
        expect(store.values, hasLength(1));
        expect(repo.lookupIds, [request]);
        expect(
          find.text('Use confirmed cancellation and refresh'),
          findsNothing,
        );
        expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Review cancellation'),
              )
              .onPressed,
          isNull,
        );
        await _finish(tester);
      },
    );
  }
  testWidgets(
    'later not-recorded lookup remains uncertainty and cannot replace UUID',
    (tester) async {
      final store = _Store(),
          repo = _Repository(store)
            ..writeError = TimeoutException('synthetic')
            ..lookupStatus = 'not_recorded';
      await _mount(tester, repo, store);
      await _review(tester);
      await _finish(tester);
      repo.serverNow = _now.add(const Duration(days: 7));
      await _mount(
        tester,
        repo,
        store,
        sessions: _Sessions(generation: 3),
        clock: () => _now.add(const Duration(days: 7)),
      );
      await _show(tester, find.text('Check original request'));
      await tester.tap(find.text('Check original request'));
      await tester.pumpAndSettle();
      expect(store.values, hasLength(1));
      expect(repo.intents, hasLength(1));
      expect(
        find.text('Original request not recorded at this check'),
        findsOneWidget,
      );
      await _finish(tester);
    },
  );
  testWidgets(
    'confirmed exact original receipt clears checkpoint under fresh owner session without replay',
    (tester) async {
      final store = _Store(),
          repo = _Repository(store)..writeError = TimeoutException('synthetic');
      await _mount(tester, repo, store);
      await _review(tester);
      await _finish(tester);
      await _mount(tester, repo, store, sessions: _Sessions(generation: 2));
      await _show(tester, find.text('Check original request'));
      await tester.tap(find.text('Check original request'));
      await tester.pumpAndSettle();
      await _show(tester, find.text('Use confirmed cancellation and refresh'));
      await tester.tap(find.text('Use confirmed cancellation and refresh'));
      await tester.pumpAndSettle();
      expect(store.values, isEmpty);
      expect(repo.intents, hasLength(1));
      await _finish(tester);
    },
  );
  testWidgets(
    'source-changed action refusal keeps original request for reconciliation',
    (tester) async {
      final store = _Store(),
          repo = _Repository(store)
            ..writeError = const PostgrestException(
              message: 'receipt_action_source_changed',
              code: '55000',
            );
      await _mount(tester, repo, store);
      await _review(tester);
      expect(store.values, hasLength(1));
      expect(repo.intents, hasLength(1));
      expect(find.textContaining('outcome unconfirmed'), findsOneWidget);
      await _finish(tester);
    },
  );
  testWidgets(
    'original request for another receipt blocks new work and exposes canonical original link',
    (tester) async {
      final store = _Store(),
          repo = _Repository(store)..writeError = TimeoutException('synthetic');
      await _mount(tester, repo, store);
      await _review(tester);
      await _finish(tester);
      await _mount(
        tester,
        repo,
        store,
        outboxId: '99710000-0000-4000-8000-000000000099',
      );
      expect(find.text('Open original receipt'), findsOneWidget);
      expect(repo.lookupIds, isEmpty);
      expect(repo.intents, hasLength(1));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Review cancellation'),
            )
            .onPressed,
        isNull,
      );
      await _finish(tester);
    },
  );
  testWidgets('different owner cannot expose stored request', (tester) async {
    final store = _Store(),
        repo = _Repository(store)..writeError = TimeoutException('synthetic');
    await _mount(tester, repo, store);
    await _review(tester);
    final request = repo.intents.single.requestId;
    await _finish(tester);
    final other = AdminIdentity(
      userId: '99710000-0000-4000-8000-000000000099',
      displayName: 'Other synthetic',
      roles: _actor.roles,
      permissions: _actor.permissions,
    );
    await _mount(
      tester,
      repo,
      store,
      identity: other,
      sessions: _Sessions(userId: other.userId),
    );
    expect(find.textContaining(request), findsNothing);
    expect(repo.lookupIds, isEmpty);
    expect(store.values, hasLength(1));
    await _finish(tester);
  });
  for (final fixture in [
    'prior-attempt-inspection',
    'revision-exhausted-inspection',
    'unavailable-inspection',
  ]) {
    testWidgets('actual $fixture exposes no eligible mutation', (tester) async {
      final store = _Store(), repo = _Repository(store);
      repo.inspection = wire.cancelFixture(fixture);
      repo.inspectionUnavailable = repo.inspection['receipt'] == null;
      final sourceId = repo.inspection['outbox_id'] as String;
      await _mount(
        tester,
        repo,
        store,
        outboxId: sourceId,
        clock: () => DateTime.parse(repo.inspection['checked_at'] as String),
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Review cancellation'),
            )
            .onPressed,
        isNull,
      );
      expect(repo.intents, isEmpty);
      if (repo.inspectionUnavailable) {
        expect(find.text('Cancellation unavailable'), findsOneWidget);
        expect(find.textContaining('Recorded state:'), findsNothing);
      } else {
        final parsed = AdminReceiptCancelInspection.parse(
          repo.inspection,
          outboxId: sourceId,
        );
        expect(find.text(parsed.eligibility!.label), findsOneWidget);
      }
      await _finish(tester);
    });
  }
  for (final code in ['42501', 'PGRST202']) {
    testWidgets('server $code remains distinct and reveals no private error', (
      tester,
    ) async {
      final store = _Store(),
          repo = _Repository(store)
            ..inspectError = PostgrestException(
              message: 'PRIVATE_CANARY',
              code: code,
            );
      await _mount(tester, repo, store);
      expect(
        find.text(
          code == '42501'
              ? 'Cancellation access denied'
              : 'Cancellation service unavailable',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
      expect(repo.intents, isEmpty);
      await _finish(tester);
    });
  }
  testWidgets(
    'departed pending inspection is not parsed or published into new session',
    (tester) async {
      final store = _Store(), repo = _Repository(store), sessions = _Sessions();
      final gate = Completer<Map<String, dynamic>>();
      repo.inspectGate = gate;
      await _mount(tester, repo, store, sessions: sessions);
      expect(find.text('Inspecting receipt'), findsOneWidget);
      repo.inspectGate = null;
      sessions.change(2);
      await tester.pumpAndSettle();
      gate.complete({'PRIVATE_CANARY': true});
      await tester.pumpAndSettle();
      expect(find.text('Eligible for cancellation'), findsOneWidget);
      expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
      expect(tester.takeException(), isNull);
      await _finish(tester);
    },
  );
  testWidgets(
    'same-owner session replacement retains pending original and suppresses late action acknowledgement',
    (tester) async {
      final store = _Store(), repo = _Repository(store), sessions = _Sessions();
      final gate = Completer<AdminReceiptCancelReceipt>();
      repo.writeGate = gate;
      await _mount(tester, repo, store, sessions: sessions);
      await _review(tester, submit: false);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Confirm cancellation'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(repo.intents, hasLength(1));
      final original = repo.intents.single;
      sessions.change(2);
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      gate.complete(
        AdminReceiptCancelReceipt.parse(
          repo.receipt(original),
          intent: original,
        ),
      );
      await tester.pumpAndSettle();
      expect(store.values, hasLength(1));
      expect(find.text('Cancellation recorded'), findsNothing);
      expect(repo.lookupIds, isEmpty);
      expect(repo.intents, hasLength(1));
      await _finish(tester);
    },
  );
  testWidgets(
    'confirmed action with clear failure retains visible evidence and original checkpoint',
    (tester) async {
      final store = _Store()..failClear = true, repo = _Repository(store);
      await _mount(tester, repo, store);
      await _review(tester);
      expect(find.text('Cancellation recorded'), findsOneWidget);
      expect(store.values, hasLength(1));
      expect(repo.intents, hasLength(1));
      expect(find.textContaining('PRIVATE_STORAGE_CANARY'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Review cancellation'),
            )
            .onPressed,
        isNull,
      );
      await _finish(tester);
    },
  );
  testWidgets('keyboard Escape retains receipt without checkpoint or action', (
    tester,
  ) async {
    final store = _Store(), repo = _Repository(store);
    await _mount(tester, repo, store);
    await _review(tester, submit: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(store.values, isEmpty);
    expect(repo.intents, isEmpty);
    await _finish(tester);
  });
  for (final dark in [true, false]) {
    testWidgets(
      '320px 2x ${dark ? 'dark' : 'light'} reason and confirmation controls are reachable',
      (tester) async {
        final store = _Store(), repo = _Repository(store);
        await _mount(tester, repo, store, width: 320, scale: 2, dark: dark);
        await _review(tester, submit: false);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Keep receipt'));
        await tester.pumpAndSettle();
        await _finish(tester);
      },
    );
    testWidgets(
      'desktop ${dark ? 'dark' : 'light'} integrated cancellation synthetic capture',
      (tester) async {
        final store = _Store(), repo = _Repository(store);
        final capture = GlobalKey();
        await _mount(
          tester,
          repo,
          store,
          integrated: true,
          shell: true,
          dark: dark,
          capture: capture,
        );
        expect(tester.takeException(), isNull);
        if (Platform.environment['COLLECT_CAPTURE_RECEIPT_CANCEL'] == 'true') {
          await tester.runAsync(() async {
            final boundary =
                capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final rendered = await boundary.toImage(pixelRatio: 1);
            final bytes = await rendered.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              'docs/release/collect-codex-goal-2026-09-30/admin-receipt-cancellation/receipt-cancellation-${dark ? 'dark' : 'light'}-synthetic.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            rendered.dispose();
          });
        }
        await _finish(tester);
      },
    );
  }
}
