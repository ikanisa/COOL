import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../services/app_access_service.dart';

/// Central [AppAccessService] provider.
///
/// All call sites that previously used `AppAccessService.instance` should
/// instead obtain the service through this provider.
final appAccessServiceProvider = Provider<AppAccessService>((ref) {
  return AppAccessService(openBox: Hive.openBox<bool>);
});
