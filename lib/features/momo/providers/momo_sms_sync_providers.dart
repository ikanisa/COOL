import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_access_provider.dart';
import '../../../core/services/app_access_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/providers/supabase_client_provider.dart';
import '../models/momo_sms_sync_status.dart';
import '../repositories/momo_sms_sync_status_repository.dart';

final momoSmsSyncStatusRepositoryProvider =
    Provider<MomoSmsSyncStatusRepository>((ref) {
      return MomoSmsSyncStatusRepository(
        client: ref.read(supabaseClientProvider),
      );
    });

final momoSmsSyncStatusProvider = FutureProvider.autoDispose<MomoSmsSyncStatus>(
  (ref) async {
    final userId = ref.watch(authProvider).user?.id;
    if (userId == null || userId.isEmpty) {
      return const MomoSmsSyncStatus();
    }

    final repository = ref.watch(momoSmsSyncStatusRepositoryProvider);
    return repository.loadStatus(userId);
  },
);

final momoSmsAccessSnapshotProvider =
    FutureProvider.autoDispose<AppAccessSnapshot>((ref) async {
      return ref
          .watch(appAccessServiceProvider)
          .getSnapshot(AppAccessPermission.sms);
    });
