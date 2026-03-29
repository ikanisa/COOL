import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/config/deep_link_config.dart';
import 'package:cool_app/core/router/app_router.dart';

void main() {
  group('DeepLinkConfig.routeForUri', () {
    test('maps https basket links to home (legacy fallback)', () {
      expect(
        DeepLinkConfig.routeForUri(Uri.parse('https://cool.app/basket')),
        AppRoutes.home,
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
        '/fan-clubs/rayon-kigali?ri=invite-1',
      );
    });

    test('maps custom scheme basket links to home (legacy fallback)', () {
      expect(
        DeepLinkConfig.routeForUri(Uri.parse('cool://basket')),
        AppRoutes.home,
      );
    });

    test('maps custom scheme invite links', () {
      expect(
        DeepLinkConfig.routeForUri(Uri.parse('cool://invite/abcd1234')),
        '/invite/ABCD1234',
      );
    });

    test('maps plain custom momo links to BioPay home', () {
      expect(
        DeepLinkConfig.routeForUri(Uri.parse('cool://momo')),
        AppRoutes.biopayHome,
      );
    });

    test('maps nested custom BioPay links under momo', () {
      expect(
        DeepLinkConfig.routeForUri(Uri.parse('cool://momo/biopay')),
        AppRoutes.biopayHome,
      );
      expect(
        DeepLinkConfig.routeForUri(
          Uri.parse('cool://momo/biopay/scan?mode=pay'),
        ),
        '${AppRoutes.biopayScan}?mode=pay',
      );
      expect(
        DeepLinkConfig.routeForUri(Uri.parse('cool://momo/biopay/nfc')),
        AppRoutes.biopayNfc,
      );
    });

    test('preserves incoming payment links on the momo handoff route', () {
      expect(
        DeepLinkConfig.routeForUri(
          Uri.parse('cool://momo?action=nfc_pay&recipient=0788&amount=5000'),
        ),
        '${AppRoutes.momo}?action=nfc_pay&recipient=0788&amount=5000',
      );
    });

    test('maps custom biopay-tab link', () {
      expect(
        DeepLinkConfig.routeForUri(Uri.parse('cool://biopay-tab')),
        AppRoutes.biopayHome,
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
