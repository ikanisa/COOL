import '../../auth/providers/auth_provider.dart';

/// The three admin role types in the COOL platform.
enum AdminRole {
  /// Full platform access — can manage everything.
  admin,

  /// Bank custodian — scoped to bank partner workspaces.
  bank,

  /// Rayon Sports admin — scoped to RS partner workspace.
  rayonSport;

  static AdminRole? fromString(String? value) {
    if (value == null) return null;
    switch (value.trim().toLowerCase()) {
      case 'admin':
        return AdminRole.admin;
      case 'bank':
        return AdminRole.bank;
      case 'rayon_sport':
        return AdminRole.rayonSport;
      default:
        return null;
    }
  }

  String get label {
    switch (this) {
      case AdminRole.admin:
        return 'Platform Admin';
      case AdminRole.bank:
        return 'Bank Admin';
      case AdminRole.rayonSport:
        return 'Rayon Sport Admin';
    }
  }

  String get dbValue {
    switch (this) {
      case AdminRole.admin:
        return 'admin';
      case AdminRole.bank:
        return 'bank';
      case AdminRole.rayonSport:
        return 'rayon_sport';
    }
  }
}

/// A single admin role assignment from the database.
class AdminRoleAssignment {
  const AdminRoleAssignment({
    required this.id,
    required this.userId,
    required this.role,
    this.partnerScopeId,
    this.partnerName,
    this.userName,
    this.userPhone,
    this.grantedBy,
    required this.grantedAt,
    this.revokedAt,
    required this.isActive,
    this.notes,
  });

  final String id;
  final String userId;
  final AdminRole role;
  final String? partnerScopeId;
  final String? partnerName;
  final String? userName;
  final String? userPhone;
  final String? grantedBy;
  final DateTime grantedAt;
  final DateTime? revokedAt;
  final bool isActive;
  final String? notes;

  factory AdminRoleAssignment.fromJson(Map<String, dynamic> json) {
    return AdminRoleAssignment(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      role: AdminRole.fromString(json['role']?.toString()) ?? AdminRole.admin,
      partnerScopeId: json['partner_scope_id']?.toString(),
      partnerName: json['partner_name']?.toString(),
      userName: json['user_name']?.toString(),
      userPhone: json['user_phone']?.toString(),
      grantedBy: json['granted_by']?.toString(),
      grantedAt:
          DateTime.tryParse(json['granted_at']?.toString() ?? '') ??
          DateTime.now(),
      revokedAt: json['revoked_at'] != null
          ? DateTime.tryParse(json['revoked_at'].toString())
          : null,
      isActive: json['is_active'] as bool? ?? true,
      notes: json['notes']?.toString(),
    );
  }
}

class AdminWorkspaceAccess {
  const AdminWorkspaceAccess({
    this.hasPlatformAccess = false,
    this.hasGlobalPartnerAccess = false,
    this.partnerAdminIds = const <String>{},
    this.hasGlobalBankAccess = false,
    this.bankAdminIds = const <String>{},
    this.roleAssignments = const <AdminRoleAssignment>[],
  });

  final bool hasPlatformAccess;
  final bool hasGlobalPartnerAccess;
  final Set<String> partnerAdminIds;
  final bool hasGlobalBankAccess;
  final Set<String> bankAdminIds;

  /// All active role assignments for this user (from DB).
  final List<AdminRoleAssignment> roleAssignments;

  bool get hasPartnerAdminAccess =>
      hasPlatformAccess || hasGlobalPartnerAccess || partnerAdminIds.isNotEmpty;

  bool get hasBankAdminAccess =>
      hasPlatformAccess || hasGlobalBankAccess || bankAdminIds.isNotEmpty;

  bool get hasAnyAdminAccess =>
      hasPlatformAccess || hasPartnerAdminAccess || hasBankAdminAccess;

  /// The set of distinct roles this user has.
  Set<AdminRole> get activeRoles => roleAssignments.map((a) => a.role).toSet();

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

  /// Parse the RPC response from `get_admin_access_for_user`.
  factory AdminWorkspaceAccess.fromRpcResponse(Map<String, dynamic> json) {
    final hasPlatformAccess = json['has_platform_access'] as bool? ?? false;
    final hasBankAccess = json['has_bank_access'] as bool? ?? false;
    final hasRayonAccess = json['has_rayon_access'] as bool? ?? false;

    final bankIds = _jsonArrayToStringSet(json['bank_partner_ids']);
    final partnerIds = _jsonArrayToStringSet(json['partner_admin_ids']);

    final rawAssignments = json['role_assignments'];
    final assignments = <AdminRoleAssignment>[];
    if (rawAssignments is List) {
      for (final raw in rawAssignments) {
        if (raw is Map<String, dynamic>) {
          assignments.add(AdminRoleAssignment.fromJson(raw));
        }
      }
    }

    return AdminWorkspaceAccess(
      hasPlatformAccess: hasPlatformAccess,
      hasGlobalPartnerAccess: hasRayonAccess,
      partnerAdminIds: partnerIds,
      hasGlobalBankAccess: hasBankAccess && bankIds.isEmpty,
      bankAdminIds: bankIds,
      roleAssignments: assignments,
    );
  }

  /// Legacy fallback: parse from Supabase app_metadata.
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

Set<String> _jsonArrayToStringSet(dynamic value) {
  if (value is List) {
    return value
        .map((entry) => entry.toString().trim())
        .where((entry) => entry.isNotEmpty && entry != 'null')
        .toSet();
  }
  return const <String>{};
}
