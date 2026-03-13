import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/hive_runtime.dart';

/// Central provider for Hive box access. Override in tests with
/// a fake in-memory implementation.
final hiveOpenBoxProvider = Provider<OpenHiveBox<dynamic>>((ref) {
  return openHiveBox<dynamic>;
});

final hiveBoolBoxProvider = Provider<OpenHiveBox<bool>>((ref) {
  return openHiveBox<bool>;
});

final hiveStringBoxProvider = Provider<OpenHiveBox<String>>((ref) {
  return openHiveBox<String>;
});
