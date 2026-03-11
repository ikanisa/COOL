import 'package:firebase_core/firebase_core.dart';

/// Thin wrapper that exposes whether Firebase was successfully initialized.
///
/// Since [main] now initializes Firebase before `runApp`, this service
/// simply checks [Firebase.apps] and caches the result so downstream
/// services can degrade gracefully when Firebase is unavailable.
class FirebaseBootstrapService {
  Future<bool> initialize() async {
    if (_didCheck) {
      return _isAvailable;
    }

    _didCheck = true;
    _isAvailable = Firebase.apps.isNotEmpty;
    return _isAvailable;
  }

  bool get isAvailable => _isAvailable;

  bool _didCheck = false;
  bool _isAvailable = false;
}
