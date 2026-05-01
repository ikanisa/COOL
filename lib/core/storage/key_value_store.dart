/// Platform-agnostic key-value store interface.
///
/// Abstracts storage backends so services don't couple directly to
/// Hive or Drift. Swap implementations without touching service code.
///
/// Implementations:
/// - [HiveKeyValueStore] — wraps existing Hive boxes (current default)
/// - [DriftKeyValueStore] — wraps Drift tables (migration target)
/// - [InMemoryKeyValueStore] — synchronous, no I/O (testing)
library;

/// A typed key-value store.
///
/// All operations are async to accommodate both in-memory and
/// disk-backed implementations.
abstract class KeyValueStore<T> {
  /// Retrieve a value by [key]. Returns `null` if absent.
  Future<T?> get(String key);

  /// Store [value] under [key]. Overwrites if already present.
  Future<void> put(String key, T value);

  /// Delete the entry for [key]. No-op if absent.
  Future<void> delete(String key);

  /// Retrieve all key-value pairs.
  Future<Map<String, T>> getAll();

  /// Remove all entries.
  Future<void> clear();

  /// Returns `true` if [key] exists.
  Future<bool> containsKey(String key);
}
