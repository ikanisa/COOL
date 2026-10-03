import 'dart:convert';
import 'dart:io';
import 'package:collect_app/admin/core/admin_receipt_operational_history_models.dart';
import 'package:collect_app/admin/core/admin_entity_audit.dart';
void main(List<String> args) {
 final observations = jsonDecode(File(args.single).readAsStringSync()) as List;
 var count = 0;
 for(final raw in observations) {
  final row=Map<String,dynamic>.from(raw as Map), response=Map<String,dynamic>.from(row['response'] as Map);
  if((row['probe'] as String).startsWith('detail')) {
   final run=AdminReceiptOperationalRun.parse(response,runId:response['run_id'] as String);
   if(run.id!=response['run_id'])throw StateError('run identity');
  } else {
   final cursor = row['cursor'] as Map?;
   final query=AdminEntityAuditQuery(kind:AdminAuditEntityKind.parse(response['entity_kind']),id:response['entity_id'] as String,limit:10,before:cursor==null?null:AdminEntityAuditCursor(recordedAt:DateTime.parse(cursor['recorded_at'] as String),eventId:cursor['event_id'] as String));
   final snapshot=AdminEntityAuditSnapshot.parse(response,query:query);
   if(snapshot.rows.length!=10)throw StateError('page size');
   if(row['expected_ids'] case final List ids) {
    if(jsonEncode(snapshot.rows.map((r)=>r.eventId).toList())!=jsonEncode(ids))throw StateError('exact page identities');
   }
  }
  count++;stdout.writeln('PASS actual nested-plan API DTO ${row['probe']}');
 }
 stdout.writeln('PASS $count actual cost-density API fixture checks');
}
