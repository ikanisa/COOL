import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

import 'package:collect_app/admin/core/admin_entity_audit.dart';
import 'package:collect_app/admin/core/admin_exception_history_v2_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

const historyExceptionId = '99510000-0000-4000-8000-000000000001';
const historyActorId = '99430000-0000-4000-8000-000000000001';
const historyEscalationId = '99510000-0000-4000-8000-000000000099';
const historyChecked = '2026-10-01T20:00:00.000000Z';
const historyActions = [
  'exception.acknowledge',
  'exception.escalate',
  'exception.workflow.assign',
  'exception.workflow.escalate',
  'exception.workflow.resolve',
  'exception.escalation.queued',
  'exception.escalation.delivered',
  'exception.escalation.opened',
  'exception.escalation.obsolete',
  'exception.escalation.recipient_unavailable',
];
Map<String, dynamic> historyCopy(Map<String, dynamic> row) =>
    jsonDecode(jsonEncode(row)) as Map<String, dynamic>;
String historyWire(DateTime value) => value
    .toUtc()
    .toIso8601String()
    .replaceFirstMapped(RegExp(r'\.(\d{3})Z$'), (m) => '.${m[1]}000Z');
String historyEventId(String source, String recordId) => const Uuid().v5(
  'c5a97546-80ab-5b57-a267-754aac043bd0',
  '$source:$recordId',
);
Map<String, dynamic> historyEvent(String action) {
  final index = historyActions.indexOf(action) + 1;
  final workflow = action.startsWith('exception.workflow.');
  final lifecycle = action.startsWith('exception.escalation.');
  final record = '99510000-0000-4000-8000-${index.toString().padLeft(12, '0')}';
  final source = lifecycle
      ? 'exception_escalation_event'
      : workflow
      ? 'exception_workflow_request'
      : 'exception_action';
  return {
    'event_id': historyEventId(source, record),
    'source': source,
    'source_record_id': record,
    'action': action,
    'recorded_at': '2026-10-01T19:00:00.000000Z',
    'actor_kind': lifecycle ? 'service' : 'operator',
    'actor_id': lifecycle ? null : historyActorId,
    'request_id': lifecycle ? null : record,
    'revision': 1,
    'workflow_revision': workflow ? 1 : null,
    'escalation_id': lifecycle || action == 'exception.workflow.escalate'
        ? historyEscalationId
        : null,
    'reason_code': lifecycle
        ? 'operator_escalation'
        : action == 'exception.workflow.resolve'
        ? 'source_rechecked'
        : 'review_started',
    'origin': lifecycle ? 'captured_transition' : 'immutable_request',
    'assignee_id': action == 'exception.workflow.assign'
        ? historyActorId
        : null,
    'due_at': action == 'exception.workflow.assign'
        ? '2026-10-02T20:00:00.000000Z'
        : null,
  };
}

// Explicit presentation/contract double, not an observed SQL reply. New SQL
// observations are consumed separately once the backend packet is available.
Map<String, dynamic> historyFixture() => {
  'contract_version': 2,
  'scope': 'rw_operator_entity_audit',
  'entity_kind': 'exception',
  'entity_id': historyExceptionId,
  'status': 'available',
  'checked_at': historyChecked,
  'sample_valid_until': '2026-10-01T20:01:00.000000Z',
  'limit': 20,
  'history_complete': false,
  'financial_action': false,
  'send_action': false,
  'rows': (historyActions.map(historyEvent).toList()
    ..sort(
      (a, b) => (b['event_id'] as String).compareTo(a['event_id'] as String),
    )),
  'next_cursor': null,
};
AdminEntityAuditQuery historyQuery({
  String id = historyExceptionId,
  int limit = 20,
  AdminEntityAuditCursor? before,
}) => AdminEntityAuditQuery(
  kind: AdminAuditEntityKind.exception,
  id: id,
  limit: limit,
  before: before,
);
Map<String, dynamic> historyWindow(
  Map<String, dynamic> raw,
  AdminEntityAuditQuery query,
) {
  final candidates = (raw['rows'] as List).where((item) {
    final row = item as Map;
    return query.before == null ||
        AdminEntityAuditCursor(
              recordedAt: DateTime.parse(row['recorded_at'] as String),
              eventId: row['event_id'] as String,
            ).compareTo(query.before!) <
            0;
  }).toList();
  final rows = candidates.take(query.limit).toList();
  return historyCopy(raw)
    ..['entity_id'] = query.id
    ..['limit'] = query.limit
    ..['rows'] = rows
    ..['next_cursor'] = candidates.length > query.limit
        ? {
            'recorded_at': (rows.last as Map)['recorded_at'],
            'event_id': (rows.last as Map)['event_id'],
          }
        : null;
}

