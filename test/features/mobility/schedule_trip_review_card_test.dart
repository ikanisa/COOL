import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/features/mobility/widgets/schedule_trip_review_card.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  group('ScheduleTripPostingGuideCard', () {
    testWidgets('renders posting trust details', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ScheduleTripPostingGuideCard(
            title: 'Posting behavior',
            message: 'Review what happens before you post.',
            visibilityLabel: 'Visible to others',
            visibilityValue: 'Drivers see your route, timing, seats, and note.',
            precisionLabel: 'Pickup precision',
            precisionValue:
                'Text route only. Confirm the exact pickup in chat.',
            coordinationLabel: 'After posting',
            coordinationValue:
                'Drivers contact you after posting. Final pickup, fare, and timing are agreed in WhatsApp.',
            offlineLabel: 'Offline fallback',
            offlineValue:
                'If the network drops, COOL saves this trip on device and syncs it later.',
          ),
        ),
      );

      expect(find.text('Posting behavior'), findsOneWidget);
      expect(find.text('Visible to others'), findsOneWidget);
      expect(
        find.text('Drivers see your route, timing, seats, and note.'),
        findsOneWidget,
      );
      expect(find.text('Pickup precision'), findsOneWidget);
      expect(
        find.text('Text route only. Confirm the exact pickup in chat.'),
        findsOneWidget,
      );
      expect(find.text('Offline fallback'), findsOneWidget);
    });
  });
}
