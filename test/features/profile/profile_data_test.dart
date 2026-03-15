import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/features/mobility/models/driver_profile.dart';
import 'package:cool_app/features/mobility/providers/driver_provider.dart';
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
          creditScoreLabel: '--',
          kycStatus: 'unverified',
          showCompletionBanner: false,
          isDriver: false,
        );

        expect(profile.walletRouteLabel, 'MoMo Code');
        expect(profile.momoDisplayLabel, 'MoMo Code 445566');
        expect(profile.languageCode, 'en');
        expect(profile.canShowMomoQr, isFalse);
      },
    );
  });

  group('DriverProfileSnapshot', () {
    test('preserves actual verification and base-location fields', () {
      final snapshot = DriverProfileSnapshot.fromState(
        const DriverState(
          profile: DriverProfile(
            userId: 'driver-1',
            fullName: '123456',
            vehicleType: 'Moto Taxi',
            plateNumber: 'RAB 123 C',
            baseLocation: 'Nyamirambo',
            vehicleStatus: 'pending_review',
            isRegularDriver: false,
            isOnline: false,
          ),
        ),
      );

      expect(snapshot.vehicleType, 'Moto Taxi');
      expect(snapshot.plateNumber, 'RAB 123 C');
      expect(snapshot.baseLocation, 'Nyamirambo');
      expect(snapshot.verificationStatusLabel, 'Pending Review');
      expect(snapshot.cadenceLabel, 'Occasional driver');
      expect(snapshot.isSetupComplete, isTrue);
    });
  });
}
