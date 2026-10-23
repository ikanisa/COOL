import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/admin_shell.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_exception_checkpoint.dart';
import 'package:collect_app/admin/core/admin_exception_models.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/collect_runtime_assets.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'admin_exception_models_test.dart' as source;

const _identity = AdminIdentity(
  userId: '99770000-0000-4000-8000-000000000099',
  displayName: 'Synthetic exception reviewer',
  roles: ['admin'],
  permissions: [
    'payments.read',
    'notifications.read',
    'system_health.read',
    'notifications.manage',
  ],
);
final _now = DateTime.parse('2026-10-01T00:00:00.123456Z');

class _Sessions extends AdminSessionController {
  _Sessions() : super(null) {
    change(1);
  }
  void change(int generation, {String? userId}) => state = (
    key: (
      userId: userId ?? _identity.userId,
      sessionId: 'synthetic-$generation',
    ),
    generation: generation,
  );
}

class _Store implements AdminExceptionCheckpointStore {
  final values = <String, String>{};
  bool failWrite = false, failRead = false;
  @override
  String? read(String ownerDigest) {
    if (failRead) throw StateError('PRIVATE_CANARY');
    return values[ownerDigest];
  }

  @override
  void write(String ownerDigest, String encoded) {
    if (failWrite) throw StateError('PRIVATE_CANARY');
    values[ownerDigest] = encoded;
  }

  @override
  void clear(String ownerDigest) => values.remove(ownerDigest);
}

class _Repository extends AdminEvidenceRepository {
  _Repository(this.store);
  final _Store store;
  Map<String, dynamic> response = source.exceptionFixture();
  AdminIdentity? actor = _identity;
  AdminRuntimeConfig? configuration;
  Object? readError, writeError, lookupError;
  Completer<Map<String, dynamic>>? readGate;
  Completer<AdminExceptionReceipt>? writeGate;
  final started = Completer<void>();
  final queries = <AdminExceptionQuery>[];
  final intents = <AdminExceptionIntent>[];
  final lookupIds = <String>[];
  String lookupStatus = 'recorded';
  @override
  Future<AdminIdentity?> currentIdentity() async => actor;
  @override
  Future<AdminRuntimeConfig?> runtimeConfig() async => configuration;
  @override
  Future<Map<String, dynamic>> exceptionInbox({
    bool active = true,
    int limit = 20,
    AdminExceptionSource? source,
    DateTime? beforeChangedAt,
    String? beforeId,
  }) async {
    queries.add(
      AdminExceptionQuery(
        active: active,
        limit: limit,
        source: source,
        beforeChangedAt: beforeChangedAt,
        beforeId: beforeId,
      ),
    );
    if (!started.isCompleted) started.complete();
    if (readError != null) throw readError!;
    if (readGate != null) return readGate!.future;
    final raw = active ? response : sourceFixtureCleared();
    final candidates = (raw['rows'] as List).where((row) {
      if (source != null && row['source_kind'] != source.wire) return false;
      if (beforeChangedAt == null) return true;
      final time = DateTime.parse(
        row['last_changed_at'] as String,
      ).compareTo(beforeChangedAt);
      return time < 0 ||
          time == 0 && (row['id'] as String).compareTo(beforeId!) < 0;
    }).toList();
    final page = candidates.take(limit).toList();
    return sourceCopy(raw)
      ..['active'] = active
      ..['source_kind'] = source?.wire
      ..['limit'] = limit
      ..['rows'] = page
      ..['checked_at'] = sourceUtc(_now)
      ..['sample_valid_until'] = sourceUtc(
        _now.add(const Duration(seconds: 60)),
      )
      ..['next_cursor'] = candidates.length <= limit
          ? null
          : {'changed_at': page.last['last_changed_at'], 'id': page.last['id']};
  }

  @override
  Future<AdminExceptionReceipt> exceptionAction(
    AdminExceptionIntent intent,
  ) async {
    final owner = adminExceptionOwnerDigest(_identity.userId);
    // Submission cannot precede acknowledged persistence of the exact intent.
    expect(
      AdminExceptionCheckpoint.parse(
        store.read(owner)!,
        owner,
      ).intent.parameters,
      intent.parameters,
    );
    intents.add(intent);
    if (writeGate != null) return writeGate!.future;
    if (writeError != null) throw writeError!;
    return _receipt(intent);
  }

