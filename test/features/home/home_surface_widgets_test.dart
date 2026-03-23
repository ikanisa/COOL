import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/core/services/momo_service.dart';
import 'package:cool_app/features/admin/models/special_product.dart';
import 'package:cool_app/features/home/models/home_dashboard_data.dart';
import 'package:cool_app/features/home/widgets/group_savings_card.dart';
import 'package:cool_app/features/home/widgets/rayon_sport_card.dart';
import 'package:cool_app/features/home/widgets/special_product_card.dart';
import 'package:cool_app/features/momo/providers/momo_service_provider.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockMomoService extends Mock implements MomoService {}

void main() {
  testWidgets('group savings card renders summary values', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GroupSavingsCard(
            data: HomeDashboardData(
              totalBalance: 150000,
              monthlyNetChange: 0,
              memberCount: 4,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Group Savings'), findsOneWidget);
    expect(find.text('150K'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('special product card launches MoMo payment on tap', (
    tester,
  ) async {
    final momoService = MockMomoService();
    const product = SpecialProduct(
      id: 'prod-1',
      slug: 'buri-munsi',
      title: 'Buri Munsi',
      amount: 1000,
      momoRecipient: '12345',
      momoRecipientType: 'code',
      targetAudience: 'Families',
    );

    when(
      () => momoService.initiatePayment(
        recipientMomo: product.momoRecipient,
        amount: product.amount,
        reference: any(named: 'reference'),
        recipientType: MomoRecipientType.code,
      ),
    ).thenAnswer((_) async {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          momoServiceProvider.overrideWithValue(momoService),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SpecialProductCard(product: product)),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Buri Munsi'), findsOneWidget);
    expect(find.text('Pay Now'), findsOneWidget);

    await tester.tap(find.text('Pay Now'));
    await tester.pumpAndSettle();

    verify(
      () => momoService.initiatePayment(
        recipientMomo: product.momoRecipient,
        amount: product.amount,
        reference: any(named: 'reference'),
        recipientType: MomoRecipientType.code,
      ),
    ).called(1);
  });

  testWidgets('rayon sport card renders the partner summary shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: RayonSportCard(
            membershipAsync: AsyncValue<RsFanMembership?>.data(null),
            clubsAsync: AsyncValue<List<RsFanClub>>.data(<RsFanClub>[
              RsFanClub(
                id: 'club-1',
                partnerId: 'rayon',
                name: 'Kigali Blue',
                region: 'Kigali',
                description: 'Supporters club',
                memberCount: 1200,
                eventCount: 4,
                rating: 4.8,
                bannerEmoji: '🥁',
              ),
            ]),
            matchesAsync: AsyncValue<List<RsMatch>>.data(<RsMatch>[]),
            initiativesAsync: AsyncValue<List<RsInitiative>>.data(
              <RsInitiative>[],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Rayon Sports FC'), findsOneWidget);
    expect(find.text('Join'), findsOneWidget);
  });
}
