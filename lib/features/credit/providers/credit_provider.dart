import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../models/credit_dashboard.dart';
import '../repositories/credit_repository.dart';

final creditRepositoryProvider = Provider<CreditRepository>((ref) {
  return CreditRepository();
});

final creditDashboardProvider = FutureProvider<CreditDashboard?>((ref) async {
  final userId = ref.watch(authProvider).user?.id;
  if (userId == null || userId.isEmpty) {
    return null;
  }

  final repository = ref.watch(creditRepositoryProvider);
  return repository.loadDashboard(userId);
});
