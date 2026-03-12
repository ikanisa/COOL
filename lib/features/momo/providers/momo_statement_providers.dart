import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../../../core/providers/supabase_client_provider.dart';
import '../models/momo_statement.dart';
import '../repositories/momo_statement_repository.dart';

final momoStatementRepositoryProvider = Provider<MomoStatementRepository>((
  ref,
) {
  return MomoStatementRepository(client: ref.read(supabaseClientProvider));
});

final momoStatementBundleProvider = FutureProvider.autoDispose
    .family<MomoStatementBundle, MomoStatementQuery>((ref, query) async {
      final userId = ref.watch(authProvider).user?.id;
      if (userId == null || userId.isEmpty) {
        return const MomoStatementBundle();
      }

      final repository = ref.watch(momoStatementRepositoryProvider);
      return repository.loadStatementBundle(userId, query: query);
    });
