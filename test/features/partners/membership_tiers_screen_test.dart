import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/features/partners/providers/rayon_sports_provider.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/features/partners/rayon/rs_membership_package.dart';
import 'package:cool_app/features/partners/rayon/screens/membership_tiers_screen.dart';

import '../../integration_smoke/test_harness.dart';

void main() {
  final membership = FanMembership(
    id: 'membership-1',
    userId: 'user-1',
    partnerId: 'partner-rayon',
    displayName: '123456',
    tier: FanTier.gold,
    points: 2600,
    chapter: 'Kigali Central',
    membershipNumber: 'RS-2026-001',
    joinedAt: DateTime(2026, 1, 1),
  );

  testWidgets('uses managed membership package content when available', (
    tester,
  ) async {
    const managedPackage = RsMembershipPackage(
      tier: FanTier.gold,
      title: 'Executive Gold',
      subtitle: 'Priority matchday access',
      description: 'Custom admin-managed package copy.',
      benefits: <RsMembershipPackageBenefit>[
        RsMembershipPackageBenefit(
          title: 'Fast-track Entry',
          description: 'Use the expedited supporter line.',
        ),
      ],
      sortOrder: 2,
    );

    await pumpScopedApp(
      tester,
      child: const MembershipTiersScreen(),
      session: fakeSession(),
      user: fakeUser(),
      overrides: [
        rayonUserMembershipProvider.overrideWith((ref) async => membership),
        rayonMembershipPackagesProvider.overrideWith(
          (ref) async => const <RsMembershipPackage>[managedPackage],
        ),
      ],
    );

    await settleTestApp(tester);

    expect(find.text('Membership Plans'), findsOneWidget);
    expect(find.text('Executive Gold'), findsOneWidget);
    expect(find.text('Fast-track Entry'), findsOneWidget);
    expect(find.textContaining('You are a Gold'), findsOneWidget);
  });

  testWidgets(
    'falls back to default package copy when admin packages are empty',
    (tester) async {
      await pumpScopedApp(
        tester,
        child: const MembershipTiersScreen(),
        session: fakeSession(),
        user: fakeUser(),
        overrides: [
          rayonUserMembershipProvider.overrideWith((ref) async => membership),
          rayonMembershipPackagesProvider.overrideWith(
            (ref) async => const <RsMembershipPackage>[],
          ),
        ],
      );

      await settleTestApp(tester);

      // When admin packages list is empty, no tier cards are rendered.
      // Only the intro card with the user's current tier info is shown.
      expect(find.textContaining('You are a Gold'), findsOneWidget);
      expect(find.text('2600 fan Tokens earned'), findsOneWidget);
    },
  );
}
