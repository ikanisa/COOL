/// Storage contains confirmation intent only, never authentication material.
abstract interface class AdminPendingAttemptStorage {
  String? read(String key);
  void write(String key, String value);
  void remove(String key);
}

/// Injectable storage for native tests. Reuse one instance to simulate reloads.
class MemoryAdminPendingAttemptStorage implements AdminPendingAttemptStorage {
  final values = <String, String>{};
  @override
  String? read(String key) => values[key];
  @override
  void write(String key, String value) => values[key] = value;
  @override
  void remove(String key) => values.remove(key);
}
