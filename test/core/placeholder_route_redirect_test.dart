import 'package:cool_app/core/router/app_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('placeholder route redirects', () {
    test('generic partner detail redirects to partners hub', () {
      expect(resolvePartnerDetailRedirect('apr-fc'), AppRoutes.partners);
    });

    test('dedicated partner detail stays on its live route', () {
      expect(resolvePartnerDetailRedirect('radiant'), isNull);
    });

    test('rayon alias redirects to the dedicated rayon surface', () {
      expect(resolvePartnerDetailRedirect('rayon-sports'), AppRoutes.rayonHome);
    });
  });
}
