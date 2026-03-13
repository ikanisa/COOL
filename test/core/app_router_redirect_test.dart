import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/router/app_redirects.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart';

void main() {
  group('resolveAppRedirect', () {
    test('redirects splash to onboarding when signed out', () {
      expect(
        resolveAppRedirect(
          location: AppRoutes.splash,
          hasSession: false,
          hasProfile: false,
        ),
        AppRoutes.onboarding,
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
        '/onboarding?redirect=%2Finvite%2FABCD1234',
      );
    });

    test(
      'preserves query parameters when redirecting signed-out deep links',
      () {
        expect(
          resolveAppRedirect(
            location: AppRoutes.register,
            requestedLocation: AppRoutes.registerLocation(
              phone: '+250788123456',
            ),
            hasSession: false,
            hasProfile: false,
          ),
          '/onboarding?redirect=%2Fregister%3Fphone%3D%252B250788123456',
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
          location: AppRoutes.onboarding,
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
  });
}
