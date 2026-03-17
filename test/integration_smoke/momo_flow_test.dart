import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/providers/app_access_provider.dart';
import 'package:cool_app/core/services/app_access_service.dart';
import 'package:cool_app/features/momo/screens/momo_screen.dart';

import '../helpers/fake_app_access_service.dart';
import 'test_harness.dart';

void main() {
  const nfcHceChannel = MethodChannel('app.cool.mobile/nfc_hce');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(nfcHceChannel, null);
  });

  group('MoMo screen', () {
    testWidgets('opens receive QR as a full page and returns cleanly', (
      tester,
    ) async {
      await pumpScopedApp(
        tester,
        child: const MomoScreen(),
        session: fakeSession(),
        user: fakeUser(momoNumber: '788123456'),
        overrides: [
          appAccessServiceProvider.overrideWithValue(
            FakeAppAccessService(
              snapshots: {
                AppAccessPermission.nfc: const AppAccessSnapshot(
                  permission: AppAccessPermission.nfc,
                  kind: AppAccessStateKind.ready,
                  enabledInApp: true,
                  supportedOnDevice: true,
                  systemGranted: true,
                ),
              },
            ),
          ),
        ],
      );

      expect(find.text('MOMO QR'), findsOneWidget);
      expect(find.text('Statements'), findsOneWidget);
      expect(find.text('NFC pay'), findsOneWidget);

      await tester.tap(find.text('MOMO QR'));
      await tester.pumpAndSettle();

      expect(find.text('MOMO QR'), findsWidgets);
      expect(find.text('Share link'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded).last);
      await tester.pumpAndSettle();

      expect(find.text('Statements'), findsOneWidget);
      expect(find.text('Get paid by QR'), findsNothing);
    });

    testWidgets('opens NFC pay as a full page and returns cleanly', (
      tester,
    ) async {
      messenger.setMockMethodCallHandler(nfcHceChannel, (call) async {
        switch (call.method) {
          case 'isSupported':
            return false;
          case 'isPaymentRequestActive':
            return false;
          case 'getPaymentRequestUri':
            return null;
        }
        return null;
      });

      await pumpScopedApp(
        tester,
        child: const MomoScreen(),
        session: fakeSession(),
        user: fakeUser(momoNumber: '788123456'),
        overrides: [
          appAccessServiceProvider.overrideWithValue(
            FakeAppAccessService(
              snapshots: {
                AppAccessPermission.nfc: const AppAccessSnapshot(
                  permission: AppAccessPermission.nfc,
                  kind: AppAccessStateKind.ready,
                  enabledInApp: true,
                  supportedOnDevice: true,
                  systemGranted: true,
                ),
              },
            ),
          ),
        ],
      );

      await tester.tap(find.text('NFC pay'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('NFC pay'), findsWidgets);
      expect(find.text('Read tag'), findsWidgets);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Statements'), findsOneWidget);
    });
  });
}
