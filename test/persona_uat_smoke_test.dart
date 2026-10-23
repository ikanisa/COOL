import 'fixtures/collect_repository_fixture.dart';

import 'dart:io';

import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/features/ledger/ledger_screen.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget appFor(Widget child, CollectRepository repository) {
    return ProviderScope(
      overrides: [collectRepositoryProvider.overrideWith((ref) => repository)],
      child: MaterialApp(theme: AppTheme.light(), home: child),
    );
  }

  test('member settings expose Rwanda MoMo only', () {
    final source = File(
      'lib/features/settings/settings_screen.dart',
    ).readAsStringSync();
    expect(source, contains("title: 'App permissions'"));
    expect(source, isNot(contains('/settings/bank-transfer')));
  });

  testWidgets(
    'recorded ledger totals preserve RWF and exclude pending MoMo intents',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FixtureCollectRepository(
        fixtureNow: DateTime.now().toUtc(),
      );
      await repository.createPaymentIntent(
        const PaymentIntentDraft(
          collectionId: 'qa-private-group',
          amountRwf: 9999,
        ),
      );
      await tester.pumpWidget(
        appFor(
          const LedgerScreen(collectionId: 'qa-private-group'),
          repository,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('RWF 35,000'), findsWidgets);
      expect(find.text('RWF 9,999'), findsNothing);
      expect(find.textContaining('MOMO-E2E'), findsWidgets);
      expect(find.text('Your recorded contributions'), findsOneWidget);
      expect(
        find.textContaining(
          'A receipt SMS or a ledger entry alone does not verify provider settlement.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('confirmed'), findsNothing);
    },
  );

  test('member contribution source exposes MoMo and USSD only', () {
    final source = File(
      'lib/features/payments/contribution_flow_screen.dart',
    ).readAsStringSync();
    expect(source, contains('rwanda_momo'));
    expect(source, isNot(contains('diaspora_bank')));
    expect(source, isNot(contains('bank_transfer')));
  });

  test(
    'Android production limits native permissions to MoMo receipt and USSD',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(manifest, contains('android.permission.RECEIVE_SMS'));
      expect(manifest, isNot(contains('android.permission.READ_SMS')));
      expect(manifest, isNot(contains('android.permission.SEND_SMS')));
      expect(manifest, contains('android.permission.CALL_PHONE'));
      expect(manifest, contains('CollectSmsReceiver'));
    },
  );
}
