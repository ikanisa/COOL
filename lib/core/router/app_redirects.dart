import '../../features/admin/models/admin_workspace_access.dart';
import '../../features/auth/providers/auth_provider.dart';
import 'app_routes.dart';

export 'app_routes.dart';

const _adminBanksRoutePrefix = '/admin/banks';

bool _isAdminRoute(String location) {
  final path = _locationPath(location);
  return path == AppRoutes.admin || path.startsWith('${AppRoutes.admin}/');
}

const _platformAdminRoutes = {
  AppRoutes.adminPlatform,
  AppRoutes.adminUsers,
  AppRoutes.adminAppConfig,
  AppRoutes.adminOperations,
};

String _locationPath(String location) {
  final uri = Uri.tryParse(location);
  final path = uri?.path ?? location;
  return path.trim().isEmpty ? location.trim() : path;
}

bool _isPlatformAdminRoute(String location) {
  return _platformAdminRoutes.contains(_locationPath(location));
}



bool _isBankWorkspaceRoute(String location) {
  final path = _locationPath(location);
  return path == _adminBanksRoutePrefix ||
      path.startsWith('$_adminBanksRoutePrefix/');
}

String? _scopedWorkspaceId(String location) {
  final segments = _locationPath(
    location,
  ).split('/').where((segment) => segment.isNotEmpty).toList(growable: false);
  return segments.length >= 3 ? segments[2] : null;
}

String? _sanitizeRedirectTarget(String? location) {
  final trimmed = location?.trim();
  if (trimmed == null || trimmed.isEmpty || !trimmed.startsWith('/')) {
    return null;
  }

  final uri = Uri.tryParse(trimmed);
  final path = uri?.path ?? trimmed;
  if (path.trim().isEmpty || path == AppRoutes.splash) {
    return null;
  }

  return trimmed;
}

/// Resolves where the user should be redirected based on auth and role state.
///
/// With anonymous auth, the splash screen handles sign-in. Once a session
/// exists, the user goes to `/home`. Admin route guards remain unchanged.
String? resolveAppRedirect({
  required String location,
  String? requestedLocation,
  required bool hasSession,
  required bool hasProfile,
  AuthProfileRestoreState profileRestoreState =
      AuthProfileRestoreState.available,
  bool isAdmin = false,
  AdminWorkspaceAccess? adminAccess,
  String? sessionPhone,
  String? pendingRedirect,
}) {
  final isAdminRoute = _isAdminRoute(location);
  final adminScope =
      adminAccess ?? AdminWorkspaceAccess(hasPlatformAccess: isAdmin);
  final hasAnyAdminAccess = adminScope.hasAnyAdminAccess;
  final isProfileRestoreBlocked =
      profileRestoreState == AuthProfileRestoreState.pending ||
      profileRestoreState == AuthProfileRestoreState.failed;
  final redirectTarget =
      _sanitizeRedirectTarget(pendingRedirect) ??
      _sanitizeRedirectTarget(requestedLocation) ??
      _sanitizeRedirectTarget(location);

  // While restoring profile, keep user on splash.
  if (hasSession && isProfileRestoreBlocked) {
    if (location == AppRoutes.splash) {
      return null;
    }
    return AppRoutes.splashLocation(redirect: redirectTarget);
  }

  // No session → stay on splash (it will auto-sign-in anonymously).
  if (!hasSession) {
    if (location == AppRoutes.splash) {
      return null;
    }
    return AppRoutes.splashLocation(redirect: redirectTarget);
  }

  // Session exists — admin route guards.
  if (isAdminRoute) {
    final path = _locationPath(location);
    if (!hasAnyAdminAccess) {
      return AppRoutes.home;
    }

    if (_isPlatformAdminRoute(path) && !adminScope.hasPlatformAccess) {
      return AppRoutes.admin;
    }



    if (_isBankWorkspaceRoute(path)) {
      final bankId = _scopedWorkspaceId(path);
      if (bankId == null || !adminScope.canAccessBankId(bankId)) {
        return AppRoutes.admin;
      }
    }

    if (path != AppRoutes.admin &&
        !_isPlatformAdminRoute(path) &&
        !_isBankWorkspaceRoute(path) &&
        !adminScope.hasPlatformAccess) {
      return AppRoutes.admin;
    }
  }

  // Session exists, on splash → go to home.
  if (location == AppRoutes.splash) {
    return redirectTarget ?? AppRoutes.home;
  }

  return null;
}
