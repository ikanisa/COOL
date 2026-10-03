import 'dart:convert';

import 'package:collect_app/admin/core/admin_entity_audit.dart';
import 'package:collect_app/admin/core/admin_exception_history_v2_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

const historyExceptionId = '99510000-0000-4000-8000-000000000001';
const historyActorId = '99430000-0000-4000-8000-000000000001';
const historyEscalationId = '99510000-0000-4000-8000-000000000099';
const historyChecked = '2026-10-01T20:00:00.000000Z';
const historyActions = [
  'exception.acknowledge', 'exception.escalate',
  'exception.workflow.assign', 'exception.workflow.escalate', 'exception.workflow.resolve',
  'exception.escalation.queued', 'exception.escalation.delivered', 'exception.escalation.opened',
  'exception.escalation.obsolete', 'exception.escalation.recipient_unavailable',
];
Map<String, dynamic> historyCopy(Map<String, dynamic> row) => jsonDecode(jsonEncode(row)) as Map<String, dynamic>;
String historyWire(DateTime value) => value.toUtc().toIso8601String().replaceFirstMapped(RegExp(r'\.(\d{3})Z$'), (m) => '.${m[1]}000Z');
String historyEventId(String source, String recordId) => const Uuid().v5('c5a97546-80ab-5b57-a267-754aac043bd0', '$source:$recordId');
Map<String, dynamic> historyEvent(String action) {
  final index = historyActions.indexOf(action) + 1;
  final workflow = action.startsWith('exception.workflow.');
  final lifecycle = action.startsWith('exception.escalation.');
  final record = '99510000-0000-4000-8000-${index.toString().padLeft(12, '0')}';
  final source = lifecycle ? 'exception_escalation_event' : workflow ? 'exception_workflow_request' : 'exception_action';
  return {
    'event_id': historyEventId(source, record),
    'source': source,
    'source_record_id': record, 'action': action, 'recorded_at': '2026-10-01T19:00:00.000000Z',
    'actor_kind': lifecycle ? 'service' : 'operator', 'actor_id': lifecycle ? null : historyActorId,
    'request_id': lifecycle ? null : record, 'revision': 1, 'workflow_revision': workflow ? 1 : null,
    'escalation_id': lifecycle || action == 'exception.workflow.escalate' ? historyEscalationId : null,
    'reason_code': lifecycle ? 'operator_escalation' : action == 'exception.workflow.resolve' ? 'source_rechecked' : 'review_started',
    'origin': lifecycle ? 'captured_transition' : 'immutable_request',
    'assignee_id': action == 'exception.workflow.assign' ? historyActorId : null,
    'due_at': action == 'exception.workflow.assign' ? '2026-10-02T20:00:00.000000Z' : null,
  };
}
// Explicit presentation/contract double, not an observed SQL reply. New SQL
// observations are consumed separately once the backend packet is available.
Map<String, dynamic> historyFixture() => {
  'contract_version': 2, 'scope': 'rw_operator_entity_audit', 'entity_kind': 'exception',
  'entity_id': historyExceptionId, 'status': 'available', 'checked_at': historyChecked,
  'sample_valid_until': '2026-10-01T20:01:00.000000Z', 'limit': 20,
  'history_complete': false, 'financial_action': false, 'send_action': false,
  'rows': (historyActions.map(historyEvent).toList()..sort((a,b)=>(b['event_id'] as String).compareTo(a['event_id'] as String))), 'next_cursor': null,
};
AdminEntityAuditQuery historyQuery({String id = historyExceptionId, int limit = 20, AdminEntityAuditCursor? before}) =>
  AdminEntityAuditQuery(kind: AdminAuditEntityKind.exception, id: id, limit: limit, before: before);
