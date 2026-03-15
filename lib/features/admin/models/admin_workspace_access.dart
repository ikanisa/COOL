import '../../auth/providers/auth_provider.dart';

class AdminWorkspaceAccess {
  const AdminWorkspaceAccess({
    this.hasPlatformAccess = false,
    this.hasGlobalPartnerAccess = false,
    this.partnerAdminIds = const <String>{},
    this.hasGlobalBankAccess = false,
    this.bankAdminIds = const <String>{},
  });

  final bool hasPlatformAccess;
  final bool hasGlobalPartnerAccess;
  final Set<String> partnerAdminIds;
  final bool hasGlobalBankAccess;
  final Set<String> bankAdminIds;

  bool get hasPartnerAdminAccess =>
      hasGlobalPartnerAccess || partnerAdminIds.isNotEmpty;

  bool get hasBankAdminAccess => hasGlobalBankAccess || bankAdminIds.isNotEmpty;

  bool get hasAnyAdminAccess =>
      hasPlatformAccess || hasPartnerAdminAccess || hasBankAdminAccess;

  bool canAccessPartnerId(String partnerId) {
    final normalizedPartnerId = partnerId.trim();
    if (normalizedPartnerId.isEmpty) {
      return false;
    }
    return hasPlatformAccess ||
        hasGlobalPartnerAccess ||
        partnerAdminIds.contains(normalizedPartnerId);
  }

  bool canAccessBankId(String partnerId) {
    final normalizedPartnerId = partnerId.trim();
    if (normalizedPartnerId.isEmpty) {
      return false;
    }
    return hasPlatformAccess ||
        hasGlobalBankAccess ||
        bankAdminIds.contains(normalizedPartnerId);
  }

  factory AdminWorkspaceAccess.fromAuthState(AuthState authState) {
    final appMetadata = authState.session?.user.appMetadata ?? const {};
    return AdminWorkspaceAccess(
      hasPlatformAccess: authState.user?.isAdmin == true,
      hasGlobalPartnerAccess: _asMetadataBool(appMetadata['is_partner_admin']),
      partnerAdminIds: _metadataIdSet(appMetadata['partner_admin_ids']),
      hasGlobalBankAccess: _asMetadataBool(appMetadata['is_bank_admin']),
      bankAdminIds: _metadataIdSet(appMetadata['bank_admin_ids']),
    );
  }
}

bool _asMetadataBool(dynamic value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.toLowerCase().trim();
    return normalized == 'true' || normalized == '1';
  }
  return false;
}

Set<String> _metadataIdSet(dynamic value) {
  if (value is List) {
    return value
        .map((entry) => entry.toString().trim())
        .where((entry) => entry.isNotEmpty)
        .toSet();
  }
  if (value is Map) {
    return value.entries
        .where((entry) => _asMetadataBool(entry.value))
        .map((entry) => entry.key.toString().trim())
        .where((entry) => entry.isNotEmpty)
        .toSet();
  }
  if (value is String) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return const <String>{};
    }
    return normalized
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toSet();
  }
  return const <String>{};
}
