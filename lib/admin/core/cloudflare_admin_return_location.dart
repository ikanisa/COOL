/// Only an Admin-local protected URI can become a post-auth destination.
/// Reject external/protocol-relative URLs and account/setup routes so a query
/// parameter cannot redirect to another origin or replay an invitation secret.
String? cloudflareAdminReturnLocation(String? location) {
  if (location == null ||
      location.length > 2000 ||
      RegExp(r'[\x00-\x20\\]').hasMatch(location)) {
    return null;
  }
  final uri = Uri.tryParse(location);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.hasFragment ||
      !(uri.path == '/admin' || uri.path.startsWith('/admin/')) ||
      const {
        '/admin/login',
        '/admin/forgot-password',
        '/admin/setup',
        '/admin/session',
      }.contains(uri.path)) {
    return null;
  }
  return uri.toString();
}

/// A verification detour returns to fresh page reads. Only the existing opaque
/// request reference can cross this boundary; never forward a claim, code,
/// token, nested returnTo or action draft from arbitrary query parameters.
String? cloudflareAdminEmailVerificationReturnLocation(String? location) {
  final candidate = cloudflareAdminReturnLocation(location);
  if (candidate == null) return null;
  final uri = Uri.parse(candidate);
  if (uri.normalizePath().path != uri.path ||
      uri.pathSegments.any(
        (segment) =>
            segment == '.' ||
            segment == '..' ||
            RegExp(r'[\x00-\x20/\\]').hasMatch(segment),
      ) ||
      uri.path.startsWith('/admin/security/')) {
    return null;
  }
  final key = uri.path == '/admin/requests'
      ? uri.queryParametersAll['key']
      : null;
  return Uri(
    path: uri.path,
    queryParameters:
        key != null &&
            key.length == 1 &&
            RegExp(r'^[A-Za-z0-9._:-]{8,200}$').hasMatch(key.single)
        ? {'key': key.single}
        : null,
  ).toString();
}
