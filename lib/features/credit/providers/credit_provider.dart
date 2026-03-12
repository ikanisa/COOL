import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../../../core/providers/supabase_client_provider.dart';
import '../models/credit_dashboard.dart';
import '../models/partner_credit_application.dart';
import '../repositories/credit_application_repository.dart';
import '../repositories/credit_repository.dart';

final creditRepositoryProvider = Provider<CreditRepository>((ref) {
  return CreditRepository(client: ref.read(supabaseClientProvider));
});

final creditApplicationRepositoryProvider =
    Provider<CreditApplicationRepository>((ref) {
      return CreditApplicationRepository(
        client: ref.read(supabaseClientProvider),
      );
    });

final creditDashboardProvider = FutureProvider<CreditDashboard?>((ref) async {
  final userId = ref.watch(authProvider).user?.id;
  if (userId == null || userId.isEmpty) {
    return null;
  }

  final repository = ref.watch(creditRepositoryProvider);
  return repository.loadDashboard(userId);
});

final myPartnerApplicationsProvider =
    FutureProvider<List<PartnerCreditApplication>>((ref) async {
      final userId = ref.watch(authProvider).user?.id;
      if (userId == null || userId.isEmpty) {
        return const <PartnerCreditApplication>[];
      }

      final repository = ref.watch(creditApplicationRepositoryProvider);
      return repository.fetchMyApplications();
    });
