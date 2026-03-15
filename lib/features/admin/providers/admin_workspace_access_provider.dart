import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../../partners/models/partner.dart';
import '../../partners/providers/partner_provider.dart';
import '../models/admin_workspace_access.dart';

final adminWorkspaceAccessProvider = Provider<AdminWorkspaceAccess>((ref) {
  final authState = ref.watch(authProvider);
  return AdminWorkspaceAccess.fromAuthState(authState);
});

final adminPartnerWorkspacesProvider = FutureProvider<List<Partner>>((
  ref,
) async {
  final access = ref.watch(adminWorkspaceAccessProvider);
  final repo = ref.read(partnerRepositoryProvider);

  if (access.hasGlobalPartnerAccess) {
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

  if (access.hasGlobalBankAccess) {
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
