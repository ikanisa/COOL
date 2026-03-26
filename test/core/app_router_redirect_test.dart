import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/router/app_redirects.dart';
import 'package:cool_app/features/admin/models/admin_workspace_access.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart';

void main() {
  group('resolveAppRedirect', () {
    test('keeps signed-out users on splash', () {
      expect(
        resolveAppRedirect(
          location: AppRoutes.splash,
          hasSession: false,
          hasProfile: false,
        ),
        isNull,
      );
    });

    test('preserves protected deep links through onboarding', () {
      expect(
        resolveAppRedirect(
          location: AppRoutes.inviteLocation('abcd1234'),
          requestedLocation: AppRoutes.inviteLocation('abcd1234'),
          hasSession: false,
          hasProfile: false,
        ),
        AppRoutes.splashLocation(
          redirect: AppRoutes.inviteLocation('abcd1234'),
        ),
      );
    });

    test(
      'preserves query parameters when redirecting signed-out deep links',
      () {
        final registerLocation = Uri(
          path: '/register',
          queryParameters: const <String, String>{'phone': '+250788123456'},
        ).toString();

        expect(
          resolveAppRedirect(
            location: AppRoutes.home,
            requestedLocation: registerLocation,
            hasSession: false,
            hasProfile: false,
          ),
          AppRoutes.splashLocation(redirect: registerLocation),
        );
      },
    );

    test('allows incomplete profiles to access protected routes', () {
      expect(
        resolveAppRedirect(
          location: AppRoutes.rayonTickets,
          hasSession: true,
          hasProfile: false,
          sessionPhone: '+250788123456',
        ),
        isNull,
      );
    });

    test('allows splash while profile restoration is incomplete', () {
      expect(
        resolveAppRedirect(
          location: AppRoutes.splash,
          hasSession: true,
          hasProfile: false,
          profileRestoreState: AuthProfileRestoreState.pending,
          sessionPhone: '+250788123456',
        ),
        isNull,
      );
    });

    test('keeps failed profile restoration on splash for retry', () {
      expect(
        resolveAppRedirect(
          location: AppRoutes.splash,
          hasSession: true,
          hasProfile: false,
          profileRestoreState: AuthProfileRestoreState.failed,
          sessionPhone: '+250788123456',
        ),
        isNull,
      );
    });

    test('preserves pending redirect when profile restoration fails', () {
      expect(
        resolveAppRedirect(
          location: AppRoutes.groups,
          hasSession: true,
          hasProfile: false,
          profileRestoreState: AuthProfileRestoreState.failed,
          sessionPhone: '+250788123456',
        ),
        AppRoutes.splashLocation(redirect: AppRoutes.groups),
      );
    });

    test('routes authenticated users away from auth screens', () {
      expect(
        resolveAppRedirect(
          location: AppRoutes.splash,
          hasSession: true,
          hasProfile: true,
          profileRestoreState: AuthProfileRestoreState.available,
          sessionPhone: '+250788123456',
        ),
        AppRoutes.home,
      );
    });

    test(
      'keeps authenticated users on protected screens during app resume',
      () {
        expect(
          resolveAppRedirect(
            location: AppRoutes.profile,
            hasSession: true,
            hasProfile: true,
            profileRestoreState: AuthProfileRestoreState.available,
            sessionPhone: '+250788123456',
          ),
          isNull,
        );
      },
    );

    test('redirects non-admin users away from admin routes', () {
      expect(
        resolveAppRedirect(
          location: AppRoutes.admin,
          hasSession: true,
          hasProfile: true,
          profileRestoreState: AuthProfileRestoreState.available,
          isAdmin: false,
        ),
        AppRoutes.home,
      );
    });

    test('allows admin users into admin routes', () {
      expect(
        resolveAppRedirect(
          location: AppRoutes.admin,
          hasSession: true,
          hasProfile: true,
          profileRestoreState: AuthProfileRestoreState.available,
          isAdmin: true,
        ),
        isNull,
      );
    });

    test('allows partner admins into the admin workspace launcher', () {
      expect(
        resolveAppRedirect(
          location: AppRoutes.admin,
          hasSession: true,
          hasProfile: true,
          profileRestoreState: AuthProfileRestoreState.available,
          adminAccess: const AdminWorkspaceAccess(
            partnerAdminIds: {'partner-rayon'},
          ),
        ),
        isNull,
      );
    });

    test('redirects partner admins away from platform admin routes', () {
      expect(
        resolveAppRedirect(
          location: AppRoutes.adminPlatform,
          hasSession: true,
          hasProfile: true,
          profileRestoreState: AuthProfileRestoreState.available,
          adminAccess: const AdminWorkspaceAccess(
            partnerAdminIds: {'partner-rayon'},
          ),
        ),
        AppRoutes.admin,
      );
    });

    test('allows scoped partner admin workspaces for matching ids', () {
      expect(
        resolveAppRedirect(
          location: AppRoutes.adminPartnerWorkspaceLocation('partner-rayon'),
          hasSession: true,
          hasProfile: true,
          profileRestoreState: AuthProfileRestoreState.available,
          adminAccess: const AdminWorkspaceAccess(
            partnerAdminIds: {'partner-rayon'},
          ),
        ),
        isNull,
      );
    });

    test('allows scoped bank admin workspaces for matching ids', () {
      expect(
        resolveAppRedirect(
          location: AppRoutes.adminBankWorkspaceLocation('bank-1'),
          hasSession: true,
          hasProfile: true,
          profileRestoreState: AuthProfileRestoreState.available,
          adminAccess: const AdminWorkspaceAccess(bankAdminIds: {'bank-1'}),
        ),
        isNull,
      );
    });

    test('redirects bank admins away from partner admin routes', () {
      expect(
        resolveAppRedirect(
          location: AppRoutes.adminRayon,
          hasSession: true,
          hasProfile: true,
          profileRestoreState: AuthProfileRestoreState.available,
          adminAccess: const AdminWorkspaceAccess(bankAdminIds: {'bank-1'}),
        ),
        AppRoutes.admin,
      );
    });

    // ── Platform admin = workspace admin for all partners ───────────
    test('platform admin can access partner workspace routes', () {
      expect(
        resolveAppRedirect(
          location: AppRoutes.adminPartnerWorkspaceLocation('any-partner-id'),
          hasSession: true,
          hasProfile: true,
          profileRestoreState: AuthProfileRestoreState.available,
          adminAccess: const AdminWorkspaceAccess(hasPlatformAccess: true),
        ),
        isNull,
      );
    });

    test('platform admin can access bank workspace routes', () {
      expect(
        resolveAppRedirect(
          location: AppRoutes.adminBankWorkspaceLocation('any-bank-id'),
          hasSession: true,
          hasProfile: true,
          profileRestoreState: AuthProfileRestoreState.available,
          adminAccess: const AdminWorkspaceAccess(hasPlatformAccess: true),
        ),
        isNull,
      );
    });

    test('platform admin can access rayon admin routes', () {
      expect(
        resolveAppRedirect(
          location: AppRoutes.adminRayon,
          hasSession: true,
          hasProfile: true,
          profileRestoreState: AuthProfileRestoreState.available,
          adminAccess: const AdminWorkspaceAccess(hasPlatformAccess: true),
        ),
        isNull,
      );
    });

    test('platform admin can access all dashboard sub-routes', () {
      for (final route in [
        '/admin/missions',
        '/admin/seasons',
        '/admin/activities',
        '/admin/analytics',
        '/admin/audit-log',
        '/admin/ai-content',
        '/admin/roles',
      ]) {
        expect(
          resolveAppRedirect(
            location: route,
            hasSession: true,
            hasProfile: true,
            profileRestoreState: AuthProfileRestoreState.available,
            adminAccess: const AdminWorkspaceAccess(hasPlatformAccess: true),
          ),
          isNull,
          reason: 'Platform admin should access $route',
        );
      }
    });
  });
}
