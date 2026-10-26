import '../../core/cloudflare/collect_cloudflare_client.dart';
import 'admin_auth_guard.dart';
import 'admin_receipt_notice_content_models.dart';

bool noticeDenied(Object e) =>
    e is AdminSessionChanged ||
    e is CollectAuthException ||
    e is CollectApiException &&
        const {
          '42501',
          '401',
          '403',
          'authentication_required',
          'invalid_token',
          'access_revoked',
          'unauthenticated',
          'session_changed',
          'fresh_auth_required',
          'recent_email_sign_in_required',
          'mfa_required',
          'admin_required',
          'permission_denied',
          'origin_denied',
        }.contains(e.code);

abstract interface class AdminReceiptNoticeContentApi {
  Future<AdminReceiptNoticeInspection> inspectPolicy(
    String collection,
    AdminReceiptNoticeFamily family,
    String language,
    bool enabled,
  );
  Future<AdminReceiptNoticeInspection> inspectContent(
    String outbox,
    String source,
    String collection,
    AdminReceiptNoticeFamily family,
  );
  Future<AdminReceiptNoticeRequest> record(AdminReceiptNoticeIntent intent);
  Future<AdminReceiptNoticeRequest> recover(AdminReceiptNoticeIntent intent);
}

class AdminReceiptNoticeContentSdk implements AdminReceiptNoticeContentApi {
  const AdminReceiptNoticeContentSdk({
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

  Future<Object?> _call(String name, Map<String, dynamic> params) async {
    _current();
    try {
      final value = await rpc(
        name,
        Map.unmodifiable(params),
      ).timeout(const Duration(seconds: 15));
      _current();
      return value;
    } catch (_) {
      _current();
      rethrow;
    }
  }

  void _bound(AdminReceiptNoticeIntent i) {
    _current();
    if (i.actorId != actorId || i.sessionId != sessionId) noticeInvalid();
  }

  @override
  Future<AdminReceiptNoticeInspection> inspectPolicy(
    String collection,
    AdminReceiptNoticeFamily family,
    String language,
    bool enabled,
  ) async {
    noticeUuid(collection);
    noticeLanguage(language);
    if (!family.contentSupported) noticeInvalid();
    final r = AdminReceiptNoticeInspection.policy(
      await _call('admin_inspect_receipt_notice_policy_v1', {
        'p_collection_id': collection,
        'p_notice_family': family.wire,
        'p_language': language,
        'p_enabled': enabled,
      }),
      collection,
      family,
      language,
      enabled,
    );
    if (!r.fresh(now())) noticeInvalid();
    return r;
  }

  @override
  Future<AdminReceiptNoticeInspection> inspectContent(
    String outbox,
    String source,
    String collection,
    AdminReceiptNoticeFamily family,
  ) async {
    noticeUuid(outbox);
    noticeUuid(source);
    noticeUuid(collection);
    final r = AdminReceiptNoticeInspection.content(
      await _call('admin_inspect_receipt_notice_content_v1', {
        'p_outbox_id': outbox,
        'p_notice_family': family.wire,
        'p_source_snapshot_id': source,
      }),
      outbox,
      source,
      collection,
      family,
    );
    if (!r.fresh(now())) noticeInvalid();
    return r;
  }

  @override
  Future<AdminReceiptNoticeRequest> record(AdminReceiptNoticeIntent i) async {
    _bound(i);
    if (!canManage()) throw const AdminSessionChanged();
    if (!i.inspection.fresh(now())) noticeInvalid();
    return AdminReceiptNoticeRequest.recorded(
      await _call(
        i.policy
            ? 'admin_approve_receipt_notice_policy_v1'
            : 'admin_prepare_receipt_notice_content_v1',
        i.parameters,
      ),
      i,
    );
  }

  @override
  Future<AdminReceiptNoticeRequest> recover(AdminReceiptNoticeIntent i) async {
    _bound(i);
    return AdminReceiptNoticeRequest.lookup(
      await _call('admin_get_receipt_notice_content_request_v1', {
        'p_request_id': i.requestId,
      }),
      i,
    );
  }
}
