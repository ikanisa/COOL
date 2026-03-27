import 'package:cool_app/features/partners/models/partner.dart';
import 'package:cool_app/features/partners/providers/partner_provider.dart';
import 'package:cool_app/features/partners/repositories/partner_repository.dart';
import 'package:cool_app/features/partners/screens/partners_screen.dart';
import 'package:cool_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockPartnerRepository extends Mock implements PartnerRepository {}

void main() {
  late MockPartnerRepository repository;

  const rayonSports = Partner(
    id: 'rayon-sports',
    name: 'Rayon Sports',
    slug: 'rayon-sports',
    category: PartnerCategory.football,
    country: 'RW',
    subtitle: 'Club experience',
    fanCount: 23000,
    clubCount: 18,
    gameCount: 4,
  );
  const prismaPartner = Partner(
    id: 'prisma',
    name: 'Prisma',
    slug: 'prisma',
    category: PartnerCategory.organization,
    country: 'RW',
    subtitle: 'Digital agency',
  );
  const bprPartner = Partner(
    id: 'bpr',
    name: 'BPR Bank',
    slug: 'bpr',
    category: PartnerCategory.bank,
    country: 'RW',
    subtitle: 'Banking partner',
  );

  Future<void> pumpPartnersScreen(
    WidgetTester tester, {
    required List<Partner> partners,
  }) async {
    when(() => repository.fetchAll()).thenAnswer((_) async => partners);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData.fromView(
          tester.view,
        ).copyWith(disableAnimations: true),
        child: ProviderScope(
          overrides: [partnerRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: PartnersScreen(),
          ),
        ),
      ),
    );

    for (var index = 0; index < 10; index++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
  }

  setUp(() {
    repository = MockPartnerRepository();
  });

  group('PartnersScreen features', () {
    testWidgets('keeps Rayon Sports out of the flat list', (tester) async {
      await pumpPartnersScreen(tester, partners: const <Partner>[rayonSports]);

      expect(find.text('PARTNERS'), findsOneWidget);
      expect(find.text('OFFICIAL PARTNER NETWORK'), findsOneWidget);
      expect(find.text('RAYON SPORTS'), findsNothing);
      expect(find.text('No partners found'), findsOneWidget);
    });

    testWidgets('renders non-Rayon partners and filters via search', (
      tester,
    ) async {
      await pumpPartnersScreen(
        tester,
        partners: const <Partner>[rayonSports, prismaPartner, bprPartner],
      );

      expect(find.text('PRISMA'), findsOneWidget);
      expect(find.text('BPR BANK'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'prisma');
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('PRISMA'), findsOneWidget);
      expect(find.text('BPR BANK'), findsNothing);
    });

    testWidgets('non-WhatsApp partner rows use the internal route affordance', (
      tester,
    ) async {
      await pumpPartnersScreen(
        tester,
        partners: const <Partner>[rayonSports, prismaPartner],
      );

      expect(find.text('PRISMA'), findsOneWidget);
      expect(find.text('DIGITAL AGENCY'), findsWidgets);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    });
  });
}