  @override
  Future<Map<String, dynamic>> exceptionActionLookup(String requestId) async {
    lookupIds.add(requestId);
    if (lookupError != null) throw lookupError!;
    final checkpoint = store.values.values
        .map((value) => jsonDecode(value) as Map)
        .single;
    final intent = AdminExceptionIntent.fromParameters(
      Map<String, dynamic>.from(checkpoint['request'] as Map),
    );
    return {
      'contract_version': 2,
      'scope': 'platform_global',
      'checked_at': sourceUtc(_now),
      'sample_valid_until': sourceUtc(_now.add(const Duration(seconds: 60))),
      'request_id': requestId,
      'status': lookupStatus,
      'receipt': lookupStatus == 'recorded' ? _receiptRaw(intent) : null,
    };
  }
}

Map<String, dynamic> sourceFixtureCleared() =>
    source.exceptionFixture('cleared');
Map<String, dynamic> sourceCopy(Map<String, dynamic> value) =>
    source.exceptionCopy(value);
String sourceUtc(DateTime value) => source.exceptionUtc(value);
Map<String, dynamic> _receiptRaw(AdminExceptionIntent intent) => {
  'contract_version': 1,
  'request_id': intent.requestId,
  'exception_id': intent.exceptionId,
  'revision': intent.revision,
  'action': intent.action.wire,
  'recorded_at': sourceUtc(_now),
  'source_resolved': false,
  'financial_action': false,
  'send_action': false,
  'escalation_delivery_verified': false,
};
AdminExceptionReceipt _receipt(AdminExceptionIntent intent) =>
    AdminExceptionReceipt.parse(_receiptRaw(intent), intent: intent);

