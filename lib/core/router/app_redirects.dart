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
  return location == AppRoutes.admin ||
      location.startsWith('${AppRoutes.admin}/');
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
  String? sessionPhone,
  String? pendingRedirect,
}) {
  final isAuthRoute = _authRoutes.contains(location);
  final isAdminRoute = _isAdminRoute(location);
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

  if (isAdminRoute && !isAdmin) {
    return AppRoutes.home;
  }

  if (location == AppRoutes.splash || isAuthRoute) {
    return redirectTarget ?? AppRoutes.home;
  }

  return null;
}
