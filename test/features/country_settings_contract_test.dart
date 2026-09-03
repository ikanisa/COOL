import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final country in ['RW', 'GB']) {
    testWidgets('$country security guidance follows its contribution rail', (
      tester,
    ) async {
      final repository = CollectRepository.fixture(
        profileOverride: CollectProfile(
          id: 'local-country-contract',
          publicId: '123456',
          whatsappPhone: '+250788123456',
          countryCode: country,
          currencyCode: country == 'RW' ? 'RWF' : 'GBP',
          momoProvider: 'mtn_momo',
          momoNumber: '0788123456',
          revolutLink: 'https://revolut.me/localtest',
          revolutAccount: 'Local test account',
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
      expect(
        find.text(
          country == 'RW'
              ? 'Approve payments in MoMo'
              : 'Approve transfers in your bank app',
        ),
        findsOneWidget,
      );
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
