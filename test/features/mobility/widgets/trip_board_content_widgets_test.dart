import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/features/mobility/models/trip.dart';
import 'package:cool_app/features/mobility/widgets/trip_board_content_widgets.dart';

void main() {
  Widget harness(Widget child) => MaterialApp(home: Scaffold(body: child));

  Trip buildTrip({String? contactPhone, String? whatsappNumber}) {
    return Trip(
      id: 'trip-1',
      userId: 'user-1',
      fromLocation: 'Kigali',
      toLocation: 'Musanze',
      departureTime: DateTime(2026, 3, 22, 14),
      vehicleType: 'Moto Taxi',
      contactPhone: contactPhone,
      whatsappNumber: whatsappNumber,
    );
  }

  group('TripBoardTripTile', () {
    testWidgets('disables WhatsApp action when no contact exists', (
      tester,
    ) async {
      var whatsappTaps = 0;

      await tester.pumpWidget(
        harness(
          TripBoardTripTile(
            trip: buildTrip(),
            buttonLabel: 'No contact yet',
            onPreviewTap: () {},
            onWhatsAppTap: () => whatsappTaps++,
          ),
        ),
      );

      await tester.tap(find.text('No contact yet'));
      await tester.pumpAndSettle();

      expect(whatsappTaps, 0);
    });

    testWidgets('opens WhatsApp action when contact exists', (tester) async {
      var whatsappTaps = 0;

      await tester.pumpWidget(
        harness(
          TripBoardTripTile(
            trip: buildTrip(contactPhone: '+250788000000'),
            buttonLabel: 'Join on WhatsApp',
            onPreviewTap: () {},
            onWhatsAppTap: () => whatsappTaps++,
          ),
        ),
      );

      await tester.tap(find.text('Join on WhatsApp'));
      await tester.pumpAndSettle();

      expect(whatsappTaps, 1);
    });
  });
}
