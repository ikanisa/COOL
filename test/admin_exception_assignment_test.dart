import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_exception_checkpoint.dart';
import 'package:collect_app/admin/core/admin_exception_followup_v2_models.dart';
import 'package:collect_app/admin/core/admin_exception_workflow_models.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'admin_exception_workflow_test.dart' as evidence;
import 'support/admin_followup_fixture.dart';

Map<String, dynamic> _fixture(String name) => followupFixture(
  name,
  exceptionId: _raw['exception_id'] as String,
  actorId: _raw['assignee_id'] as String,
);

final _raw = evidence.workflowFixture('workflow');
final _id = _raw['exception_id'] as String;
final _at = DateTime.parse(_fixture('recorded-lookup')['checked_at'] as String);
final _directoryRaw = _fixture('directory-first');
final _other = (_directoryRaw['rows'] as List)[1] as Map;
final _otherId = _other['operator_id'] as String;
final _otherLabel = _other['display_label'] as String;
final _actor = AdminIdentity(
  userId: _raw['assignee_id'] as String,
  displayName: 'Declared synthetic owner',
  roles: const ['platform_owner'],
  permissions: const [
    'payments.read',
    'notifications.read',
    'system_health.read',
    'notifications.manage',
  ],
);
final _owner = adminExceptionOwnerDigest('workflow:${_actor.userId}:$_id');
final _authority = StateProvider<AdminIdentity?>((_) => _actor);
AdminIdentity _identity({List<String>? roles, List<String>? permissions}) =>
    AdminIdentity(
      userId: _actor.userId,
      displayName: 'Declared synthetic identity',
      roles: roles ?? _actor.roles,
      permissions: permissions ?? _actor.permissions,
    );

class _Sessions extends AdminSessionController {
  _Sessions() : super(null) {
    change('opening');
  }
  int generation = 0;
  void change(String sessionId) => state = (
    key: (userId: _actor.userId, sessionId: sessionId),
    generation: ++generation,
  );
  void close() => state = null;
}

class _Store implements AdminExceptionCheckpointStore {
  final values = <String, String>{};
  final written = <String>[];
  bool failWrite = false, corruptReadback = false, failRead = false;
  void Function()? onWrite;
  @override
  String? read(String key) {
    if (failRead) {
      throw StateError('PRIVATE_STORAGE_CANARY');
    }
    final value = values[key];
    return corruptReadback && value != null ? '$value ' : value;
  }

  @override
  void write(String key, String encoded) {
    if (failWrite) {
      throw StateError('PRIVATE_QUOTA_CANARY');
    }
    values[key] = encoded;
    written.add(encoded);
    onWrite?.call();
  }

  @override
  void clear(String key) => values.remove(key);
}

class _Repository extends AdminEvidenceRepository {
  _Repository(this.store);
  final _Store store;
  DateTime now = _at;
  AdminIdentity? actor = _actor;
  int workflowReads = 0, identityReads = 0;
  Map<String, dynamic> workflow = evidence.copy(_raw)
    ..['source_active'] = true
    ..['status'] = 'assigned'
    ..['checked_at'] = evidence.wire(_at)
    ..['sample_valid_until'] = evidence.wire(
      _at.add(const Duration(seconds: 60)),
    );
  final queries = <AdminExceptionFollowupDirectoryQuery>[];
  final actions = <AdminExceptionWorkflowIntent>[];
  final lookups = <AdminExceptionFollowupReference>[];
  final legacyLookupIds = <String>[];
  AdminExceptionWorkflowIntent? priorLookupIntent;
  bool loseReply = false,
      badLookupFingerprint = false,
      paginate = false,
      emptyDirectory = false,
      privateDirectory = false;
  String lookupStatus = 'recorded';
  Completer<AdminIdentity?>? identityGate;
  Completer<Map<String, dynamic>>? directoryGate,
      workflowGate,
      actionGate,
      lookupGate;
  bool directoryFails = false;
  @override
  Future<AdminIdentity?> currentIdentity() {
    identityReads++;
    return identityGate?.future ?? Future.value(actor);
  }

  @override
  Future<Map<String, dynamic>> exceptionWorkflow(String id) async {
    workflowReads++;
    return workflowReads > 1 && workflowGate != null
        ? workflowGate!.future
        : evidence.copy(workflow);
  }

  Map<String, dynamic> directory(AdminExceptionFollowupDirectoryQuery query) {
    // Declared protocol double with a controlled widget clock.
    final raw = evidence.copy(
      _fixture(query.before == null ? 'directory-first' : 'directory-last'),
    );
    raw['limit'] = query.limit;
    raw['checked_at'] = evidence.wire(now);
    raw['sample_valid_until'] = evidence.wire(
      now.add(const Duration(seconds: 60)),
    );
    if (!paginate) {
      raw['rows'] = (raw['rows'] as List).take(2).toList();
      raw['next_cursor'] = null;
    }
    if (emptyDirectory) {
      raw['rows'] = [];
      raw['next_cursor'] = null;
    }
    if (privateDirectory) {
      raw['email'] = 'PRIVATE_CONTACT_CANARY';
    }
    return raw;
  }

