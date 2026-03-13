import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../../../core/providers/supabase_client_provider.dart';
import '../models/momo_statement.dart';
import '../repositories/momo_statement_repository.dart';
import '../services/momo_statement_download_service.dart';
import '../services/momo_statement_export_service.dart';

final momoStatementRepositoryProvider = Provider<MomoStatementRepository>((
  ref,
) {
  return MomoStatementRepository(client: ref.read(supabaseClientProvider));
});

final momoStatementExportServiceProvider = Provider<MomoStatementExportService>(
  (ref) {
    return MomoStatementExportService();
  },
);

final momoStatementDownloadServiceProvider =
    Provider<MomoStatementDownloadService>((ref) {
      return MomoStatementDownloadService();
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
