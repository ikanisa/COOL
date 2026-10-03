import 'package:supabase_flutter/supabase_flutter.dart';

/// Per-page PKCE state. A reload requires starting authentication again.
final class CollectMemoryPkceStorage extends GotrueAsyncStorage {
  final Map<String, String> _values = {};

  @override
  Future<String?> getItem({required String key}) async => _values[key];

  @override
  Future<void> removeItem({required String key}) async => _values.remove(key);

  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }
}

FlutterAuthClientOptions collectAuthOptions({required bool browser}) => browser
    ? FlutterAuthClientOptions(
        autoRefreshToken: true,
        persistSession: false,
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: CollectMemoryPkceStorage(),
      )
    : const FlutterAuthClientOptions(
        autoRefreshToken: true,
        persistSession: true,
      );
