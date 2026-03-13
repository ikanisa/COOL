import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/core/router/app_router.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart';
import 'package:cool_app/features/auth/repositories/auth_repository.dart';

import 'helpers/test_bootstrap.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

ProviderContainer _createContainer() {
  final repository = MockAuthRepository();
  when(() => repository.currentSession).thenReturn(null);
  return createTestContainer(
    overrides: [authRepositoryProvider.overrideWithValue(repository)],
  );
}

void main() {
  test('router boots at splash and preserves register phone query', () {
    final container = _createContainer();

    final router = container.read(appRouterProvider);

    expect(router.routeInformationProvider.value.uri.path, AppRoutes.splash);

    router.go('/register?phone=%2B250788123456');

    final uri = router.routeInformationProvider.value.uri;
    expect(uri.path, AppRoutes.register);
    expect(uri.queryParameters['phone'], '+250788123456');
  });

  test('router preserves invite code routes', () {
    final container = _createContainer();

    final router = container.read(appRouterProvider);

    router.go('/invite/ABCD1234');

    final uri = router.routeInformationProvider.value.uri;
    expect(uri.path, '/invite/ABCD1234');
    expect(uri.pathSegments.last, 'ABCD1234');
  });

  test('auth routes preserve redirect targets for invite deep links', () {
    expect(
      AppRoutes.otpLocation(redirect: AppRoutes.inviteLocation('abcd1234')),
      '/otp?redirect=%2Finvite%2FABCD1234',
    );
    expect(
      AppRoutes.otpVerifyLocation(
        phone: '+250788123456',
        redirect: AppRoutes.inviteLocation('abcd1234'),
      ),
      '/otp-verify?phone=%2B250788123456&redirect=%2Finvite%2FABCD1234',
    );
    expect(
      AppRoutes.registerLocation(
        phone: '+250788123456',
        redirect: AppRoutes.inviteLocation('abcd1234'),
      ),
      '/register?phone=%2B250788123456&redirect=%2Finvite%2FABCD1234',
    );
  });
}
