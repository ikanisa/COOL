import 'admin_account_api.dart';
import 'admin_burimunsi_api.dart';
import 'cloudflare_admin_session.dart';

class BuriApprovalUnconfirmed extends AdminAccountException {
  const BuriApprovalUnconfirmed()
    : super(
        'Approval was not confirmed. Check the original request before trying again.',
      );
}

mixin CloudflareAdminBuriMunsiApi implements AdminBuriMunsiApi {
  CloudflareAdminSession get session;
  @override
  bool get buriAvailable => session.managedInvitationProtocolAvailable;
  @override
  Object get buriAuthorityFence => session.authorityFence;
  @override
  bool get buriAuthorized {
    final user = session.user, now = DateTime.now();
    return buriAvailable &&
        user != null &&
        user.usesCanonicalEvidence &&
        !session.sensitiveEmailVerificationUnconfirmed &&
        user.role == AdminAccountRole.owner &&
        user.email.toLowerCase() == 'info@ikanisa.com' &&
        user.permissions.contains('admin_users.manage') &&
        user.expiresAt.isAfter(now) &&
        user.hasRecentSensitiveVerification(now: now);
  }

  void _buriOwned(Object fence) {
    if (!buriAuthorized || fence != buriAuthorityFence) {
      throw const AdminAccountException(
        'Verify your current owner sign-in to manage BuriMunsi access.',
      );
    }
  }

  @override
  Future<BuriOperatorDirectory> loadBuriDirectory() async {
    final fence = buriAuthorityFence;
    _buriOwned(fence);
    final value = await session.request(
      'burimunsi/operators',
      authenticated: true,
      method: 'GET',
      responseCurrent: () => buriAuthorized && fence == buriAuthorityFence,
    );
    _buriOwned(fence);
    return BuriOperatorDirectory.parse(value);
  }

  @override
  Future<Map<String, dynamic>> submitBuriApproval(
    BuriApprovalIntent intent,
    Object fence,
  ) async {
    _buriOwned(fence);
    try {
      final value = await session.request(
        'burimunsi/operators',
        body: intent.body,
        authenticated: true,
        method: 'POST',
        idempotencyKey: intent.requestId,
        responseCurrent: () => buriAuthorized && fence == buriAuthorityFence,
      );
      _buriOwned(fence);
      intent.verify(value);
      return value;
    } catch (_) {
      _buriOwned(fence);
      throw const BuriApprovalUnconfirmed();
    }
  }

  @override
  Future<Map<String, dynamic>?> lookupBuriApproval(
    BuriApprovalIntent intent,
    Object fence,
  ) async {
    _buriOwned(fence);
    final value = await session.request(
      'burimunsi/operators/requests/${intent.requestId}',
      authenticated: true,
      method: 'GET',
      responseCurrent: () => buriAuthorized && fence == buriAuthorityFence,
    );
    _buriOwned(fence);
    if (value['contractVersion'] != 1 ||
        value['found'] is! bool ||
        value['collectionId'] != intent.collectionId) {
      throw const BuriApprovalUnconfirmed();
    }
    if (value['found'] == false && value.length == 3) return null;
    if (value['found'] != true || value['receipt'] is! Map) {
      throw const BuriApprovalUnconfirmed();
    }
    final receipt = Map<String, dynamic>.from(value['receipt'] as Map);
    intent.verify(receipt);
    return receipt;
  }
}
