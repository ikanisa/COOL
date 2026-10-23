// Actual 0700 SQL producer bytes are retained separately and hashed. This
// caller harness adapts the v5 summary sample/cutoff to precede the third
// inspection, assembles legacy history over those exact candidate/retirement
// fields, and binds synthetic HTTP request IDs. It does not execute SQL/Auth.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_checkpoint.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_models.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_sdk.dart';
import 'successor_fixture.dart';

Map<String, dynamic> retryObserved(String name) => Map<String, dynamic>.from(
  jsonDecode(
        File(
          'test/fixtures/receipt_successor_retry_v2/$name.json',
        ).readAsStringSync(),
      )
      as Map,
);

AdminReceiptSuccessorBinding retryBinding(Map<String, dynamic> receipt) =>
    AdminReceiptSuccessorBinding(
      requestId: receipt['request_id'] as String,
      action: 'approve_successor',
      expected: {
        for (final key in [
          'outbox_id',
          'source_snapshot_id',
          'expected_root_revision',
          'expected_lineage_revision',
          'preview_sha256',
          'predecessor_job_id',
          'predecessor_proof_sha256',
        ])
          key: receipt[key],
      },
    );

class RetryFixture {
  RetryFixture() {
    now = DateTime.parse(
      producerSummary['checked_at'] as String,
    ).add(const Duration(milliseconds: 10));
    legacy.now = now;
    legacy.outboxOverride = root;
    legacy.sourceOverride = source;
  }
  final legacy = SuccessorFixture();
  final calls = <({String name, Map<String, dynamic> params})>[];
  final inspection = retryObserved('third-inspection-v2');
  final producerSummary = retryObserved('second-revoked-investigation-v5');
  late DateTime now;
  Map<String, dynamic>? executionOverride, inspectionOverride, recorded;
  Object? executionError, inspectionError, lookupError;
  Completer<void>? executionEntered, executionRelease;
  Completer<void>? inspectionEntered, inspectionRelease;
  bool lostResponse = false;
  String outcome = 'recorded';
  String get root => inspection['outbox_id'] as String;
  String get source => inspection['source_snapshot_id'] as String;
  String get approval => producerSummary['approval_id'] as String;
  String get predecessor => inspection['predecessor_job_id'] as String;
  AdminSessionKey? get session => legacy.session;
  set session(AdminSessionKey? value) => legacy.session = value;
  bool get current => legacy.current;
  set current(bool value) => legacy.current = value;
  bool get manage => legacy.manage;
  set manage(bool value) => legacy.manage = value;
  String get owner => successorOwnerDigest(session!.userId);
  AdminReceiptSuccessorSdk get sdk => AdminReceiptSuccessorSdk(
    rpc: rpc,
    isCurrent: () => current,
    currentSession: () => session,
    canManage: () => manage,
    now: () => now,
  );

  Map<String, dynamic> summary() {
    if (executionOverride != null) return clone(executionOverride!);
    final result = clone(producerSummary);
    final checked = DateTime.parse(
      inspection['checked_at'] as String,
    ).subtract(const Duration(microseconds: 100));
    result['checked_at'] = stamp(checked);
    result['sample_valid_until'] = stamp(
      checked.add(const Duration(seconds: 60)),
    );
    result['cutoff_revision'] = 8;
    return result;
  }

