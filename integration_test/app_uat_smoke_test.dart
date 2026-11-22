import '../test/fixtures/collect_scroll_fixture.dart';
import '../test/fixtures/contribution_layout_repository_fixture.dart';

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
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

  Future<GoRouter> pumpMainAppAt(
    WidgetTester tester,
    String initialLocation, {
    required CollectRepository repository,
  }) async {
    final router = createAppRouter(initialLocation: initialLocation);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectBackendClientProvider.overrideWithValue(null),
          appRouterProvider.overrideWithValue(router),
          collectRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: const CollectApp(),
      ),
    );
    await pumpLaunchFrames(tester);
    return router;
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
      await pumpMainAppAt(
        tester,
        '/groups',
        repository: ContributionLayoutRepository(),
      );
      await pumpLaunchFrames(tester);

      expect(find.text('Groups'), findsWidgets);
      expect(find.text('Platform admin'), findsNothing);
      expectNoGlobalSecrets();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'contributor creates intent and waits for receiver SMS allocation',
    (tester) async {
      final repository = ContributionLayoutRepository();
      final router = await pumpMainAppAt(
        tester,
        '/groups/qa-private-group/contribute',
        repository: repository,
      );

      await revealCollectPageContent(tester, find.text('Continue to MoMo'));
      expect(find.text('Initiate payment'), findsNothing);
      expect(find.textContaining('manual'), findsNothing);

      final intent = await repository.createPaymentIntent(
        const PaymentIntentDraft(
          collectionId: 'qa-private-group',
          amountRwf: 5000,
        ),
      );
      router.go('/groups/qa-private-group');
      await pumpLaunchFrames(tester);

      expect(find.text('Payment intent'), findsNothing);
      expect(find.text('Pending payment'), findsNothing);
      expect(intent.status, 'pending');
      router.go('/groups/qa-private-group/ledger');
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
      final router = await pumpMainAppAt(
        tester,
        '/groups/qa-private-group/share',
        repository: ContributionLayoutRepository(),
      );

      void expectShareSheet() {
        expect(find.text('Share group'), findsOneWidget);
        expect(find.text('QA private group'), findsOneWidget);
        expect(find.text('Share link'), findsOneWidget);
        expect(find.text('Share QR code'), findsOneWidget);
        expect(find.text('Save QR'), findsOneWidget);
        expect(find.text('Copy link'), findsOneWidget);
        expect(find.textContaining('0788123456'), findsNothing);
        expect(find.textContaining('+250788'), findsNothing);
        expect(find.text('SMS'), findsNothing);
        expect(find.text('WhatsApp'), findsNothing);
        expect(find.text('Copy deep link'), findsNothing);
        expect(find.byType(TextField), findsNothing);
        expect(find.textContaining('/c/'), findsNothing);
        expectNoGlobalSecrets();
      }

      expectShareSheet();
      router.go('/groups/qa-private-group/invite');
      await pumpLaunchFrames(tester);
      expect(
        router.routeInformationProvider.value.uri.path,
        '/groups/qa-private-group/share',
      );
      expectShareSheet();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
