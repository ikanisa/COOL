import 'admin_auth_guard.dart';
import 'admin_receipt_notice_content_models.dart';
import 'admin_receipt_notice_dispatch_models.dart';

abstract interface class AdminReceiptNoticeDispatchApi {
  Future<AdminReceiptNoticeDispatchConfiguration> configuration();
  Future<AdminReceiptNoticeDispatchInspection> inspect(
    AdminReceiptNoticePreparedReference reference,
  );
  Future<AdminReceiptNoticeDispatchRequest> record(
    AdminReceiptNoticeDispatchIntent intent,
  );
  Future<AdminReceiptNoticeDispatchRequest> recover(
    AdminReceiptNoticeDispatchIntent intent,
  );
}

class AdminReceiptNoticeDispatchSdk implements AdminReceiptNoticeDispatchApi {
  const AdminReceiptNoticeDispatchSdk({
    required this.rpc,
    required this.actorId,
    required this.sessionId,
    required this.isCurrent,
    required this.canManage,
    required this.now,
  });
  final Future<Object?> Function(String, Map<String, dynamic>) rpc;
  final String actorId, sessionId;
  final bool Function() isCurrent, canManage;
  final DateTime Function() now;
  void _current() {
    if (!isCurrent()) throw const AdminSessionChanged();
  }

  void _owner(String actor, String session) {
    _current();
    if (actor != actorId || session != sessionId) noticeInvalid();
  }

  Future<Object?> _call(String name, Map<String, dynamic> parameters) async {
    _current();
    try {
      final result = await rpc(
        name,
        Map.unmodifiable(parameters),
      ).timeout(const Duration(seconds: 15));
      _current();
      return result;
    } catch (_) {
      _current();
      rethrow;
    }
  }

  @override
  Future<AdminReceiptNoticeDispatchConfiguration> configuration() async {
    final row = AdminReceiptNoticeDispatchConfiguration.parse(
      await _call('admin_inspect_receipt_notice_dispatch_configuration_v1', {}),
    );
    if (!row.fresh(now())) noticeInvalid();
    return row;
  }

  @override
  Future<AdminReceiptNoticeDispatchInspection> inspect(
    AdminReceiptNoticePreparedReference reference,
  ) async {
    _owner(reference.actorId, reference.sessionId);
    final row = AdminReceiptNoticeDispatchInspection.parse(
      await _call('admin_inspect_receipt_notice_dispatch_v1', {
        'p_prepared_review_id': reference.preparedReviewId,
      }),
      reference,
    );
    if (!row.fresh(now())) noticeInvalid();
    return row;
  }

  @override
  Future<AdminReceiptNoticeDispatchRequest> record(
    AdminReceiptNoticeDispatchIntent intent,
  ) async {
    _owner(intent.actorId, intent.sessionId);
    if (!canManage()) throw const AdminSessionChanged();
    if (!intent.fresh(now())) noticeInvalid();
    final name = switch (intent.action) {
      AdminReceiptNoticeDispatchAction.configure =>
        'admin_configure_receipt_notice_dispatch_v1',
      AdminReceiptNoticeDispatchAction.approve =>
        'admin_approve_receipt_notice_dispatch_v1',
      AdminReceiptNoticeDispatchAction.revoke =>
        'admin_revoke_receipt_notice_dispatch_v1',
    };
    return AdminReceiptNoticeDispatchRequest.recorded(
      await _call(name, intent.parameters),
      intent,
    );
  }

  @override
  Future<AdminReceiptNoticeDispatchRequest> recover(
    AdminReceiptNoticeDispatchIntent intent,
  ) async {
    _owner(intent.actorId, intent.sessionId);
    return AdminReceiptNoticeDispatchRequest.lookup(
      await _call('admin_get_receipt_notice_dispatch_request_v1', {
        'p_request_id': intent.requestId,
      }),
      intent,
    );
  }
}
