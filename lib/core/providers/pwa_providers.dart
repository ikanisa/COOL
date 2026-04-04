import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pwa/pwa_bridge_service.dart';

final pwaBridgeServiceProvider = Provider<PwaBridgeService>((ref) {
  final service = createPwaBridgeService();
  ref.onDispose(service.dispose);
  return service;
});
