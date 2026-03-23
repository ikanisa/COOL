import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/features/partners/rayon/providers/rs_admin_provider.dart';
import 'package:cool_app/features/partners/rayon/screens/rs_admin_analytics_screen.dart';
import 'package:cool_app/features/partners/rayon/screens/rs_admin_initiatives_screen.dart';
import 'package:cool_app/features/partners/rayon/screens/rs_admin_members_screen.dart';
import 'package:cool_app/features/partners/rayon/screens/rs_admin_orders_screen.dart';

import '../../helpers/google_fonts_test_assets.dart';
import '../../integration_smoke/test_harness.dart';

void main() {
  setUp(setUpBundledGoogleFonts);
  tearDown(tearDownBundledGoogleFonts);

  const product = RsProduct(
    id: 'product-1',
    partnerId: 'partner-rayon',
    name: 'Replica Jersey',
    category: ProductCategory.kits,
    price: 5000,
    imageEmoji: '👕',
    bgColor: Color(0xFF0A57B7),
    stock: 12,
    isActive: true,
    isNew: false,
    description: 'Official home jersey',
  );

  final order = RsShopOrder(
    id: 'abcd1234-0001',
    userId: 'user-1',
    partnerId: 'partner-rayon',
    items: <CartItem>[
      CartItem(product: product, quantity: 2, selectedVariant: 'XL'),
    ],
    subtotal: 10000,
    discountAmount: 0,
    deliveryFee: 500,
    total: 10500,
    deliveryAddress: 'Kigali Heights',
    momoReference: 'MOMO-123',
    status: OrderStatus.paid,
    createdAt: DateTime(2026, 4, 2, 14, 30),
  );

  final member = FanMembership(
    id: 'membership-1',
    userId: 'user-1',
    partnerId: 'partner-rayon',
    displayName: 'Alex Fan',
    tier: FanTier.gold,
    points: 2400,
    chapter: 'Kigali Central',
    membershipNumber: 'RS-2030-001',
    joinedAt: DateTime(2026, 1, 1),
    expiresAt: DateTime(2030, 1, 1),
  );

  final initiative = RsInitiative(
    id: 'initiative-1',
    partnerId: 'partner-rayon',
    title: 'Community Pitch Roof',
    description: 'Protect matchday supporters and youth academy sessions.',
    category: InitiativeCategory.community,
    targetAmount: 900000,
    raisedAmount: 450000,
    supporterCount: 87,
    isActive: true,
    endsAt: DateTime(2026, 9, 30),
  );

  testWidgets('admin orders screen renders stronger order command surfaces', (
    tester,
  ) async {
    await pumpScopedApp(
      tester,
      child: const RsAdminOrdersScreen(),
      user: fakeUser(isAdmin: true),
      session: fakeSession(
        appMetadata: const <String, dynamic>{'is_admin': true},
      ),
      overrides: [
        rsAdminOrdersProvider.overrideWith((ref) async => <RsShopOrder>[order]),
      ],
    );

    await settleTestApp(tester);

    expect(find.text('RAYON SPORTS COMMAND'), findsOneWidget);
    expect(find.text('#ABCD1234'), findsOneWidget);
    expect(find.text('Move to Confirmed'), findsOneWidget);

    await tester.tap(find.text('#ABCD1234'));
    await settleTestApp(tester);

    expect(find.text('Official Fulfilment Order'), findsOneWidget);
  });

  testWidgets('admin members screen renders stronger roster card actions', (
    tester,
  ) async {
    await pumpScopedApp(
      tester,
      child: const RsAdminMembersScreen(),
      user: fakeUser(isAdmin: true),
      session: fakeSession(
        appMetadata: const <String, dynamic>{'is_admin': true},
      ),
      overrides: [
        rsAdminMembersProvider.overrideWith(
          (ref) async => <FanMembership>[member],
        ),
      ],
    );

    await settleTestApp(tester);

    expect(find.text('Alex Fan'), findsOneWidget);
    expect(find.text('RS-2030-001  •  GOLD'), findsOneWidget);
    expect(find.text('Tier'), findsOneWidget);
    expect(find.text('Renew'), findsOneWidget);
  });

  testWidgets('admin initiatives screen renders stronger cause command tile', (
    tester,
  ) async {
    await pumpScopedApp(
      tester,
      child: const RsAdminInitiativesScreen(),
      user: fakeUser(isAdmin: true),
      session: fakeSession(
        appMetadata: const <String, dynamic>{'is_admin': true},
      ),
      overrides: [
        rsAdminInitiativesProvider.overrideWith(
          (ref) async => <RsInitiative>[initiative],
        ),
      ],
    );

    await settleTestApp(tester);

    expect(find.text('Community Pitch Roof'), findsOneWidget);
    expect(find.text('Supporters'), findsOneWidget);
    expect(find.text('ACTIVE'), findsWidgets);
  });

  testWidgets('admin analytics screen renders executive scoreboard', (
    tester,
  ) async {
    await pumpScopedApp(
      tester,
      child: const RsAdminAnalyticsScreen(),
      user: fakeUser(isAdmin: true),
      session: fakeSession(
        appMetadata: const <String, dynamic>{'is_admin': true},
      ),
      overrides: [
        rsAdminOrdersProvider.overrideWith((ref) async => <RsShopOrder>[order]),
        rsAdminMembersProvider.overrideWith(
          (ref) async => <FanMembership>[member],
        ),
        rsAdminFanAnalyticsProvider.overrideWith(
          (ref) async => <String, dynamic>{
            'total_members': 1,
            'active_memberships': 1,
            'total_tickets_sold': 16,
            'ticket_revenue': 3750,
            'total_matches': 4,
            'upcoming_matches': 2,
            'membership_packages': 3,
            'notifications_sent': 9,
          },
        ),
      ],
    );

    await settleTestApp(tester);

    expect(find.text('Executive Scoreboard'), findsOneWidget);
    expect(find.text('14,250 RWF'), findsOneWidget);
    expect(find.text('Members by Tier'), findsOneWidget);
  });
}
