import '../router/app_routes.dart';

abstract final class DeepLinkConfig {

  static const _legacyHosts = <String>{
    'cool.app',
    'www.cool.app',
    'cool.ikanisa.com',
    'www.cool.ikanisa.com',
  };
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
        segments.length < 2
            ? AppRoutes.contributionCircles
            : AppRoutes.contributionCircleDetailLocation(segments[1]),
      'home' => AppRoutes.home,
      'momo' => _momoRouteForSegments(segments, uri),
      'biopay-tab' => AppRoutes.biopayHome,
      'profile' => AppRoutes.profile,
      'match' => AppRoutes.home,
      'initiative' => AppRoutes.home,
      'club' => AppRoutes.home,
      'shop' => AppRoutes.home,
      'status' => AppRoutes.profile,
      _ => null,
    };

    if (route == null || uri.queryParameters.isEmpty) {
      return route;
    }

    return Uri(path: route, queryParameters: uri.queryParameters).toString();
  }

  static String _momoRouteForSegments(List<String> segments, Uri uri) {
    if (segments.length == 1) {
      return AppRoutes.biopayHome;
    }

    return switch (segments[1].toLowerCase()) {
      'biopay' => switch (segments.length > 2
          ? segments[2].toLowerCase()
          : '') {
        'register' => AppRoutes.biopayRegister,
        'scan' => AppRoutes.biopayScan,
        'nfc' => AppRoutes.biopayNfc,
        _ => AppRoutes.biopayHome,
      },
      _ => AppRoutes.biopayHome,
    };
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
        normalizedHost == 'www.$primaryHost' ||
        _legacyHosts.contains(normalizedHost);
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
