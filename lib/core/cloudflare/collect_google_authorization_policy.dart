import '../supabase/collect_supabase_configuration.dart';

const collectSupabaseGoogleCallbackOrigin =
    'https://platform-admin.collect.ikanisa.com';

const collectSupabaseGoogleQaCallbackOrigin =
    'https://admin-supabase-qa.collect.ikanisa.com';

bool collectSupabaseGoogleCallbackOriginAllowed(String origin) =>
    origin == collectSupabaseGoogleCallbackOrigin ||
    origin == collectSupabaseGoogleQaCallbackOrigin;

/// Select one callback authority from the configured API, never from a reply.
String? collectSupabaseGoogleCallbackOriginForApi(Uri api) {
  if (api.scheme != 'https' ||
      !api.hasAuthority ||
      api.userInfo.isNotEmpty ||
      api.fragment.isNotEmpty) {
    return null;
  }
  if (api.origin == collectSupabaseGoogleQaCallbackOrigin) {
    return collectSupabaseGoogleQaCallbackOrigin;
  }
  if (api.origin == collectSupabaseGoogleCallbackOrigin ||
      api.origin == 'https://rrlduytparvsjfmegalh.supabase.co') {
    return collectSupabaseGoogleCallbackOrigin;
  }
  return null;
}

/// Validate the configured authorize hop; never trust an origin from a reply.
bool collectGoogleAuthorizationUrlAllowed(
  Uri? candidate, {
  required bool usesSupabase,
  String supabaseCallbackOrigin = collectSupabaseGoogleCallbackOrigin,
  CollectSupabaseConfiguration? supabaseConfiguration,
}) {
  try {
    if (candidate == null ||
        !candidate.hasAuthority ||
        candidate.scheme != 'https' ||
        candidate.userInfo.isNotEmpty ||
        candidate.fragment.isNotEmpty) {
      return false;
    }
    if (!usesSupabase) {
      return candidate.host == 'accounts.google.com' &&
          candidate.path == '/o/oauth2/v2/auth';
    }
    final configuration = supabaseConfiguration;
    final callbackAllowed = configuration == null
        ? collectSupabaseGoogleCallbackOriginAllowed(supabaseCallbackOrigin)
        : configuration.googleCallbackOrigin == supabaseCallbackOrigin;
    final authorizationOrigin =
        configuration?.googleAuthorizationOrigin ??
        'https://rrlduytparvsjfmegalh.supabase.co';
    if (!callbackAllowed ||
        candidate.origin != authorizationOrigin ||
        candidate.path != '/auth/v1/authorize') {
      return false;
    }
    final query = candidate.queryParametersAll;
    const allowed = {
      'provider',
      'redirect_to',
      'code_challenge',
      'code_challenge_method',
      'scopes',
      'prompt',
    };
    if (query.keys.any((key) => !allowed.contains(key)) ||
        query.values.any((values) => values.length != 1) ||
        query['provider']?.single != 'google' ||
        query['code_challenge_method']?.single != 's256' ||
        !RegExp(
          r'^[A-Za-z0-9_-]{43}$',
        ).hasMatch(query['code_challenge']?.single ?? '') ||
        (query.containsKey('scopes') &&
            query['scopes']!.single != 'openid email profile') ||
        (query.containsKey('prompt') &&
            query['prompt']!.single != 'select_account')) {
      return false;
    }
    final redirect = Uri.tryParse(query['redirect_to']?.single ?? '');
    return redirect != null &&
        redirect.hasAuthority &&
        redirect.scheme == 'https' &&
        redirect.origin == supabaseCallbackOrigin &&
        redirect.path == '/functions/v1/collect-api/v1/auth/google/callback' &&
        redirect.userInfo.isEmpty &&
        redirect.fragment.isEmpty &&
        redirect.queryParametersAll.length == 1 &&
        redirect.queryParametersAll['state']?.length == 1 &&
        RegExp(
          r'^[A-Za-z0-9_-]{43}$',
        ).hasMatch(redirect.queryParameters['state'] ?? '');
  } on FormatException {
    return false;
  }
}
