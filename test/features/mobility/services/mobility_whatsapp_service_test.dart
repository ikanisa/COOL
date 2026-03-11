import 'package:cool_app/features/auth/models/user_profile.dart';
import 'package:cool_app/features/mobility/models/driver_info.dart';
import 'package:cool_app/features/mobility/models/trip.dart';
import 'package:cool_app/features/mobility/services/mobility_whatsapp_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const requester = UserProfile(
    id: 'user-1',
    phone: '250788000111',
    fullName: 'Jean Bosco',
    momoNumber: '250788000111',
    momoProvider: 'mtn',
    country: 'RW',
    languageCode: 'en',
    isDriver: false,
  );

  test('buildTripInquiryMessage references route and WhatsApp agreement', () {
    final trip = Trip(
      id: 'trip-1',
      fromLocation: 'Nyamirambo',
      toLocation: 'Kigali Heights',
      departureTime: DateTime.utc(2026, 3, 12, 7, 30),
      vehicleType: 'Moto',
      contactName: 'Aline',
      whatsappNumber: '250788000222',
    );

    final message = MobilityWhatsAppService.buildTripInquiryMessage(
      trip: trip,
      requester: requester,
    );

    expect(message, contains('Hi Aline'));
    expect(message, contains("I'm Jean"));
    expect(message, contains('Nyamirambo to Kigali Heights'));
    expect(
      message,
      contains('agree on price and the exact pickup point here on WhatsApp'),
    );
  });

  test(
    'buildDriverInquiryMessage includes driver context and marketplace flow',
    () {
      const driver = DriverInfo(
        driverId: 'driver-1',
        displayName: 'Eric Driver',
        vehicleType: 'Cab',
        distanceKm: 1.4,
        isOnline: true,
        scheduledRoute: 'Remera → Kimironko',
        contactPhone: '250788000333',
      );

      final message = MobilityWhatsAppService.buildDriverInquiryMessage(
        driver: driver,
        requester: requester,
      );

      expect(message, contains('Hi Eric Driver'));
      expect(message, contains('Cab profile on COOL'));
      expect(message, contains('Remera → Kimironko'));
      expect(message, contains('1.4 km away'));
      expect(message, contains('discuss price and pickup here on WhatsApp'));
    },
  );
}
