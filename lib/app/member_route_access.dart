part of 'router.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _CollectRouterRefresh();
  final memberAccess = _MemberRouteAccess();
  ref.listen(collectAuthenticatedUserIdProvider, (_, _) => refresh.notify());
  ref.listen(
    collectRepositoryProvider.select(
      (state) => (
        state.currentProfile?.id,
        state.currentProfile?.countryCode,
        state.isLoading,
        state.lastSuccessfulSyncAt != null,
        state.usingStaleCache,
        state.memberScopeUncertain,
      ),
    ),
    (_, _) => refresh.notify(),
  );

  final router = createAppRouter(
    refreshListenable: refresh,
    routeRedirect: (route) => memberAccess.redirect(
      route.uri,
      ref.read(collectRepositoryProvider),
      liveOwner: ref.read(collectBackendClientProvider)?.auth.currentUser?.id,
    ),
  );

  void observeNavigation() => memberAccess.observeNavigation(router);
  router.routeInformationProvider.addListener(observeNavigation);
  ref.onDispose(() {
    router.routeInformationProvider.removeListener(observeNavigation);
    router.dispose();
    refresh.dispose();
  });
  return router;
});

class _MemberRouteAccess {
  static const _privacyRequestPath = '/settings/account/delete';

  String? _privacyRouteOwner;
  bool _privacyRouteInvalidated = false;
  Object? _lastPrivacyNavigation;

  String? redirect(Uri uri, CollectState collectState, {String? liveOwner}) {
    final profileOwner = collectState.currentProfile?.id;
    if (uri.path == _privacyRequestPath) {
      if (_privacyRouteInvalidated) return '/auth';
      if (_privacyRouteOwner != null &&
          (liveOwner != _privacyRouteOwner ||
              (profileOwner != _privacyRouteOwner &&
                  !collectState.isLoading))) {
        _privacyRouteInvalidated = true;
        _privacyRouteOwner = null;
        return '/auth';
      }
      if (profileOwner != null && profileOwner == liveOwner) {
        _privacyRouteOwner = profileOwner;
      }
      // Keep the owned privacy form during a pending same-owner reread.
      // A denied completed read, logout or account switch removes the form.
      if (_privacyRouteOwner != null &&
          _privacyRouteOwner == liveOwner &&
          (profileOwner == _privacyRouteOwner || collectState.isLoading)) {
        return null;
      }
      _privacyRouteOwner = null;
    }
    return collectAuthenticationRedirect(
      uri: uri,
      hasProfile: collectState.currentProfile != null,
      isLoading:
          collectState.isLoading &&
          (profileOwner == null ||
              profileOwner != liveOwner ||
              collectState.lastSuccessfulSyncAt == null ||
              collectState.usingStaleCache ||
              collectState.memberScopeUncertain),
    );
  }

  // Auth refreshes can reparse a departed owner's request before the route
  // information catches up. Only a fresh navigation from outside this page
  // admits a new form for the active account.
  void observeNavigation(GoRouter router) {
    final information = router.routeInformationProvider.value;
    final navigation = information.state;
    if (information.uri.path != _privacyRequestPath ||
        navigation is! RouteInformationState ||
        navigation.type == NavigatingType.restore ||
        identical(navigation, _lastPrivacyNavigation)) {
      return;
    }
    _lastPrivacyNavigation = navigation;
    if (router.routerDelegate.currentConfiguration.uri.path !=
        _privacyRequestPath) {
      _privacyRouteOwner = null;
      _privacyRouteInvalidated = false;
    }
  }
}

String? collectAuthenticationRedirect({
  required Uri uri,
  required bool hasProfile,
  required bool isLoading,
}) {
  final isHeldSplash =
      uri.path == '/' && uri.queryParameters['holdSplash'] == '1';

  if (isLoading) {
    if (isHeldSplash) return null;
    return Uri(
      path: '/',
      queryParameters: {'holdSplash': '1', 'next': uri.toString()},
    ).toString();
  }

  if (isHeldSplash) {
    final next = _safeInternalRoute(uri.queryParameters['next']);
    if (hasProfile) return next?.toString() ?? '/home';
    if (next != null && _isPublicUnauthenticatedPath(next.path)) {
      return next.toString();
    }
    return '/auth';
  }

  if (hasProfile) {
    if (uri.path == '/') return '/home';
    if (uri.path == '/auth') {
      return _safeInternalRoute(uri.queryParameters['next'])?.toString() ??
          '/home';
    }
    return null;
  }

  if (uri.path == '/') return '/auth';
  if (!_isPublicUnauthenticatedPath(uri.path)) return '/auth';
  return null;
}

bool _isPublicUnauthenticatedPath(String path) {
  if (path == '/' ||
      path == '/auth' ||
      path == '/groups' ||
      path == '/contribute' ||
      path.startsWith('/c/')) {
    return true;
  }
  if (path == '/groups/create' ||
      path == '/groups/scan' ||
      path == '/groups/join') {
    return false;
  }
  return RegExp(r'^/groups/[^/]+(?:/contribute|/share)?$').hasMatch(path);
}

Uri? _safeInternalRoute(String? rawRoute) {
  if (rawRoute == null || rawRoute.isEmpty) return null;
  final route = Uri.tryParse(rawRoute);
  if (route == null ||
      route.hasScheme ||
      route.hasAuthority ||
      !route.path.startsWith('/') ||
      route.path.startsWith('//') ||
      route.path == '/') {
    return null;
  }
  return route;
}

class _CollectRouterRefresh extends ChangeNotifier {
  bool _scheduled = false;
  bool _disposed = false;

  void notify() {
    if (_disposed) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_scheduled) return;
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduled = false;
        if (!_disposed) notifyListeners();
      });
      WidgetsBinding.instance.ensureVisualUpdate();
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
