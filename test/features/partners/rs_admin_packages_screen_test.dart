import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/features/partners/providers/rayon_sports_provider.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/features/partners/rayon/providers/rs_admin_provider.dart';
import 'package:cool_app/features/partners/rayon/rs_membership_package.dart';
import 'package:cool_app/features/partners/rayon/screens/rs_admin_packages_screen.dart';
import 'package:cool_app/features/partners/repositories/rayon_sports_repository.dart';

import '../../integration_smoke/test_harness.dart';

class _MockRayonSportsRepository extends Mock
    implements RayonSportsRepository {}

void main() {
  const package = RsMembershipPackage(
    tier: FanTier.gold,
    title: 'Gold Membership',
    message: '2,000 pts - elite supporter',
    description: 'Priority access for loyal matchday supporters.',
    benefits: <RsMembershipPackageBenefit>[
      RsMembershipPackageBenefit(
        title: 'Priority Tickets',
        description: 'Get earlier access to match tickets.',
      ),
      RsMembershipPackageBenefit(
        title: '10% Shop Discount',
        description: 'Unlock supporter pricing on official gear.',
      ),
    ],
    isActive: false,
    sortOrder: 2,
  );

  final member = FanMembership(
    id: 'membership-1',
    userId: 'user-1',
    partnerId: 'partner-rayon',
    displayName: '123456',
    tier: FanTier.gold,
    points: 2400,
    chapter: 'Kigali Central',
    membershipNumber: 'RS-2026-001',
    joinedAt: DateTime(2026, 1, 1),
  );

  testWidgets('renders packages and toggles package visibility', (
    tester,
  ) async {
    final repository = _MockRayonSportsRepository();
    when(
      () => repository.upsertMembershipPackage(
        tier: package.tier,
        title: package.title,
        message: package.subtitle,
        description: package.description,
        benefits: package.benefits,
        isActive: true,
        sortOrder: package.sortOrder,
      ),
    ).thenAnswer(
      (_) async => const RsMembershipPackage(
        tier: FanTier.gold,
        title: 'Gold Membership',
        message: '2,000 pts - elite supporter',
        description: 'Priority access for loyal matchday supporters.',
        benefits: <RsMembershipPackageBenefit>[
          RsMembershipPackageBenefit(
            title: 'Priority Tickets',
            description: 'Get earlier access to match tickets.',
          ),
          RsMembershipPackageBenefit(
            title: '10% Shop Discount',
            description: 'Unlock supporter pricing on official gear.',
          ),
        ],
        isActive: true,
        sortOrder: 2,
      ),
    );

    await pumpScopedApp(
      tester,
      child: const RsAdminPackagesScreen(),
      session: fakeSession(
        appMetadata: const <String, dynamic>{
          'partner_admin_ids': ['partner-rayon'],
        },
      ),
      user: fakeUser(),
      overrides: [
        rayonSportsRepositoryProvider.overrideWithValue(repository),
        rsAdminMembershipPackagesProvider.overrideWith(
          (ref) async => const <RsMembershipPackage>[package],
        ),
        rsAdminMembersProvider.overrideWith(
          (ref) async => <FanMembership>[member],
        ),
      ],
    );

    await settleTestApp(tester);

    expect(find.text('Membership Packages'), findsWidgets);
    expect(find.text('Gold Membership'), findsOneWidget);
    expect(find.text('Priority Tickets'), findsOneWidget);
    expect(find.text('Activate'), findsOneWidget);

    await tester.tap(find.text('Activate'));
    await settleTestApp(tester);

    verify(
      () => repository.upsertMembershipPackage(
        tier: package.tier,
        title: package.title,
        message: package.subtitle,
        description: package.description,
        benefits: package.benefits,
        isActive: true,
        sortOrder: package.sortOrder,
      ),
    ).called(1);
  });
}
