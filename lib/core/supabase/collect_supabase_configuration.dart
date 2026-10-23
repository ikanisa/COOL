import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../app/env/app_env.dart';

/// Compile-time opt-in to the Supabase-backed Collect compatibility protocol.
/// Auth stays server-owned; this is never a second SDK session or token store.
final class CollectSupabaseConfiguration {
  CollectSupabaseConfiguration.fromEnvironment(AppEnv env)
    : project = _origin(env.supabaseUrl),
      api = _origin(
        env.supabaseApiUrl.isEmpty ? env.supabaseUrl : env.supabaseApiUrl,
      ),
      adminApi = env.supabaseAdminApiUrl.isEmpty
          ? null
          : _origin(env.supabaseAdminApiUrl),
      publishableKey = env.supabasePublishableKey {
    if (env.backend != 'supabase' ||
        !RegExp(
          r'^sb_publishable_[A-Za-z0-9_-]{10,300}$',
        ).hasMatch(publishableKey)) {
      throw ArgumentError(
        'Supabase requires an explicit origin and publishable key.',
      );
    }
    if (env.authCaptchaEnabled && api.host.endsWith('.supabase.co')) {
      throw ArgumentError(
        'Supabase HTML verification requires a custom API domain.',
      );
    }
  }

  final Uri project;
  final Uri api;
  final Uri? adminApi;
  final String publishableKey;
  static const memberPrefix = '/functions/v1/collect-api/';
  static const adminPrefix = '/functions/v1/admin-api/api/admin/';

  Uri get challengeEndpoint =>
      api.replace(path: '${memberPrefix}v1/security/challenge');

  /// Every project receives a different protected native namespace. Switching
  /// provider/project cannot import an old session or replay its refresh token.
  String get storageOwner {
    final digest = sha256
        .convert(
          utf8.encode('collect-auth-session:v1:supabase:${project.origin}'),
        )
        .toString();
    return '${digest.substring(0, 8)}-${digest.substring(8, 12)}-4${digest.substring(13, 16)}-8${digest.substring(17, 20)}-${digest.substring(20, 32)}';
  }

  Uri adminRequest(String path, {required Uri browserOrigin}) {
    final target = adminApi;
    if (target == null || !_sameSite(target, browserOrigin)) {
      throw ArgumentError(
        'Supabase Admin requires an explicitly configured same-site API origin.',
      );
    }
    final uri = target.resolve('$adminPrefix$path');
    if (uri.origin != target.origin ||
        !uri.path.startsWith(adminPrefix) ||
        uri.fragment.isNotEmpty) {
      throw ArgumentError('Invalid Supabase Admin request.');
    }
    return uri;
  }

  static bool _sameSite(Uri a, Uri b) {
    if (a.scheme != b.scheme) return false;
    if (a.host == b.host) return true;
    return a.host.endsWith('.collect.ikanisa.com') &&
        b.host.endsWith('.collect.ikanisa.com');
  }

  static Uri _origin(String value) {
    final uri = Uri.tryParse(value);
    final loopback =
        uri != null &&
        const {'localhost', '127.0.0.1', '::1'}.contains(uri.host);
    if (uri == null ||
        value != value.trim() ||
        uri.host.isEmpty ||
        (uri.scheme != 'https' && !(loopback && uri.scheme == 'http')) ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        (uri.hasPort && !loopback && uri.port != 443)) {
      throw ArgumentError('Supabase URL must be an HTTPS origin.');
    }
    return uri.replace(path: '/');
  }
}