Map<String, dynamic> historyWindow(Map<String, dynamic> raw, AdminEntityAuditQuery query) {
  final candidates = (raw['rows'] as List).where((item) {
    final row = item as Map;
    return query.before == null || AdminEntityAuditCursor(recordedAt: DateTime.parse(row['recorded_at'] as String), eventId: row['event_id'] as String).compareTo(query.before!) < 0;
  }).toList();
  final rows = candidates.take(query.limit).toList();
  return historyCopy(raw)..['entity_id'] = query.id..['limit'] = query.limit..['rows'] = rows
    ..['next_cursor'] = candidates.length > query.limit ? {'recorded_at': (rows.last as Map)['recorded_at'], 'event_id': (rows.last as Map)['event_id']} : null;
}
void main() {
  for (final action in historyActions) {
    test('$action retains exact finite evidence without current action authority', () {
      final raw = historyEvent(action), event = AdminExceptionHistoryEvent.parse(raw);
      expect(event.action, action); expect(event.actionLabel, isNotEmpty); expect(event.sourceRecordId, raw['source_record_id']);
      expect(event.cursor.eventId, raw['event_id']); expect(event.recordedAt, DateTime.parse(raw['recorded_at'] as String));
      expect(event.revision, 1); expect(event.reasonLabel, isNotNull);
      if (action == 'exception.workflow.assign') { expect(event.assigneeId, historyActorId); expect(event.dueAt, isNotNull); }
      if (action.startsWith('exception.escalation.')) { expect(event.requestId, isNull); expect(event.workflowRevision, isNull); expect(event.actorId, isNull); }
    });
  }
  test('joined source IDs may repeat across sources while stable event IDs stay distinct', () {
    final raw = historyFixture();
    final rows = raw['rows'] as List;
    final review = rows.singleWhere((e)=>(e as Map)['action']=='exception.acknowledge') as Map;
    final assignment = rows.singleWhere((e)=>(e as Map)['action']=='exception.workflow.assign') as Map;
    assignment['source_record_id'] = review['source_record_id'];
    assignment['request_id'] = review['request_id'];
    assignment['event_id'] = historyEventId(assignment['source'] as String, assignment['source_record_id'] as String);
    rows.sort((a,b)=>(b['event_id'] as String).compareTo(a['event_id'] as String));
    final snapshot = AdminExceptionHistorySnapshot.parse(raw, query: historyQuery());
    expect(snapshot.rows.map((e) => e.eventId).toSet(), hasLength(10));
    final reviewEvent=snapshot.rows.singleWhere((e)=>e.action=='exception.acknowledge');
    final assignmentEvent=snapshot.rows.singleWhere((e)=>e.action=='exception.workflow.assign');
    expect(reviewEvent.sourceRecordId,assignmentEvent.sourceRecordId);
    expect(reviewEvent.eventId,isNot(assignmentEvent.eventId));
  });
  test('wrong namespace cross-source record or invented stable event identity is refused', () {
    final row=historyEvent('exception.workflow.assign');
    for(final bad in [
      {...row,'event_id':const Uuid().v5('00000000-0000-0000-0000-000000000000','${row['source']}:${row['source_record_id']}')},
      {...row,'event_id':historyEventId('exception_action',row['source_record_id'] as String)},
      {...row,'event_id':historyEventId(row['source'] as String,historyEscalationId)},
    ]) { expect(()=>AdminExceptionHistoryEvent.parse(bad),throwsFormatException); }
  });
  test('unknown retained attribution and actual service transitions never invent a human actor', () {
    final retained = historyEvent('exception.escalation.delivered')..['origin'] = 'retained_source'..['actor_kind'] = 'unknown';
    expect(AdminExceptionHistoryEvent.parse(retained).actorKindLabel, 'Actor not recorded');
    for (final bad in [
      {...retained, 'actor_kind': 'service'}, {...retained, 'actor_id': historyActorId},
      {...historyEvent('exception.escalation.opened'), 'actor_kind': 'operator'},
      {...historyEvent('exception.escalation.delivered'), 'actor_id': historyActorId},
    ]) { expect(() => AdminExceptionHistoryEvent.parse(bad), throwsFormatException); }
    final operator = historyEvent('exception.escalation.opened')..['actor_kind'] = 'operator'..['actor_id'] = historyActorId;
    expect(AdminExceptionHistoryEvent.parse(operator).actorId, historyActorId);
  });
  test('historical assignment deadline remains dated even when read long after it', () {
    final raw = historyFixture()..['checked_at'] = '2026-10-10T20:00:00.000000Z'..['sample_valid_until'] = '2026-10-10T20:01:00.000000Z';
    final snapshot = AdminExceptionHistorySnapshot.parse(raw, query: historyQuery());
    final assigned = snapshot.rows.singleWhere((e) => e.action == 'exception.workflow.assign');
    expect(assigned.dueAt!.isBefore(snapshot.checkedAt), isTrue);
  });
  test('cross-phase actor request escalation assignment and reason claims fail closed', () {
    final bad = <Map<String, dynamic>>[
      {...historyEvent('exception.acknowledge'), 'request_id': historyEscalationId},
      {...historyEvent('exception.acknowledge'), 'workflow_revision': 1},
      {...historyEvent('exception.escalate'), 'escalation_id': historyEscalationId},
      {...historyEvent('exception.acknowledge'), 'reason_code': 'source_rechecked'},
      {...historyEvent('exception.workflow.assign'), 'assignee_id': null},
      {...historyEvent('exception.workflow.assign'), 'due_at': null},
      {...historyEvent('exception.workflow.resolve'), 'reason_code': 'review_started'},
      {...historyEvent('exception.workflow.escalate'), 'escalation_id': null},
      {...historyEvent('exception.workflow.resolve'), 'due_at': '2026-10-02T20:00:00.000000Z'},
      {...historyEvent('exception.escalation.opened'), 'request_id': historyEscalationId},
      {...historyEvent('exception.escalation.queued'), 'reason_code': 'review_started'},
      {...historyEvent('exception.escalation.obsolete'), 'origin': 'immutable_request'},
    ];
    for (final raw in bad) { expect(() => AdminExceptionHistoryEvent.parse(raw), throwsFormatException); }
  });
  test('query exception scope paired exactUTC6 and limits stay isolated from oldv1 kinds', () {
    final before = AdminEntityAuditCursor(recordedAt: DateTime.utc(2026, 10, 1, 19), eventId: historyEvent(historyActions.last)['event_id'] as String);
    final query = historyQuery(limit: 1, before: before);
    expect(adminExceptionHistoryParameters(query), {'p_exception_id': historyExceptionId, 'p_limit': 1, 'p_before_at': '2026-10-01T19:00:00.000000Z', 'p_before_event_id': before.eventId});
    for (final bad in [historyQuery(limit: 0), historyQuery(limit: 26), historyQuery(id: 'PRIVATE_UUID'),
      const AdminEntityAuditQuery(kind: AdminAuditEntityKind.receipt, id: historyExceptionId),
      historyQuery(before: AdminEntityAuditCursor(recordedAt: DateTime.utc(0), eventId: historyExceptionId))]) {
      expect(() => adminExceptionHistoryParameters(bad), throwsFormatException);
    }
  });
  test('paired audit pages preserve exact time ties immutable rows and last cursor', () {
    final raw = historyFixture(), query = historyQuery(limit: 3);
    final first = AdminExceptionHistorySnapshot.parse(historyWindow(raw, query), query: query);
    final nextQuery = historyQuery(limit: 3, before: first.nextCursor);
    final next = AdminExceptionHistorySnapshot.parse(historyWindow(raw, nextQuery), query: nextQuery);
    expect(first.rows, hasLength(3)); expect(next.rows, hasLength(3));
    expect({...first.rows.map((e) => e.eventId), ...next.rows.map((e) => e.eventId)}, hasLength(6));
    expect(() => first.rows.clear(), throwsUnsupportedError);
    final mismatched = historyWindow(raw, nextQuery)..['next_cursor'] = {'recorded_at': historyChecked, 'event_id': historyExceptionId};
    expect(() => AdminExceptionHistorySnapshot.parse(mismatched, query: nextQuery), throwsFormatException);
  });
  test('malformed private impossible complete financial or send claims cannot become history', () {
    final original = historyFixture();
    for (final patch in [
      {'contract_version': 1}, {'contract_version': 2.0}, {'scope': 'current_operator'}, {'entity_kind': 'receipt'}, {'entity_id': historyEscalationId},
      {'limit': 25}, {'history_complete': true}, {'financial_action': true}, {'send_action': true},
      {'history_complete': 'false'}, {'status': 'healthy'}, {'status': 'unavailable'}, {'authorization': 'PRIVATE_CANARY'},
      {'checked_at': '2026-02-30T00:00:00.000000Z'}, {'sample_valid_until': '2026-10-01T20:01:00.000001Z'},
    ]) { expect(() => AdminExceptionHistorySnapshot.parse({...original, ...patch}, query: historyQuery()), throwsFormatException); }
    for (final key in original.keys) { expect(() => AdminExceptionHistorySnapshot.parse(historyCopy(original)..remove(key), query: historyQuery()), throwsFormatException); }
  });
  test('unsupported and empty windows remain distinct incomplete evidence', () {
    final empty = historyFixture()..['rows'] = [];
    expect(AdminExceptionHistorySnapshot.parse(empty, query: historyQuery()).available, isTrue);
    empty['status'] = 'unavailable';
    expect(AdminExceptionHistorySnapshot.parse(empty, query: historyQuery()).available, isFalse);
  });
  test('event closed fields finite UUID UTC revisions and time order reject private rows', () {
    final event = historyEvent('exception.workflow.assign');
    for (final patch in [
      {'source': 'raw_sms'}, {'action': 'send_sms'}, {'origin': 'approved'}, {'actor_kind': 'admin'},
      {'actor_id': 'PRIVATE_ACTOR'}, {'event_id': 'UPPER_UUID'}, {'revision': 0}, {'revision': 1000000001},
      {'workflow_revision': 0}, {'due_at': '2026-02-30T00:00:00.000000Z'}, {'payload': 'PRIVATE_TEXT'},
    ]) { expect(() => AdminExceptionHistoryEvent.parse({...event, ...patch}), throwsFormatException); }
    for (final key in event.keys) { expect(() => AdminExceptionHistoryEvent.parse(historyCopy(event)..remove(key)), throwsFormatException); }
    final raw = historyFixture(); final rows = raw['rows'] as List;
    rows.add(historyCopy(rows.first as Map<String, dynamic>));
    expect(() => AdminExceptionHistorySnapshot.parse(raw, query: historyQuery()), throwsFormatException);
    final reversed = historyFixture()..['rows'] = (historyFixture()['rows'] as List).reversed.toList();
    expect(() => AdminExceptionHistorySnapshot.parse(reversed, query: historyQuery()), throwsFormatException);
  });
  test('history read expires at exactboundary without renewing original evidence', () {
    final value = AdminExceptionHistorySnapshot.parse(historyFixture(), query: historyQuery());
    expect(value.isFresh(value.checkedAt.subtract(const Duration(seconds: 5))), isTrue);
    expect(value.isFresh(value.checkedAt.subtract(const Duration(seconds: 5, microseconds: 1))), isFalse);
    expect(value.isFresh(value.validUntil), isFalse);
    expect(value.rows.first.recordedAt.isBefore(value.checkedAt), isTrue);
  });
}
