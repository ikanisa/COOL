import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_client_provider.dart';
import '../models/bank_admin_models.dart';
import '../repositories/bank_admin_repository.dart';

final bankAdminRepositoryProvider = Provider<BankAdminRepository>((ref) {
  return BankAdminRepository(client: ref.read(supabaseClientProvider));
});

final bankAdminWorkspaceProvider = FutureProvider.autoDispose
    .family<BankAdminWorkspaceSnapshot, String>((ref, partnerId) async {
      if (partnerId.trim().isEmpty) {
        return const BankAdminWorkspaceSnapshot();
      }

      final repository = ref.read(bankAdminRepositoryProvider);
      return repository.loadWorkspaceSnapshot(partnerId);
    });

/// Loans for a bank partner.
final bankLoansProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, partnerId) async {
  final repo = ref.read(bankAdminRepositoryProvider);
  return repo.fetchLoans(partnerId);
});

/// Savings baskets for a bank partner.
final bankBasketsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, partnerId) async {
  final repo = ref.read(bankAdminRepositoryProvider);
  return repo.fetchBaskets(partnerId);
});

/// Analytics summary for a bank partner.
final bankAnalyticsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, partnerId) async {
  final repo = ref.read(bankAdminRepositoryProvider);
  return repo.fetchBankAnalytics(partnerId);
});
