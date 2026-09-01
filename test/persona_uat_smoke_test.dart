import 'dart:io';

import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/features/ledger/ledger_screen.dart';
import 'package:collect_app/features/payments/contribution_flow_screen.dart';
import 'package:collect_app/features/settings/bank_transfer_settings_screen.dart';
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

  test('member settings route by Rwanda and diaspora profile', () {
    final source = File(
      'lib/features/settings/settings_screen.dart',
    ).readAsStringSync();

    expect(source, contains("title: 'MoMo and USSD'"));
    expect(source, contains("title: 'Diaspora bank transfer details'"));
    expect(source, contains("context.go('/settings/bank-transfer')"));
    expect(source, contains("title: 'Notifications'"));
    expect(source, contains("title: 'App permissions'"));
  });

  testWidgets('bank settings shows copyable EUR SEPA details', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = CollectRepository.fixture();
    await tester.pumpWidget(
      appFor(const BankTransferSettingsScreen(), repository),
    );
    await tester.pumpAndSettle();

    expect(find.text('Approved beneficiary'), findsOneWidget);
    expect(find.text('IKANISA Collect'), findsOneWidget);
    expect(find.text('DE89370400440532013000'), findsOneWidget);
    expect(find.text('EUR'), findsOneWidget);
    expect(
      find.text('SEPA credit transfer · Instant supported'),
      findsOneWidget,
    );
    expect(find.byTooltip('Copy IBAN'), findsOneWidget);
    expect(find.text('Revolut setup'), findsNothing);
  });

  testWidgets('member reviews exact transfer before opening Revolut', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = CollectRepository.fixture(
      fixtureNow: DateTime.now().toUtc(),
      profileOverride: const CollectProfile(
        id: 'local-user',
        publicId: '038491',
        whatsappPhone: '+250788123456',
        displayName: 'Jean Bosco',
        countryCode: 'DE',
        currencyCode: 'EUR',
        revolutName: 'Jean Bosco',
        revolutLink: 'https://revolut.me/jeanbosco',
        revolutAccount: 'Personal EUR account',
      ),
    );
    await tester.pumpWidget(
      appFor(
        const ContributionFlowScreen(collectionId: 'col-church'),
        repository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Contribution amount'), findsOneWidget);
    expect(find.text('Approved beneficiary'), findsOneWidget);
    expect(find.text('Review transfer'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '123.45');
    await tester.tap(find.widgetWithText(FilledButton, 'Review transfer'));
    await tester.pumpAndSettle();

    expect(find.text('EUR 123.45'), findsOneWidget);
    expect(find.text('Exact reference'), findsOneWidget);
    expect(find.text('Open Revolut'), findsOneWidget);
    expect(
      File(
        'lib/features/payments/contribution_flow_screen.dart',
      ).readAsStringSync(),
      contains('Confirm inside your bank app'),
    );
    expect(repository.state.contributions, hasLength(2));
  });

  testWidgets(
    'reconciled ledger uses EUR and excludes pending transfer requests',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = CollectRepository.fixture(
        fixtureNow: DateTime.now().toUtc(),
      );
      await repository.createPaymentIntent(
        const PaymentIntentDraft(collectionId: 'col-church', amountRwf: 9999),
      );
      await tester.pumpWidget(
        appFor(const LedgerScreen(collectionId: 'col-church'), repository),
      );
      await tester.pumpAndSettle();

      expect(find.text('RWF 35,000'), findsWidgets);
      expect(find.text('RWF 9,999'), findsNothing);
      expect(find.textContaining('MOMO-E2E'), findsWidgets);
    },
  );

  test('member product surfaces expose both geographic handoffs', () {
    final paths = <String>[
      'lib/features/payments/contribution_flow_screen.dart',
      'lib/features/settings/bank_transfer_settings_screen.dart',
      'lib/features/collections/collection_create_screen.dart',
      'lib/features/collections/group_profile_screen.dart',
      'lib/features/ledger/ledger_screen.dart',
      'lib/features/activity/activity_screen.dart',
    ];
    final source = paths
        .map((path) => File(path).readAsStringSync())
        .join('\n');

    expect(source, contains('Open Revolut'));
    expect(source, contains('statement reconciliation'));
    expect(source.toLowerCase(), isNot(contains('stripe')));
    expect(source, contains('Open MoMo'));
    expect(source, contains('USSD'));
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
