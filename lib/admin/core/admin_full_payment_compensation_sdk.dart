import 'admin_auth_guard.dart';
import 'admin_full_payment_compensation_models.dart';

abstract interface class AdminFullPaymentCompensationApi {
  Future<AdminFullPaymentCompensationInspection> inspect(String paymentId);
  Future<AdminFullPaymentCompensationResult> record(
    AdminFullPaymentCompensationIntent original,
  );
  Future<AdminFullPaymentCompensationLookup> recover(
    AdminFullPaymentCompensationIntent original,
  );
}

class AdminFullPaymentCompensationSdk
    implements AdminFullPaymentCompensationApi {
  const AdminFullPaymentCompensationSdk({
    required this.rpc,
    required this.actorId,
    required this.sessionId,
    required this.isCurrent,
    required this.canRecord,
    required this.now,
  });
  final Future<Object?> Function(String, Map<String, dynamic>) rpc;
  final String actorId, sessionId;
  final bool Function() isCurrent, canRecord;
  final DateTime Function() now;
  void _current() {
    if (!isCurrent()) throw const AdminSessionChanged();
  }

  void _original(AdminFullPaymentCompensationIntent original) {
    _current();
    if (original.actorId != actorId || original.sessionId != sessionId) {
      compensationInvalid();
    }
  }

  Future<Object?> _call(String name, Map<String, dynamic> params) async {
    _current();
    try {
      final row = await rpc(
        name,
        Map.unmodifiable(params),
      ).timeout(const Duration(seconds: 15));
      _current();
      return row;
    } catch (_) {
      _current();
      rethrow;
    }
  }

  @override
  Future<AdminFullPaymentCompensationInspection> inspect(
    String paymentId,
  ) async {
    compensationUuid(paymentId);
    final row = AdminFullPaymentCompensationInspection.parse(
      await _call('admin_inspect_full_payment_compensation_v1', {
        'p_payment_id': paymentId,
      }),
    );
    if (row.paymentId != paymentId || !row.fresh(now())) compensationInvalid();
    return row;
  }

  @override
  Future<AdminFullPaymentCompensationResult> record(
    AdminFullPaymentCompensationIntent original,
  ) async {
    _original(original);
    if (!canRecord()) throw const AdminSessionChanged();
    if (!original.inspection.fresh(now())) compensationInvalid();
    return AdminFullPaymentCompensationResult.parse(
      await _call(
        'admin_record_full_payment_compensation_v1',
        original.parameters,
      ),
      original,
    );
  }

  @override
  Future<AdminFullPaymentCompensationLookup> recover(
    AdminFullPaymentCompensationIntent original,
  ) async {
    _current();
    if (original.actorId != actorId) compensationInvalid();
    final result = AdminFullPaymentCompensationLookup.parse(
      await _call('admin_get_full_payment_compensation_request_v1', {
        'p_request_id': original.requestId,
      }),
      original,
    );
    if (!result.fresh(now())) compensationInvalid();
    return result;
  }
}
