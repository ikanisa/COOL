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

/// The live session identity used to bind interrupted invitations. Device
/// evidence harnesses override this provider with a synthetic UUID; release
/// builds always read the current Supabase Auth user.
final _collectAuthStateProvider = StreamProvider<AuthState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client?.auth.onAuthStateChange ?? const Stream<AuthState>.empty();
});

final collectAuthenticatedUserIdProvider = Provider<String?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final authState = ref.watch(_collectAuthStateProvider);
  if (authState case AsyncData<AuthState>(:final value)) {
    return value.session?.user.id;
  }
  return client?.auth.currentUser?.id;
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
