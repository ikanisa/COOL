import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_workspace_access.dart';

/// Repository for admin role management (assign, revoke, list).
class AdminRoleRepository {
  AdminRoleRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  // ═══════════════════════════════════════════════════════════════
  // READ — get admin access for the current user
  // ═══════════════════════════════════════════════════════════════

  /// Fetch structured admin access from the database.
  /// Returns null if the RPC is not available (backward compat).
  Future<AdminWorkspaceAccess?> fetchAdminAccess({String? userId}) async {
    try {
      final params = <String, dynamic>{};
      if (userId != null) {
        params['p_user_id'] = userId;
      }
      final result = await _client.rpc(
        'get_admin_access_for_user',
        params: params,
      );
      if (result is Map<String, dynamic>) {
        return AdminWorkspaceAccess.fromRpcResponse(result);
      }
      return null;
    } catch (_) {
      // RPC not deployed yet — caller will use app_metadata fallback
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // WRITE — assign / revoke roles (super admin only)
  // ═══════════════════════════════════════════════════════════════

  /// Assign an admin role to a user.
  /// Returns a status map with the assignment ID.
  Future<Map<String, dynamic>> assignRole({
    required String targetUserId,
    required AdminRole role,
    String? bankId,
    String? notes,
  }) async {
    final result = await _client.rpc(
      'assign_admin_role',
      params: {
        'p_target_user_id': targetUserId,
        'p_role': role.dbValue,
        ...?(bankId == null
            ? null
            : <String, dynamic>{'p_partner_scope_id': bankId}),
        ...?(notes == null ? null : <String, dynamic>{'p_notes': notes}),
      },
    );
    return result as Map<String, dynamic>;
  }

  /// Revoke an admin role assignment (soft-delete).
  Future<Map<String, dynamic>> revokeRole({
    required String assignmentId,
    String? notes,
  }) async {
    final result = await _client.rpc(
      'revoke_admin_role',
      params: {
        'p_assignment_id': assignmentId,
        ...?(notes == null ? null : <String, dynamic>{'p_notes': notes}),
      },
    );
    return result as Map<String, dynamic>;
  }

  // ═══════════════════════════════════════════════════════════════
  // LIST — list all role assignments (super admin only)
  // ═══════════════════════════════════════════════════════════════

  /// List all admin role assignments, optionally filtered by role.
  Future<List<AdminRoleAssignment>> listRoleAssignments({
    AdminRole? role,
    bool activeOnly = true,
  }) async {
    final result = await _client.rpc(
      'list_admin_role_assignments',
      params: {
        if (role != null) 'p_role': role.dbValue,
        'p_active_only': activeOnly,
      },
    );
    if (result is List) {
      return result
          .cast<Map<String, dynamic>>()
          .map(AdminRoleAssignment.fromJson)
          .toList(growable: false);
    }
    return const [];
  }
}
