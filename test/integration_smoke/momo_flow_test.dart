import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/features/momo/screens/momo_screen.dart';
import 'package:cool_app/shared/widgets/cool_button.dart';

import 'test_harness.dart';

void main() {
  group('MoMo screen', () {
    testWidgets('shows a dominant send-money flow with secondary tools', (
      tester,
    ) async {
      await pumpScopedApp(
        tester,
        child: const MomoScreen(),
        session: fakeSession(),
        user: fakeUser(momoNumber: '788123456'),
      );

      expect(find.text('Send money'), findsWidgets);
      expect(find.text('More tools'), findsOneWidget);
      expect(find.text('Statements'), findsOneWidget);
      expect(find.text('My QR code'), findsOneWidget);
      expect(find.text('NFC tools'), findsOneWidget);
      expect(find.textContaining('From 0788123456'), findsOneWidget);
    });

    testWidgets('Send money sheet validates inputs', (tester) async {
      await pumpScopedApp(
        tester,
        child: const MomoScreen(),
        session: fakeSession(),
        user: fakeUser(momoNumber: '788123456'),
      );

      await tester.tap(find.widgetWithText(CoolButton, 'Send money'));
      await settleTestApp(tester);
      await tester.tap(find.text('Confirm Send'));
      await settleTestApp(tester);

      expect(find.text('Enter a valid recipient and amount.'), findsOneWidget);
    });
  });
}
