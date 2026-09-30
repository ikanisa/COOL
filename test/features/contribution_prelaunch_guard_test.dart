import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/features/payments/contribution_flow_screen.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/collect_repository_fixture.dart';

class _RouteChangingRepository extends FixtureCollectRepository {
  int createCalls = 0;

  @override
  Future<PaymentIntentModel> createPaymentIntent(
    PaymentIntentDraft draft,
  ) async {
    final intent = await super.createPaymentIntent(draft);
    createCalls++;
    if (createCalls != 2) return intent;
    return PaymentIntentModel(
      id: intent.id,
      collectionId: intent.collectionId,
      expectedAmountRwf: intent.expectedAmountRwf,
      receiverMomoNumber: '0788999999',
      receiverMomoNumberHash: 'new-active-route',
      receiverMomoLabel: 'Changed receiver',
      momoNetwork: intent.momoNetwork,
      senderPhoneHash: intent.senderPhoneHash,
      status: intent.status,
      createdAt: intent.createdAt,
      expiresAt: intent.expiresAt,
    );
  }
}

class _CountingRepository extends FixtureCollectRepository {
  int createCalls = 0;

  @override
  Future<PaymentIntentModel> createPaymentIntent(
    PaymentIntentDraft draft,
  ) async {
    createCalls++;
    return super.createPaymentIntent(draft);
  }
}

class _SwitchingRepository extends FixtureCollectRepository {
  void switchAccount() {
    state = state.copyWith(
      currentProfile: const CollectProfile(
        id: 'different-account',
        publicId: '123456',
        whatsappPhone: '+250788999999',
        countryCode: 'RW',
        currencyCode: 'RWF',
        momoProvider: 'mtn_momo',
        momoNumber: '0788999999',
      ),
    );
  }
}

Future<void> _prepare(WidgetTester tester, CollectRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [collectRepositoryProvider.overrideWith((ref) => repo)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const ContributionFlowScreen(collectionId: 'qa-private-group'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, '6000');
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Continue to MoMo'));
  await tester.pumpAndSettle();
  expect(find.text('Open MoMo USSD'), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('unchanged intent is rechecked before opening MoMo USSD', (
    tester,
  ) async {
    final repo = _CountingRepository();
    var launchCalls = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('collect/momo_ussd');
    messenger.setMockMethodCallHandler(channel, (call) async {
      launchCalls++;
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await _prepare(tester, repo);
    final openAction = find.widgetWithText(FilledButton, 'Open MoMo USSD');
    await tester.ensureVisible(openAction);
    await tester.pumpAndSettle();
    await tester.tap(openAction);
    await tester.pumpAndSettle();

    expect(repo.createCalls, 2);
    expect(launchCalls, 1);
    expect(find.text('Waiting for the receipt SMS'), findsOneWidget);
  });

  testWidgets('changed receiver blocks USSD and returns to preparation', (
    tester,
  ) async {
    final repo = _RouteChangingRepository();
    var launchCalls = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('collect/momo_ussd');
    messenger.setMockMethodCallHandler(channel, (call) async {
      launchCalls++;
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await _prepare(tester, repo);
    final openAction = find.widgetWithText(FilledButton, 'Open MoMo USSD');
    await tester.ensureVisible(openAction);
    await tester.pumpAndSettle();
    await tester.tap(openAction);
    await tester.pumpAndSettle();

    expect(repo.createCalls, 2);
    expect(launchCalls, 0);
    expect(find.text('Continue to MoMo'), findsOneWidget);
    expect(
      find.text(
        'Payment details changed. Review the group receiver and prepare again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('account switch clears prepared receiver before launch', (
    tester,
  ) async {
    final repo = _SwitchingRepository();
    await _prepare(tester, repo);

    repo.switchAccount();
    await tester.pumpAndSettle();

    expect(find.text('Open MoMo USSD'), findsNothing);
    expect(find.text('Continue to MoMo'), findsOneWidget);
  });
}
