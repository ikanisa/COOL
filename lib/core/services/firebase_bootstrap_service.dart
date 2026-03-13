import 'package:cool_app/core/config/env_config.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';

class FirebaseBootstrapService {
  static FirebaseOptions? currentOptions() {
    try {
      return DefaultFirebaseOptions.currentPlatformForFlavor(EnvConfig.flavor);
    } on UnsupportedError {
      return null;
    } on StateError catch (error) {
      debugPrint('[Firebase] ⚠️ $error');
      return null;
    }
  }

  static Future<void> ensureInitialized() async {
    if (Firebase.apps.isNotEmpty) {
      return;
    }

    final options = currentOptions();
    if (options == null) {
      debugPrint(
        '[Firebase] ⚠️ Unsupported platform for explicit Firebase bootstrap.',
      );
      return;
    }

    await Firebase.initializeApp(options: options);
  }

  Future<bool> initialize() async {
    if (_didCheck) {
      return _isAvailable;
    }

    _didCheck = true;
    try {
      await ensureInitialized();
      _isAvailable = Firebase.apps.isNotEmpty;
    } catch (error) {
      _isAvailable = false;
      debugPrint('[Firebase] ❌ Bootstrap failed: $error');
    }
    return _isAvailable;
  }

  bool get isAvailable => _isAvailable;

  bool _didCheck = false;
  bool _isAvailable = false;
}
