import '../../features/admin/models/admin_workspace_access.dart';
import '../../features/auth/providers/auth_provider.dart';
import 'app_routes.dart';

export 'app_routes.dart';

const _authRoutes = {
  AppRoutes.splash,
  AppRoutes.onboarding,
  AppRoutes.otp,
  AppRoutes.otpVerify,
};

bool _isAdminRoute(String location) {
  final path = _locationPath(location);
  return path == AppRoutes.admin || path.startsWith('${AppRoutes.admin}/');
}

const _platformAdminRoutes = {
  AppRoutes.adminPlatform,
  AppRoutes.adminUsers,
  AppRoutes.adminPartners,
  AppRoutes.adminServices,
  AppRoutes.adminQuickActions,
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

bool _isRayonAdminRoute(String location) {
  final path = _locationPath(location);
  return path == AppRoutes.adminRayon ||
      path.startsWith('${AppRoutes.adminRayon}/');
}

String? _adminPartnerWorkspaceId(String location) {
  final segments = Uri.parse(_locationPath(location)).pathSegments;
  if (segments.length < 3) {
    return null;
  }
  if (segments[0] != 'admin' || segments[1] != 'partners') {
    return null;
  }
  final partnerId = segments[2].trim();
  return partnerId.isEmpty ? null : partnerId;
}

String? _adminBankWorkspaceId(String location) {
  final segments = Uri.parse(_locationPath(location)).pathSegments;
  if (segments.length < 3) {
    return null;
  }
  if (segments[0] != 'admin' || segments[1] != 'banks') {
    return null;
  }
  final partnerId = segments[2].trim();
  return partnerId.isEmpty ? null : partnerId;
}

String? _normalizeRedirectTarget(String? target) {
  if (target == null) {
    return null;
  }

  final trimmed = target.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final uri = Uri.tryParse(trimmed);
  final path = uri?.path ?? trimmed;
  if (path.isEmpty || path == AppRoutes.splash || _authRoutes.contains(path)) {
    return null;
  }

  if (path == '/basket') {
    return AppRoutes.home;
  }

  return trimmed.startsWith('/') ? trimmed : '/$trimmed';
}

String? resolveAppRedirect({
  required String location,
  String? requestedLocation,
  required bool hasSession,
  required bool hasProfile,
  AuthProfileRestoreState profileRestoreState =
      AuthProfileRestoreState.available,
  bool isAdmin = false,
  AdminWorkspaceAccess? adminAccess,
  bool hasRayonAdminAccess = false,
  String? sessionPhone,
  String? pendingRedirect,
}) {
  final isAuthRoute = _authRoutes.contains(location);
  final isAdminRoute = _isAdminRoute(location);
  final adminScope =
      adminAccess ?? AdminWorkspaceAccess(hasPlatformAccess: isAdmin);
  final hasAnyAdminAccess = adminScope.hasAnyAdminAccess;
  final redirectSource =
      pendingRedirect ?? (isAuthRoute ? null : requestedLocation ?? location);
  final redirectTarget = _normalizeRedirectTarget(redirectSource);
  final isProfileRestoreBlocked =
      profileRestoreState == AuthProfileRestoreState.pending ||
      profileRestoreState == AuthProfileRestoreState.failed;

  if (hasSession && isProfileRestoreBlocked) {
    if (location == AppRoutes.splash) {
      return null;
    }
    return AppRoutes.splashLocation(redirect: redirectTarget);
  }

  if (!hasSession) {
    if (location == AppRoutes.splash) {
      return AppRoutes.onboardingLocation(redirect: redirectTarget);
    }
    return isAuthRoute
        ? null
        : AppRoutes.onboardingLocation(
            redirect: _normalizeRedirectTarget(requestedLocation ?? location),
          );
  }

  if (isAdminRoute) {
    final path = _locationPath(location);
    if (!hasAnyAdminAccess) {
      return AppRoutes.home;
    }

    if (_isPlatformAdminRoute(path) && !adminScope.hasPlatformAccess) {
      return AppRoutes.admin;
    }

    final partnerId = _adminPartnerWorkspaceId(path);
    if (partnerId != null && !adminScope.canAccessPartnerId(partnerId)) {
      return AppRoutes.admin;
    }

    final bankId = _adminBankWorkspaceId(path);
    if (bankId != null && !adminScope.canAccessBankId(bankId)) {
      return AppRoutes.admin;
    }

    if (_isRayonAdminRoute(path) &&
        !adminScope.hasPlatformAccess &&
        !adminScope.hasPartnerAdminAccess &&
        !hasRayonAdminAccess) {
      return AppRoutes.admin;
    }

    if (path != AppRoutes.admin &&
        !_isPlatformAdminRoute(path) &&
        !_isRayonAdminRoute(path) &&
        partnerId == null &&
        bankId == null &&
        !adminScope.hasPlatformAccess) {
      return AppRoutes.admin;
    }
  }

  if (location == AppRoutes.splash || isAuthRoute) {
    return redirectTarget ?? AppRoutes.home;
  }

  return null;
}
