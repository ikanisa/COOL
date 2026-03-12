import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Central [SupabaseClient] provider.
///
/// Every repository and service that needs Supabase access should depend on
/// this provider rather than calling `Supabase.instance.client` directly.
/// This makes the dependency explicit and allows easy overriding in tests.
///
/// ```dart
/// final myRepoProvider = Provider<MyRepository>((ref) {
///   return MyRepository(client: ref.read(supabaseClientProvider));
/// });
/// ```
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});
