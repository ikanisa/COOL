import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_client_provider.dart';
import '../models/partner.dart';
import '../repositories/partner_repository.dart';

final partnerRepositoryProvider = Provider<PartnerRepository>((ref) {
  return PartnerRepository(client: ref.read(supabaseClientProvider));
});

final partnerListProvider = FutureProvider<List<Partner>>((ref) async {
  final repository = ref.read(partnerRepositoryProvider);
  return repository.fetchAll();
});

final partnerByIdProvider = FutureProvider.family<Partner?, String>((
  ref,
  partnerId,
) async {
  final repository = ref.read(partnerRepositoryProvider);
  return repository.fetchById(partnerId);
});