  @override
  Future<Map<String, dynamic>> exceptionFollowupOperators(
    AdminExceptionFollowupDirectoryQuery query,
  ) async {
    queries.add(query);
    if (directoryFails) {
      throw StateError('PRIVATE_DIRECTORY_CANARY');
    }
    return directoryGate?.future ?? directory(query);
  }

  Map<String, dynamic> receipt(AdminExceptionWorkflowIntent intent) => {
    'contract_version': 2,
    'request_id': intent.requestId,
    'exception_id': intent.exceptionId,
    'source_revision': intent.sourceRevision,
    'workflow_revision': intent.workflowRevision + 1,
    'action': intent.action,
    'escalation_id': null,
    'source_resolved': false,
    'financial_action': false,
    'send_action': false,
    'recorded_at': evidence.wire(now),
    'request_fingerprint': adminExceptionFollowupFingerprint(intent),
  };
  @override
  Future<Map<String, dynamic>> exceptionFollowupAction(
    AdminExceptionWorkflowIntent intent,
  ) async {
    final encoded = store.read(_owner)!;
    final original = AdminExceptionFollowupBookmark.decode(
      encoded,
      _owner,
      _actor.userId,
      _id,
    );
    expect(
      original.reference.toJson(),
      AdminExceptionFollowupReference.fromIntent(intent).toJson(),
    );
    expect(jsonDecode(encoded)['version'], 3);
    expect((jsonDecode(encoded)['request'] as Map), hasLength(7));
    for (final forbidden in [
      'p_assignee_id',
      'p_due_at',
      'p_reason_code',
      _actor.userId,
      intent.assigneeId!,
      'Collect ID',
      'Bearer',
    ]) {
      expect(encoded, isNot(contains(forbidden)));
    }
    actions.add(intent);
    if (loseReply) {
      throw TimeoutException('PRIVATE_REPLY_CANARY');
    }
    return actionGate?.future ?? receipt(intent);
  }

  Map<String, dynamic> lookup(AdminExceptionFollowupReference original) => {
    'contract_version': 2,
    'request_id': original.requestId,
    'request_fingerprint': badLookupFingerprint
        ? 'a' * 64
        : original.requestFingerprint,
    'expires_at': evidence.wire(original.expiresAt),
    'checked_at': evidence.wire(now),
    'sample_valid_until': evidence.wire(now.add(const Duration(seconds: 60))),
    'status': lookupStatus,
    'receipt': lookupStatus == 'recorded'
        ? receipt(priorLookupIntent ?? actions.single)
        : null,
  };
  @override
  Future<Map<String, dynamic>> exceptionWorkflowRequest(
    String requestId,
  ) async {
    legacyLookupIds.add(requestId);
    throw const FormatException(
      'Legacy lookup must not receive v3 corruption.',
    );
  }

  @override
  Future<Map<String, dynamic>> exceptionFollowupRequest(
    AdminExceptionFollowupReference original,
  ) async {
    lookups.add(original);
    return lookupGate?.future ?? lookup(original);
  }
}

class _Harness {
  _Harness() {
    repository = _Repository(store);
  }
  final store = _Store();
  final sessions = _Sessions();
  late final _Repository repository;
  late ProviderContainer container;
  bool _closed = false;
  Future<void> mount(
    WidgetTester tester, {
    double width = 600,
    double scale = 1,
    AdminIdentity? identity,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 1100));
    container = ProviderContainer(
      overrides: [
        collectBackendClientProvider.overrideWithValue(null),
        adminIdentityProvider.overrideWith(
          (ref) async => ref.watch(_authority),
        ),
        adminRepositoryProvider.overrideWithValue(repository),
        adminAuthSessionScopeProvider.overrideWith((ref) => sessions),
        adminExceptionCheckpointStoreProvider.overrideWithValue(store),
        adminClockProvider.overrideWithValue(() => repository.now),
      ],
    );
    if (identity != null) {
      container.read(_authority.notifier).state = identity;
      repository.actor = identity;
    }
    addTearDown(() async {
      await close(tester);
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: CollectTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AdminExceptionWorkflowCard(exceptionId: _id),
              ),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    if (_closed) {
      return;
    }
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    _closed = true;
    // Drain Riverpod's queued zero-duration auto-dispose work before another
    // independent container mounts, and before widget invariant checks.
    await tester.pump(Duration.zero);
  }

  Future<void> open(WidgetTester tester) async {
    await _tap(tester, 'Choose operator and deadline');
    expect(find.text('Assign exception follow-up'), findsOneWidget);
  }

