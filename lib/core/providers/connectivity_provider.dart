import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Exposes a real-time `bool` indicating whether the device has any
/// network connectivity (Wi-Fi, mobile data, ethernet, etc.).
///
/// This is a lightweight heuristic — it checks if the *interface* is up,
/// not if the internet is actually reachable.  Good enough for a
/// non-blocking "you're offline" banner.
final isOfflineProvider = StreamProvider<bool>((ref) {
  final connectivity = Connectivity();

  // Seed with the current state.
  final controller = StreamController<bool>();

  Future<void> emitCurrent() async {
    final results = await connectivity.checkConnectivity();
    controller.add(_isOffline(results));
  }

  emitCurrent();

  final subscription = connectivity.onConnectivityChanged.listen((results) {
    controller.add(_isOffline(results));
  });

  ref.onDispose(() {
    subscription.cancel();
    controller.close();
  });

  return controller.stream;
});

bool _isOffline(List<ConnectivityResult> results) {
  return results.isEmpty ||
      (results.length == 1 && results.first == ConnectivityResult.none);
}
