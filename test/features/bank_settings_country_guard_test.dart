import '../fixtures/collect_repository_fixture.dart';

import 'dart:async';

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/features/settings/bank_transfer_settings_screen.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _BankSettingsRepository extends FixtureCollectRepository {
  _BankSettingsRepository(String? country) : super() {
    setCountry(country);
  }

  int destinationReads = 0;
  Completer<BankTransferDestination>? pending;

  void setCountry(String? country) {
    state = state.copyWith(
      currentProfile: country == null
          ? null
          : CollectProfile(
              id: 'local-user',
              publicId: '038491',
              whatsappPhone: '+250788123456',
              countryCode: country,
              currencyCode: country == 'RW' ? 'RWF' : 'EUR',
              momoProvider: 'mtn_momo',
              momoNumber: '0788123456',
              revolutLink: 'https://revolut.me/synthetic',
              revolutAccount: '000123456789',
            ),
    );
  }

  @override
  Future<BankTransferDestination> getBankTransferDestination() {
    destinationReads++;
    return pending?.future ?? super.getBankTransferDestination();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'a non-fixture offline repository never invents approved bank details',
    () async {
      final repository = CollectRepository();
      addTearDown(repository.dispose);
      await expectLater(
        repository.getBankTransferDestination(),
        throwsStateError,
      );
    },
  );

  testWidgets(
    'country change hides a late bank response without another read',
    (tester) async {
      final repository = _BankSettingsRepository('DE');
      final fixtureDestination = await repository.getBankTransferDestination();
      repository.destinationReads = 0;
      repository.pending = Completer<BankTransferDestination>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectRepositoryProvider.overrideWith((ref) => repository),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const BankTransferSettingsScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(repository.destinationReads, 1);
      repository.setCountry('RW');
      await tester.pump();
      repository.pending!.complete(fixtureDestination);
      await tester.pumpAndSettle();
      expect(repository.destinationReads, 1);
      expect(find.text('IBAN'), findsNothing);
      expect(find.text('Profile'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final country in <String?>['RW', '', 'ZZ', null]) {
    testWidgets('$country bank deep link never requests a bank destination', (
      tester,
    ) async {
      final repository = _BankSettingsRepository(country);
      final router = createAppRouter(
        initialLocation: '/settings/bank-transfer',
      );
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
      expect(repository.destinationReads, 0);
      expect(find.text('Bank transfer details'), findsNothing);
      expect(find.text('IBAN'), findsNothing);
      expect(
        router.routeInformationProvider.value.uri.path,
        '/settings/profile',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('eligible diaspora can read the bank destination', (
    tester,
  ) async {
    final repository = _BankSettingsRepository('DE');
    final router = createAppRouter(initialLocation: '/settings/bank-transfer');
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
    expect(repository.destinationReads, 1);
    expect(find.text('Bank transfer details'), findsOneWidget);
    expect(
      router.routeInformationProvider.value.uri.path,
      '/settings/bank-transfer',
    );
    expect(tester.takeException(), isNull);
  });
}
