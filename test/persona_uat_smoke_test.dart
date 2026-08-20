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

void main() {
  Widget appFor(Widget child, CollectRepository repository) {
    return ProviderScope(
      overrides: [collectRepositoryProvider.overrideWith((ref) => repository)],
      child: MaterialApp(theme: AppTheme.light(), home: child),
    );
  }

  test('member settings routes to governed bank and permission screens', () {
    final source = File(
      'lib/features/settings/settings_screen.dart',
    ).readAsStringSync();

    expect(source, contains("title: 'Bank transfer details'"));
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
    expect(find.text('Revolut setup'), findsOneWidget);
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

      expect(find.text('EUR 350.00'), findsWidgets);
      expect(find.text('EUR 99.99'), findsNothing);
      expect(find.textContaining('BANK-E2E'), findsWidgets);
    },
  );

  test('member product surfaces contain no payment-provider flow', () {
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
    expect(source, isNot(contains('Contribute with MoMo')));
    expect(source, isNot(contains('Open MoMo')));
    expect(source, isNot(contains('USSD')));
  });

  test(
    'public production manifest has no financial SMS or call permission',
    () {
      final manifest = File(
        'android/app/src/production/AndroidManifest.xml',
      ).readAsStringSync();

      expect(manifest, isNot(contains('android.permission.RECEIVE_SMS')));
      expect(manifest, isNot(contains('android.permission.READ_SMS')));
      expect(manifest, isNot(contains('android.permission.CALL_PHONE')));
      expect(manifest, isNot(contains('CollectSmsReceiver')));
    },
  );
}
