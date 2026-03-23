import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_client_provider.dart';
import '../repositories/admin_ai_content_repository.dart';

final adminAiContentRepositoryProvider = Provider<AdminAiContentRepository>((
  ref,
) {
  return AdminAiContentRepository(client: ref.read(supabaseClientProvider));
});

final adminAiContentGenerationConfigProvider =
    FutureProvider.autoDispose<AdminAiContentGenerationConfig?>((ref) async {
      final repository = ref.read(adminAiContentRepositoryProvider);
      return repository.fetchGenerationConfig();
    });
