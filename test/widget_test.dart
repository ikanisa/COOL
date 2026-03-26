import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/router/app_router.dart';

void main() {
  test('invite route helper uppercases invite codes', () {
    expect(AppRoutes.inviteLocation('abcd1234'), '/invite/ABCD1234');
  });

  test('splash redirect helper preserves nested deep links', () {
    expect(
      AppRoutes.splashLocation(redirect: AppRoutes.inviteLocation('abcd1234')),
      '/?redirect=%2Finvite%2FABCD1234',
    );
  });

  test('splash redirect helper preserves nested query parameters', () {
    final registerLocation = Uri(
      path: '/register',
      queryParameters: const <String, String>{'phone': '+250788123456'},
    ).toString();

    expect(
      AppRoutes.splashLocation(redirect: registerLocation),
      '/?redirect=%2Fregister%3Fphone%3D%252B250788123456',
    );
  });
}
