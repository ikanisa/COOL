import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../../../core/providers/supabase_client_provider.dart';
import '../models/home_dashboard_data.dart';
import '../repositories/home_dashboard_repository.dart';

final homeDashboardRepositoryProvider = Provider<HomeDashboardRepository>((ref) {
  return HomeDashboardRepository(client: ref.read(supabaseClientProvider));
});

final homeDashboardProvider = FutureProvider<HomeDashboardData?>((ref) async {
  final userId = ref.watch(authProvider).user?.id;
  if (userId == null || userId.isEmpty) {
    return null;
  }

  final repository = ref.watch(homeDashboardRepositoryProvider);
  return repository.load(userId);
});
