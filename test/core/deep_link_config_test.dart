import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/config/deep_link_config.dart';
import 'package:cool_app/core/router/app_router.dart';

void main() {
  group('DeepLinkConfig.routeForUri', () {
    test('maps https basket links', () {
      expect(
        DeepLinkConfig.routeForUri(Uri.parse('https://cool.app/basket')),
        AppRoutes.basket,
      );
    });

    test('maps https invite links', () {
      expect(
        DeepLinkConfig.routeForUri(
          Uri.parse('https://cool.app/invite/abcd1234'),
        ),
        '/invite/ABCD1234',
      );
    });

    test('preserves query parameters for invite links', () {
      expect(
        DeepLinkConfig.routeForUri(
          Uri.parse('https://cool.app/invite/abcd1234?ri=invite-1&campaign=gc'),
        ),
        '/invite/ABCD1234?ri=invite-1&campaign=gc',
      );
    });

    test('maps club deep links', () {
      expect(
        DeepLinkConfig.routeForUri(
          Uri.parse('https://cool.app/club/rayon-kigali?ri=invite-1'),
        ),
        '/partners/rayon-sports/clubs/rayon-kigali?ri=invite-1',
      );
    });

    test('maps custom scheme basket links', () {
      expect(
        DeepLinkConfig.routeForUri(Uri.parse('cool://basket')),
        AppRoutes.basket,
      );
    });

    test('maps custom scheme invite links', () {
      expect(
        DeepLinkConfig.routeForUri(Uri.parse('cool://invite/abcd1234')),
        '/invite/ABCD1234',
      );
    });

    test('ignores unsupported hosts', () {
      expect(
        DeepLinkConfig.routeForUri(Uri.parse('https://example.com/basket')),
        isNull,
      );
    });
  });
}
