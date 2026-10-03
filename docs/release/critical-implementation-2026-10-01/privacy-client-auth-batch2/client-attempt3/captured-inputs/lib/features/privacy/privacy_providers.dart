import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../app/env/app_env.dart';
import '../../core/supabase/supabase_module.dart';
import 'privacy_request_controller.dart';
import 'privacy_session.dart';
import 'privacy_transport.dart';

/// Staged integration points. Screens must cancel/dispose their controller,
/// and logout initiation must invalidate the authority before any await.
final privacySessionAuthorityProvider =
    Provider<GoTruePrivacySessionAuthority?>((ref) {
      final auth = ref.watch(supabaseClientProvider)?.auth;
      if (auth == null) return null;
      final authority = GoTruePrivacySessionAuthority(auth);
      ref.onDispose(() => unawaited(authority.dispose()));
      return authority;
    });

final privacyRequestTransportProvider = Provider<PrivacyRequestTransport?>((
  ref,
) {
  final env = ref.watch(appEnvProvider);
  if (!env.hasSupabaseConfig) return null;
  final client = http.Client();
  ref.onDispose(client.close);
  return SupabasePrivacyRequestTransport(
    httpClient: client,
    supabaseUrl: env.supabaseUrl,
    publishableKey: env.supabaseAnonKey,
    captchaRequired: env.authCaptchaEnabled,
  );
});

final privacyRequestControllerProvider =
    Provider.autoDispose<PrivacyRequestController?>((ref) {
      final authority = ref.watch(privacySessionAuthorityProvider);
      final transport = ref.watch(privacyRequestTransportProvider);
      if (authority == null || transport == null) return null;
      final controller = PrivacyRequestController(
        authority: authority,
        transport: transport,
      );
      ref.onDispose(controller.dispose);
      return controller;
    });
