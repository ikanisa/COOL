import 'dart:convert';
import 'dart:io';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_checkpoint.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_sdk.dart';

Map<String, dynamic> observed(String name) => Map<String, dynamic>.from(
  jsonDecode(File('test/fixtures/successor_$name.json').readAsStringSync())
      as Map,
);
Map<String, dynamic> clone(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
String stamp(DateTime at) =>
    '${at.toUtc().toIso8601String().split('.').first}.${at.millisecond.toString().padLeft(3, '0')}${at.microsecond.toString().padLeft(3, '0')}Z';
const request = '99780000-0000-4000-8000-000000080001';
const nextRequest = '99780000-0000-4000-8000-000000080002';

class MemoryStore implements AdminReceiptSuccessorCheckpointStore {
  final values = <String, String>{};
  bool failWrite = false, failClear = false;
  @override
  String? read(String owner) => values[owner];
  @override
  void write(String owner, String encoded) {
    if (failWrite) throw StateError('Synthetic quota');
    values[owner] = encoded;
  }

  @override
  void clear(String owner) {
    if (failClear) throw StateError('Synthetic clear');
    values.remove(owner);
  }
}

class SuccessorFixture {
  SuccessorFixture() {
    now = DateTime.parse(observed('retry_preview')['checked_at'] as String);
  }
  late DateTime now;
  AdminSessionKey? session = (
    userId: '99780000-0000-4000-8000-000000000001',
    sessionId: '99780000-0000-4000-8000-000000010001',
  );
  bool current = true, manage = true, closed = true, timeout = false;
  String outcome = 'not_recorded';
  final calls = <({String name, Map<String, dynamic> params})>[];
  Map<String, dynamic>? recorded;
  final approvals = <Map<String, dynamic>>[];
  String? outboxOverride, sourceOverride;
  String get outbox =>
      outboxOverride ?? observed('retry_preview')['outbox_id'] as String;
  String get source =>
      sourceOverride ??
      observed('retry_preview')['source_snapshot_id'] as String;
  String get owner => successorOwnerDigest(session!.userId);
  AdminReceiptSuccessorSdk get sdk => AdminReceiptSuccessorSdk(
    rpc: rpc,
    isCurrent: () => current,
    currentSession: () => session,
    canManage: () => manage,
    now: () => now,
  );
  Map<String, dynamic> closureRow() {
    final r = observed('closure_inspection');
    r['outbox_id'] = outbox;
    r['checked_at'] = stamp(now);
    r['sample_valid_until'] = stamp(now.add(const Duration(seconds: 60)));
    r['can_close'] = !closed;
    r['reason_code'] = closed ? 'already_closed' : 'unarmed_eligible';
    r['root_revision'] = closed ? 2 : 1;
    r['lineage_revision'] = closed ? 2 : 1;
    return r;
  }

  Map<String, dynamic> previewRow() {
    final r = observed('retry_preview');
    r['outbox_id'] = outbox;
    r['source_snapshot_id'] = source;
    (r['preview'] as Map)['root_outbox_id'] = outbox;
    (r['preview'] as Map)['source_snapshot_id'] = source;
    r['checked_at'] = stamp(now);
    r['sample_valid_until'] = stamp(now.add(const Duration(seconds: 60)));
    if (!closed) {
      r['reason_code'] = 'irreversible_closure_required';
      r['can_approve'] = false;
      r['preview'] = null;
      r['preview_sha256'] = null;
    }
    return r;
  }

  Map<String, dynamic> receipt(String name, Map<String, dynamic> p) {
    final type = name.contains('close_unarmed')
        ? 'closure_receipt'
        : name.contains('approve_receipt')
        ? 'approval_receipt'
        : 'revocation_receipt';
    final r = observed(type);
    r['request_id'] = p['p_request_id'];
    r['outbox_id'] = outbox;
    r['recorded_at'] = stamp(now);
    r['expected_lineage_revision'] = p['p_expected_lineage_revision'];
    r['lineage_revision'] = (p['p_expected_lineage_revision'] as int) + 1;
    if (type != 'revocation_receipt') {
      r['expected_root_revision'] = p['p_expected_root_revision'];
    }
    if (type == 'closure_receipt') {
      r['root_revision'] = (p['p_expected_root_revision'] as int) + 1;
    }
    if (type == 'approval_receipt') {
      r['preview_sha256'] = p['p_preview_sha256'];
      r['source_snapshot_id'] = p['p_source_snapshot_id'];
      r['expires_at'] = stamp(now.add(const Duration(minutes: 15)));
    }
    if (type == 'revocation_receipt') {
      r['approval_id'] = p['p_approval_id'];
    }
    return r;
  }

  Future<Object?> rpc(String name, Map<String, dynamic> params) async {
    calls.add((name: name, params: params));
    if (name == 'admin_inspect_unarmed_receipt_closure_v1') return closureRow();
    if (name == 'admin_inspect_receipt_successor_v1') return previewRow();
    if (name == 'admin_list_receipt_successors_v1') {
      final r = Map<String, dynamic>.from(
        observed('lineage_pages')['first'] as Map,
      );
      r['outbox_id'] = outbox;
      r['items'] = approvals;
      r['has_more'] = false;
      r['next_after'] = null;
      return r;
    }
    if (name == 'admin_get_receipt_successor_request_v1') {
      return {
        'contract_version': 1,
        'scope': 'rw_receipt_successors',
        'request_id': params['p_request_id'],
        'status': outcome,
        'receipt': outcome == 'recorded' ? recorded : null,
      };
    }
    recorded = receipt(name, params);
    if (timeout) throw StateError('Synthetic lost HTTP response');
    if (name.contains('close_unarmed')) closed = true;
    outcome = 'recorded';
    return recorded;
  }
}
