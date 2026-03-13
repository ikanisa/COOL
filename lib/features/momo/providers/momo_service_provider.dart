import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/hive_providers.dart';
import '../../../core/providers/supabase_client_provider.dart';
import '../../../core/services/momo_service.dart';

/// Central [MomoService] provider.
///
/// All call sites that previously used `MomoService.instance` should instead
/// obtain the service through this provider via `ref.read(momoServiceProvider)`.
final momoServiceProvider = Provider<MomoService>((ref) {
  return MomoService(
    client: ref.read(supabaseClientProvider),
    openBox: ref.read(hiveOpenBoxProvider),
  );
});
