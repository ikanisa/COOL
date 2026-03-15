import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/features/momo/screens/momo_screen.dart';
import 'package:cool_app/shared/widgets/cool_button.dart';

import 'test_harness.dart';

void main() {
  group('MoMo screen', () {
    testWidgets('shows receive QR first with send and tools secondary', (
      tester,
    ) async {
      await pumpScopedApp(
        tester,
        child: const MomoScreen(),
        session: fakeSession(),
        user: fakeUser(momoNumber: '788123456'),
      );

      expect(find.text('Get paid by QR'), findsOneWidget);
      expect(find.text('Receive QR · Rwanda · RWF'), findsOneWidget);
      expect(find.text('Send Money'), findsWidgets);
      expect(find.text('Before you pay'), findsOneWidget);
      final moreTools = find.text('Extra Tools');
      expect(moreTools, findsOneWidget);
      await tester.tap(moreTools);
      await tester.pumpAndSettle();

      expect(find.text('Statements'), findsOneWidget);
      expect(find.text('Full-screen QR'), findsOneWidget);
      expect(find.text('NFC tools'), findsOneWidget);
      expect(find.textContaining('From'), findsOneWidget);
    });

    testWidgets('Send money sheet validates inputs', (tester) async {
      await pumpScopedApp(
        tester,
        child: const MomoScreen(),
        session: fakeSession(),
        user: fakeUser(momoNumber: '788123456'),
      );

      await tester.tap(find.widgetWithText(CoolButton, 'Send Money'));
      await settleTestApp(tester);
      await tester.tap(find.text('Continue to USSD'));
      await settleTestApp(tester);

      expect(find.textContaining('valid recipient'), findsOneWidget);
    });
  });
}
