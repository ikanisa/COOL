import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_client_provider.dart';
import '../models/bank_admin_models.dart';
import '../repositories/bank_admin_repository.dart';

final bankAdminRepositoryProvider = Provider<BankAdminRepository>((ref) {
  return BankAdminRepository(client: ref.read(supabaseClientProvider));
});

final bankAdminWorkspaceProvider = FutureProvider.autoDispose
    .family<BankAdminWorkspaceSnapshot, String>((ref, bankId) async {
      if (bankId.trim().isEmpty) {
        return const BankAdminWorkspaceSnapshot();
      }

      final repository = ref.read(bankAdminRepositoryProvider);
      return repository.loadWorkspaceSnapshot(bankId);
    });

/// Analytics summary for a bank partner.
final bankAnalyticsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, bankId) async {
      final repo = ref.read(bankAdminRepositoryProvider);
      return repo.fetchBankAnalytics(bankId);
    });
