import 'admin_auth_guard.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_receipt_cancel_models.dart';
import 'admin_receipt_successor_models.dart';
import 'admin_receipt_successor_execution_sdk.dart';

typedef AdminReceiptSuccessorRpc =
    Future<Object?> Function(String, Map<String, dynamic>);

class AdminReceiptSuccessorRejected implements Exception {
  const AdminReceiptSuccessorRejected(this.code);
  final String code;
}

class AdminReceiptSuccessorIntent {
  AdminReceiptSuccessorIntent._(
    this.binding,
    this.session,
    this.rpcName,
    this.parameters,
    this.validUntil,
  );
  final AdminReceiptSuccessorBinding binding;
  final AdminSessionKey session;
  final String rpcName;
  final Map<String, dynamic> parameters;
  final DateTime validUntil;
}

abstract interface class AdminReceiptSuccessorApi {
  Future<AdminReceiptClosureInspection> closure(String outbox);
  Future<AdminReceiptSuccessorInspection> inspect(String outbox, String source);
  Future<AdminReceiptSuccessorHistory> history(
    String outbox, {
    int? after,
    int limit = 20,
  });
  AdminReceiptSuccessorIntent prepareClosure(
    String request,
    AdminReceiptClosureInspection inspection,
    String reason,
  );
  AdminReceiptSuccessorIntent prepareApproval(
    String request,
    AdminReceiptSuccessorInspection inspection,
    String reason,
  );
  AdminReceiptSuccessorIntent prepareRevocation(
    String request,
    AdminReceiptSuccessorApproval approval,
    String reason,
  );
  Future<AdminReceiptSuccessorReceipt> submit(
    AdminReceiptSuccessorIntent intent,
  );
  Future<AdminReceiptSuccessorLookup> lookup(
    AdminReceiptSuccessorBinding original,
  );
}

/// A repeated retry first verifies the selected approval's stopped execution.
/// The preceding job identifier is obtained from the validated backend route.
abstract interface class AdminReceiptSuccessorRetryApi {
  Future<AdminReceiptSuccessorInspection> inspectRetry(
    String outbox,
    String source,
    String predecessorApproval,
  );
}

