import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/providers/auth_provider.dart';
import '../../partners/models/partner.dart';
import '../../partners/providers/partner_provider.dart';
import '../models/admin_workspace_access.dart';
import '../repositories/admin_role_repository.dart';

// ═══════════════════════════════════════════════════════════════
// Core providers
// ═══════════════════════════════════════════════════════════════

final adminRoleRepositoryProvider = Provider<AdminRoleRepository>((ref) {
  return AdminRoleRepository(client: Supabase.instance.client);
});

/// Async RPC-based admin access — single source of truth.
/// Falls back to app_metadata if the RPC is unavailable.
final adminAccessFromRpcProvider =
    FutureProvider<AdminWorkspaceAccess>((ref) async {
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
    error: (_, __) {
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
final adminRoleAssignmentsProvider =
    FutureProvider<List<AdminRoleAssignment>>((ref) async {
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

// ═══════════════════════════════════════════════════════════════
// Workspace listing providers (for admin entry screen)
// ═══════════════════════════════════════════════════════════════

final adminPartnerWorkspacesProvider = FutureProvider<List<Partner>>((
  ref,
) async {
  final access = ref.watch(adminWorkspaceAccessProvider);
  final repo = ref.read(partnerRepositoryProvider);

  if (access.hasPlatformAccess || access.hasGlobalPartnerAccess) {
    return repo.fetchByCategory(PartnerCategory.football);
  }
  if (access.partnerAdminIds.isEmpty) {
    return const <Partner>[];
  }
  final partners = await repo.fetchByIds(
    access.partnerAdminIds.toList(growable: false),
  );
  return partners
      .where((partner) => partner.category == PartnerCategory.football)
      .toList(growable: false);
});

final adminBankWorkspacesProvider = FutureProvider<List<Partner>>((ref) async {
  final access = ref.watch(adminWorkspaceAccessProvider);
  final repo = ref.read(partnerRepositoryProvider);

  if (access.hasPlatformAccess || access.hasGlobalBankAccess) {
    return repo.fetchByCategory(PartnerCategory.bank);
  }
  if (access.bankAdminIds.isEmpty) {
    return const <Partner>[];
  }
  final partners = await repo.fetchByIds(
    access.bankAdminIds.toList(growable: false),
  );
  return partners
      .where((partner) => partner.category == PartnerCategory.bank)
      .toList(growable: false);
});

final rayonAdminAccessProvider = FutureProvider<bool>((ref) async {
  final access = ref.watch(adminWorkspaceAccessProvider);
    if (access.partnerAdminIds.isEmpty && !access.hasPlatformAccess && !access.hasGlobalPartnerAccess) {
      return false;
    }
  if (access.hasPlatformAccess || access.hasGlobalPartnerAccess) {
    return true;
  }

  final rayon = await ref.read(partnerBySlugProvider('rayon-sports').future);
  if (rayon == null) {
    return false;
  }
  return access.canAccessPartnerId(rayon.id);
});

