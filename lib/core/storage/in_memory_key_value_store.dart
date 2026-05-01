import 'key_value_store.dart';

/// In-memory [KeyValueStore] for unit and widget tests.
///
/// No I/O, no temp directories, no setup — just a [Map].
class InMemoryKeyValueStore<T> implements KeyValueStore<T> {
  final Map<String, T> _data = {};

  @override
  Future<T?> get(String key) async => _data[key];

  @override
  Future<void> put(String key, T value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<Map<String, T>> getAll() async => Map.unmodifiable(_data);

  @override
  Future<void> clear() async => _data.clear();

  @override
  Future<bool> containsKey(String key) async => _data.containsKey(key);

  /// Number of entries — useful in test assertions.
  int get length => _data.length;

  /// Whether the store is empty — useful in test assertions.
  bool get isEmpty => _data.isEmpty;
}
