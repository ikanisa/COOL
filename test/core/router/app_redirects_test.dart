import 'package:flutter_test/flutter_test.dart';
import 'package:cool_app/core/router/app_redirects.dart';
import 'package:cool_app/features/admin/models/admin_workspace_access.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart';

void main() {
  group('resolveAppRedirect', () {
    // ── No session ────────────────────────────────────────────────────
    group('no session', () {
      test('on splash → stays on splash', () {
        final result = resolveAppRedirect(
          location: AppRoutes.splash,
          hasSession: false,
          hasProfile: false,
        );
        expect(result, isNull);
      });

      test('on home → redirects to splash with pending redirect', () {
        final result = resolveAppRedirect(
          location: AppRoutes.home,
          hasSession: false,
          hasProfile: false,
        );
        expect(result, isNotNull);
        expect(result, contains(AppRoutes.splash));
      });

      test('on admin → redirects to splash', () {
        final result = resolveAppRedirect(
          location: AppRoutes.admin,
          hasSession: false,
          hasProfile: false,
        );
        expect(result, isNotNull);
        expect(result, contains(AppRoutes.splash));
      });
    });

    // ── Session with pending profile restore ──────────────────────────
    group('session with pending profile restore', () {
      test('on home → redirects to splash', () {
        final result = resolveAppRedirect(
          location: AppRoutes.home,
          hasSession: true,
          hasProfile: false,
          profileRestoreState: AuthProfileRestoreState.pending,
        );
        expect(result, isNotNull);
        expect(result, contains(AppRoutes.splash));
      });

      test('on splash → stays on splash', () {
        final result = resolveAppRedirect(
          location: AppRoutes.splash,
          hasSession: true,
          hasProfile: false,
          profileRestoreState: AuthProfileRestoreState.pending,
        );
        expect(result, isNull);
      });
    });

    // ── Session with failed profile restore ───────────────────────────
    group('session with failed profile restore', () {
      test('on home → redirects to splash', () {
        final result = resolveAppRedirect(
          location: AppRoutes.home,
          hasSession: true,
          hasProfile: false,
          profileRestoreState: AuthProfileRestoreState.failed,
        );
        expect(result, isNotNull);
        expect(result, contains(AppRoutes.splash));
      });
    });

    // ── Session available → normal navigation ─────────────────────────
    group('session available', () {
      test('on splash → redirects to home', () {
        final result = resolveAppRedirect(
          location: AppRoutes.splash,
          hasSession: true,
          hasProfile: true,
          profileRestoreState: AuthProfileRestoreState.available,
        );
        expect(result, AppRoutes.home);
      });

      test('on splash with pending redirect → follows redirect', () {
        const target = '/groups/abc123';
        final result = resolveAppRedirect(
          location: AppRoutes.splash,
          hasSession: true,
          hasProfile: true,
          profileRestoreState: AuthProfileRestoreState.available,
          pendingRedirect: target,
        );
        expect(result, target);
      });

      test('on home → no redirect (stays)', () {
        final result = resolveAppRedirect(
          location: AppRoutes.home,
          hasSession: true,
          hasProfile: true,
          profileRestoreState: AuthProfileRestoreState.available,
        );
        expect(result, isNull);
      });

      test('on groups → no redirect (stays)', () {
        final result = resolveAppRedirect(
          location: AppRoutes.contributionCircles,
          hasSession: true,
          hasProfile: true,
          profileRestoreState: AuthProfileRestoreState.available,
        );
        expect(result, isNull);
      });
    });

    // ── Admin route guards ────────────────────────────────────────────
    group('admin route guards', () {
      test('non-admin user on admin → redirects to home', () {
        final result = resolveAppRedirect(
          location: AppRoutes.admin,
          hasSession: true,
          hasProfile: true,
          isAdmin: false,
          profileRestoreState: AuthProfileRestoreState.available,
        );
        expect(result, AppRoutes.home);
      });

      test('admin user on admin root → no redirect', () {
        final result = resolveAppRedirect(
          location: AppRoutes.admin,
          hasSession: true,
          hasProfile: true,
          isAdmin: true,
          profileRestoreState: AuthProfileRestoreState.available,
        );
        expect(result, isNull);
      });

      test('non-platform admin on platform route → redirects to admin root',
          () {
        final result = resolveAppRedirect(
          location: AppRoutes.adminPlatform,
          hasSession: true,
          hasProfile: true,
          isAdmin: true,
          adminAccess: const AdminWorkspaceAccess(
            hasPlatformAccess: false,
            bankAdminIds: {'bank-1'},
          ),
          profileRestoreState: AuthProfileRestoreState.available,
        );
        expect(result, AppRoutes.admin);
      });

      test('platform admin on platform route → no redirect', () {
        final result = resolveAppRedirect(
          location: AppRoutes.adminPlatform,
          hasSession: true,
          hasProfile: true,
          isAdmin: true,
          adminAccess: const AdminWorkspaceAccess(hasPlatformAccess: true),
          profileRestoreState: AuthProfileRestoreState.available,
        );
        expect(result, isNull);
      });

      test('bank admin on wrong bank → redirects to admin root', () {
        final result = resolveAppRedirect(
          location: '/admin/banks/bank-99',
          hasSession: true,
          hasProfile: true,
          isAdmin: true,
          adminAccess: const AdminWorkspaceAccess(
            hasPlatformAccess: false,
            bankAdminIds: {'bank-1'},
          ),
          profileRestoreState: AuthProfileRestoreState.available,
        );
        expect(result, AppRoutes.admin);
      });

      test('bank admin on own bank → no redirect', () {
        final result = resolveAppRedirect(
          location: '/admin/banks/bank-1',
          hasSession: true,
          hasProfile: true,
          isAdmin: true,
          adminAccess: const AdminWorkspaceAccess(
            hasPlatformAccess: false,
            bankAdminIds: {'bank-1'},
          ),
          profileRestoreState: AuthProfileRestoreState.available,
        );
        expect(result, isNull);
      });
    });

    // ── Edge cases ────────────────────────────────────────────────────
    group('edge cases', () {
      test('empty pending redirect is ignored', () {
        final result = resolveAppRedirect(
          location: AppRoutes.splash,
          hasSession: true,
          hasProfile: true,
          profileRestoreState: AuthProfileRestoreState.available,
          pendingRedirect: '',
        );
        expect(result, AppRoutes.home);
      });

      test('relative pending redirect is ignored', () {
        final result = resolveAppRedirect(
          location: AppRoutes.splash,
          hasSession: true,
          hasProfile: true,
          profileRestoreState: AuthProfileRestoreState.available,
          pendingRedirect: 'groups',
        );
        expect(result, AppRoutes.home);
      });

      test('splash pending redirect is ignored (no loop)', () {
        final result = resolveAppRedirect(
          location: AppRoutes.splash,
          hasSession: true,
          hasProfile: true,
          profileRestoreState: AuthProfileRestoreState.available,
          pendingRedirect: AppRoutes.splash,
        );
        expect(result, AppRoutes.home);
      });
    });
  });
}
