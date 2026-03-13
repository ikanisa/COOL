import '../router/app_routes.dart';

abstract final class DeepLinkConfig {
  static const host = String.fromEnvironment(
    'COOL_DEEP_LINK_HOST',
    defaultValue: 'cool.app',
  );
  static const customScheme = 'cool';
  static const androidPackageId = String.fromEnvironment(
    'COOL_ANDROID_PACKAGE_ID',
    defaultValue: 'app.cool.mobile',
  );
  static const playStoreUrl = String.fromEnvironment(
    'COOL_PLAY_STORE_URL',
    defaultValue:
        'https://play.google.com/store/apps/details?id=app.cool.mobile',
  );
  static const appStoreUrl = String.fromEnvironment(
    'COOL_APP_STORE_URL',
    defaultValue: 'https://cool.app/download-ios/',
  );

  static Uri inviteUri(
    String inviteCode, {
    Map<String, String>? queryParameters,
  }) {
    return _httpsUri(
      '/invite/${inviteCode.trim().toUpperCase()}',
      queryParameters: queryParameters,
    );
  }

  // basketUri removed — /basket route no longer exists

  static Uri groupDetailUri(
    String groupId, {
    Map<String, String>? queryParameters,
  }) {
    return _httpsUri('/groups/$groupId', queryParameters: queryParameters);
  }

  static Uri matchUri(String matchId, {Map<String, String>? queryParameters}) {
    return _httpsUri('/match/$matchId', queryParameters: queryParameters);
  }

  static Uri initiativeUri(
    String initiativeId, {
    Map<String, String>? queryParameters,
  }) {
    return _httpsUri(
      '/initiative/$initiativeId',
      queryParameters: queryParameters,
    );
  }

  static Uri clubUri(String clubId, {Map<String, String>? queryParameters}) {
    return _httpsUri('/club/$clubId', queryParameters: queryParameters);
  }

  static Uri tripUri(String tripId, {Map<String, String>? queryParameters}) {
    return _httpsUri('/trip/$tripId', queryParameters: queryParameters);
  }

  static Uri shopProductUri(
    String productId, {
    Map<String, String>? queryParameters,
  }) {
    return _httpsUri('/shop/$productId', queryParameters: queryParameters);
  }

  static Uri statusUri(String userId, {Map<String, String>? queryParameters}) {
    return _httpsUri('/status/$userId', queryParameters: queryParameters);
  }

  static Uri customSchemeUriForRoute(String route) {
    final normalizedRoute = route.startsWith('/') ? route.substring(1) : route;
    return Uri.parse('$customScheme://$normalizedRoute');
  }

  static String? routeForUri(Uri uri) {
    if (!_supportsUri(uri)) {
      return null;
    }

    final segments = _normalizedSegments(uri);
    if (segments.isEmpty) {
      return null;
    }

    final route = switch (segments.first.toLowerCase()) {
      'basket' => AppRoutes.home, // legacy deep links redirect to home
      'invite' =>
        segments.length < 2 ? null : '/invite/${segments[1].toUpperCase()}',
      'groups' =>
        segments.length < 2 ? AppRoutes.groups : '/groups/${segments[1]}',
      'home' => AppRoutes.home,
      'momo' => AppRoutes.momo,
      'profile' => AppRoutes.profile,
      'mobility' =>
        segments.length >= 2 && segments[1] == 'trips'
            ? AppRoutes.mobilityTrips
            : AppRoutes.mobility,
      'match' => segments.length < 2 ? null : '/partners/rayon-sports/tickets',
      'initiative' =>
        segments.length < 2
            ? null
            : '/partners/rayon-sports/support/${segments[1]}',
      'club' =>
        segments.length < 2
            ? null
            : '/partners/rayon-sports/clubs/${segments[1]}',
      'trip' => AppRoutes.mobilityTrips,
      'shop' => AppRoutes.rayonShop,
      'status' => AppRoutes.profile,
      _ => null,
    };

    if (route == null || uri.queryParameters.isEmpty) {
      return route;
    }

    return Uri(path: route, queryParameters: uri.queryParameters).toString();
  }

  static bool _supportsUri(Uri uri) {
    if (uri.scheme == customScheme) {
      return true;
    }

    if (uri.scheme != 'https' && uri.scheme != 'http') {
      return false;
    }

    final normalizedHost = uri.host.toLowerCase();
    final primaryHost = host.toLowerCase();
    return normalizedHost == primaryHost ||
        normalizedHost == 'www.$primaryHost';
  }

  static List<String> _normalizedSegments(Uri uri) {
    if (uri.scheme == customScheme) {
      final segments = <String>[];
      if (uri.host.isNotEmpty) {
        segments.add(uri.host);
      }
      segments.addAll(uri.pathSegments.where((segment) => segment.isNotEmpty));
      return segments;
    }

    return uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
  }

  static Uri _httpsUri(String path, {Map<String, String>? queryParameters}) {
    return Uri.https(
      host,
      path,
      queryParameters == null || queryParameters.isEmpty
          ? null
          : queryParameters,
    );
  }
}
