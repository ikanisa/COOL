import '../fixtures/collect_repository_fixture.dart';

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final country in ['RW']) {
    testWidgets('$country security guidance follows its contribution rail', (
      tester,
    ) async {
      final repository = FixtureCollectRepository(
        profileOverride: CollectProfile(
          id: 'local-country-contract',
          publicId: '123456',
          whatsappPhone: '+250788123456',
          countryCode: country,
          currencyCode: 'RWF',
          momoProvider: 'mtn_momo',
          momoNumber: '0788123456',
        ),
      );
      final router = createAppRouter(initialLocation: '/settings/security');
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appRouterProvider.overrideWithValue(router),
            collectRepositoryProvider.overrideWith((ref) => repository),
          ],
          child: const CollectApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Approve payments in MoMo'), findsOneWidget);
      if (country == 'RW') {
        expect(
          find.textContaining('statement-reconciled bank receipts'),
          findsNothing,
        );
        expect(find.text('Bank detail privacy'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
