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
