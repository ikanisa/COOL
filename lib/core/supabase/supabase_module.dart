import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/env/app_env.dart';

/// Keeps the renewable session on-device until explicit sign-out. Access and
/// refresh tokens remain subject to normal server revocation and rotation.
const collectDurableAuthOptions = FlutterAuthClientOptions(
  autoRefreshToken: true,
  persistSession: true,
);

final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  final env = ref.watch(appEnvProvider);
  if (!env.hasSupabaseConfig) {
    return null;
  }
  return SupabaseClient(env.supabaseUrl, env.supabaseAnonKey);
});

Future<SupabaseClient?> createSupabaseClientFromEnvironment({
  AppEnv? environment,
}) async {
  final env = environment ?? AppEnv.fromEnvironment();
  if (!env.hasSupabaseConfig) {
    return null;
  }
  final supabase = await Supabase.initialize(
    url: env.supabaseUrl,
    publishableKey: env.supabaseAnonKey,
    authOptions: collectDurableAuthOptions,
  );
  return supabase.client;
}
