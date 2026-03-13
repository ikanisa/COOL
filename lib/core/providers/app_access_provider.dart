import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_access_service.dart';
import 'hive_providers.dart';

/// Central [AppAccessService] provider.
///
/// All app-layer call sites should obtain the service through this provider.
final appAccessServiceProvider = Provider<AppAccessService>((ref) {
  return AppAccessService(openBox: ref.read(hiveBoolBoxProvider));
});
