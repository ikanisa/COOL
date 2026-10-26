import 'package:collect_app/admin/cloudflare_admin_app.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/main_admin_cloudflare.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'cloudflare_evidence_test_support.dart';
import '../support/legacy_backend_fixture.dart';

Future<ProviderContainer> evidenceView(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session = CloudflareAdminSession(
    MockClient((request) async {
      if (request.url.path.endsWith('/auth/session')) {
        return evidenceResponse(evidenceTestSession());
      }
      if (request.url.path.endsWith('/core/overview')) {
        return evidenceResponse(evidenceFixture('after_reversal'));
      }
      if (request.url.path.endsWith('/core/ledgers')) {
        return evidenceResponse(evidenceFixture('reversal_ledger'));
      }
      if (request.url.path.endsWith('/core/transactions')) {
        return evidenceResponse(evidenceFixture('transactions'));
      }
      return evidenceResponse({
        'error': {'message': 'Unavailable in this fixture'},
      }, 501);
    }),
    origin: Uri.parse('https://admin.example.test/'),
    environment: legacyBackendFixtureEnvironment,
  );
  final container = ProviderContainer(
    overrides: [
      ...cloudflareAdminOverrides(),
      cloudflareAdminSessionProvider.overrideWith((_) => session),
    ],
  );
  addTearDown(container.dispose);
  await session.refresh();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const CloudflareAdminApp(),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
    'overview shows source-bound amounts and no accounting-journal claim',
    (tester) async {
      final container = await evidenceView(tester);
      expect(find.text('Net recorded contributions'), findsOneWidget);
      expect(find.text('Recorded evidence amount'), findsOneWidget);
      expect(find.text('Posted journals'), findsNothing);
      expect(find.text('Balanced ledgers'), findsNothing);
      expect(
        find.text(
          'Amounts reflect retained evidence and recorded contributions. Provider settlement and accounting journals are not verified.',
        ),
        findsOneWidget,
      );
      container.read(cloudflareAdminSessionProvider.notifier).clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'ledger reversal keeps the visible negative amount and disables unsupported posting',
    (tester) async {
      final container = await evidenceView(tester);
      container
          .read(cloudflareAdminRouterProvider)
          .go('/admin/ledgers?status=reversal');
      await tester.pumpAndSettle();
      expect(find.text('Signed amount (RWF)'), findsOneWidget);
      expect(find.text('Contribution reversal'), findsOneWidget);
      final amount =
          ((evidenceFixture('reversal_ledger')['rows'] as List).single
                  as Map)['signed_amount_rwf']
              as int;
      final digits = (-amount).toString();
      final grouped = digits.replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );
      expect(find.text('-$grouped'), findsWidgets);
      expect(find.text('Debit'), findsNothing);
      expect(find.text('Credit'), findsNothing);
      expect(find.text('Balanced'), findsNothing);
      final control = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Journal posting unavailable'),
      );
      expect(control.onPressed, isNull);
      expect(tester.takeException(), isNull);
      container.read(cloudflareAdminSessionProvider.notifier).clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
