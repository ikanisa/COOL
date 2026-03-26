import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/features/profile/widgets/profile_data.dart';

void main() {
  group('ProfileData', () {
    test(
      'formats code-based wallet routes in English even with non-English input',
      () {
        const profile = ProfileData(
          name: '123456',
          officialName: '',
          userId: '123456',
          phone: '+250788123456',
          officialPhone: '',
          momoNumber: '',
          momoCode: '445566',
          momoRouteType: MomoRecipientType.code,
          countryCode: 'RW',
          country: 'Rwanda',
          currencyCode: 'RWF',
          momoLinked: true,
          languageCode: 'rw',
          notificationsEnabled: true,
          showCompletionBanner: false,
        );

        expect(profile.walletRouteLabel, 'MoMo Code');
        expect(profile.momoDisplayLabel, 'MoMo Code 445566');
        expect(profile.languageCode, 'en');
        expect(profile.canShowMomoQr, isFalse);
      },
    );
  });
}