  Future<void> choose(WidgetTester tester, {String? due}) async {
    await _tap(tester, _otherLabel);
    if (due != null) {
      await tester.enterText(find.byType(TextField), due);
      await tester.pump();
    }
    await _tap(tester, 'Use operator and deadline');
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String text) async {
  final target = find.text(text).first;
  await tester.pump();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await _settle(tester);
}

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 10 && !condition(); i++) {
    await _settle(tester);
  }
  expect(
    condition(),
    isTrue,
    reason:
        'Required async continuation must finish within ten bounded event-loop/frame cycles.',
  );
}

ButtonStyleButton _button(WidgetTester tester, String text) =>
    tester.widget<ButtonStyleButton>(
      find
          .ancestor(
            of: find.text(text),
            matching: find.byWidgetPredicate(
              (widget) => widget is ButtonStyleButton,
            ),
          )
          .first,
    );

AdminExceptionWorkflowIntent _quarantineIntent() =>
    AdminExceptionWorkflowIntent(
      requestId: '99500000-0000-4000-8000-000000000099',
      exceptionId: _id,
      sourceRevision: _raw['source_revision'] as int,
      workflowRevision: _raw['workflow_revision'] as int,
      action: 'assign',
      assigneeId: _otherId,
      dueAt: _at.add(const Duration(hours: 2)),
      expiresAt: _at.add(const Duration(seconds: 90)),
    );
String _corruptOriginal({String? fingerprint, bool removeFingerprint = false}) {
  final row =
      jsonDecode(
            AdminExceptionFollowupBookmark.fromIntent(
              _quarantineIntent(),
              _owner,
              _actor.userId,
            ).encode(),
          )
          as Map<String, dynamic>;
  row['private'] = 'PRIVATE_CANARY';
  final request = row['request'] as Map;
  request['p_assignee_id'] = _otherId;
  request['p_due_at'] = 'PRIVATE_CANARY';
  if (removeFingerprint) {
    request.remove('request_fingerprint');
  } else if (fingerprint != null) {
    request['request_fingerprint'] = fingerprint;
  }
  return jsonEncode(row);
}

