import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/env/app_env.dart';

final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  final env = ref.watch(appEnvProvider);
  if (!env.hasSupabaseConfig) {
    return null;
  }
  return SupabaseClient(env.supabaseUrl, env.supabaseAnonKey);
});

Future<SupabaseClient?> createSupabaseClientFromEnvironment() async {
  final env = AppEnv.fromEnvironment();
  if (!env.hasSupabaseConfig) {
    return null;
  }
  final supabase = await Supabase.initialize(
    url: env.supabaseUrl,
    anonKey: env.supabaseAnonKey,
  );
  return supabase.client;
}
