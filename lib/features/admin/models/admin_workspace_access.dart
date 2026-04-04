import '../../auth/providers/auth_provider.dart';

/// Supported admin role types returned by auth metadata and RPC responses.
enum AdminRole {
  /// Full platform access — can manage everything.
  admin,

  /// Scoped access to bank workspaces.
  bank;

  static AdminRole? fromString(String? value) {
    if (value == null) {
      return null;
    }

    switch (value.trim().toLowerCase()) {
      case 'admin':
        return AdminRole.admin;
      case 'bank':
        return AdminRole.bank;
      default:
        return null;
    }
  }

  String get label => switch (this) {
    AdminRole.admin => 'Platform Admin',
    AdminRole.bank => 'Bank Admin',
  };

  String get dbValue => switch (this) {
    AdminRole.admin => 'admin',
    AdminRole.bank => 'bank',
  };
}

/// A single admin role assignment from the database.
class AdminRoleAssignment {
  const AdminRoleAssignment({
    required this.id,
    required this.userId,
    required this.role,
    this.bankId,
    this.bankName,
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
  final String? bankId;
  final String? bankName;
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
      // Older RPCs still emit partner_* keys for bank-scoped assignments.
      bankId: (json['bank_id'] ?? json['partner_scope_id'])?.toString(),
      bankName: (json['bank_name'] ?? json['partner_name'])?.toString(),
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
    this.hasBankAccess = false,
    this.bankAdminIds = const <String>{},
    this.roleAssignments = const <AdminRoleAssignment>[],
  });

  final bool hasPlatformAccess;
  final bool hasBankAccess;
  final Set<String> bankAdminIds;

  /// All active role assignments for this user (from DB).
  final List<AdminRoleAssignment> roleAssignments;

  bool get hasBankAdminAccess =>
      hasPlatformAccess ||
      hasBankAccess ||
      bankAdminIds.isNotEmpty ||
      roleAssignments.any((assignment) => assignment.role == AdminRole.bank);

  bool get hasAnyAdminAccess => hasPlatformAccess || hasBankAdminAccess;

  /// The set of distinct roles this user has.
  Set<AdminRole> get activeRoles =>
      roleAssignments.map((assignment) => assignment.role).toSet();

  bool canAccessBankId(String bankId) {
    final normalized = bankId.trim();
    if (normalized.isEmpty) {
      return false;
    }
    if (hasPlatformAccess) {
      return true;
    }
    return bankAdminIds.contains(normalized);
  }

  /// Parse the RPC response from `get_admin_access_for_user`.
  factory AdminWorkspaceAccess.fromRpcResponse(Map<String, dynamic> json) {
    final rawAssignments = json['role_assignments'];
    final assignments = <AdminRoleAssignment>[];
    if (rawAssignments is List) {
      for (final raw in rawAssignments) {
        if (raw is Map<String, dynamic>) {
          assignments.add(AdminRoleAssignment.fromJson(raw));
        } else if (raw is Map) {
          assignments.add(AdminRoleAssignment.fromJson(raw.cast()));
        }
      }
    }

    return AdminWorkspaceAccess(
      hasPlatformAccess: json['has_platform_access'] as bool? ?? false,
      hasBankAccess: json['has_bank_access'] as bool? ?? false,
      bankAdminIds: _stringSet(json['bank_partner_ids']),
      roleAssignments: assignments,
    );
  }

  /// Legacy fallback: parse from Supabase app_metadata.
  factory AdminWorkspaceAccess.fromAuthState(AuthState authState) {
    final metadata = _metadataMap(authState);
    final hasPlatformAccess =
        authState.user?.isAdmin == true ||
        _boolValue(
          metadata['has_platform_access'] ??
              metadata['is_admin'] ??
              metadata['admin'],
        );
    final hasBankAccess = _boolValue(
      metadata['has_bank_access'] ?? metadata['is_bank_admin'],
    );
    final bankAdminIds = _stringSet(
      metadata['bank_partner_ids'] ?? metadata['bank_admin_ids'],
    );

    return AdminWorkspaceAccess(
      hasPlatformAccess: hasPlatformAccess,
      hasBankAccess: hasBankAccess,
      bankAdminIds: bankAdminIds,
    );
  }

  static Map<String, dynamic> _metadataMap(AuthState authState) {
    final raw = authState.session?.user.toJson()['app_metadata'];
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return raw.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }

  static bool _boolValue(dynamic raw) {
    if (raw is bool) {
      return raw;
    }
    if (raw is num) {
      return raw != 0;
    }
    if (raw is String) {
      switch (raw.trim().toLowerCase()) {
        case 'true':
        case '1':
        case 'yes':
          return true;
        default:
          return false;
      }
    }
    return false;
  }

  static Set<String> _stringSet(dynamic raw) {
    if (raw is! List) {
      return const <String>{};
    }

    return raw
        .map((value) => value?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet();
  }
}