Future<ProviderContainer> _mount(
  WidgetTester tester,
  _Repository repository,
  _Store store, {
  AdminIdentity identity = _identity,
  _Sessions? sessions,
  DateTime Function()? clock,
  bool dark = true,
  double width = 1440,
  double scale = 1,
  bool shell = false,
  GlobalKey? capture,
  int pageSize = 20,
  bool disableAnimations = false,
  AdminIdentity? Function()? currentIdentity,
}) async {
  tester.view.physicalSize = Size(width, shell ? 2200 : 1300);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      collectBackendClientProvider.overrideWithValue(null),
      adminIdentityProvider.overrideWith(
        (ref) async => currentIdentity == null ? identity : currentIdentity(),
      ),
      adminRepositoryProvider.overrideWithValue(repository),
      adminClockProvider.overrideWithValue(clock ?? () => _now),
      adminAuthSessionScopeProvider.overrideWith(
        (ref) => sessions ?? _Sessions(),
      ),
      adminExceptionCheckpointStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: dark ? CollectTheme.dark() : CollectTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: disableAnimations,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: RepaintBoundary(
            key: capture,
            child: shell
                ? AdminShell(
                    location: '/admin/exceptions',
                    child: AdminExceptionsPage(pageSize: pageSize),
                  )
                : AdminExceptionsPage(pageSize: pageSize),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 30));
  if (capture != null) {
    await tester.runAsync(
      () => precacheImage(
        const AssetImage(CollectRuntimeAssets.officialLogo),
        capture.currentContext!,
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  return container;
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  expect(tester.takeException(), isNull);
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _review(
  WidgetTester tester, {
  bool escalate = false,
  bool submit = true,
}) async {
  final label = escalate ? 'Request escalation' : 'Acknowledge';
  final button = find.widgetWithText(OutlinedButton, label).first;
  await _show(tester, button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.text('Original request ID'), findsOneWidget);
  if (submit) {
    await tester.tap(
      find.widgetWithText(
        FilledButton,
        escalate ? 'Record escalation request' : 'Record acknowledgment',
      ),
    );
    await tester.pumpAndSettle();
  }
}

void _seed(_Store store) {
  final row = source.parseList(source.exceptionFixture()).rows.first;
  final owner = adminExceptionOwnerDigest(_identity.userId);
  store.write(
    owner,
    AdminExceptionCheckpoint(
      owner,
      AdminExceptionIntent(
        requestId: '99770000-0000-4000-8000-000000000333',
        exceptionId: row.id,
        revision: row.revision,
        action: AdminExceptionAction.escalate,
        reason: AdminExceptionReviewReason.ownerReviewRequired,
      ),
    ).encode(),
  );
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
  test(
    'disposed inbox provider rejects pending old evidence before parsing',
    () async {
      final store = _Store(),
          repo = _Repository(store)
            ..readGate = Completer<Map<String, dynamic>>();
      final container = ProviderContainer(
        overrides: [
          collectBackendClientProvider.overrideWithValue(null),
          adminRepositoryProvider.overrideWithValue(repo),
          adminIdentityProvider.overrideWith((ref) async => _identity),
        ],
      );
      const query = AdminExceptionQuery();
      final subscription = container.listen(
        adminExceptionInboxProvider(query),
        (previous, next) {},
      );
      final future = container.read(adminExceptionInboxProvider(query).future);
      final expectation = expectLater(
        future,
        throwsA(isA<AdminSessionChanged>()),
      );
      await repo.started.future;
      subscription.close();
      await container.pump();
      repo.readGate!.complete({'private': 'PRIVATE_CANARY'});
      await expectation;
      container.dispose();
    },
  );
  test('canonical exception route independently requires all three reads', () {
    expect(adminRoutePaths, contains('/admin/exceptions'));
    expect(
      adminRequiredPermissionForPath('/admin/exceptions'),
      'payments.read',
    );
    expect(adminCanOpenPath(_identity, '/admin/exceptions'), isTrue);
    for (final missing in [
      'payments.read',
      'notifications.read',
      'system_health.read',
    ]) {
      expect(
        adminCanOpenPath(
          AdminIdentity(
            userId: _identity.userId,
            displayName: 'Denied',
            roles: [],
            permissions: _identity.permissions
                .where((item) => item != missing)
                .toList(),
          ),
          '/admin/exceptions',
        ),
        isFalse,
      );
    }
  });
  for (final missing in [
    'payments.read',
    'notifications.read',
    'system_health.read',
  ]) {
    testWidgets('missing $missing avoids all read and mutation requests', (
      tester,
    ) async {
      final store = _Store(), repo = _Repository(_Store());
      await _mount(
        tester,
        repo,
        store,
        identity: AdminIdentity(
          userId: _identity.userId,
          displayName: 'Denied',
          roles: [],
          permissions: _identity.permissions
              .where((item) => item != missing)
              .toList(),
        ),
      );
      expect(repo.queries, isEmpty);
      expect(repo.intents, isEmpty);
      expect(
        find.text(
          'Permission required: payments.read, notifications.read and system_health.read',
        ),
        findsOneWidget,
      );
      await _finish(tester);
    });
  }
  testWidgets(
    'recorded source flags and incomplete scan never imply resolution or delivery',
    (tester) async {
      final store = _Store(), repo = _Repository(_Store());
      await _mount(tester, repo, store);
      expect(find.text('Historical scan incomplete'), findsOneWidget);
      expect(find.text('Send outcome uncertain'), findsOneWidget);
      expect(find.text('Verification pending'), findsNWidgets(2));
      expect(repo.queries, hasLength(1));
      expect(repo.intents, isEmpty);
      final refresh = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Refresh inbox'),
      );
      expect(refresh.onPressed, isNotNull);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Refresh inbox'));
      await tester.pumpAndSettle();
      expect(repo.queries, hasLength(2));
      expect(repo.intents, isEmpty);
      await _finish(tester);
    },
  );
  testWidgets('read-only capability displays visible disabled review actions', (
    tester,
  ) async {
    final store = _Store(), repo = _Repository(store);
    await _mount(
      tester,
      repo,
      store,
      identity: AdminIdentity(
        userId: _identity.userId,
        displayName: 'Read only',
        roles: ['admin'],
        permissions: _identity.permissions
            .where((item) => item != 'notifications.manage')
            .toList(),
      ),
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Acknowledge').first,
          )
          .onPressed,
      isNull,
    );
    expect(repo.intents, isEmpty);
    await _finish(tester);
  });
  for (final error in [
    const CollectApiException(message: 'PRIVATE_CANARY', code: '42501'),
    UnsupportedError('PRIVATE_CANARY'),
    const FormatException('PRIVATE_CANARY'),
  ]) {
    testWidgets('redacted distinct inbox state ${error.runtimeType}', (
      tester,
    ) async {
      final store = _Store(), repo = _Repository(store)..readError = error;
      await _mount(tester, repo, store);
      expect(
        find.text(
          error is CollectApiException
              ? 'Exception access denied'
              : error is UnsupportedError
              ? 'Exception service unavailable'
              : 'Exception read failed',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
      expect(repo.intents, isEmpty);
      await _finish(tester);
    });
  }
  testWidgets('read TTL hides stale rows and controls without source rescan', (
    tester,
  ) async {
    var now = _now;
    final store = _Store(), repo = _Repository(store);
    await _mount(tester, repo, store, clock: () => now);
    now = now.add(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Exception snapshot expired'), findsOneWidget);
    expect(find.text('Acknowledge'), findsNothing);
    expect(repo.queries, hasLength(1));
    await _finish(tester);
  });
  testWidgets(
    'server category and cleared filters reset cursor without global counts',
    (tester) async {
      final store = _Store(), repo = _Repository(store);
      await _mount(tester, repo, store);
      await tester.tap(find.text('All sources'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Payment message').last);
      await tester.pumpAndSettle();
      expect(repo.queries.last.source, AdminExceptionSource.rawSms);
      await tester.tap(find.text('Active'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cleared').last);
      await tester.pumpAndSettle();
      expect(repo.queries.last.active, isFalse);
      expect(repo.queries.last.beforeId, isNull);
      expect(find.text('Recorded cleared'), findsOneWidget);
      expect(find.text('Acknowledge'), findsNothing);
      await _finish(tester);
    },
  );
  testWidgets(
    'paired keyset next previous and refresh preserve actual source IDs',
    (tester) async {
      final store = _Store(), repo = _Repository(store);
      await _mount(tester, repo, store, pageSize: 2);
      await _show(tester, find.text('Next page'));
      await tester.tap(find.text('Next page'));
      await tester.pumpAndSettle();
      expect(repo.queries.last.beforeId, isNotNull);
      expect(repo.queries.last.beforeChangedAt, isNotNull);
      await _show(tester, find.text('Previous page'));
      await tester.tap(find.text('Previous page'));
      await tester.pumpAndSettle();
      expect(find.text('Gateway network needs review'), findsOneWidget);
      await _show(tester, find.text('Refresh inbox'));
      await tester.tap(find.text('Refresh inbox'));
      await tester.pumpAndSettle();
      expect(repo.queries.last.beforeId, isNull);
      await _finish(tester);
    },
  );
  testWidgets(
    'review saves exact original checkpoint before one action and refreshes actual source',
    (tester) async {
      final store = _Store(), repo = _Repository(store);
      await _mount(tester, repo, store);
      await _review(tester);
      expect(repo.intents, hasLength(1));
      expect(repo.intents.single.action, AdminExceptionAction.acknowledge);
      expect(store.values, isEmpty);
      expect(repo.queries, hasLength(2));
      expect(find.text('Immutable review receipt'), findsOneWidget);
      expect(find.text('Recorded active'), findsNWidgets(6));
      await _finish(tester);
    },
  );
  testWidgets(
    'checkpoint write failure prevents submission and remains redacted',
    (tester) async {
      final store = _Store()..failWrite = true, repo = _Repository(store);
      await _mount(tester, repo, store);
      await _review(tester);
      expect(repo.intents, isEmpty);
      expect(find.text('Recovery storage unavailable'), findsOneWidget);
      expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
      await _finish(tester);
    },
  );
  testWidgets(
    'source revision refusal clears unsent review checkpoint and never resolves source',
    (tester) async {
      final store = _Store(),
          repo = _Repository(store)
            ..writeError = const CollectApiException(
              message: 'PRIVATE_CANARY',
              code: '55000',
            );
      await _mount(tester, repo, store);
      await _review(tester);
      expect(repo.intents, hasLength(1));
      expect(store.values, isEmpty);
      expect(
        find.text(
          'The source changed or cleared before review. Refresh the inbox and review its latest revision.',
        ),
        findsOneWidget,
      );
      expect(find.text('Recorded active'), findsNWidgets(6));
      await _finish(tester);
    },
  );
  testWidgets(
    'current live capability loss prevents action after reviewed dialog',
    (tester) async {
      final store = _Store(), repo = _Repository(store);
      await _mount(tester, repo, store);
      await _review(tester, submit: false);
      repo.actor = AdminIdentity(
        userId: _identity.userId,
        displayName: 'Revoked',
        roles: ['admin'],
        permissions: [],
      );
      await tester.tap(find.text('Record acknowledgment'));
      await tester.pumpAndSettle();
      expect(repo.intents, isEmpty);
      expect(store.values, isEmpty);
      await _finish(tester);
    },
  );
  testWidgets(
    'keyboard Escape cancels concrete review without storing or submitting',
    (tester) async {
      final store = _Store(), repo = _Repository(store);
      await _mount(tester, repo, store);
      await _review(tester, submit: false);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Record acknowledgment'), findsNothing);
      expect(store.values, isEmpty);
      expect(repo.intents, isEmpty);
      await _finish(tester);
    },
  );
  testWidgets('session replacement closes reviewed dialog without writing', (
    tester,
  ) async {
    final store = _Store(), repo = _Repository(store), sessions = _Sessions();
    await _mount(tester, repo, store, sessions: sessions);
    await _review(tester, submit: false);
    sessions.change(2);
    await tester.pumpAndSettle();
    expect(find.text('Record acknowledgment'), findsNothing);
    expect(repo.intents, isEmpty);
    await _finish(tester);
  });
  testWidgets(
    'follow-up dialog closes on same-user session replacement and stays closed after A-B-A',
    (tester) async {
      final store = _Store(), repo = _Repository(store), sessions = _Sessions();
      await _mount(tester, repo, store, sessions: sessions);
      final opener = find.text('Manage follow-up').first;
      await _show(tester, opener);
      await tester.tap(opener);
      await tester.pumpAndSettle();
      expect(find.text('Close follow-up'), findsOneWidget);
      sessions.change(2);
      await tester.pumpAndSettle();
      expect(find.text('Close follow-up'), findsNothing);
      sessions.change(1);
      await tester.pumpAndSettle();
      expect(find.text('Close follow-up'), findsNothing);
      expect(repo.intents, isEmpty);
      expect(store.values, isEmpty);
      await _finish(tester);
    },
  );
  testWidgets('follow-up dialog closes on same-account capability departure', (
    tester,
  ) async {
    final store = _Store(), repo = _Repository(store);
    final container = await _mount(
      tester,
      repo,
      store,
      currentIdentity: () => repo.actor,
    );
    final opener = find.text('Manage follow-up').first;
    await _show(tester, opener);
    await tester.tap(opener);
    await tester.pumpAndSettle();
    expect(find.text('Close follow-up'), findsOneWidget);
    repo.actor = AdminIdentity(
      userId: _identity.userId,
      displayName: 'Same reviewer with revoked capability',
      roles: _identity.roles,
      permissions: const [],
    );
    container.invalidate(adminIdentityProvider);
    await tester.pumpAndSettle();
    expect(find.text('Close follow-up'), findsNothing);
    repo.actor = _identity;
    container.invalidate(adminIdentityProvider);
    await tester.pumpAndSettle();
    expect(find.text('Close follow-up'), findsNothing);
    expect(repo.intents, isEmpty);
    expect(store.values, isEmpty);
    await _finish(tester);
  });
  testWidgets('follow-up route respects reduced motion and keyboard Escape', (
    tester,
  ) async {
    final store = _Store(), repo = _Repository(store);
    await _mount(tester, repo, store, disableAnimations: true);
    final opener = find.text('Manage follow-up').first;
    await _show(tester, opener);
    await tester.tap(opener);
    await tester.pumpAndSettle();
    final route = ModalRoute.of(tester.element(find.text('Close follow-up')))!;
    expect(route, isA<DialogRoute<void>>());
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Close follow-up'), findsNothing);
    expect(repo.intents, isEmpty);
    await _finish(tester);
  });
  testWidgets(
    'uncertain action retains original UUID across reload with manual lookup and no replay',
    (tester) async {
      final store = _Store(),
          repo = _Repository(store)..writeError = StateError('PRIVATE_CANARY');
      await _mount(tester, repo, store);
      await _review(tester, escalate: true);
      final id = repo.intents.single.requestId;
      expect(store.values, hasLength(1));
      expect(repo.lookupIds, isEmpty);
      await _finish(tester);
      await _mount(tester, repo, store);
      expect(find.text(id), findsOneWidget);
      expect(repo.lookupIds, isEmpty);
      expect(repo.intents, hasLength(1));
      repo.lookupStatus = 'not_recorded';
      await _show(tester, find.text('Check original request'));
      await tester.tap(find.text('Check original request'));
      await tester.pumpAndSettle();
      expect(find.text('No receipt visible for this request'), findsOneWidget);
      expect(store.values, hasLength(1));
      repo.lookupStatus = 'recorded';
      await tester.tap(find.text('Check original request'));
      await tester.pumpAndSettle();
      await _show(tester, find.text('Use recorded result and refresh'));
      await tester.tap(find.text('Use recorded result and refresh'));
      await tester.pumpAndSettle();
      expect(store.values, isEmpty);
      expect(repo.lookupIds, [id, id]);
      expect(repo.intents, hasLength(1));
      await _finish(tester);
    },
  );
  for (final status in ['in_progress', 'authority_busy']) {
    testWidgets(
      '$status recovery preserves original checkpoint and independent source read',
      (tester) async {
        final store = _Store();
        _seed(store);
        final repo = _Repository(store)..lookupStatus = 'in_progress';
        if (status == 'authority_busy') {
          repo.lookupError = const CollectApiException(
            message: 'PRIVATE_CANARY',
            code: '55P03',
          );
        }
        await _mount(tester, repo, store);
        expect(repo.lookupIds, isEmpty);
        await _show(tester, find.text('Check original request'));
        await tester.tap(find.text('Check original request'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            status == 'authority_busy'
                ? 'Current authority busy'
                : 'Request still in progress',
          ),
          findsOneWidget,
        );
        expect(store.values, hasLength(1));
        expect(repo.intents, isEmpty);
        expect(find.text('Gateway network needs review'), findsOneWidget);
        expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
        await _finish(tester);
      },
    );
  }
  testWidgets(
    'fresh same-owner session recovers reference without automatic read or mutation',
    (tester) async {
      final store = _Store();
      _seed(store);
      final repo = _Repository(store), sessions = _Sessions()..change(2);
      await _mount(tester, repo, store, sessions: sessions);
      expect(find.text('Check original request'), findsOneWidget);
      expect(store.values, hasLength(1));
      expect(repo.lookupIds, isEmpty);
      expect(repo.intents, isEmpty);
      await tester.tap(find.text('Check original request'));
      await tester.pumpAndSettle();
      expect(repo.lookupIds, hasLength(1));
      expect(repo.intents, isEmpty);
      await _finish(tester);
    },
  );
  testWidgets('another actor cannot expose or look up saved original request', (
    tester,
  ) async {
    final store = _Store();
    _seed(store);
    final actor = AdminIdentity(
      userId: '99770000-0000-4000-8000-000000000098',
      displayName: 'Synthetic other owner',
      roles: ['admin'],
      permissions: _identity.permissions,
    );
    final sessions = _Sessions()..change(1, userId: actor.userId);
    final repo = _Repository(store)..actor = actor;
    await _mount(tester, repo, store, identity: actor, sessions: sessions);
    expect(find.text('Check original request'), findsNothing);
    expect(store.values, hasLength(1));
    expect(repo.lookupIds, isEmpty);
    expect(repo.intents, isEmpty);
    await _finish(tester);
  });
  for (final dark in [true, false]) {
    testWidgets(
      '320px 2x ${dark ? 'dark' : 'light'} labels and review controls remain reachable',
      (tester) async {
        final store = _Store(), repo = _Repository(store);
        await _mount(tester, repo, store, width: 320, scale: 2, dark: dark);
        await _review(tester, submit: false);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await _finish(tester);
      },
    );
    testWidgets(
      'desktop ${dark ? 'dark' : 'light'} synthetic exception capture',
      (tester) async {
        final store = _Store(),
            repo = _Repository(store),
            capture = GlobalKey();
        await _mount(
          tester,
          repo,
          store,
          shell: true,
          capture: capture,
          dark: dark,
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Refresh inbox'),
              )
              .onPressed,
          isNotNull,
        );
        final selected = tester
            .widgetList<ListTile>(find.byType(ListTile))
            .singleWhere((tile) => tile.selected);
        expect(selected.selectedColor, isNotNull);
        expect(tester.takeException(), isNull);
        if (Platform.environment['COLLECT_CAPTURE_ADMIN_EXCEPTIONS'] ==
            'true') {
          await tester.runAsync(() async {
            final boundary =
                capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final rendered = await boundary.toImage(pixelRatio: 1);
            final bytes = await rendered.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '.cache/test-captures/admin-exceptions/exceptions-${dark ? 'dark' : 'light'}-synthetic.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            rendered.dispose();
          });
        }
        await _finish(tester);
      },
    );
  }
}
