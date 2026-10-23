import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/env/app_env.dart';
import '../startup/collect_startup_controller.dart';
import 'collect_cloudflare_client.dart';
import 'collect_turnstile.dart';
import '../supabase/collect_supabase_configuration.dart';
export 'collect_cloudflare_client.dart';

/// A native session uses its own encrypted store and its own key. It cannot
/// replace or clear the protected account/financial snapshot namespace.
final class CollectNativeSessionStorage implements CollectAuthSessionStorage {
  const CollectNativeSessionStorage({
    MethodChannel? channel,
    this.ownerId = '00000000-0000-4000-8000-000000000001',
  }) : _channel = channel ?? const MethodChannel('collect/secure_auth_session');
  final MethodChannel _channel;
  final String ownerId;
  @override
  Future<String?> read() =>
      _channel.invokeMethod<String>('read', {'owner_id': ownerId});
  @override
  Future<void> write(String value) async {
    final saved = await _channel.invokeMethod<bool>('write', {
      'owner_id': ownerId,
      'value': value,
    });
    if (saved != true) {
      throw StateError('Protected sign-in storage is unavailable');
    }
  }

  @override
  Future<void> clear() async {
    final cleared = await _channel.invokeMethod<bool>('clear');
    if (cleared != true) {
      throw StateError('Protected sign-in storage is unavailable');
    }
  }
}

/// App entrypoints install the one initialized client. Never create a second
/// authentication client while an existing process owns its credential fence.
final collectBackendClientProvider = Provider<CollectCloudflareClient?>((ref) {
  if (!ref.watch(appEnvProvider).hasBackendConfig) return null;
  throw StateError('Collect backend must be initialized by the app entrypoint');
});

final _collectAuthStateProvider = StreamProvider<CollectAuthState>((ref) {
  final client = ref.watch(collectBackendClientProvider);
  return client?.auth.onAuthStateChange ??
      const Stream<CollectAuthState>.empty();
});

final collectAuthenticatedUserIdProvider = Provider<String?>((ref) {
  final client = ref.watch(collectBackendClientProvider);
  final state = ref.watch(_collectAuthStateProvider);
  if (state case AsyncData<CollectAuthState>(:final value)) {
    return value.session?.user.id;
  }
  return client?.auth.currentUser?.id;
});

Future<CollectCloudflareClient?> createCollectBackendClientFromEnvironment({
  AppEnv? environment,
  String surface = 'member',
}) async {
  final env = environment ?? AppEnv.fromEnvironment();
  if (!env.hasBackendConfig) return null;
  CollectCloudflareClient? client;
  try {
    if (!const {'cloudflare', 'supabase'}.contains(env.backend)) {
      throw ArgumentError('Unsupported Collect backend.');
    }
    final supabase = env.usesSupabase
        ? CollectSupabaseConfiguration.fromEnvironment(env)
        : null;
    if (supabase != null && surface != 'member') {
      throw ArgumentError(
        'Supabase Admin requires the cookie-authenticated entrypoint.',
      );
    }
    final challenge = CollectTurnstileChallenge(
      endpoint: supabase?.challengeEndpoint,
    );
    client = CollectCloudflareClient(
      supabase?.api.origin ?? env.apiUrl,
      surface: surface,
      captchaProvider: supabase != null && !env.authCaptchaEnabled
          ? null
          : challenge.acquire,
      cancelCaptcha: challenge.cancel,
      supabaseConfiguration: supabase,
      sessionStorage: kIsWeb
          ? CollectMemorySessionStorage()
          : CollectNativeSessionStorage(
              ownerId:
                  supabase?.storageOwner ??
                  '00000000-0000-4000-8000-000000000001',
            ),
    );
    await client.initialize();
    return client;
  } catch (_) {
    var retryAllowed = true;
    try {
      await client?.dispose();
    } catch (_) {
      retryAllowed = false;
    }
    throw CollectStartupFailure(retryAllowed: retryAllowed);
  }
}