  Map<String, dynamic> history() {
    final page = Map<String, dynamic>.from(
      observed('lineage_pages')['first'] as Map,
    );
    final receipt = retryObserved('retry-approval-v2');
    final preview = retryObserved('retry-inspection-v2')['preview'];
    final execution = producerSummary['execution'] as Map;
    final grant = (execution['execution_events'] as List).first as Map;
    final retirement = execution['revocation'] as Map;
    return {
      ...page,
      'outbox_id': root,
      'items': [
        {
          'approval_id': approval,
          'outbox_id': root,
          'sequence': 2,
          'action': 'retry_uninvoked',
          'status': 'revoked',
          'preview': preview,
          'preview_sha256': receipt['preview_sha256'],
          'reason_code': 'definitely_not_invoked',
          'reason': 'Synthetic joined stopped retry history',
          'recorded_at': receipt['recorded_at'],
          'expires_at': receipt['expires_at'],
          'lineage_revision': 8,
          'events': [
            {
              'event_id': grant['approved_event_id'],
              'revision': 1,
              'event_kind': 'approved',
              'request_id': receipt['request_id'],
              'lineage_revision': receipt['lineage_revision'],
              'reason': 'Synthetic joined original review event',
              'recorded_at': receipt['recorded_at'],
            },
            {
              'event_id': retirement['approval_event_id'],
              'revision': 2,
              'event_kind': 'revoked',
              'request_id': nextRequest,
              'lineage_revision': 8,
              'reason': 'Synthetic joined permanent retirement event',
              'recorded_at': retirement['recorded_at'],
            },
          ],
        },
      ],
      'has_more': false,
      'next_after': null,
    };
  }

  Future<Object?> rpc(String name, Map<String, dynamic> parameters) async {
    calls.add((name: name, params: parameters));
    if (name == 'admin_get_receipt_successor_execution_v5') {
      executionEntered?.complete();
      await executionRelease?.future;
      if (executionError != null) throw executionError!;
      return summary();
    }
    if (name == 'admin_inspect_receipt_successor_retry_v2') {
      inspectionEntered?.complete();
      await inspectionRelease?.future;
      if (inspectionError != null) throw inspectionError!;
      return clone(inspectionOverride ?? inspection);
    }
    if (name == 'admin_approve_receipt_successor_retry_v2') {
      recorded = retryObserved('third-approval-v2');
      recorded!['request_id'] = parameters['p_request_id'];
      if (lostResponse) {
        throw TimeoutException('Synthetic response lost after commit');
      }
      return clone(recorded!);
    }
    if (name == 'admin_get_receipt_successor_retry_request_v2') {
      if (lookupError != null) throw lookupError!;
      return {
        'contract_version': 2,
        'scope': 'rw_receipt_successor_retries',
        'request_id': parameters['p_request_id'],
        'status': outcome,
        'result': outcome == 'recorded' ? recorded : null,
        'financial_action': false,
        'send_action': false,
        'primary_receipt_retained': true,
        'carrier_proof': false,
        'delivery_proven': false,
      };
    }
    if (name == 'admin_inspect_unarmed_receipt_closure_v1') {
      return legacy.closureRow();
    }
    if (name == 'admin_inspect_receipt_successor_v1') {
      return {
        for (final entry in inspection.entries)
          if (!{
            'predecessor_job_id',
            'predecessor_proof_sha256',
            'retired_jobs',
          }.contains(entry.key))
            entry.key: entry.value,
        'contract_version': 1,
        'scope': 'rw_receipt_successors',
        'can_approve': false,
        'reason_code': 'approval_pending',
        'preview_sha256': null,
      };
    }
    if (name == 'admin_list_receipt_successors_v1') return history();
    if (name == 'admin_list_receipt_successor_observations_v5') {
      final snapshot = summary();
      return {
        'contract_version': 5,
        'scope': 'rw_receipt_successor_observations',
        'approval_id': approval,
        'primary_receipt_id': root,
        'cutoff_revision': snapshot['cutoff_revision'],
        'after_revision': parameters['p_after_revision'],
        'limit': parameters['p_limit'],
        'checked_at': snapshot['checked_at'],
        'sample_valid_until': snapshot['sample_valid_until'],
        'status': 'available',
        'items': [],
        'next_after_revision': null,
        'financial_action': false,
        'send_action': false,
        'carrier_proof': false,
        'delivery_proven': false,
      };
    }
    throw StateError('Unallowlisted synthetic successor RPC: $name');
  }
}
