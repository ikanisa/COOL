import 'package:cool_app/core/router/app_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('placeholder route redirects', () {
    test('basket compatibility route redirects to home', () {
      expect(basketCompatibilityRedirectLocation(), AppRoutes.home);
    });

    test('generic partner detail redirects to partners hub', () {
      expect(resolvePartnerDetailRedirect('apr-fc'), AppRoutes.partners);
    });

    test('generic partner fans route redirects to partners hub', () {
      expect(resolvePartnerFansRedirect('apr-fc'), AppRoutes.partners);
    });

    test('dedicated partner detail stays on its live route', () {
      expect(resolvePartnerDetailRedirect('radiant'), isNull);
      expect(resolvePartnerFansRedirect('radiant'), '/partners/radiant');
    });

    test('rayon aliases redirect to the dedicated rayon surface', () {
      expect(resolvePartnerDetailRedirect('rayon-sports'), AppRoutes.rayonHome);
      expect(resolvePartnerFansRedirect('rayon-sports'), AppRoutes.rayonHome);
    });
  });
}
