import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_client_provider.dart';

import '../../auth/providers/auth_provider.dart';

import '../models/admin_workspace_access.dart';
import '../repositories/admin_role_repository.dart';

// ═══════════════════════════════════════════════════════════════
// Core providers
// ═══════════════════════════════════════════════════════════════

final adminRoleRepositoryProvider = Provider<AdminRoleRepository>((ref) {
  return AdminRoleRepository(client: ref.read(supabaseClientProvider));
});

/// Async RPC-based admin access — single source of truth.
/// Falls back to app_metadata if the RPC is unavailable.
final adminAccessFromRpcProvider = FutureProvider<AdminWorkspaceAccess>((
  ref,
) async {
  final authState = ref.watch(authProvider);
  if (authState.session == null) {
    return const AdminWorkspaceAccess();
  }

  final repo = ref.read(adminRoleRepositoryProvider);
  final rpcAccess = await repo.fetchAdminAccess();

  if (rpcAccess != null) {
    return rpcAccess;
  }

  // Fallback to app_metadata when RPC not deployed
  return AdminWorkspaceAccess.fromAuthState(authState);
});

/// Primary synchronous provider used by gate widgets and dashboard.
/// Uses the RPC result when loaded; otherwise falls back to app_metadata.
final adminWorkspaceAccessProvider = Provider<AdminWorkspaceAccess>((ref) {
  final rpcAsync = ref.watch(adminAccessFromRpcProvider);
  return rpcAsync.when(
    data: (access) => access,
    loading: () {
      // Instant fallback while RPC loads
      final authState = ref.read(authProvider);
      return AdminWorkspaceAccess.fromAuthState(authState);
    },
    error: (_, _) {
      // Fallback on error
      final authState = ref.read(authProvider);
      return AdminWorkspaceAccess.fromAuthState(authState);
    },
  );
});

// ═══════════════════════════════════════════════════════════════
// Role management providers (super admin)
// ═══════════════════════════════════════════════════════════════

/// Lists all admin role assignments (super admin only).
final adminRoleAssignmentsProvider = FutureProvider<List<AdminRoleAssignment>>((
  ref,
) async {
  final repo = ref.read(adminRoleRepositoryProvider);
  return repo.listRoleAssignments();
});

/// Lists role assignments filtered by a specific role.
final adminRoleAssignmentsByRoleProvider =
    FutureProvider.family<List<AdminRoleAssignment>, AdminRole>((
      ref,
      role,
    ) async {
      final repo = ref.read(adminRoleRepositoryProvider);
      return repo.listRoleAssignments(role: role);
    });
