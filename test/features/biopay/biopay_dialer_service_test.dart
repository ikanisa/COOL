import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/features/biopay/models/biopay_profile.dart';
import 'package:cool_app/features/biopay/services/biopay_dialer_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BiopayDialerService', () {
    const service = BiopayDialerService();

    test('builds Rwanda phone-number USSD without amount', () {
      final ussd = service.buildUssdCode(
        routeType: MomoRecipientType.phoneNumber,
        recipientValue: '0781234567',
      );

      expect(ussd, '*182*1*1*781234567#');
    });

    test('builds Rwanda merchant-code USSD without amount', () {
      final ussd = service.buildUssdCode(
        routeType: MomoRecipientType.code,
        recipientValue: '123456',
      );

      expect(ussd, '*182*8*1*123456#');
    });

    test('builds encoded dial URI from a BioPay profile', () {
      final uri = service.buildProfileDialUri(
        const BiopayProfile(
          id: 'profile-1',
          publicId: '123456',
          userId: 'user-1',
          displayName: 'Marie',
          routeType: MomoRecipientType.phoneNumber,
          recipientValue: '0781234567',
          countryCode: 'RW',
          active: true,
          consentVersion: 'biopay-v1',
        ),
      );

      expect(uri.toString(), 'tel:*182*1*1*781234567%23');
    });
  });
}
