import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config_provider.dart';
import '../../../core/config/app_config_repository.dart';
import '../../../core/providers/hive_providers.dart';
import '../../../core/providers/supabase_client_provider.dart';
import '../models/biopay_profile.dart';
import '../repositories/biopay_repository.dart';
import '../services/biopay_auth_gate_service.dart';
import '../services/biopay_cache_service.dart';
import '../services/biopay_dialer_service.dart';
import '../services/biopay_embedding_service.dart';

final biopayRepositoryProvider = Provider<BiopayRepository>((ref) {
  return BiopayRepository(client: ref.read(supabaseClientProvider));
});

final biopayDialerServiceProvider = Provider<BiopayDialerService>((ref) {
  return const BiopayDialerService();
});

final biopayAuthAdapterProvider = Provider<BiopayAuthAdapter>((ref) {
  return LocalAuthBiopayAuthAdapter();
});

final biopayAuthGateServiceProvider = Provider<BiopayAuthGateService>((ref) {
  return BiopayAuthGateService(adapter: ref.read(biopayAuthAdapterProvider));
});

final biopayCacheServiceProvider = Provider<BiopayCacheService>((ref) {
  return BiopayCacheService(openBox: ref.read(hiveOpenBoxProvider));
});

final biopayModelAssetIssueProvider = FutureProvider<String?>((ref) async {
  final service = BiopayEmbeddingService();
  try {
    return await service.getModelAssetIssue();
  } finally {
    service.dispose();
  }
});

final biopayMatchThresholdProvider = FutureProvider<double>((ref) async {
  final repo = ref.read(appConfigRepositoryProvider);
  final raw = await repo.getValue(AppConfigKeys.biopayMatchThreshold);
  return double.tryParse(raw ?? '') ?? 0.72;
});

final biopayCacheTtlHoursProvider = FutureProvider<int>((ref) async {
  final repo = ref.read(appConfigRepositoryProvider);
  final raw = await repo.getValue(AppConfigKeys.biopayCacheTtlHours);
  return int.tryParse(raw ?? '') ?? 24;
});

final biopayStableFramesProvider = FutureProvider<int>((ref) async {
  final repo = ref.read(appConfigRepositoryProvider);
  final raw = await repo.getValue(AppConfigKeys.biopayStableFrames);
  return int.tryParse(raw ?? '') ?? 3;
});

final biopayProfileProvider = FutureProvider<BiopayProfile?>((ref) {
  return ref.read(biopayRepositoryProvider).getMyProfile();
});