/// Production wiring must call AdminRepository.rpcMap(automaticRetry:false),
/// capture its current auth scope, and invalidate this instance on role/session
/// change. Every await rechecks that captured scope, including error responses.
class AdminReceiptSuccessorSdk
    implements AdminReceiptSuccessorApi, AdminReceiptSuccessorRetryApi {
  const AdminReceiptSuccessorSdk({
    required this.rpc,
    required this.isCurrent,
    required this.currentSession,
    required this.canManage,
    required this.now,
  });
  final AdminReceiptSuccessorRpc rpc;
  final bool Function() isCurrent, canManage;
  final AdminSessionKey? Function() currentSession;
  final DateTime Function() now;
  void _current() {
    if (!isCurrent() || currentSession() == null) {
      throw const AdminSessionChanged();
    }
  }

  AdminSessionKey _manage() {
    _current();
    if (!canManage()) {
      throw StateError('Current receipt management access is required.');
    }
    return currentSession()!;
  }

  String _reason(String reason) {
    final clean = reason.trim();
    if (clean.length < 8 || clean.length > 500) successorInvalid();
    return clean;
  }

  Future<Object?> _call(String name, Map<String, dynamic> params) async {
    _current();
    try {
      final raw = await rpc(
        name,
        Map.unmodifiable(params),
      ).timeout(const Duration(seconds: 15));
      _current();
      return raw;
    } on PostgrestException catch (error) {
      _current();
      if ({'22023', '42501', '55000', '55P03', '40001'}.contains(error.code)) {
        throw AdminReceiptSuccessorRejected(error.code!);
      }
      rethrow;
    } catch (_) {
      _current();
      rethrow;
    }
  }

  @override
  Future<AdminReceiptClosureInspection> closure(String outbox) async {
    cancelUuid(outbox);
    final raw = await _call('admin_inspect_unarmed_receipt_closure_v1', {
      'p_outbox_id': outbox,
    });
    final value = AdminReceiptClosureInspection.parse(raw, outbox);
    if (!value.fresh(now())) successorInvalid();
    return value;
  }

  @override
  Future<AdminReceiptSuccessorInspection> inspect(
    String outbox,
    String source,
  ) async {
    cancelUuid(outbox);
    cancelUuid(source);
    final raw = await _call('admin_inspect_receipt_successor_v1', {
      'p_outbox_id': outbox,
      'p_action': 'retry_uninvoked',
      'p_source_snapshot_id': source,
    });
    final value = AdminReceiptSuccessorInspection.parse(raw, outbox, source);
    if (!value.fresh(now())) successorInvalid();
    return value;
  }

  @override
  Future<AdminReceiptSuccessorInspection> inspectRetry(
    String outbox,
    String source,
    String predecessorApproval,
  ) async {
    _current();
    final session = currentSession();
    cancelUuid(outbox);
    cancelUuid(source);
    cancelUuid(predecessorApproval);
    final execution = await AdminReceiptSuccessorExecutionSdk(
      rpc: _call,
      isCurrent: () => isCurrent() && currentSession() == session,
      now: now,
      executionVersion: 5,
    ).inspect(predecessorApproval, outbox);
    if (!execution.available || execution.state != 'unarmed_revoked') {
      throw const AdminReceiptSuccessorRejected('RETIRED_PREDECESSOR_REQUIRED');
    }
    final route = execution.execution!['route'] as Map<String, dynamic>;
    final predecessor = cancelUuid(route['dispatch_job_id']);
    final raw = await _call('admin_inspect_receipt_successor_retry_v2', {
      'p_outbox_id': outbox,
      'p_predecessor_job_id': predecessor,
      'p_source_snapshot_id': source,
    });
    if (currentSession() != session) throw const AdminSessionChanged();
    final value = AdminReceiptSuccessorInspection.parse(
      raw,
      outbox,
      source,
      predecessorJobId: predecessor,
    );
    if (!value.fresh(now()) ||
        !execution.fresh(now()) ||
        value.checkedAt.isBefore(execution.checkedAt)) {
      successorInvalid();
    }
    return value;
  }

  @override
  Future<AdminReceiptSuccessorHistory> history(
    String outbox, {
    int? after,
    int limit = 20,
  }) async {
    cancelUuid(outbox);
    if (limit < 1 || limit > 50) successorInvalid();
    if (after != null) cancelRevision(after);
    final raw = await _call('admin_list_receipt_successors_v1', {
      'p_outbox_id': outbox,
      'p_after': after,
      'p_limit': limit,
    });
    return AdminReceiptSuccessorHistory.parse(
      raw,
      outbox,
      after: after,
      limit: limit,
    );
  }

  @override
  AdminReceiptSuccessorIntent prepareClosure(
    String request,
    AdminReceiptClosureInspection inspection,
    String reason,
  ) {
    final session = _manage();
    cancelUuid(request);
    reason = _reason(reason);
    if (!inspection.canClose || !inspection.fresh(now())) successorInvalid();
    final expected = <String, Object?>{
      'outbox_id': inspection.outboxId,
      'expected_root_revision': inspection.rootRevision,
      'expected_lineage_revision': inspection.lineageRevision,
    };
    return AdminReceiptSuccessorIntent._(
      AdminReceiptSuccessorBinding(
        requestId: request,
        action: 'close_unarmed',
        expected: expected,
      ),
      session,
      'admin_close_unarmed_receipt_v1',
      Map.unmodifiable({
        'p_request_id': request,
        'p_outbox_id': inspection.outboxId,
        'p_expected_root_revision': inspection.rootRevision,
        'p_expected_lineage_revision': inspection.lineageRevision,
        'p_reason_code': 'definitely_not_invoked',
        'p_reason': reason,
      }),
      inspection.validUntil,
    );
  }

  @override
  AdminReceiptSuccessorIntent prepareApproval(
    String request,
    AdminReceiptSuccessorInspection inspection,
    String reason,
  ) {
    final session = _manage();
    cancelUuid(request);
    reason = _reason(reason);
    if (!inspection.canApprove ||
        !inspection.fresh(now()) ||
        inspection.preview == null) {
      successorInvalid();
    }
    final p = inspection.preview!;
    final expected = <String, Object?>{
      'outbox_id': p.outboxId,
      'source_snapshot_id': p.sourceId,
      'expected_root_revision': p.rootRevision,
      'expected_lineage_revision': p.lineageRevision,
      'preview_sha256': inspection.previewHash,
      if (inspection.isRetiredRetry) ...{
        'predecessor_job_id': inspection.predecessorJobId,
        'predecessor_proof_sha256': inspection.predecessorProofHash,
      },
    };
    return AdminReceiptSuccessorIntent._(
      AdminReceiptSuccessorBinding(
        requestId: request,
        action: 'approve_successor',
        expected: expected,
      ),
      session,
      inspection.isRetiredRetry
          ? 'admin_approve_receipt_successor_retry_v2'
          : 'admin_approve_receipt_successor_v1',
      Map.unmodifiable({
        'p_request_id': request,
        'p_outbox_id': p.outboxId,
        if (!inspection.isRetiredRetry) 'p_action': 'retry_uninvoked',
        if (inspection.isRetiredRetry) ...{
          'p_predecessor_job_id': inspection.predecessorJobId,
          'p_predecessor_proof_sha256': inspection.predecessorProofHash,
        },
        'p_source_snapshot_id': p.sourceId,
        'p_expected_root_revision': p.rootRevision,
        'p_expected_lineage_revision': p.lineageRevision,
        'p_preview_sha256': inspection.previewHash,
        'p_sample_valid_until': inspection.row['sample_valid_until'],
        if (!inspection.isRetiredRetry)
          'p_reason_code': 'definitely_not_invoked',
        'p_reason': reason,
      }),
      inspection.validUntil,
    );
  }

  @override
  AdminReceiptSuccessorIntent prepareRevocation(
    String request,
    AdminReceiptSuccessorApproval approval,
    String reason,
  ) {
    final session = _manage();
    cancelUuid(request);
    reason = _reason(reason);
    if (approval.status == 'revoked') successorInvalid();
    final expected = <String, Object?>{
      'outbox_id': approval.preview.outboxId,
      'approval_id': approval.id,
      'expected_lineage_revision': approval.lineageRevision,
    };
    return AdminReceiptSuccessorIntent._(
      AdminReceiptSuccessorBinding(
        requestId: request,
        action: 'revoke_successor',
        expected: expected,
      ),
      session,
      'admin_revoke_receipt_successor_v1',
      Map.unmodifiable({
        'p_request_id': request,
        'p_approval_id': approval.id,
        'p_expected_lineage_revision': approval.lineageRevision,
        'p_reason': reason,
      }),
      now().toUtc().add(const Duration(seconds: 60)),
    );
  }

  @override
  Future<AdminReceiptSuccessorReceipt> submit(
    AdminReceiptSuccessorIntent intent,
  ) async {
    if (_manage() != intent.session ||
        !now().toUtc().isBefore(intent.validUntil)) {
      throw const AdminSessionChanged();
    }
    final raw = await _call(intent.rpcName, intent.parameters);
    if (_manage() != intent.session) throw const AdminSessionChanged();
    final receipt = AdminReceiptSuccessorReceipt.parse(raw, intent.binding);
    if (receipt.recordedAt.isAfter(
      now().toUtc().add(const Duration(seconds: 5)),
    )) {
      successorInvalid();
    }
    return receipt;
  }

  @override
  Future<AdminReceiptSuccessorLookup> lookup(
    AdminReceiptSuccessorBinding original,
  ) async {
    final raw = await _call(
      original.isRetiredRetry
          ? 'admin_get_receipt_successor_retry_request_v2'
          : 'admin_get_receipt_successor_request_v1',
      {'p_request_id': original.requestId},
    );
    return AdminReceiptSuccessorLookup.parse(raw, original);
  }
}
