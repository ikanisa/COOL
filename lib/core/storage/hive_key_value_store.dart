import 'package:hive_flutter/hive_flutter.dart';

import 'key_value_store.dart';

/// [KeyValueStore] implementation backed by a Hive [Box].
///
/// This is the current default implementation used during Phase A/B
/// of the Hive → Drift migration. Services receive this via Riverpod
/// and are unaware of the underlying storage backend.
class HiveKeyValueStore<T> implements KeyValueStore<T> {
  HiveKeyValueStore(this._box);

  final Box<T> _box;

  @override
  Future<T?> get(String key) async => _box.get(key);

  @override
  Future<void> put(String key, T value) => _box.put(key, value);

  @override
  Future<void> delete(String key) => _box.delete(key);

  @override
  Future<Map<String, T>> getAll() async {
    return Map<String, T>.fromEntries(
      _box.keys.cast<String>().map(
        (key) => MapEntry(key, _box.get(key) as T),
      ),
    );
  }

  @override
  Future<void> clear() => _box.clear().then((_) {});

  @override
  Future<bool> containsKey(String key) async => _box.containsKey(key);
}
