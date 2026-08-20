import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpLaunchFrames(WidgetTester tester) async {
    for (var i = 0; i < 14; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpMainAppAt(
    WidgetTester tester,
    String initialLocation, {
    CollectRepository? repository,
  }) async {
    debugPrint('[uat-smoke] pumpMainAppAt router create $initialLocation');
    final router = createAppRouter(initialLocation: initialLocation);
    addTearDown(router.dispose);
    debugPrint('[uat-smoke] pumpMainAppAt app pump start $initialLocation');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          if (repository != null)
            collectRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: const CollectApp(),
      ),
    );
    debugPrint('[uat-smoke] pumpMainAppAt app pump done $initialLocation');
    await pumpLaunchFrames(tester);
    debugPrint('[uat-smoke] pumpMainAppAt frames done $initialLocation');
  }

  void expectNoGlobalSecrets() {
    expect(find.textContaining('service_role'), findsNothing);
    expect(find.textContaining('OPENAI_API_KEY'), findsNothing);
    expect(find.textContaining('WHATSAPP'), findsNothing);
    expect(find.textContaining('SMS_HOOK'), findsNothing);
  }

  testWidgets(
    'main app launches without admin or secret-bearing surface',
    (tester) async {
      debugPrint('[uat-smoke] main app pump start');
      await pumpMainAppAt(
        tester,
        '/groups',
        repository: CollectRepository.fixture(),
      );
      debugPrint('[uat-smoke] main app pump frames start');
      await pumpLaunchFrames(tester);
      debugPrint('[uat-smoke] main app assertions start');

      expect(find.text('Groups'), findsWidgets);
      expect(find.text('Platform admin'), findsNothing);
      expectNoGlobalSecrets();
      debugPrint('[uat-smoke] main app assertions passed');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'contributor creates intent and waits for receiver SMS allocation',
    (tester) async {
      final repository = CollectRepository.fixture();
      await pumpMainAppAt(
        tester,
        '/groups/col-church/contribute',
        repository: repository,
      );

      expect(find.text('Review contribution'), findsWidgets);
      expect(find.text('Initiate payment'), findsNothing);
      expect(find.textContaining('manual'), findsNothing);

      final intent = await repository.createPaymentIntent(
        const PaymentIntentDraft(collectionId: 'col-church', amountRwf: 5000),
      );
      final router = GoRouter.of(
        tester.element(find.text('Review contribution').first),
      );
      router.go('/groups/col-church');
      await pumpLaunchFrames(tester);

      expect(find.text('Payment intent'), findsNothing);
      expect(find.text('Pending payment'), findsNothing);
      expect(intent.status, 'pending');
      router.go('/groups/col-church/ledger');
      await pumpLaunchFrames(tester);

      expect(find.text('Ledger'), findsWidgets);
      expect(find.text('Payment intent'), findsNothing);
      expect(find.text('Pending payment'), findsNothing);
      expect(find.text('Anonymous supporter'), findsNothing);
      expect(find.text('Safe ledger'), findsNothing);
      expectNoGlobalSecrets();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'creator shares group link and invite without receiver leakage',
    (tester) async {
      await pumpMainAppAt(
        tester,
        '/groups/col-church/share',
        repository: CollectRepository.fixture(),
      );

      expect(find.text('Share group'), findsOneWidget);
      expect(find.text('Share link'), findsOneWidget);
      expect(find.text('Share QR code'), findsOneWidget);
      expect(find.text('St Michel building fund'), findsNothing);
      expect(
        find.textContaining('does not include phone numbers'),
        findsNothing,
      );
      expect(find.textContaining('+250788'), findsNothing);

      final router = GoRouter.of(tester.element(find.text('Share link')));
      router.go('/groups/col-church/invite');
      await pumpLaunchFrames(tester);

      expect(find.text('Share group'), findsOneWidget);
      expect(find.text('St Michel building fund'), findsNothing);
      expect(find.text('Share link'), findsOneWidget);
      expect(find.text('Share QR code'), findsOneWidget);
      expect(find.text('Save QR'), findsOneWidget);
      expect(find.text('Copy link'), findsOneWidget);
      expect(find.text('SMS'), findsNothing);
      expect(find.text('WhatsApp'), findsNothing);
      expect(find.text('Copy deep link'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('/c/'), findsNothing);
      expectNoGlobalSecrets();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
