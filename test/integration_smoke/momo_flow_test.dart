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

      expect(find.text('Send Money'), findsWidgets);
      expect(find.text('More tools'), findsOneWidget);
      expect(find.text('Statements'), findsOneWidget);
      expect(find.text('MoMo QR'), findsOneWidget);
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
      await tester.tap(find.text('Confirm and send'));
      await settleTestApp(tester);

      expect(find.textContaining('valid recipient'), findsOneWidget);
    });
  });
}
