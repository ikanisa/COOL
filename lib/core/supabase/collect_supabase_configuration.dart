import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../app/env/app_env.dart';
import 'collect_deployment_profile.dart';
export 'collect_deployment_profile.dart';

/// Compile-time opt-in to the Supabase-backed Collect compatibility protocol.
/// Auth stays server-owned; this is never a second SDK session or token store.
final class CollectSupabaseConfiguration {
  factory CollectSupabaseConfiguration.fromEnvironment(AppEnv env) {
    final project = _origin(env.supabaseUrl);
    final api = _origin(
      env.supabaseApiUrl.isEmpty ? env.supabaseUrl : env.supabaseApiUrl,
    );
    final adminApi = env.supabaseAdminApiUrl.isEmpty
        ? null
        : _origin(env.supabaseAdminApiUrl);
    final publishableKey = env.supabasePublishableKey;
    final profile = CollectDeploymentProfile.parse(
      env.deploymentProfile,
      env.deploymentProfileSha256,
    );
    if (project.origin != CollectDeploymentProfile.managedProject) {
      throw ArgumentError('Supabase requires the Collect Cloud project.');
    }
    if (profile == null &&
        (!_supabaseApiOrigins.contains(api.origin) ||
            (adminApi != null &&
                !_supabaseApiOrigins.contains(adminApi.origin)))) {
      throw ArgumentError('Supabase requires an approved Collect API origin.');
    }
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
    if (profile != null &&
        (project.origin != profile.supabaseOrigin ||
            api.origin != profile.memberApiOrigin ||
            adminApi?.origin != profile.adminOrigin ||
            env.publicUrl != profile.publicOrigin ||
            env.adminAppUrl != profile.adminOrigin ||
            env.environmentName != profile.environment)) {
      throw ArgumentError('Collect origins must match the deployment profile.');
    }
    final issuer = '${project.origin}/auth/v1';
    if (env.supabaseAuthIssuer.isNotEmpty && env.supabaseAuthIssuer != issuer) {
      throw ArgumentError('Collect Auth must use the public Supabase issuer.');
    }
    return CollectSupabaseConfiguration._(
      project,
      api,
      adminApi,
      publishableKey,
      profile,
    );
  }

  const CollectSupabaseConfiguration._(
    this.project,
    this.api,
    this.adminApi,
    this.publishableKey,
    this.deploymentProfile,
  );

  final Uri project;
  final Uri api;
  final Uri? adminApi;
  final String publishableKey;
  final CollectDeploymentProfile? deploymentProfile;
  String get authIssuer => '${project.origin}/auth/v1';
  String get googleAuthorizationOrigin => project.origin;
  String? get googleCallbackOrigin {
    if (deploymentProfile case final profile?) {
      return profile.googleCallbackOrigin;
    }
    if (api.origin == 'https://admin-supabase-qa.collect.ikanisa.com') {
      return api.origin;
    }
    if (api.origin == project.origin ||
        api.origin == 'https://platform-admin.collect.ikanisa.com') {
      return 'https://platform-admin.collect.ikanisa.com';
    }
    return null;
  }

  static const memberPrefix = '/functions/v1/collect-api/';
  static const _supabaseApiOrigins = {
    CollectDeploymentProfile.managedProject,
    'https://collect.ikanisa.com',
    'https://admin.collect.ikanisa.com',
    'https://platform-admin.collect.ikanisa.com',
    'https://admin-supabase-qa.collect.ikanisa.com',
  };

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

  static Uri _origin(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        value != value.trim() ||
        uri.host.isEmpty ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        (uri.hasPort && uri.port != 443)) {
      throw ArgumentError('Supabase URL must be an HTTPS origin.');
    }
    return uri.replace(path: '/');
  }
}
