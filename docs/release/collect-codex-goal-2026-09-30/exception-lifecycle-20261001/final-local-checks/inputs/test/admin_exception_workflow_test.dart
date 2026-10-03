import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_exception_checkpoint.dart';
import 'package:collect_app/admin/core/admin_exception_workflow_models.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> observed(String name) => Map<String, dynamic>.from(
  jsonDecode(
        File(
          'docs/release/collect-codex-goal-2026-09-30/exception-lifecycle-20261001/attempt6/observed-$name.json',
        ).readAsStringSync(),
      )
      as Map,
);
Map<String, dynamic> copy(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
String wire(DateTime time) => time.toUtc().toIso8601String().replaceFirstMapped(
  RegExp(r'\.(\d{3})Z$'),
  (match) => '.${match[1]}000Z',
);
final _raw = observed('workflow');
final _now = DateTime.parse(_raw['checked_at'] as String);
final _id = _raw['exception_id'] as String;
final _actor = AdminIdentity(
  userId: _raw['assignee_id'] as String,
  displayName: 'Synthetic owner',
  roles: const ['platform_owner'],
  permissions: const [
    'payments.read',
    'notifications.read',
    'system_health.read',
    'notifications.manage',
  ],
);

class _Sessions extends AdminSessionController {
  _Sessions() : super(null) {
    change(1);
  }
  void change(int generation) => state = (
    key: (userId: _actor.userId, sessionId: 'synthetic-$generation'),
    generation: generation,
  );
}

class _Store implements AdminExceptionCheckpointStore {
  final values = <String, String>{};
  bool failWrite = false;
  @override
  String? read(String key) => values[key];
  @override
  void write(String key, String encoded) {
    if (failWrite) throw StateError('PRIVATE_ERROR_CANARY');
    values[key] = encoded;
  }

  @override
  void clear(String key) => values.remove(key);
}

class _Repository extends AdminEvidenceRepository {
  _Repository(this.store);
  final _Store store;
  AdminIdentity? actor = _actor;
  Map<String, dynamic> workflow = copy(_raw)
    ..['source_active'] = true
    ..['status'] = 'assigned';
  final intents = <AdminExceptionWorkflowIntent>[];
  final openedEscalations = <String>[];
  Completer<Map<String, dynamic>>? readEscalationGate;
  bool invalidReadAcknowledgement = false;
  bool loseResponse = false, gateIdentity = false;
  final identityGate = Completer<AdminIdentity?>();
  String lookupStatus = 'recorded';
  DateTime lookupAt = _now;
  @override
  Future<AdminIdentity?> currentIdentity() async =>
      gateIdentity ? identityGate.future : actor;
  @override
  Future<Map<String, dynamic>> exceptionWorkflow(String id) async => workflow;
  Map<String, dynamic> receipt(AdminExceptionWorkflowIntent intent) => {
    'contract_version': 1,
    'request_id': intent.requestId,
    'exception_id': intent.exceptionId,
    'source_revision': intent.sourceRevision,
    'workflow_revision': intent.workflowRevision + 1,
    'action': intent.action,
    'escalation_id': intent.action == 'escalate'
        ? '11111111-1111-4111-8111-111111111111'
        : null,
    'source_resolved': intent.action == 'resolve',
    'financial_action': false,
    'send_action': false,
    'recorded_at': wire(_now),
  };
  @override
  Future<Map<String, dynamic>> exceptionWorkflowAction(
    AdminExceptionWorkflowIntent intent,
  ) async {
    final owner = adminExceptionOwnerDigest('workflow:${_actor.userId}:$_id');
    expect(
      AdminExceptionWorkflowIntent.decode(store.read(owner)!, owner).parameters,
      intent.parameters,
    );
    intents.add(intent);
    if (loseResponse) throw TimeoutException('PRIVATE_ERROR_CANARY');
    return receipt(intent);
  }

  @override
  Future<Map<String, dynamic>> exceptionWorkflowRequest(
    String requestId,
  ) async => {
    'contract_version': 1,
    'request_id': requestId,
    'checked_at': wire(lookupAt),
    'sample_valid_until': wire(lookupAt.add(const Duration(seconds: 60))),
    'status': lookupStatus,
    'receipt': lookupStatus == 'recorded' ? receipt(intents.single) : null,
  };
  @override
  Future<Map<String, dynamic>> exceptionEscalationInbox() async =>
      observed('inbox');
  @override
  Future<Map<String, dynamic>> readExceptionEscalation(String id) async {
    openedEscalations.add(id);
    if (readEscalationGate != null) return readEscalationGate!.future;
    final row = (observed('inbox')['rows'] as List).singleWhere(
      (row) => row['escalation_id'] == id,
    );
    return {
      'contract_version': 1,
      'escalation_id': invalidReadAcknowledgement
          ? '11111111-1111-4111-8111-111111111111'
          : id,
      'read_at': row['delivered_at'],
      'source_resolved': false,
    };
  }
}

Future<ProviderContainer> _mount(
  WidgetTester tester,
  _Repository repository,
  _Store store,
  _Sessions sessions, {
  DateTime Function()? clock,
  bool inbox = false,
  double width = 560,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 1100));
  final container = ProviderContainer(
    overrides: [
      supabaseClientProvider.overrideWithValue(null),
      adminIdentityProvider.overrideWith((ref) async => repository.actor),
      adminRepositoryProvider.overrideWithValue(repository),
      adminAuthSessionScopeProvider.overrideWith((ref) => sessions),
      adminExceptionCheckpointStoreProvider.overrideWithValue(store),
      adminClockProvider.overrideWithValue(clock ?? () => _now),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: CollectTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: inbox
                  ? const AdminExceptionEscalationInbox()
                  : AdminExceptionWorkflowCard(exceptionId: _id),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  expect(tester.takeException(), isNull);
}

void main() {
  test(
    'actual SQL workflow and inbox projections parse without dropping evidence',
    () {
      final workflow = AdminExceptionWorkflow.parse(_raw, _id);
      expect(workflow.escalations, isNotEmpty);
      expect(workflow.status, 'source_cleared');
      expect(
        AdminExceptionEscalationSnapshot.parse(observed('inbox')).rows,
        isNotEmpty,
      );
    },
  );
  test('actual unassigned and resolved unassigned SQL evidence parse', () {
    for (final name in ['unassigned', 'unassigned-resolved']) {
      final raw = observed(name);
      final value = AdminExceptionWorkflow.parse(
        raw,
        raw['exception_id'] as String,
      );
      expect(value.assigneeId, isNull);
      expect(value.dueAt, isNull);
      expect(value.overdue, isFalse);
    }
  });
  for (final mutation in <String, void Function(Map<String, dynamic>)>{
    'floating contract': (v) => v['contract_version'] = 1.0,
    'floating revision': (v) => v['workflow_revision'] = 2.0,
    'unknown field': (v) => v['destination'] = 'PRIVATE_CONTACT_CANARY',
    'wrong exception': (v) =>
        v['exception_id'] = '11111111-1111-4111-8111-111111111111',
    'active resolved': (v) {
      v['status'] = 'resolved';
      v['source_active'] = true;
    },
    'false delivery': (v) {
      final row = (v['escalations'] as List).firstWhere(
        (row) => row['state'] == 'delivered',
      );
      row['state'] = 'queued';
    },
    'wrong freshness': (v) => v['sample_valid_until'] = v['checked_at'],
    'duplicate escalation': (v) =>
        (v['escalations'] as List).add((v['escalations'] as List).first),
  }.entries) {
    test('rejects ${mutation.key}', () {
      final raw = copy(_raw);
      mutation.value(raw);
      expect(
        () => AdminExceptionWorkflow.parse(raw, _id),
        throwsFormatException,
      );
    });
  }
  test(
    'a fresh negative lookup before expiry never clears an unknown request',
    () {
      final store = _Store(), repository = _Repository(_Store());
      final intent = AdminExceptionWorkflowIntent(
        requestId: '11111111-1111-4111-8111-111111111111',
        exceptionId: _id,
        sourceRevision: 1,
        workflowRevision: 0,
        action: 'assign',
        assigneeId: _actor.userId,
        dueAt: _now.add(const Duration(hours: 1)),
        expiresAt: _now.add(const Duration(seconds: 90)),
      );
      final digest = adminExceptionOwnerDigest(
        'workflow:${_actor.userId}:$_id',
      );
      store.write(digest, intent.encode(digest));
      expect(
        AdminExceptionWorkflowIntent.decode(
          store.read(digest)!,
          digest,
        ).parameters,
        intent.parameters,
      );
      repository.intents.add(intent);
      final lookup = AdminExceptionWorkflowLookup.parse({
        'contract_version': 1,
        'request_id': intent.requestId,
        'checked_at': wire(_now),
        'sample_valid_until': wire(_now.add(const Duration(seconds: 60))),
        'status': 'not_recorded',
        'receipt': null,
      }, intent);
      expect(lookup.canClearUnrecorded(intent, _now), isFalse);
    },
  );
  test(
    'negative lookup after expiry closes only while the observation is fresh',
    () {
      final intent = AdminExceptionWorkflowIntent(
        requestId: '11111111-1111-4111-8111-111111111111',
        exceptionId: _id,
        sourceRevision: 1,
        workflowRevision: 0,
        action: 'resolve',
        expiresAt: _now.subtract(const Duration(seconds: 1)),
      );
      final lookup = AdminExceptionWorkflowLookup.parse({
        'contract_version': 1,
        'request_id': intent.requestId,
        'checked_at': wire(_now),
        'sample_valid_until': wire(_now.add(const Duration(seconds: 60))),
        'status': 'not_recorded',
        'receipt': null,
      }, intent);
      expect(lookup.canClearUnrecorded(intent, _now), isTrue);
      expect(
        lookup.canClearUnrecorded(
          intent,
          _now.add(const Duration(seconds: 60)),
        ),
        isFalse,
      );
    },
  );
  testWidgets(
    'persisted reviewed assignment precedes submission and clears after bound receipt',
    (tester) async {
      final store = _Store(), sessions = _Sessions();
      final repository = _Repository(store);
      await _mount(tester, repository, store, sessions);
      await tester.tap(find.text('Assign to me · due in 1 hour'));
      await tester.pumpAndSettle();
      expect(repository.intents.single.action, 'assign');
      expect(store.values, isEmpty);
      expect(find.text('Follow-up action recorded.'), findsOneWidget);
      await close(tester);
    },
  );
  testWidgets(
    'unknown response survives widget recreation and reconciles original request',
    (tester) async {
      final store = _Store(), sessions = _Sessions();
      final repository = _Repository(store)..loseResponse = true;
      await _mount(tester, repository, store, sessions);
      await tester.tap(find.text('Assign to me · due in 1 hour'));
      await tester.pumpAndSettle();
      expect(store.values.length, 1);
      expect(find.textContaining('PRIVATE_ERROR_CANARY'), findsNothing);
      await close(tester);
      await _mount(tester, repository, store, _Sessions());
      expect(
        find.textContaining('pending follow-up request was recovered'),
        findsOneWidget,
      );
      await tester.tap(find.text('Check follow-up request'));
      await tester.pumpAndSettle();
      expect(repository.intents.length, 1);
      expect(store.values, isEmpty);
      await close(tester);
    },
  );
  testWidgets('storage failure prevents submission and further actions', (
    tester,
  ) async {
    final store = _Store()..failWrite = true, sessions = _Sessions();
    final repository = _Repository(store);
    await _mount(tester, repository, store, sessions);
    await tester.tap(find.text('Assign to me · due in 1 hour'));
    await tester.pumpAndSettle();
    expect(repository.intents, isEmpty);
    expect(
      find.textContaining('Recovery storage is unavailable'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Assign to me · due in 1 hour'),
          )
          .onPressed,
      isNull,
    );
    await close(tester);
  });
  testWidgets(
    'session replacement during identity recheck prevents old submission',
    (tester) async {
      final store = _Store(), sessions = _Sessions();
      final repository = _Repository(store);
      await _mount(tester, repository, store, sessions);
      repository.gateIdentity = true;
      await tester.tap(find.text('Assign to me · due in 1 hour'));
      await tester.pump();
      sessions.change(2);
      repository.gateIdentity = false;
      repository.identityGate.complete(_actor);
      await tester.pumpAndSettle();
      expect(repository.intents, isEmpty);
      await close(tester);
    },
  );
  testWidgets('expired observation disables follow-up mutations', (
    tester,
  ) async {
    final store = _Store(), sessions = _Sessions();
    final repository = _Repository(store);
    await _mount(
      tester,
      repository,
      store,
      sessions,
      clock: () => _now.add(const Duration(seconds: 60)),
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Assign to me · due in 1 hour'),
          )
          .onPressed,
      isNull,
    );
    await close(tester);
  });
  testWidgets('compact follow-up reflows and keeps named controls', (
    tester,
  ) async {
    final store = _Store(), sessions = _Sessions();
    final repository = _Repository(store);
    await _mount(tester, repository, store, sessions, width: 320);
    expect(find.text('Exception follow-up'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });
  testWidgets('recipient inbox reads lazily and presents delivered evidence', (
    tester,
  ) async {
    final store = _Store(), sessions = _Sessions();
    final repository = _Repository(store);
    await _mount(
      tester,
      repository,
      store,
      sessions,
      inbox: true,
      clock: () => DateTime.parse(observed('inbox')['checked_at'] as String),
    );
    await tester.tap(find.text('Your escalation inbox'));
    await tester.pumpAndSettle();
    expect(find.text('Open exception follow-up'), findsWidgets);
    expect(tester.takeException(), isNull);
    await close(tester);
  });
  testWidgets(
    'recipient read acknowledgement opens a guarded dialog and session departure closes it',
    (tester) async {
      final store = _Store(), sessions = _Sessions();
      final repository = _Repository(store);
      await _mount(
        tester,
        repository,
        store,
        sessions,
        inbox: true,
        clock: () => DateTime.parse(observed('inbox')['checked_at'] as String),
      );
      await tester.tap(find.text('Your escalation inbox'));
      await tester.pumpAndSettle();
      final opener = find.text('Open exception follow-up').first;
      await tester.ensureVisible(opener);
      await tester.tap(opener);
      await tester.pumpAndSettle();
      expect(repository.openedEscalations, hasLength(1));
      expect(find.text('Close follow-up'), findsOneWidget);
      sessions.change(2);
      await tester.pumpAndSettle();
      expect(find.text('Close follow-up'), findsNothing);
      expect(repository.intents, isEmpty);
      await close(tester);
    },
  );
  testWidgets('recipient inbox rejects an acknowledgement for another delivery', (
    tester,
  ) async {
    final store = _Store(), sessions = _Sessions();
    final repository = _Repository(store)..invalidReadAcknowledgement = true;
    await _mount(
      tester,
      repository,
      store,
      sessions,
      inbox: true,
      clock: () => DateTime.parse(observed('inbox')['checked_at'] as String),
    );
    await tester.tap(find.text('Your escalation inbox'));
    await tester.pumpAndSettle();
    final opener = find.text('Open exception follow-up').first;
    await tester.ensureVisible(opener);
    await tester.tap(opener);
    await tester.pumpAndSettle();
    expect(repository.openedEscalations, hasLength(1));
    expect(find.text('Close follow-up'), findsNothing);
    expect(find.textContaining('Opening could not be recorded'), findsOneWidget);
    expect(repository.intents, isEmpty);
    await close(tester);
  });
  testWidgets('session departure during inbox read prevents opening old delivery', (
    tester,
  ) async {
    final store = _Store(), sessions = _Sessions();
    final repository = _Repository(store)
      ..readEscalationGate = Completer<Map<String, dynamic>>();
    await _mount(
      tester,
      repository,
      store,
      sessions,
      inbox: true,
      clock: () => DateTime.parse(observed('inbox')['checked_at'] as String),
    );
    await tester.tap(find.text('Your escalation inbox'));
    await tester.pumpAndSettle();
    final opener = find.text('Open exception follow-up').first;
    await tester.ensureVisible(opener);
    await tester.tap(opener);
    await tester.pump();
    expect(repository.openedEscalations, hasLength(1));
    sessions.change(2);
    await tester.pump();
    repository.readEscalationGate!.complete({'PRIVATE_CANARY': 'old response'});
    await tester.pumpAndSettle();
    expect(find.text('Close follow-up'), findsNothing);
    expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
    expect(repository.intents, isEmpty);
    await close(tester);
  });
}
