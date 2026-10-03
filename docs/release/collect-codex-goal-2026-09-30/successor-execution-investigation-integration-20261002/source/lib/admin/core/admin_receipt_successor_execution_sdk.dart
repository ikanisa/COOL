import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_auth_guard.dart';
import 'admin_receipt_cancel_models.dart';
import 'admin_receipt_successor_execution_models.dart';

/// Authoritative denial uses the same Admin session/Auth/PostgREST error types
/// as the shared protected readers. A cached local identity is not authority.
bool executionAccessDenied(Object error) =>
    error is AdminSessionChanged ||
    error is AuthException ||
    error is PostgrestException &&
        const {
          '42501',
          '28000',
          'PGRST301',
          'PGRST302',
          'PGRST303',
        }.contains(error.code);

class AdminReceiptSuccessorExecutionDenied implements Exception {
  const AdminReceiptSuccessorExecutionDenied();
}

abstract interface class AdminReceiptSuccessorExecutionApi {
  Future<AdminReceiptSuccessorExecutionSnapshot> inspect(
    String approval,
    String root,
  );
  Future<AdminReceiptSuccessorObservationPage> observations(
    AdminReceiptSuccessorExecutionSnapshot snapshot, {
    int? after,
    int limit = 20,
  });
}

class AdminReceiptSuccessorExecutionSdk
    implements AdminReceiptSuccessorExecutionApi {
  const AdminReceiptSuccessorExecutionSdk({
    required this.rpc,
    required this.isCurrent,
    required this.now,
  });
  final Future<Object?> Function(String, Map<String, dynamic>) rpc;
  final bool Function() isCurrent;
  final DateTime Function() now;
  void _current() {
    if (!isCurrent()) throw const AdminSessionChanged();
  }

  Future<Object?> _read(String name, Map<String, dynamic> parameters) async {
    _current();
    try {
      final result = await rpc(
        name,
        Map.unmodifiable(parameters),
      ).timeout(const Duration(seconds: 15));
      _current();
      return result;
    } on PostgrestException catch (error) {
      _current();
      if (executionAccessDenied(error)) {
        throw const AdminReceiptSuccessorExecutionDenied();
      }
      rethrow;
    } catch (error) {
      _current();
      if (executionAccessDenied(error)) {
        throw const AdminReceiptSuccessorExecutionDenied();
      }
      rethrow;
    }
  }

  @override
  Future<AdminReceiptSuccessorExecutionSnapshot> inspect(
    String approval,
    String root,
  ) async {
    cancelUuid(approval);
    cancelUuid(root);
    final value = AdminReceiptSuccessorExecutionSnapshot.parse(
      await _read('admin_get_receipt_successor_execution_v4', {
        'p_approval_id': approval,
      }),
      approval,
      root,
    );
    if (!value.fresh(now())) executionInvalid();
    return value;
  }

  @override
  Future<AdminReceiptSuccessorObservationPage> observations(
    AdminReceiptSuccessorExecutionSnapshot snapshot, {
    int? after,
    int limit = 20,
  }) async {
    if (!snapshot.available ||
        limit < 1 ||
        limit > 50 ||
        after != null && cancelRevision(after) > snapshot.cutoff!) {
      executionInvalid();
    }
    final value = AdminReceiptSuccessorObservationPage.parse(
      await _read('admin_list_receipt_successor_observations_v4', {
        'p_approval_id': snapshot.approvalId,
        'p_cutoff_revision': snapshot.cutoff,
        'p_after_revision': after,
        'p_limit': limit,
      }),
      snapshot,
      after,
      limit,
    );
    if (!value.fresh(now())) executionInvalid();
    return value;
  }
}