void main() {
  for (final (kind, privatePayload) in [
    ('code units', 'X' * 16385),
    ('UTF8 bytes', 'é' * 8193),
  ]) {
    testWidgets(
      'oversized $kind recovery sanitizes bounded metadata and blocks all actions across reload',
      (tester) async {
        final h = _Harness();
        final raw = jsonDecode(_corruptOriginal()) as Map<String, dynamic>;
        raw['private'] = privatePayload;
        h.store.values[_owner] = jsonEncode(raw);
        await h.mount(tester);
        final saved = h.store.values[_owner]!;
        expect(saved.length, lessThanOrEqualTo(2048));
        expect(utf8.encode(saved).length, lessThanOrEqualTo(2048));
        final quarantine = AdminExceptionFollowupQuarantine.parse(
          saved,
          _owner,
          _actor.userId,
          _id,
        );
        expect(quarantine.reference, isNull);
        expect(quarantine.requestId, isNull);
        expect(saved, isNot(contains(privatePayload)));
        expect(
          _button(tester, 'Choose operator and deadline').onPressed,
          isNull,
        );
        expect(find.text('Check original assignment proof'), findsNothing);
        expect(find.text('Check follow-up request'), findsNothing);
        expect(h.repository.actions, isEmpty);
        expect(h.repository.lookups, isEmpty);
        expect(h.repository.legacyLookupIds, isEmpty);
        await h.close(tester);
        final reloaded = _Harness();
        reloaded.store.values[_owner] = saved;
        await reloaded.mount(tester);
        expect(reloaded.store.values[_owner], saved);
        expect(
          _button(tester, 'Choose operator and deadline').onPressed,
          isNull,
        );
        expect(reloaded.repository.actions, isEmpty);
        expect(reloaded.repository.lookups, isEmpty);
        expect(reloaded.repository.legacyLookupIds, isEmpty);
      },
    );
  }
  testWidgets(
    'private malformed v3 becomes sanitized quarantine and only matching v2 recorded proof clears it',
    (tester) async {
      final h = _Harness();
      h.store.values[_owner] = _corruptOriginal();
      h.repository.priorLookupIntent = _quarantineIntent();
      h.repository.badLookupFingerprint = true;
      await h.mount(tester);
      final saved = h.store.values[_owner]!;
      expect(jsonDecode(saved)['version'], 4);
      final quarantined = AdminExceptionFollowupQuarantine.parse(
        saved,
        _owner,
        _actor.userId,
        _id,
      );
      expect(
        quarantined.reference!.requestFingerprint,
        adminExceptionFollowupFingerprint(_quarantineIntent()),
      );
      for (final private in [
        'PRIVATE_CANARY',
        'p_assignee_id',
        'p_due_at',
        _otherId,
        _actor.userId,
      ]) {
        expect(saved, isNot(contains(private)));
        expect(find.textContaining(private), findsNothing);
      }
      expect(find.text('Check original follow-up request'), findsNothing);
      expect(_button(tester, 'Choose operator and deadline').onPressed, isNull);
      await _tap(tester, 'Check original assignment proof');
      expect(h.store.values[_owner], saved);
      expect(h.repository.legacyLookupIds, isEmpty);
      expect(h.repository.actions, isEmpty);
      h.repository.badLookupFingerprint = false;
      await _tap(tester, 'Check original assignment proof');
      await _until(tester, () => h.store.values.isEmpty);
      expect(h.repository.lookups, hasLength(2));
      expect(
        h.repository.lookups.map((value) => value.lookupParameters).toList(),
        [
          quarantined.reference!.lookupParameters,
          quarantined.reference!.lookupParameters,
        ],
      );
      expect(h.repository.legacyLookupIds, isEmpty);
      expect(h.repository.actions, isEmpty);
    },
  );
  testWidgets(
    'fresh expired absence cannot clear rejected v3 metadata quarantine',
    (tester) async {
      final h = _Harness();
      h.store.values[_owner] = _corruptOriginal();
      h.repository.lookupStatus = 'not_recorded';
      h.repository.now = _quarantineIntent().expiresAt;
      await h.mount(tester);
      final saved = h.store.values[_owner]!;
      expect(jsonDecode(saved)['version'], 4);
      await _tap(tester, 'Check original assignment proof');
      expect(h.repository.lookups, hasLength(1));
      expect(
        h.repository.lookups.single.expiresAt,
        _quarantineIntent().expiresAt,
      );
      expect(h.store.values[_owner], saved);
      expect(h.repository.legacyLookupIds, isEmpty);
      expect(h.repository.actions, isEmpty);
      expect(_button(tester, 'Choose operator and deadline').onPressed, isNull);
    },
  );
  for (final fault in ['missing', 'nonhex', 'uppercase']) {
    testWidgets(
      '$fault v3 fingerprint sanitizes then remains blocked across reload with no lookup',
      (tester) async {
        final h = _Harness();
        h.store.values[_owner] = _corruptOriginal(
          removeFingerprint: fault == 'missing',
          fingerprint: fault == 'nonhex'
              ? 'PRIVATE_HASH_CANARY'
              : fault == 'uppercase'
              ? 'A' * 64
              : null,
        );
        await h.mount(tester);
        final saved = h.store.values[_owner]!;
        final quarantine = AdminExceptionFollowupQuarantine.parse(
          saved,
          _owner,
          _actor.userId,
          _id,
        );
        expect(quarantine.reference, isNull);
        expect(quarantine.requestId, _quarantineIntent().requestId);
        expect(saved, isNot(contains('PRIVATE')));
        expect(saved, isNot(contains('request_fingerprint')));
        expect(find.text('Check original follow-up request'), findsNothing);
        expect(find.text('Check original assignment proof'), findsNothing);
        expect(
          _button(tester, 'Choose operator and deadline').onPressed,
          isNull,
        );
        await h.close(tester);
        final reloaded = _Harness();
        reloaded.store.values[_owner] = saved;
        await reloaded.mount(tester);
        expect(reloaded.store.values[_owner], saved);
        expect(find.text('Check original follow-up request'), findsNothing);
        expect(find.text('Check original assignment proof'), findsNothing);
        expect(
          _button(tester, 'Choose operator and deadline').onPressed,
          isNull,
        );
        expect(h.repository.lookups, isEmpty);
        expect(h.repository.legacyLookupIds, isEmpty);
        expect(reloaded.repository.lookups, isEmpty);
        expect(reloaded.repository.legacyLookupIds, isEmpty);
        expect(reloaded.repository.actions, isEmpty);
      },
    );
  }
  for (final version in [2, 99, '3']) {
    testWidgets(
      'tampered version $version with fingerprint metadata never downgrades to legacy lookup',
      (tester) async {
        final h = _Harness();
        final raw = jsonDecode(_corruptOriginal()) as Map<String, dynamic>;
        raw['version'] = version;
        h.store.values[_owner] = jsonEncode(raw);
        await h.mount(tester);
        final saved = h.store.values[_owner]!;
        final quarantine = AdminExceptionFollowupQuarantine.parse(
          saved,
          _owner,
          _actor.userId,
          _id,
        );
        expect(quarantine.reference, isNull);
        expect(saved, isNot(contains('PRIVATE')));
        expect(find.text('Check original follow-up request'), findsNothing);
        expect(find.text('Check follow-up request'), findsNothing);
        expect(find.text('Check original assignment proof'), findsNothing);
        expect(
          _button(tester, 'Choose operator and deadline').onPressed,
          isNull,
        );
        expect(h.repository.lookups, isEmpty);
        expect(h.repository.legacyLookupIds, isEmpty);
        expect(h.repository.actions, isEmpty);
      },
    );
  }
  for (final attack in ['root fingerprint', 'removed metadata fingerprint']) {
    testWidgets('$attack version2 cannot acquire a legacy original lookup', (
      tester,
    ) async {
      final h = _Harness();
      final raw = jsonDecode(_corruptOriginal()) as Map<String, dynamic>;
      raw['version'] = 2;
      final request = raw['request'] as Map;
      final fingerprint = request.remove('request_fingerprint');
      if (attack == 'root fingerprint') {
        raw['request_fingerprint'] = fingerprint;
        // All nine legacy request fields are otherwise well-formed. The root
        // fingerprint marker must fence this corrupt v3-shaped original.
        request['p_assignee_id'] = 'self';
        request['p_due_at'] = evidence.wire(_quarantineIntent().dueAt!);
        request['p_reason_code'] = 'review_started';
      }
      h.store.values[_owner] = jsonEncode(raw);
      await h.mount(tester);
      final saved = h.store.values[_owner]!;
      final quarantine = AdminExceptionFollowupQuarantine.parse(
        saved,
        _owner,
        _actor.userId,
        _id,
      );
      expect(quarantine.reference, isNull);
      expect(saved, isNot(contains('PRIVATE')));
      expect(find.text('Check original follow-up request'), findsNothing);
      expect(find.text('Check follow-up request'), findsNothing);
      expect(find.text('Check original assignment proof'), findsNothing);
      expect(_button(tester, 'Choose operator and deadline').onPressed, isNull);
      expect(h.repository.lookups, isEmpty);
      expect(h.repository.legacyLookupIds, isEmpty);
      expect(h.repository.actions, isEmpty);
    });
  }
  testWidgets(
    'strict legacy v2 self-assignment recovery keeps only its original v1 lookup route',
    (tester) async {
      final h = _Harness(), original = _quarantineIntent();
      final self = AdminExceptionWorkflowIntent(
        requestId: original.requestId,
        exceptionId: _id,
        sourceRevision: original.sourceRevision,
        workflowRevision: original.workflowRevision,
        action: 'assign',
        assigneeId: _actor.userId,
        dueAt: original.dueAt,
        expiresAt: original.expiresAt,
      );
      final saved = self.encode(_owner, _actor.userId);
      h.store.values[_owner] = saved;
      await h.mount(tester);
      expect(find.text('Check follow-up request'), findsOneWidget);
      expect(find.text('Check original assignment proof'), findsNothing);
      expect(h.store.values[_owner], saved);
      await _tap(tester, 'Check follow-up request');
      expect(h.repository.legacyLookupIds, [self.requestId]);
      expect(h.repository.lookups, isEmpty);
      expect(h.repository.actions, isEmpty);
      expect(h.store.values[_owner], saved);
    },
  );
  testWidgets(
    'reviewed different operator and Kigali deadline produce exact v3 durable action',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      await h.open(tester);
      await h.choose(tester, due: '2026-10-01 17:15');
      await _until(
        tester,
        () => h.repository.actions.length == 1 && h.store.values.isEmpty,
      );
      final intent = h.repository.actions.single;
      expect(intent.assigneeId, _otherId);
      expect(intent.dueAt, DateTime.utc(2026, 10, 1, 15, 15));
      expect(intent.sourceRevision, _raw['source_revision']);
      expect(intent.workflowRevision, _raw['workflow_revision']);
      expect(intent.expiresAt, _at.add(const Duration(seconds: 90)));
      expect(h.store.written, hasLength(1));
      expect(
        find.textContaining('Assignment recorded for $_otherLabel'),
        findsOneWidget,
      );
      expect(h.repository.workflowReads, greaterThanOrEqualTo(3));
    },
  );
  for (final due in [
    '2026-02-30 17:15',
    '2026-10-01 01:00',
    '2026-11-02 17:15',
  ]) {
    testWidgets(
      'invalid calendar past or beyond30day deadline $due does not submit',
      (tester) async {
        final h = _Harness();
        await h.mount(tester);
        await h.open(tester);
        await h.choose(tester, due: due);
        expect(
          find.text('Enter a valid future deadline within 30 days.'),
          findsOneWidget,
        );
        expect(h.repository.actions, isEmpty);
        expect(h.store.written, isEmpty);
        expect(find.text('Assign exception follow-up'), findsOneWidget);
      },
    );
  }
  testWidgets('cancel picker leaves no action or recovery bookmark', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    await h.open(tester);
    await _tap(tester, _otherLabel);
    await _tap(tester, 'Cancel assignment');
    expect(find.text('Assign exception follow-up'), findsNothing);
    expect(h.repository.actions, isEmpty);
    expect(h.store.written, isEmpty);
  });
  for (final fault in ['empty', 'error', 'private']) {
    testWidgets('$fault operator observation cannot choose or leak source text', (
      tester,
    ) async {
      final h = _Harness();
      h.repository.emptyDirectory = fault == 'empty';
      h.repository.directoryFails = fault == 'error';
      h.repository.privateDirectory = fault == 'private';
      await h.mount(tester);
      await h.open(tester);
      expect(
        find.text(
          fault == 'empty'
              ? 'No eligible operators were found on this page.'
              : 'Eligible operators could not be verified. Refresh and check current email access.',
        ),
        findsOneWidget,
      );
      expect(_button(tester, 'Use operator and deadline').onPressed, isNull);
      expect(find.textContaining('PRIVATE_'), findsNothing);
      expect(h.repository.actions, isEmpty);
      h.repository.emptyDirectory = false;
      h.repository.directoryFails = false;
      h.repository.privateDirectory = false;
      await _tap(tester, 'Refresh operators');
      expect(find.text(_otherLabel), findsOneWidget);
      expect(h.repository.queries, hasLength(2));
    });
  }
  testWidgets('operator observation expires until a manual refresh', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    await h.open(tester);
    await _tap(tester, _otherLabel);
    h.repository.now = h.repository.now.add(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.text(
        'The operator observation expired. Refresh before choosing an operator.',
      ),
      findsOneWidget,
    );
    expect(_button(tester, 'Use operator and deadline').onPressed, isNull);
    expect(h.repository.actions, isEmpty);
    await _tap(tester, 'Refresh operators');
    expect(
      find.text(
        'The operator observation expired. Refresh before choosing an operator.',
      ),
      findsNothing,
    );
    expect(h.repository.queries, hasLength(2));
  });
  testWidgets('actual paired directory pagination clears a prior selection', (
    tester,
  ) async {
    final h = _Harness();
    h.repository.paginate = true;
    await h.mount(tester);
    await h.open(tester);
    await _tap(tester, _otherLabel);
    expect(_button(tester, 'Use operator and deadline').onPressed, isNotNull);
    await _tap(tester, 'Next operators');
    final first = AdminExceptionFollowupDirectory.parse(
      h.repository.directory(const AdminExceptionFollowupDirectoryQuery()),
      query: const AdminExceptionFollowupDirectoryQuery(),
    );
    expect(h.repository.queries.last.before, first.nextCursor);
    expect(find.text(_otherLabel), findsNothing);
    expect(_button(tester, 'Use operator and deadline').onPressed, isNull);
    await _tap(tester, 'Previous operators');
    expect(find.text(_otherLabel), findsOneWidget);
    expect(_button(tester, 'Use operator and deadline').onPressed, isNull);
    expect(h.repository.actions, isEmpty);
  });
  testWidgets(
    'fresh workflow revision conflict preserves reviewed operator and due for reopening',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      await h.open(tester);
      h.repository.workflow['workflow_revision'] =
          (_raw['workflow_revision'] as int) + 1;
      await h.choose(tester, due: '2026-10-01 17:15');
      await _until(tester, () => h.repository.workflowReads >= 3);
      expect(
        find.text(
          'Follow-up changed during review. Your operator and deadline are kept for review. Check the refreshed follow-up before submitting.',
        ),
        findsOneWidget,
      );
      expect(h.repository.actions, isEmpty);
      expect(h.store.written, isEmpty);
      await h.open(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '2026-10-01 17:15',
      );
      expect(_button(tester, 'Use operator and deadline').onPressed, isNotNull);
      await _tap(tester, 'Use operator and deadline');
      await _until(tester, () => h.repository.actions.length == 1);
      expect(
        h.repository.actions.single.workflowRevision,
        (_raw['workflow_revision'] as int) + 1,
      );
    },
  );
  for (final missing in [
    'platform_owner',
    'payments.read',
    'notifications.read',
    'system_health.read',
    'notifications.manage',
  ]) {
    testWidgets('missing $missing prevents the v2 picker query and action', (
      tester,
    ) async {
      final h = _Harness();
      final identity = missing == 'platform_owner'
          ? _identity(roles: ['admin'])
          : _identity(
              permissions: _actor.permissions
                  .where((p) => p != missing)
                  .toList(),
            );
      await h.mount(tester, identity: identity);
      final choose = find.text('Choose operator and deadline');
      if (choose.evaluate().isNotEmpty) {
        expect(
          _button(tester, 'Choose operator and deadline').onPressed,
          isNull,
        );
      }
      expect(h.repository.queries, isEmpty);
      expect(h.repository.actions, isEmpty);
    });
  }
  testWidgets(
    'permission loss closes opening dialog and prevents held directory disclosure',
    (tester) async {
      final h = _Harness();
      h.repository.directoryGate = Completer();
      await h.mount(tester);
      await h.open(tester);
      expect(find.text('Checking eligible operators…'), findsOneWidget);
      h.container.read(_authority.notifier).state = _identity(
        permissions: ['payments.read', 'notifications.read'],
      );
      await _settle(tester);
      expect(find.text('Assign exception follow-up'), findsNothing);
      h.repository.directoryGate!.complete(
        h.repository.directory(const AdminExceptionFollowupDirectoryQuery()),
      );
      await _settle(tester);
      expect(find.text(_otherLabel), findsNothing);
      expect(h.repository.actions, isEmpty);
    },
  );
  testWidgets(
    'opening session A-B-A closes modal and suppresses late directory result',
    (tester) async {
      final h = _Harness();
      h.repository.directoryGate = Completer();
      await h.mount(tester);
      await h.open(tester);
      h.sessions.change('replacement');
      await tester.pump();
      h.sessions.change('opening');
      await _settle(tester);
      expect(find.text('Assign exception follow-up'), findsNothing);
      h.repository.directoryGate!.complete(
        h.repository.directory(const AdminExceptionFollowupDirectoryQuery()),
      );
      await _settle(tester);
      expect(find.text(_otherLabel), findsNothing);
      expect(h.repository.actions, isEmpty);
    },
  );
  testWidgets(
    'changed current actor authority after picker prevents assignment',
    (tester) async {
      final h = _Harness();
      h.repository.actor = _identity(roles: ['admin']);
      await h.mount(tester);
      await h.open(tester);
      await h.choose(tester);
      await _until(tester, () => h.repository.identityReads == 1);
      expect(h.repository.actions, isEmpty);
      expect(h.store.written, isEmpty);
      expect(
        find.textContaining('Assignment was not submitted.'),
        findsOneWidget,
      );
    },
  );
  for (final stage in ['identity', 'workflow', 'action']) {
    testWidgets(
      'session loss during $stage await suppresses later action or outcome',
      (tester) async {
        final h = _Harness();
        if (stage == 'identity') {
          h.repository.identityGate = Completer();
        }
        if (stage == 'workflow') {
          h.repository.workflowGate = Completer();
        }
        if (stage == 'action') {
          h.repository.actionGate = Completer();
        }
        await h.mount(tester);
        await h.open(tester);
        await h.choose(tester);
        await _until(
          tester,
          () => stage == 'identity'
              ? h.repository.identityReads == 1
              : stage == 'workflow'
              ? h.repository.workflowReads >= 2
              : h.repository.actions.length == 1,
        );
        h.sessions.change('replacement');
        await _settle(tester);
        if (stage == 'identity') {
          h.repository.identityGate!.complete(_actor);
        }
        if (stage == 'workflow') {
          h.repository.workflowGate!.complete(
            evidence.copy(h.repository.workflow),
          );
        }
        if (stage == 'action') {
          h.repository.actionGate!.complete(
            h.repository.receipt(h.repository.actions.single),
          );
        }
        await _settle(tester);
        expect(h.repository.actions, hasLength(stage == 'action' ? 1 : 0));
        expect(find.textContaining('Assignment recorded for'), findsNothing);
        if (stage == 'action') {
          expect(h.store.values, hasLength(1));
        } else {
          expect(h.store.written, isEmpty);
        }
      },
    );
  }
  testWidgets(
    'lost reply retains exact original and manual recorded lookup never resends',
    (tester) async {
      final h = _Harness();
      h.repository.loseReply = true;
      await h.mount(tester);
      await h.open(tester);
      await h.choose(tester);
      await _until(
        tester,
        () =>
            h.repository.actions.length == 1 &&
            find.text('Check assignment request').evaluate().isNotEmpty,
      );
      expect(
        find.text(
          'Assignment outcome unconfirmed. Check the original request before another action.',
        ),
        findsOneWidget,
      );
      final saved = h.store.values[_owner]!,
          original = AdminExceptionFollowupBookmark.decode(
            saved,
            _owner,
            _actor.userId,
            _id,
          );
      expect(_button(tester, 'Choose operator and deadline').onPressed, isNull);
      await _tap(tester, 'Check assignment request');
      await _until(tester, () => h.store.values.isEmpty);
      expect(
        h.repository.lookups.single.lookupParameters,
        original.reference.lookupParameters,
      );
      expect(h.repository.actions, hasLength(1));
      expect(
        find.text('The original assignment request was recorded.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'reload recovers metadata only and clears fresh absent original only after expiry',
    (tester) async {
      final h = _Harness();
      final intent = AdminExceptionWorkflowIntent(
        requestId: '99500000-0000-4000-8000-000000000001',
        exceptionId: _id,
        sourceRevision: _raw['source_revision'] as int,
        workflowRevision: _raw['workflow_revision'] as int,
        action: 'assign',
        assigneeId: _otherId,
        dueAt: _at.add(const Duration(hours: 2)),
        expiresAt: _at.add(const Duration(seconds: 90)),
      );
      final bookmark = AdminExceptionFollowupBookmark.fromIntent(
        intent,
        _owner,
        _actor.userId,
      );
      h.store.values[_owner] = bookmark.encode();
      h.repository.lookupStatus = 'not_recorded';
      await h.mount(tester);
      expect(find.text('Check assignment request'), findsOneWidget);
      await _tap(tester, 'Check assignment request');
      expect(h.store.values[_owner], bookmark.encode());
      expect(h.repository.actions, isEmpty);
      expect(
        find.text(
          'The original request may still arrive. Its reference is retained.',
        ),
        findsOneWidget,
      );
      h.repository.now = intent.expiresAt;
      await _tap(tester, 'Check assignment request');
      await _until(tester, () => h.store.values.isEmpty);
      expect(h.repository.lookups, hasLength(2));
      expect(h.repository.actions, isEmpty);
      expect(h.repository.lookups.map((r) => r.lookupParameters).toList(), [
        bookmark.reference.lookupParameters,
        bookmark.reference.lookupParameters,
      ]);
      expect(
        find.text(
          'The original assignment expired without being recorded. Refresh before a new action.',
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'wrong fingerprint on lookup retains unknown original without resend',
    (tester) async {
      final h = _Harness();
      h.repository.loseReply = true;
      await h.mount(tester);
      await h.open(tester);
      await h.choose(tester);
      await _until(
        tester,
        () =>
            h.repository.actions.length == 1 &&
            find.text('Check assignment request').evaluate().isNotEmpty,
      );
      final saved = h.store.values[_owner];
      h.repository.badLookupFingerprint = true;
      await _tap(tester, 'Check assignment request');
      expect(h.store.values[_owner], saved);
      expect(h.repository.actions, hasLength(1));
      expect(
        find.text(
          'The original assignment outcome could not be verified. Its reference is retained.',
        ),
        findsOneWidget,
      );
      expect(_button(tester, 'Choose operator and deadline').onPressed, isNull);
    },
  );
  for (final fault in ['quota', 'read', 'readback']) {
    testWidgets(
      '$fault checkpoint failure prevents dispatch and leaks no error',
      (tester) async {
        final h = _Harness();
        await h.mount(tester);
        await h.open(tester);
        h.store.failWrite = fault == 'quota';
        h.store.failRead = fault == 'read';
        h.store.corruptReadback = fault == 'readback';
        await h.choose(tester);
        await _until(tester, () => h.repository.identityReads == 1);
        expect(h.repository.actions, isEmpty);
        expect(find.textContaining('PRIVATE_'), findsNothing);
        expect(
          find.text(
            'Recovery storage is unavailable. Follow-up actions are disabled.',
          ),
          findsOneWidget,
        );
      },
    );
  }
  testWidgets(
    'a pending original inserted during review is never overwritten',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      await h.open(tester);
      h.store.values[_owner] = 'PRIVATE_EXISTING_ORIGINAL_CANARY';
      await h.choose(tester);
      await _until(tester, () => h.repository.identityReads == 1);
      expect(h.store.values[_owner], 'PRIVATE_EXISTING_ORIGINAL_CANARY');
      expect(h.store.written, isEmpty);
      expect(h.repository.actions, isEmpty);
      expect(find.textContaining('PRIVATE_'), findsNothing);
    },
  );
  testWidgets(
    'expired directory during actor preflight retains review without send',
    (tester) async {
      final h = _Harness();
      h.repository.identityGate = Completer();
      await h.mount(tester);
      await h.open(tester);
      await h.choose(tester);
      await _until(tester, () => h.repository.identityReads == 1);
      h.repository.now = h.repository.now.add(const Duration(seconds: 60));
      h.repository.identityGate!.complete(_actor);
      await _settle(tester);
      expect(h.repository.actions, isEmpty);
      expect(h.store.written, isEmpty);
      expect(
        find.textContaining('Assignment was not submitted.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    '320px twice-sized text preserves named keyboard controls without overflow',
    (tester) async {
      final h = _Harness();
      await h.mount(tester, width: 320, scale: 2);
      await h.open(tester);
      final semantics = tester.ensureSemantics();
      try {
        expect(find.text('Eligible operators'), findsOneWidget);
        await tester.ensureVisible(find.byType(TextField));
        await tester.tap(find.byType(TextField));
        await tester.pump();
        expect(
          tester.widget<TextField>(find.byType(TextField)).keyboardType,
          TextInputType.datetime,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Due at (Africa/Kigali)'), findsOneWidget);
        expect(find.text('Cancel assignment'), findsOneWidget);
        expect(find.text('Use operator and deadline'), findsOneWidget);
        await _tap(tester, 'Cancel assignment');
        expect(tester.takeException(), isNull);
        expect(h.repository.actions, isEmpty);
      } finally {
        semantics.dispose();
      }
    },
  );
}
