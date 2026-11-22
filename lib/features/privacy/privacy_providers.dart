import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../app/env/app_env.dart';
import '../../core/cloudflare/cloudflare_module.dart';
import '../../core/cloudflare/collect_turnstile.dart';
import 'privacy_request_controller.dart';
import 'privacy_session.dart';
import 'privacy_transport.dart';

// A same-user replacement session must also renew the visible review status;
// the subject-ID provider alone can suppress that change as an equal value.
final privacyAuthStateProvider = StreamProvider.autoDispose<CollectAuthState>((
  ref,
) {
  final client = ref.watch(collectBackendClientProvider);
  return client?.auth.onAuthStateChange ??
      const Stream<CollectAuthState>.empty();
});

/// Staged integration points. Screens must cancel/dispose their controller,
/// and logout initiation must invalidate the authority before any await.
final privacySessionAuthorityProvider =
    Provider<CollectPrivacySessionAuthority?>((ref) {
      final auth = ref.watch(collectBackendClientProvider)?.auth;
      if (auth == null) return null;
      final authority = CollectPrivacySessionAuthority(auth);
      ref.onDispose(() => unawaited(authority.dispose()));
      return authority;
    });

final privacyRequestTransportProvider = Provider<PrivacyRequestTransport?>((
  ref,
) {
  final env = ref.watch(appEnvProvider);
  if (!env.hasBackendConfig) return null;
  final authority = ref.watch(privacySessionAuthorityProvider);
  if (authority == null) return null;
  final client = http.Client();
  final supabase = ref
      .watch(collectBackendClientProvider)
      ?.supabaseConfiguration;
  final challenge = CollectTurnstileChallenge(
    endpoint: supabase?.challengeEndpoint,
  );
  ref.onDispose(client.close);
  ref.onDispose(challenge.cancel);
  return CollectPrivacyRequestTransport(
    httpClient: client,
    apiUrl: supabase?.api.origin ?? env.apiUrl,
    supabaseConfiguration: supabase,
    captchaRequired: supabase == null || env.authCaptchaEnabled,
    captchaProvider: supabase != null && !env.authCaptchaEnabled
        ? null
        : challenge.acquire,
    cancelCaptcha: challenge.cancel,
    isSessionCurrent: (session) {
      try {
        return authority.capture().sameFence(session);
      } catch (_) {
        return false;
      }
    },
  );
});

final privacyRequestControllerProvider =
    Provider.autoDispose<PrivacyRequestController?>((ref) {
      final subjectId = ref.watch(collectAuthenticatedUserIdProvider);
      final authority = ref.watch(privacySessionAuthorityProvider);
      final transport = ref.watch(privacyRequestTransportProvider);
      if (subjectId == null || authority == null || transport == null) {
        return null;
      }
      final controller = PrivacyRequestController(
        authority: authority,
        transport: transport,
        subjectId: subjectId,
      );
      ref.onDispose(controller.dispose);
      return controller;
    });
