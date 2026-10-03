import 'dart:convert';
import 'package:collect_app/admin/core/admin_exception_escalation_inbox_v2_models.dart';
import 'package:collect_app/admin/core/admin_exception_workflow_models.dart';
import 'package:flutter_test/flutter_test.dart';

const inboxRecipientId = '99430000-0000-4000-8000-000000000001';
const inboxExceptionId = '99520000-0000-4000-8000-000000000001';
const inboxChecked = '2026-10-01T20:00:00.000000Z';
Map<String, dynamic> inboxCopy(Map<String, dynamic> row) => jsonDecode(jsonEncode(row)) as Map<String, dynamic>;
String inboxWire(DateTime at) => at.toUtc().toIso8601String().replaceFirstMapped(RegExp(r'\.(\d{3})Z$'), (m) => '.${m[1]}000Z');
Map<String, dynamic> inboxRow(int index) => {
  'escalation_id': '99520000-0000-4000-8000-${index.toString().padLeft(12,'0')}',
  'exception_id': inboxExceptionId, 'source_revision': 1,
  'reason_code': index.isEven ? 'deadline_exceeded' : 'operator_escalation',
  'source_active': true, 'current_source_revision': 1,
  'delivered_at': '2026-10-01T19:00:00.000000Z', 'read_at': null,
};
// Declared contract double; actual new SQL observations are added separately.
Map<String, dynamic> inboxFixture({String recipientId = inboxRecipientId, int count = 35}) => {
  'contract_version': 2, 'channel': 'admin_inbox', 'scope': 'current_operator',
  'recipient_id': recipientId, 'checked_at': inboxChecked,
  'sample_valid_until': '2026-10-01T20:01:00.000000Z', 'limit': 20,
  'rows': List.generate(count, (i) => inboxRow(count-i)), 'next_cursor': null,
};
Map<String, dynamic> inboxWindow(Map<String, dynamic> raw, AdminExceptionEscalationInboxQuery query) {
  final candidates = (raw['rows'] as List).where((value) {
    final row = value as Map;
    return query.before == null || AdminExceptionEscalationInboxCursor(deliveredAt: DateTime.parse(row['delivered_at'] as String), escalationId: row['escalation_id'] as String).compareTo(query.before!) < 0;
  }).toList();
  final rows = candidates.take(query.limit).toList();
  return inboxCopy(raw)..['limit'] = query.limit..['rows'] = rows
    ..['next_cursor'] = candidates.length > query.limit ? {'delivered_at': (rows.last as Map)['delivered_at'], 'escalation_id': (rows.last as Map)['escalation_id']} : null;
}
void main() {
  const query = AdminExceptionEscalationInboxQuery();
  test('strict current recipient pages beyond20 preserve delivery identity and ties', () {
    final raw = inboxFixture(), first = AdminExceptionEscalationInboxSnapshot.parse(inboxWindow(raw, query), query: query, recipientId: inboxRecipientId);
    final nextQuery = AdminExceptionEscalationInboxQuery(before: first.nextCursor);
    final next = AdminExceptionEscalationInboxSnapshot.parse(inboxWindow(raw, nextQuery), query: nextQuery, recipientId: inboxRecipientId);
    expect(first.rows, hasLength(20)); expect(next.rows, hasLength(15)); expect(next.nextCursor, isNull);
    expect({...first.rows.map((e)=>e.id), ...next.rows.map((e)=>e.id)}, hasLength(35));
    expect(first.rows.first, isA<AdminExceptionInboxDelivery>());
    expect(() => first.rows.clear(), throwsUnsupportedError);
    expect(nextQuery.parameters, {'p_limit': 20, 'p_before_delivered_at': '2026-10-01T19:00:00.000000Z', 'p_before_escalation_id': first.rows.last.id});
    expect(nextQuery, AdminExceptionEscalationInboxQuery(before: first.nextCursor));
    expect(nextQuery.hashCode, AdminExceptionEscalationInboxQuery(before: first.nextCursor).hashCode);
  });
  test('recipient channel scope and exact echoed limit cannot cross current operator', () {
    final raw = inboxWindow(inboxFixture(), query);
    for (final patch in [
      {'contract_version':1}, {'contract_version':2.0}, {'channel':'sms'}, {'scope':'platform_global'},
      {'recipient_id':inboxExceptionId}, {'limit':25}, {'limit':20.0}, {'email':'PRIVATE_CONTACT'},
      {'sample_valid_until':'2026-10-01T20:01:00.000001Z'},
    ]) { expect(() => AdminExceptionEscalationInboxSnapshot.parse({...raw,...patch},query:query,recipientId:inboxRecipientId),throwsFormatException); }
    for(final key in raw.keys) { expect(() => AdminExceptionEscalationInboxSnapshot.parse(inboxCopy(raw)..remove(key),query:query,recipientId:inboxRecipientId),throwsFormatException); }
  });
  test('inbox row immutable delivery and current source state remain independently truthful', () {
    final raw = inboxWindow(inboxFixture(count:1),query), row = (raw['rows'] as List).single as Map;
    row['source_active'] = false; row['current_source_revision'] = 2; row['read_at'] = '2026-10-01T19:30:00.000000Z';
    final value = AdminExceptionEscalationInboxSnapshot.parse(raw,query:query,recipientId:inboxRecipientId).rows.single;
    expect(value.sourceActive,isFalse); expect(value.sourceRevision,1); expect(value.currentSourceRevision,2); expect(value.readAt,isNotNull);
    for (final patch in [{'current_source_revision':0},{'read_at':'2026-10-01T18:59:59.999999Z'},{'read_at':'2026-10-01T20:00:00.000001Z'}, {'reason_code':'delivered_sms'},{'recipient_email':'PRIVATE'}]) {
      final bad=inboxCopy(raw); (bad['rows'] as List)[0]={...row,...patch};
      expect(() => AdminExceptionEscalationInboxSnapshot.parse(bad,query:query,recipientId:inboxRecipientId),throwsFormatException);
    }
  });
  test('duplicate reversed overlimit mismatched or shortpage cursors are refused', () {
    final raw=inboxWindow(inboxFixture(),query);
    final duplicate=inboxCopy(raw); ((duplicate['rows'] as List).last as Map)['escalation_id']=(duplicate['rows'] as List).first['escalation_id'];
    final reverse=inboxCopy(raw)..['rows']=(raw['rows'] as List).reversed.toList();
    final over=inboxCopy(raw); (over['rows'] as List).add(inboxRow(0));
    final cursor=inboxCopy(raw)..['next_cursor']={'delivered_at':inboxChecked,'escalation_id':inboxExceptionId};
    final short=inboxWindow(inboxFixture(count:1),query)..['next_cursor']={'delivered_at':'2026-10-01T19:00:00.000000Z','escalation_id':inboxRow(1)['escalation_id']};
    for(final bad in [duplicate,reverse,over,cursor,short]) { expect(() => AdminExceptionEscalationInboxSnapshot.parse(bad,query:query,recipientId:inboxRecipientId),throwsFormatException); }
  });
  test('query finite bounds invalid identity and calendar fail before dispatch parameters', () {
    for(final bad in [const AdminExceptionEscalationInboxQuery(limit:0),const AdminExceptionEscalationInboxQuery(limit:26),
      AdminExceptionEscalationInboxQuery(before:AdminExceptionEscalationInboxCursor(deliveredAt:DateTime.utc(0),escalationId:inboxExceptionId)),
      AdminExceptionEscalationInboxQuery(before:AdminExceptionEscalationInboxCursor(deliveredAt:DateTime.utc(2026),escalationId:'PRIVATE'))]) {
      expect(() => bad.parameters,throwsFormatException);
    }
    expect(() => AdminExceptionEscalationInboxCursor.parse({'delivered_at':'2026-02-30T00:00:00.000000Z','escalation_id':inboxExceptionId}),throwsFormatException);
    expect(() => query.parameters['p_limit']=25,throwsUnsupportedError);
  });
  test('strict60s read expiry does not grant previous rows a fresh actor session', () {
    final raw=inboxWindow(inboxFixture(),query),value=AdminExceptionEscalationInboxSnapshot.parse(raw,query:query,recipientId:inboxRecipientId);
    expect(value.isFresh(value.checkedAt.subtract(const Duration(microseconds:1))),isFalse);
    expect(value.isFresh(value.checkedAt),isTrue); expect(value.isFresh(value.validUntil),isFalse);
    expect(value.rows.first.readAt,isNull);
  });
  test('new current-authority opening receipt binds original delivered escalation only', () {
    final row=inboxRow(1), id=row['escalation_id'] as String;
    final raw={'contract_version':2,'escalation_id':id,'read_at':'2026-10-01T19:30:00.000000Z','source_resolved':false};
    final receipt=AdminExceptionEscalationReadReceipt.parse(raw,escalationId:id,deliveredAt:DateTime.parse(row['delivered_at'] as String));
    expect(receipt.escalationId,id); expect(receipt.readAt,DateTime.utc(2026,10,1,19,30));
    for(final patch in [{'contract_version':1},{'escalation_id':inboxExceptionId},{'read_at':'2026-10-01T18:59:59.999999Z'},{'source_resolved':true},{'payload':'PRIVATE'}]) {
      expect(() => AdminExceptionEscalationReadReceipt.parse({...raw,...patch},escalationId:id,deliveredAt:DateTime.parse(row['delivered_at'] as String)),throwsFormatException);
    }
  });
}
