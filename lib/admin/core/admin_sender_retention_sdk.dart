import '../../core/cloudflare/collect_cloudflare_client.dart';
import 'admin_auth_guard.dart';
import 'admin_sender_retention_models.dart';

bool retentionDenied(Object e) =>
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

abstract interface class AdminRetentionApi {
  Future<AdminRetentionSnapshot> read();
  Future<AdminRetentionRequest> configure(AdminRetentionIntent intent);
  Future<AdminRetentionRequest> recover(AdminRetentionIntent intent);
}

class AdminRetentionSdk implements AdminRetentionApi {
  const AdminRetentionSdk({
    required this.rpc,
    required this.actorId,
    required this.sessionId,
    required this.isCurrent,
    required this.now,
  });
  final Future<Object?> Function(String, Map<String, dynamic>) rpc;
  final String actorId, sessionId;
  final bool Function() isCurrent;
  final DateTime Function() now;
  void _current() {
    if (!isCurrent()) throw const AdminSessionChanged();
  }

  Future<Object?> _call(String name, Map<String, dynamic> params) async {
    _current();
    final value = await rpc(
      name,
      Map.unmodifiable(params),
    ).timeout(const Duration(seconds: 15));
    _current();
    return value;
  }

  void _bound(AdminRetentionIntent i) {
    if (i.actorId != actorId || i.sessionId != sessionId) retentionInvalid();
  }

  @override
  Future<AdminRetentionSnapshot> read() async {
    final s = AdminRetentionSnapshot.parse(
      await _call('admin_get_receipt_retention_controls_v1', {}),
      actorId,
      sessionId,
    );
    if (!s.fresh(now())) retentionInvalid();
    return s;
  }

  @override
  Future<AdminRetentionRequest> configure(AdminRetentionIntent i) async {
    _bound(i);
    if (!now().toUtc().isBefore(i.expiresAt)) retentionInvalid();
    final r = AdminRetentionRequest.parse(
      await _call(
        'admin_configure_receipt_retention_controls_v1',
        i.parameters,
      ),
      i,
    );
    if (!r.recorded) retentionInvalid();
    return r;
  }

  @override
  Future<AdminRetentionRequest> recover(AdminRetentionIntent i) async {
    _bound(i);
    return AdminRetentionRequest.parse(
      await _call('admin_get_receipt_retention_control_request_v1', {
        'p_request_id': i.requestId,
        'p_fingerprint_sha256': i.fingerprint,
        'p_intent': i.row,
      }),
      i,
    );
  }
}
