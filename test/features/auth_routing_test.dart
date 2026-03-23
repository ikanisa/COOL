import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/router/app_redirects.dart';
import 'package:cool_app/features/admin/models/admin_workspace_access.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart';

/// QA-02: Auth Routing & Profile-Gating Regression Tests
///
/// Tests the pure [resolveAppRedirect] function to ensure every entry
/// state (unauthenticated, session-no-profile, fully-authenticated)
/// routes correctly under splash, deep link, and app resume scenarios.
///
/// CRITICAL INVARIANT: After OTP verification, users ALWAYS land on /home.
/// Profile completion is OPTIONAL and accessed from the Profile screen.
/// The router MUST NOT force users to /register.
void main() {
  group('Unauthenticated user', () {
    test('splash redirects to onboarding', () {
      final result = resolveAppRedirect(
        location: '/',
        hasSession: false,
        hasProfile: false,
      );
      expect(result, AppRoutes.onboarding);
    });

    test('onboarding stays on onboarding', () {
      final result = resolveAppRedirect(
        location: AppRoutes.onboarding,
        hasSession: false,
        hasProfile: false,
      );
      expect(result, isNull);
    });

    test('/home redirects to onboarding with redirect target', () {
      final result = resolveAppRedirect(
        location: AppRoutes.home,
        hasSession: false,
        hasProfile: false,
      );
      expect(result, isNotNull);
      expect(result, contains(AppRoutes.onboarding));
    });

    test('protected route /groups redirects to onboarding', () {
      final result = resolveAppRedirect(
        location: AppRoutes.groups,
        hasSession: false,
        hasProfile: false,
      );
      expect(result, isNotNull);
      expect(result, contains(AppRoutes.onboarding));
    });

    test('deep link /partners/rayon-sports redirects to onboarding', () {
      final result = resolveAppRedirect(
        location: AppRoutes.rayonHome,
        hasSession: false,
        hasProfile: false,
      );
      expect(result, isNotNull);
      expect(result, contains(AppRoutes.onboarding));
    });
  });

  group('Session but incomplete profile (no forced register)', () {
    // After the post-OTP routing refactor, incomplete profiles are allowed
    // through to all routes. Profile completion is optional and accessed
    // from the Profile screen. The router MUST NOT force /register.

    test('/register passes through (accessible from Profile screen)', () {
      final result = resolveAppRedirect(
        location: AppRoutes.register,
        hasSession: true,
        hasProfile: false,
        profileRestoreState: AuthProfileRestoreState.available,
        sessionPhone: '250781234567',
      );
      // /register is NOT in _authRoutes — users can navigate here voluntarily
      expect(result, isNull);
    });

    test('splash redirects to home (not register) after profile restore', () {
      final result = resolveAppRedirect(
        location: AppRoutes.splash,
        hasSession: true,
        hasProfile: false,
        profileRestoreState: AuthProfileRestoreState.available,
        sessionPhone: '250781234567',
      );
      expect(result, equals(AppRoutes.home));
    });

    test('splash stays on splash while profile restore is pending', () {
      final result = resolveAppRedirect(
        location: AppRoutes.splash,
        hasSession: true,
        hasProfile: false,
        profileRestoreState: AuthProfileRestoreState.pending,
        sessionPhone: '250781234567',
      );
      expect(result, isNull);
    });

    test('splash stays on splash when profile restore failed', () {
      final result = resolveAppRedirect(
        location: AppRoutes.splash,
        hasSession: true,
        hasProfile: false,
        profileRestoreState: AuthProfileRestoreState.failed,
        sessionPhone: '250781234567',
      );
      expect(result, isNull);
    });

    test('/home passes through for incomplete profile', () {
      final result = resolveAppRedirect(
        location: AppRoutes.home,
        hasSession: true,
        hasProfile: false,
        profileRestoreState: AuthProfileRestoreState.available,
        sessionPhone: '250781234567',
      );
      expect(result, isNull);
    });

    test('/groups passes through for incomplete profile', () {
      final result = resolveAppRedirect(
        location: AppRoutes.groups,
        hasSession: true,
        hasProfile: false,
        profileRestoreState: AuthProfileRestoreState.available,
        sessionPhone: '250781234567',
      );
      expect(result, isNull);
    });

    test('/app-access redirects signed-in users to home', () {
      final result = resolveAppRedirect(
        location: AppRoutes.appAccess,
        hasSession: true,
        hasProfile: false,
        profileRestoreState: AuthProfileRestoreState.available,
        sessionPhone: '250781234567',
      );
      expect(result, AppRoutes.home);
    });

    test('protected route redirects back to splash when restore failed', () {
      final result = resolveAppRedirect(
        location: AppRoutes.groups,
        hasSession: true,
        hasProfile: false,
        profileRestoreState: AuthProfileRestoreState.failed,
        sessionPhone: '250781234567',
      );
      expect(result, AppRoutes.splashLocation(redirect: AppRoutes.groups));
    });

    test('onboarding redirects to home for incomplete profile', () {
      final result = resolveAppRedirect(
        location: AppRoutes.onboarding,
        hasSession: true,
        hasProfile: false,
        profileRestoreState: AuthProfileRestoreState.available,
      );
      expect(result, equals(AppRoutes.home));
    });

    test('/admin redirects to home for non-admin with incomplete profile', () {
      final result = resolveAppRedirect(
        location: AppRoutes.admin,
        hasSession: true,
        hasProfile: false,
        profileRestoreState: AuthProfileRestoreState.available,
        isAdmin: false,
      );
      expect(result, equals(AppRoutes.home));
    });
  });

  group('Fully authenticated (session + complete profile)', () {
    test('/home passes through', () {
      final result = resolveAppRedirect(
        location: AppRoutes.home,
        hasSession: true,
        hasProfile: true,
        profileRestoreState: AuthProfileRestoreState.available,
      );
      expect(result, isNull);
    });

    test('/groups passes through', () {
      final result = resolveAppRedirect(
        location: AppRoutes.groups,
        hasSession: true,
        hasProfile: true,
        profileRestoreState: AuthProfileRestoreState.available,
      );
      expect(result, isNull);
    });

    test('/partners/rayon-sports passes through', () {
      final result = resolveAppRedirect(
        location: AppRoutes.rayonHome,
        hasSession: true,
        hasProfile: true,
        profileRestoreState: AuthProfileRestoreState.available,
      );
      expect(result, isNull);
    });

    test('onboarding redirects to home', () {
      final result = resolveAppRedirect(
        location: AppRoutes.onboarding,
        hasSession: true,
        hasProfile: true,
        profileRestoreState: AuthProfileRestoreState.available,
      );
      expect(result, equals(AppRoutes.home));
    });

    test('/otp redirects to home', () {
      final result = resolveAppRedirect(
        location: AppRoutes.otp,
        hasSession: true,
        hasProfile: true,
        profileRestoreState: AuthProfileRestoreState.available,
      );
      expect(result, equals(AppRoutes.home));
    });

    test('/register passes through (no longer an auth route)', () {
      final result = resolveAppRedirect(
        location: AppRoutes.register,
        hasSession: true,
        hasProfile: true,
        profileRestoreState: AuthProfileRestoreState.available,
      );
      expect(result, isNull);
    });

    test('splash redirects to home after auth restore', () {
      final result = resolveAppRedirect(
        location: AppRoutes.splash,
        hasSession: true,
        hasProfile: true,
        profileRestoreState: AuthProfileRestoreState.available,
      );
      expect(result, equals(AppRoutes.home));
    });
  });

  group('Edge cases', () {
    test('/credit passes through for authenticated user', () {
      final result = resolveAppRedirect(
        location: AppRoutes.credit,
        hasSession: true,
        hasProfile: true,
        profileRestoreState: AuthProfileRestoreState.available,
      );
      expect(result, isNull);
    });

    test('/mobility passes through for authenticated user', () {
      final result = resolveAppRedirect(
        location: AppRoutes.mobility,
        hasSession: true,
        hasProfile: true,
        profileRestoreState: AuthProfileRestoreState.available,
      );
      expect(result, isNull);
    });

    test('/admin redirects to home for non-admin user', () {
      final result = resolveAppRedirect(
        location: AppRoutes.admin,
        hasSession: true,
        hasProfile: true,
        profileRestoreState: AuthProfileRestoreState.available,
        isAdmin: false,
      );
      expect(result, equals(AppRoutes.home));
    });

    test('/admin passes through for admin user', () {
      final result = resolveAppRedirect(
        location: AppRoutes.admin,
        hasSession: true,
        hasProfile: true,
        profileRestoreState: AuthProfileRestoreState.available,
        isAdmin: true,
      );
      expect(result, isNull);
    });

    test('/admin passes through for partner admin user', () {
      final result = resolveAppRedirect(
        location: AppRoutes.admin,
        hasSession: true,
        hasProfile: true,
        profileRestoreState: AuthProfileRestoreState.available,
        adminAccess: const AdminWorkspaceAccess(
          partnerAdminIds: {'partner-rayon'},
        ),
      );
      expect(result, isNull);
    });

    test('/admin/platform redirects partner admin user back to launcher', () {
      final result = resolveAppRedirect(
        location: AppRoutes.adminPlatform,
        hasSession: true,
        hasProfile: true,
        profileRestoreState: AuthProfileRestoreState.available,
        adminAccess: const AdminWorkspaceAccess(
          partnerAdminIds: {'partner-rayon'},
        ),
      );
      expect(result, equals(AppRoutes.admin));
    });
  });
}
