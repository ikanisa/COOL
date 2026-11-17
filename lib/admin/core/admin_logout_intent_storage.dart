/// Browser-persistent sign-out intent contains public-session fingerprints only.
/// It never contains a cookie, CSRF value, password, token or account identity.
abstract interface class AdminLogoutIntentStorage {
  Set<String> readPending();
  void add(String sessionFingerprint);
  void remove(String sessionFingerprint);
}

/// Injectable shared storage for isolated tests and non-browser callers.
class MemoryAdminLogoutIntentStorage implements AdminLogoutIntentStorage {
  final _pending = <String>{};

  @override
  Set<String> readPending() => Set.unmodifiable(_pending);

  @override
  void add(String sessionFingerprint) => _pending.add(sessionFingerprint);

  @override
  void remove(String sessionFingerprint) => _pending.remove(sessionFingerprint);
}
