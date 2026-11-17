import 'admin_account_api.dart';
import 'admin_burimunsi_api.dart';
import 'cloudflare_admin_session.dart';

class BuriApprovalUnconfirmed extends AdminAccountException {
  const BuriApprovalUnconfirmed()
    : super(
        'Approval was not confirmed. Check the original request before trying again.',
      );
}

mixin CloudflareAdminBuriMunsiApi implements AdminBuriMunsiScopeApi {
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
        user.isCurrentOwner &&
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
  Future<List<BuriScopeChoice>> loadBuriScopes() async {
    final fence = buriAuthorityFence;
    _buriOwned(fence);
    final value = await session.request(
      'momo/native-setup',
      authenticated: true,
      method: 'GET',
      responseCurrent: () => buriAuthorized && fence == buriAuthorityFence,
    );
    _buriOwned(fence);
    if (value['contractVersion'] != 1 ||
        value['collections'] is! List ||
        value['scopes'] is! List) {
      throw const FormatException(
        'The available BuriMunsi groups could not be verified.',
      );
    }
    final titles = <String, String>{};
    for (final raw in value['collections'] as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      if (row['id'] is! String || row['title'] is! String) {
        throw const FormatException('Invalid group.');
      }
      titles[row['id'] as String] = row['title'] as String;
    }
    return [
      for (final raw in value['scopes'] as List)
        if (raw is Map &&
            raw['collectionId'] is String &&
            titles.containsKey(raw['collectionId']))
          BuriScopeChoice(
            raw['collectionId'] as String,
            titles[raw['collectionId']]!,
          ),
    ];
  }

  String _buriQuery(String path, String? collectionId) => collectionId == null
      ? path
      : '$path?${Uri(queryParameters: {'collectionId': collectionId}).query}';

  @override
  Future<BuriOperatorDirectory> loadBuriDirectory({
    String? collectionId,
  }) async {
    final fence = buriAuthorityFence;
    _buriOwned(fence);
    final value = await session.request(
      _buriQuery('burimunsi/operators', collectionId),
      authenticated: true,
      method: 'GET',
      responseCurrent: () => buriAuthorized && fence == buriAuthorityFence,
    );
    _buriOwned(fence);
    final result = BuriOperatorDirectory.parse(value);
    if (collectionId != null && result.collectionId != collectionId) {
      throw const FormatException('The selected group changed.');
    }
    return result;
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
      _buriQuery(
        'burimunsi/operators/requests/${intent.requestId}',
        intent.collectionId,
      ),
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

  @override
  Future<BuriProvisioningDirectory> loadBuriProvisioning({
    String? collectionId,
  }) async {
    final fence = buriAuthorityFence;
    _buriOwned(fence);
    final value = await session.request(
      _buriQuery('burimunsi/provisioning', collectionId),
      authenticated: true,
      method: 'GET',
      responseCurrent: () => buriAuthorized && fence == buriAuthorityFence,
    );
    _buriOwned(fence);
    final result = BuriProvisioningDirectory.parse(value);
    if (collectionId != null && result.collectionId != collectionId) {
      throw const FormatException('The selected group changed.');
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> submitBuriProvisioning(
    BuriProvisioningIntent intent,
    Object fence, {
    String? pin,
  }) async {
    _buriOwned(fence);
    try {
      final value = await session.request(
        'burimunsi/provisioning',
        authenticated: true,
        method: 'POST',
        body: intent.body(pin: pin),
        idempotencyKey: intent.requestId,
        responseCurrent: () => buriAuthorized && fence == buriAuthorityFence,
      );
      _buriOwned(fence);
      intent.verify(value);
      return value;
    } catch (_) {
      _buriOwned(fence);
      throw const AdminAccountException(
        'Native setup was not confirmed. Check the original request before continuing.',
      );
    }
  }

  @override
  Future<Map<String, dynamic>?> lookupBuriProvisioning(
    BuriProvisioningIntent intent,
    Object fence,
  ) async {
    _buriOwned(fence);
    final value = await session.request(
      _buriQuery(
        'burimunsi/provisioning/requests/${intent.requestId}',
        intent.collectionId,
      ),
      authenticated: true,
      method: 'GET',
      responseCurrent: () => buriAuthorized && fence == buriAuthorityFence,
    );
    _buriOwned(fence);
    if (value['contractVersion'] != 1 ||
        value['collectionId'] != intent.collectionId ||
        value['requestId'] != intent.requestId ||
        value['found'] is! bool ||
        value.length != (value['found'] == true ? 5 : 4)) {
      throw const FormatException(
        'The original native setup outcome could not be verified.',
      );
    }
    if (value['found'] == false) return null;
    final receipt = Map<String, dynamic>.from(value['receipt'] as Map);
    intent.verify(receipt);
    return receipt;
  }

  @override
  Future<Map<String, dynamic>> cancelBuriProvisioning(
    BuriProvisioningIntent intent,
    Object fence,
  ) async {
    _buriOwned(fence);
    final value = await session.request(
      'burimunsi/provisioning/requests/${intent.requestId}/cancel',
      authenticated: true,
      method: 'POST',
      body: {'collectionId': intent.collectionId},
      idempotencyKey: intent.requestId,
      responseCurrent: () => buriAuthorized && fence == buriAuthorityFence,
    );
    _buriOwned(fence);
    intent.verify(value);
    return value;
  }

  @override
  Future<BuriNativeDelivery> loadBuriDelivery(
    BuriProvisioningIntent intent,
    Object fence,
  ) async {
    _buriOwned(fence);
    final value = await session.request(
      'burimunsi/provisioning/requests/${intent.requestId}/delivery',
      authenticated: true,
      method: 'POST',
      body: {
        'collectionId': intent.collectionId,
        'installationId': intent.installationId,
        'profile': intent.profile,
        'grantVersion': intent.expectedGrantVersion! + 1,
      },
      responseCurrent: () => buriAuthorized && fence == buriAuthorityFence,
    );
    _buriOwned(fence);
    return BuriNativeDelivery.parse(value, intent);
  }
}
