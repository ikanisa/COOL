import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/features/credit/models/credit_dashboard.dart';
import 'package:cool_app/features/credit/models/partner_credit_application.dart';
import 'package:cool_app/features/credit/providers/credit_provider.dart';
import 'package:cool_app/features/credit/repositories/credit_application_repository.dart';
import 'package:cool_app/features/credit/repositories/credit_repository.dart';
import 'package:cool_app/features/credit/screens/credit_readiness_screen.dart';
import 'package:cool_app/features/partners/models/partner.dart';
import 'package:cool_app/features/partners/providers/partner_provider.dart';
import 'package:cool_app/features/partners/repositories/partner_repository.dart';

import 'test_harness.dart';

class MockCreditRepository extends Mock implements CreditRepository {}

class MockCreditApplicationRepository extends Mock
    implements CreditApplicationRepository {}

class MockPartnerRepository extends Mock implements PartnerRepository {}

void main() {
  group('Credit readiness screen', () {
    testWidgets('shows one primary next step and a shortened checklist', (
      tester,
    ) async {
      final creditRepository = MockCreditRepository();
      final applicationRepository = MockCreditApplicationRepository();
      final partnerRepository = MockPartnerRepository();

      const dashboard = CreditDashboard(
        statementCount: 18,
        groupContributionCount: 5,
        activeMonthCount: 4,
        score: 720,
        scoreBand: 'good',
      );
      const applications = <PartnerCreditApplication>[
        PartnerCreditApplication(
          id: 'app-1',
          userId: 'user-1',
          partnerId: 'partner-1',
          partnerName: 'BK Bank',
          partnerSlug: 'bk-bank',
          partnerEmoji: '🏦',
          applicationType: 'loan',
          status: 'in_review',
          readinessState: 'ready',
          officialName: 'Alex Fan',
          officialPhone: '+250788123456',
          kycStatus: 'verified',
          creditScore: 720,
        ),
      ];
      const partners = <Partner>[
        Partner(
          id: 'partner-1',
          name: 'BK Bank',
          slug: 'bk-bank',
          category: PartnerCategory.bank,
          country: 'RW',
          subtitle: 'Flexible lending for active wallet users',
        ),
      ];

      when(
        () => creditRepository.loadDashboard(any()),
      ).thenAnswer((_) async => dashboard);
      when(
        () => applicationRepository.fetchMyApplications(),
      ).thenAnswer((_) async => applications);
      when(
        () => partnerRepository.fetchAll(country: any(named: 'country')),
      ).thenAnswer((_) async => partners);

      final user = fakeUser().copyWith(
        officialName: 'Alex Fan',
        officialPhone: '+250788123456',
        kycStatus: 'verified',
      );

      await pumpScopedApp(
        tester,
        child: const CreditReadinessScreen(),
        session: fakeSession(),
        user: user,
        overrides: <Override>[
          creditRepositoryProvider.overrideWithValue(creditRepository),
          creditApplicationRepositoryProvider.overrideWithValue(
            applicationRepository,
          ),
          partnerRepositoryProvider.overrideWithValue(partnerRepository),
        ],
      );

      expect(find.text('Credit readiness'), findsOneWidget);
      expect(find.text('Next step'), findsOneWidget);
      expect(find.text('The user can move to partners'), findsOneWidget);
      expect(find.text('Readiness checks'), findsOneWidget);
      expect(find.text('+6 more checks'), findsOneWidget);
      expect(find.text('Recent applications'), findsOneWidget);
      expect(find.text('Eligible partners'), findsOneWidget);
      expect(find.text('BK Bank'), findsWidgets);
    });
  });
}