void main() {
  const fixtureRoot = 'scripts/tests/fixtures/exception_inbox_audit_v2';
  Map<String, dynamic> observed(String name) =>
      jsonDecode(File('$fixtureRoot/observed-$name.json').readAsStringSync())
          as Map<String, dynamic>;
  AdminEntityAuditQuery observedQuery(
    Map<String, dynamic> raw, {
    AdminEntityAuditCursor? before,
  }) => historyQuery(
    id: raw['entity_id'] as String,
    limit: raw['limit'] as int,
    before: before,
  );
  for (final name in [
    'audit-after-pump-commit',
    'audit-allocation-event',
    'audit-complete',
    'audit-final',
    'audit-first',
    'audit-last',
    'audit-legacy-target-refusal',
    'audit-obsolete-resolved',
    'audit-receipt_backlog',
    'audit-receipt_event',
    'audit-retained',
    'audit-unavailable',
    'audit-unknown',
    'audit-unscoped',
  ]) {
    test(
      'actual accepted isolated SQL $name obeys exception-only v2 immutable contract',
      () {
        final raw = observed(name);
        final first = observed('audit-first');
        final cursor = AdminEntityAuditCursor(
          recordedAt: DateTime.parse(
            (first['next_cursor'] as Map)['recorded_at'] as String,
          ),
          eventId: (first['next_cursor'] as Map)['event_id'] as String,
        );
        final value = AdminExceptionHistorySnapshot.parse(
          raw,
          query: observedQuery(
            raw,
            before: name == 'audit-last' ? cursor : null,
          ),
        );
        expect(value.available, raw['status'] == 'available');
        expect(value.rows, hasLength((raw['rows'] as List).length));
        expect(value.isFresh(value.checkedAt), isTrue);
        expect(value.isFresh(value.validUntil), isFalse);
        for (final row in value.rows) {
          expect(row.eventId, historyEventId(row.source, row.sourceRecordId));
        }
      },
    );
  }
  test(
    'actual SQL paired history pages have stable boundaries and no lost or repeated original events',
    () {
      final completeRaw = observed('audit-complete'),
          firstRaw = observed('audit-first'),
          lastRaw = observed('audit-last');
      final complete = AdminExceptionHistorySnapshot.parse(
        completeRaw,
        query: observedQuery(completeRaw),
      );
      final first = AdminExceptionHistorySnapshot.parse(
        firstRaw,
        query: observedQuery(firstRaw),
      );
      final last = AdminExceptionHistorySnapshot.parse(
        lastRaw,
        query: observedQuery(lastRaw, before: first.nextCursor),
      );
      expect(first.rows, hasLength(2));
      expect(last.rows, hasLength(4));
      expect([
        ...first.rows.map((e) => e.eventId),
        ...last.rows.map((e) => e.eventId),
      ], complete.rows.map((e) => e.eventId));
      expect(last.nextCursor, isNull);
    },
  );
  test(
    'actual SQL same request UUID across review and workflow remains source-derived with dated assignment',
    () {
      final raw = observed('audit-complete');
      final rows = AdminExceptionHistorySnapshot.parse(
        raw,
        query: observedQuery(raw),
      ).rows;
      final review = rows.singleWhere(
        (r) => r.action == 'exception.acknowledge',
      );
      final assignment = rows.singleWhere(
        (r) => r.action == 'exception.workflow.assign',
      );
      expect(review.sourceRecordId, assignment.sourceRecordId);
      expect(review.eventId, isNot(assignment.eventId));
      expect(assignment.assigneeId, '99790000-0000-4000-8000-000000000001');
      expect(assignment.dueAt, isNotNull);
      expect(rows.map((r) => r.action).toSet(), {
        'exception.acknowledge',
        'exception.workflow.assign',
        'exception.workflow.escalate',
        'exception.escalation.queued',
        'exception.escalation.delivered',
        'exception.escalation.opened',
      });
    },
  );
  test(
    'actual retained backfill has only known phase times and no fabricated executing operator',
    () {
      final raw = observed('audit-retained');
      final rows = AdminExceptionHistorySnapshot.parse(
        raw,
        query: observedQuery(raw),
      ).rows.where((r) => r.origin == 'retained_source').toList();
      expect(rows.map((r) => r.action).toSet(), {
        'exception.escalation.queued',
        'exception.escalation.delivered',
        'exception.escalation.opened',
      });
      expect(
        rows.every(
          (r) =>
              r.actorKind == 'unknown' &&
              r.actorId == null &&
              r.requestId == null &&
              r.assigneeId == null &&
              r.dueAt == null,
        ),
        isTrue,
      );
      expect(
        rows.any(
          (r) => r.action == 'exception.escalation.recipient_unavailable',
        ),
        isFalse,
      );
    },
  );
  test(
    'original100-case observations stay byte-bound to their archived producer and provenance',
    () {
      final provenance =
          jsonDecode(File('$fixtureRoot/provenance.json').readAsStringSync())
              as Map;
      const accepted =
          'a83543aa0266eb40ba5abd4c94c26b0db6d3fc8e238929bc2794154a7fa773f9';
      expect(provenance['migration_sha256'], accepted);
      expect(
        sha256
            .convert(
              File(
                'docs/release/collect-codex-goal-2026-09-30/exception-inbox-audit-v2-20261001/attempt8/executed-inputs/supabase/migrations/20261001200000_exception_inbox_audit_v2.sql',
              ).readAsBytesSync(),
            )
            .toString(),
        accepted,
      );
      expect(
        provenance['kind'],
        'actual_isolated_synthetic_SQL_not_production',
      );
      expect(provenance['actual_sql_cases'], 100);
      expect(provenance['fixtures'], hasLength(19));
      for (final row in provenance['fixtures'] as List) {
        expect(row['schema_valid'], isTrue);
        expect(
          sha256
              .convert(File(row['path'] as String).readAsBytesSync())
              .toString(),
          row['sha256'],
        );
      }
    },
  );
  Map<String, dynamic> boundedObserved(String name) =>
      jsonDecode(
            File('$fixtureRoot/bounded-observed-$name.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  AdminEntityAuditCursor boundedBoundary() => AdminEntityAuditCursor(
    // Exact original RPC query from the affected proof producer; no fixture
    // timestamp or event ID is rewritten to manufacture first-page evidence.
    recordedAt: DateTime.parse('2026-10-01T15:36:07.860693Z'),
    eventId: 'ffffffff-ffff-ffff-ffff-ffffffffffff',
  );
  for (final name in [
    'public-small-page',
    'authenticated-public-page',
    'authenticated-public-older',
    'audit-final',
  ]) {
    test(
      'actual affected37 SQL $name keeps the unchanged strict codec and original query',
      () {
        final raw = boundedObserved(name);
        final firstRaw = boundedObserved('authenticated-public-page');
        final first = AdminExceptionHistorySnapshot.parse(
          firstRaw,
          query: observedQuery(firstRaw, before: boundedBoundary()),
        );
        final query = observedQuery(
          raw,
          before: name == 'authenticated-public-page'
              ? boundedBoundary()
              : name == 'authenticated-public-older'
              ? first.nextCursor
              : null,
        );
        final value = AdminExceptionHistorySnapshot.parse(raw, query: query);
        expect(value.rows, hasLength((raw['rows'] as List).length));
        expect(value.available, isTrue);
        expect(value.isFresh(value.validUntil), isFalse);
        expect(query.limit, name.startsWith('authenticated') ? 20 : 25);
      },
    );
  }
  test(
    'actual affected37 equal-time public pages advance namespace keysets without replaying identities',
    () {
      final firstRaw = boundedObserved('authenticated-public-page');
      final first = AdminExceptionHistorySnapshot.parse(
        firstRaw,
        query: observedQuery(firstRaw, before: boundedBoundary()),
      );
      final olderRaw = boundedObserved('authenticated-public-older');
      final query = observedQuery(olderRaw, before: first.nextCursor);
      final older = AdminExceptionHistorySnapshot.parse(olderRaw, query: query);
      expect(first.rows, hasLength(20));
      expect(older.rows, hasLength(20));
      expect({
        ...first.rows.map((r) => r.eventId),
        ...older.rows.map((r) => r.eventId),
      }, hasLength(40));
      expect(query.before, first.rows.last.cursor);
      expect(adminExceptionHistoryParameters(query), {
        'p_exception_id': olderRaw['entity_id'],
        'p_limit': 20,
        'p_before_at': '2026-10-01T15:36:07.860693Z',
        'p_before_event_id': first.rows.last.eventId,
      });
      expect(
        older.rows.every((r) => r.cursor.compareTo(first.rows.last.cursor) < 0),
        isTrue,
      );
      final finalRaw = boundedObserved('audit-final');
      final afterRollback = AdminExceptionHistorySnapshot.parse(
        finalRaw,
        query: observedQuery(finalRaw),
      );
      expect(afterRollback.rows, hasLength(6));
      expect(afterRollback.nextCursor, isNull);
    },
  );
  test(
    'current branch-bounded SQL and five new observations bind separately to affected37 proof',
    () {
      final provenance =
          jsonDecode(
                File(
                  '$fixtureRoot/bounded-read-provenance.json',
                ).readAsStringSync(),
              )
              as Map;
      const current =
          '7f6aea2058be51ae93b4f25d0dc0463b05f13476d6e41093a355bdc6871033d7';
      const migration =
          'supabase/migrations/20261001200000_exception_inbox_audit_v2.sql';
      expect(provenance['migration_sha256'], current);
      expect(
        sha256.convert(File(migration).readAsBytesSync()).toString(),
        current,
      );
      final result =
          jsonDecode(
                File(
                  provenance['accepted_result'] as String,
                ).readAsStringSync(),
              )
              as Map;
      expect(result['status'], 'pass');
      expect(result['sources_unchanged'], isTrue);
      expect(result['cases'], hasLength(37));
      expect((result['source_sha256'] as Map)[migration], current);
      expect(provenance['fixtures'], hasLength(5));
      for (final row in provenance['fixtures'] as List) {
        expect(
          sha256
              .convert(File(row['path'] as String).readAsBytesSync())
              .toString(),
          row['sha256'],
        );
      }
    },
  );
  for (final action in historyActions) {
    test(
      '$action retains exact finite evidence without current action authority',
      () {
        final raw = historyEvent(action),
            event = AdminExceptionHistoryEvent.parse(raw);
        expect(event.action, action);
        expect(event.actionLabel, isNotEmpty);
        expect(event.sourceRecordId, raw['source_record_id']);
        expect(event.cursor.eventId, raw['event_id']);
        expect(event.recordedAt, DateTime.parse(raw['recorded_at'] as String));
        expect(event.revision, 1);
        expect(event.reasonLabel, isNotNull);
        if (action == 'exception.workflow.assign') {
          expect(event.assigneeId, historyActorId);
          expect(event.dueAt, isNotNull);
        }
        if (action.startsWith('exception.escalation.')) {
          expect(event.requestId, isNull);
          expect(event.workflowRevision, isNull);
          expect(event.actorId, isNull);
        }
      },
    );
  }
  test(
    'joined source IDs may repeat across sources while stable event IDs stay distinct',
    () {
      final raw = historyFixture();
      final rows = raw['rows'] as List;
      final review =
          rows.singleWhere(
                (e) => (e as Map)['action'] == 'exception.acknowledge',
              )
              as Map;
      final assignment =
          rows.singleWhere(
                (e) => (e as Map)['action'] == 'exception.workflow.assign',
              )
              as Map;
      assignment['source_record_id'] = review['source_record_id'];
      assignment['request_id'] = review['request_id'];
      assignment['event_id'] = historyEventId(
        assignment['source'] as String,
        assignment['source_record_id'] as String,
      );
      rows.sort(
        (a, b) => (b['event_id'] as String).compareTo(a['event_id'] as String),
      );
      final snapshot = AdminExceptionHistorySnapshot.parse(
        raw,
        query: historyQuery(),
      );
      expect(snapshot.rows.map((e) => e.eventId).toSet(), hasLength(10));
      final reviewEvent = snapshot.rows.singleWhere(
        (e) => e.action == 'exception.acknowledge',
      );
      final assignmentEvent = snapshot.rows.singleWhere(
        (e) => e.action == 'exception.workflow.assign',
      );
      expect(reviewEvent.sourceRecordId, assignmentEvent.sourceRecordId);
      expect(reviewEvent.eventId, isNot(assignmentEvent.eventId));
    },
  );
  test(
    'wrong namespace cross-source record or invented stable event identity is refused',
    () {
      final row = historyEvent('exception.workflow.assign');
      for (final bad in [
        {
          ...row,
          'event_id': const Uuid().v5(
            '00000000-0000-0000-0000-000000000000',
            '${row['source']}:${row['source_record_id']}',
          ),
        },
        {
          ...row,
          'event_id': historyEventId(
            'exception_action',
            row['source_record_id'] as String,
          ),
        },
        {
          ...row,
          'event_id': historyEventId(
            row['source'] as String,
            historyEscalationId,
          ),
        },
      ]) {
        expect(
          () => AdminExceptionHistoryEvent.parse(bad),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'unknown retained attribution and actual service transitions never invent a human actor',
    () {
      final retained = historyEvent('exception.escalation.delivered')
        ..['origin'] = 'retained_source'
        ..['actor_kind'] = 'unknown';
      expect(
        AdminExceptionHistoryEvent.parse(retained).actorKindLabel,
        'Actor not recorded',
      );
      for (final bad in [
        {...retained, 'actor_kind': 'service'},
        {...retained, 'actor_id': historyActorId},
        {
          ...historyEvent('exception.escalation.opened'),
          'actor_kind': 'operator',
        },
        {
          ...historyEvent('exception.escalation.delivered'),
          'actor_id': historyActorId,
        },
      ]) {
        expect(
          () => AdminExceptionHistoryEvent.parse(bad),
          throwsFormatException,
        );
      }
      final operator = historyEvent('exception.escalation.opened')
        ..['actor_kind'] = 'operator'
        ..['actor_id'] = historyActorId;
      expect(
        AdminExceptionHistoryEvent.parse(operator).actorId,
        historyActorId,
      );
    },
  );
  test(
    'historical assignment deadline remains dated even when read long after it',
    () {
      final raw = historyFixture()
        ..['checked_at'] = '2026-10-10T20:00:00.000000Z'
        ..['sample_valid_until'] = '2026-10-10T20:01:00.000000Z';
      final snapshot = AdminExceptionHistorySnapshot.parse(
        raw,
        query: historyQuery(),
      );
      final assigned = snapshot.rows.singleWhere(
        (e) => e.action == 'exception.workflow.assign',
      );
      expect(assigned.dueAt!.isBefore(snapshot.checkedAt), isTrue);
    },
  );
  test(
    'cross-phase actor request escalation assignment and reason claims fail closed',
    () {
      final bad = <Map<String, dynamic>>[
        {
          ...historyEvent('exception.acknowledge'),
          'request_id': historyEscalationId,
        },
        {...historyEvent('exception.acknowledge'), 'workflow_revision': 1},
        {
          ...historyEvent('exception.escalate'),
          'escalation_id': historyEscalationId,
        },
        {
          ...historyEvent('exception.acknowledge'),
          'reason_code': 'source_rechecked',
        },
        {...historyEvent('exception.workflow.assign'), 'assignee_id': null},
        {...historyEvent('exception.workflow.assign'), 'due_at': null},
        {
          ...historyEvent('exception.workflow.resolve'),
          'reason_code': 'review_started',
        },
        {...historyEvent('exception.workflow.escalate'), 'escalation_id': null},
        {
          ...historyEvent('exception.workflow.resolve'),
          'due_at': '2026-10-02T20:00:00.000000Z',
        },
        {
          ...historyEvent('exception.escalation.opened'),
          'request_id': historyEscalationId,
        },
        {
          ...historyEvent('exception.escalation.queued'),
          'reason_code': 'review_started',
        },
        {
          ...historyEvent('exception.escalation.obsolete'),
          'origin': 'immutable_request',
        },
      ];
      for (final raw in bad) {
        expect(
          () => AdminExceptionHistoryEvent.parse(raw),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'query exception scope paired exactUTC6 and limits stay isolated from oldv1 kinds',
    () {
      final before = AdminEntityAuditCursor(
        recordedAt: DateTime.utc(2026, 10, 1, 19),
        eventId: historyEvent(historyActions.last)['event_id'] as String,
      );
      final query = historyQuery(limit: 1, before: before);
      expect(adminExceptionHistoryParameters(query), {
        'p_exception_id': historyExceptionId,
        'p_limit': 1,
        'p_before_at': '2026-10-01T19:00:00.000000Z',
        'p_before_event_id': before.eventId,
      });
      for (final bad in [
        historyQuery(limit: 0),
        historyQuery(limit: 26),
        historyQuery(id: 'PRIVATE_UUID'),
        const AdminEntityAuditQuery(
          kind: AdminAuditEntityKind.receipt,
          id: historyExceptionId,
        ),
        historyQuery(
          before: AdminEntityAuditCursor(
            recordedAt: DateTime.utc(0),
            eventId: historyExceptionId,
          ),
        ),
      ]) {
        expect(
          () => adminExceptionHistoryParameters(bad),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'paired audit pages preserve exact time ties immutable rows and last cursor',
    () {
      final raw = historyFixture(), query = historyQuery(limit: 3);
      final first = AdminExceptionHistorySnapshot.parse(
        historyWindow(raw, query),
        query: query,
      );
      final nextQuery = historyQuery(limit: 3, before: first.nextCursor);
      final next = AdminExceptionHistorySnapshot.parse(
        historyWindow(raw, nextQuery),
        query: nextQuery,
      );
      expect(first.rows, hasLength(3));
      expect(next.rows, hasLength(3));
      expect({
        ...first.rows.map((e) => e.eventId),
        ...next.rows.map((e) => e.eventId),
      }, hasLength(6));
      expect(() => first.rows.clear(), throwsUnsupportedError);
      final mismatched = historyWindow(raw, nextQuery)
        ..['next_cursor'] = {
          'recorded_at': historyChecked,
          'event_id': historyExceptionId,
        };
      expect(
        () => AdminExceptionHistorySnapshot.parse(mismatched, query: nextQuery),
        throwsFormatException,
      );
    },
  );
  test(
    'malformed private impossible complete financial or send claims cannot become history',
    () {
      final original = historyFixture();
      for (final patch in [
        {'contract_version': 1},
        {'contract_version': 2.0},
        {'scope': 'current_operator'},
        {'entity_kind': 'receipt'},
        {'entity_id': historyEscalationId},
        {'limit': 25},
        {'history_complete': true},
        {'financial_action': true},
        {'send_action': true},
        {'history_complete': 'false'},
        {'status': 'healthy'},
        {'status': 'unavailable'},
        {'authorization': 'PRIVATE_CANARY'},
        {'checked_at': '2026-02-30T00:00:00.000000Z'},
        {'sample_valid_until': '2026-10-01T20:01:00.000001Z'},
      ]) {
        expect(
          () => AdminExceptionHistorySnapshot.parse({
            ...original,
            ...patch,
          }, query: historyQuery()),
          throwsFormatException,
        );
      }
      for (final key in original.keys) {
        expect(
          () => AdminExceptionHistorySnapshot.parse(
            historyCopy(original)..remove(key),
            query: historyQuery(),
          ),
          throwsFormatException,
        );
      }
    },
  );
  test('unsupported and empty windows remain distinct incomplete evidence', () {
    final empty = historyFixture()..['rows'] = [];
    expect(
      AdminExceptionHistorySnapshot.parse(
        empty,
        query: historyQuery(),
      ).available,
      isTrue,
    );
    empty['status'] = 'unavailable';
    expect(
      AdminExceptionHistorySnapshot.parse(
        empty,
        query: historyQuery(),
      ).available,
      isFalse,
    );
  });
  test(
    'event closed fields finite UUID UTC revisions and time order reject private rows',
    () {
      final event = historyEvent('exception.workflow.assign');
      for (final patch in [
        {'source': 'raw_sms'},
        {'action': 'send_sms'},
        {'origin': 'approved'},
        {'actor_kind': 'admin'},
        {'actor_id': 'PRIVATE_ACTOR'},
        {'event_id': 'UPPER_UUID'},
        {'revision': 0},
        {'revision': 1000000001},
        {'workflow_revision': 0},
        {'due_at': '2026-02-30T00:00:00.000000Z'},
        {'payload': 'PRIVATE_TEXT'},
      ]) {
        expect(
          () => AdminExceptionHistoryEvent.parse({...event, ...patch}),
          throwsFormatException,
        );
      }
      for (final key in event.keys) {
        expect(
          () =>
              AdminExceptionHistoryEvent.parse(historyCopy(event)..remove(key)),
          throwsFormatException,
        );
      }
      final raw = historyFixture();
      final rows = raw['rows'] as List;
      rows.add(historyCopy(rows.first as Map<String, dynamic>));
      expect(
        () => AdminExceptionHistorySnapshot.parse(raw, query: historyQuery()),
        throwsFormatException,
      );
      final reversed = historyFixture()
        ..['rows'] = (historyFixture()['rows'] as List).reversed.toList();
      expect(
        () => AdminExceptionHistorySnapshot.parse(
          reversed,
          query: historyQuery(),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'history read expires at exactboundary without renewing original evidence',
    () {
      final value = AdminExceptionHistorySnapshot.parse(
        historyFixture(),
        query: historyQuery(),
      );
      expect(
        value.isFresh(value.checkedAt.subtract(const Duration(seconds: 5))),
        isTrue,
      );
      expect(
        value.isFresh(
          value.checkedAt.subtract(const Duration(seconds: 5, microseconds: 1)),
        ),
        isFalse,
      );
      expect(value.isFresh(value.validUntil), isFalse);
      expect(value.rows.first.recordedAt.isBefore(value.checkedAt), isTrue);
    },
  );
}
