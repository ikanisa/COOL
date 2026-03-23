import 'dart:convert';
import 'dart:io';

import 'package:cool_app/core/providers/production_redesign_provider.dart';
import 'package:cool_app/features/auth/models/user_profile.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart';
import 'package:cool_app/features/partners/providers/rayon_sports_provider.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/features/partners/rayon/rayon_payment.dart';
import 'package:cool_app/features/partners/rayon/rayon_ticket_qr.dart';
import 'package:cool_app/features/partners/rayon/screens/club_shop_screen.dart';
import 'package:cool_app/features/partners/rayon/screens/fan_club_detail_screen.dart';
import 'package:cool_app/features/partners/rayon/screens/fan_clubs_screen.dart';
import 'package:cool_app/features/partners/rayon/screens/member_registry_screen.dart';
import 'package:cool_app/features/partners/rayon/screens/rayon_home_screen.dart';
import 'package:cool_app/features/partners/rayon/screens/shop_checkout_screen.dart';
import 'package:cool_app/features/partners/rayon/screens/ticket_confirmation_screen.dart';
import 'package:cool_app/features/partners/rayon/screens/tickets_screen.dart';
import 'package:cool_app/features/partners/repositories/rayon_sports_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_fonts/src/google_fonts_base.dart';
import 'package:mocktail/mocktail.dart';

class MockRayonSportsRepository extends Mock implements RayonSportsRepository {}

UserProfile _fakeUser({
  String id = 'user-1',
  String phone = '+250788123456',
  String fullName = 'Alex Fan',
  String momoNumber = '0788123456',
  String? momoCode = '123456',
  String momoProvider = 'mtn_rwanda',
  String country = 'RW',
}) {
  return UserProfile(
    id: id,
    phone: phone,
    fullName: fullName,
    momoNumber: momoNumber,
    momoCode: momoCode,
    momoProvider: momoProvider,
    country: country,
    isDriver: false,
  );
}

Future<void> _settleGoldenApp(WidgetTester tester, {int frames = 8}) async {
  for (var index = 0; index < frames * 10; index++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (!tester.binding.hasScheduledFrame) {
      break;
    }
  }
}

void main() {
  const captureKey = Key('golden-capture');
  const phoneSize = Size(390, 844);

  late FanMembership membership;
  late RsFanClub club;
  late RsProduct product;
  late RsMatch match;
  late RsTicket ticket;
  late RayonSportsData homeData;
  late PartnerPaymentRoute paymentRoute;
  late MockRayonSportsRepository repository;

  Future<void> pumpGolden(
    WidgetTester tester, {
    required Widget child,
    List<Override> overrides = const <Override>[],
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = phoneSize;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productionRedesignConfigProvider.overrideWith(
            (ref) => ProductionRedesignConfig.defaults(),
          ),
          ...overrides,
        ],
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: MediaQuery(
            data: const MediaQueryData(
              size: phoneSize,
              devicePixelRatio: 1,
              disableAnimations: true,
            ),
            child: TickerMode(
              enabled: false,
              child: RepaintBoundary(key: captureKey, child: child),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await _settleGoldenApp(tester, frames: 8);
  }

  Future<void> expectGolden(WidgetTester tester, String name) {
    return expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  setUpAll(() {
    registerFallbackValue(FanTier.blue);
    GoogleFonts.config.allowRuntimeFetching = false;
    assetManifest = const _RayonGoldenAssetManifest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', _handleMockAssetLoad);
  });

  tearDownAll(() {
    clearCache();
    assetManifest = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  setUp(() {
    membership = FanMembership(
      id: 'membership-1',
      userId: 'user-1',
      partnerId: 'partner-1',
      displayName: 'Alex Fan',
      tier: FanTier.gold,
      points: 2200,
      chapter: 'Kigali Central',
      membershipNumber: 'RS-2026-AAA111',
      joinedAt: DateTime(2026, 1, 1),
    );
    club = const RsFanClub(
      id: 'club-1',
      partnerId: 'partner-1',
      name: 'Kigali Blue',
      region: 'Kigali',
      description: 'Main chapter for city supporters.',
      memberCount: 120,
      eventCount: 5,
      rating: 4.8,
      bannerEmoji: '🥁',
    );
    product = const RsProduct(
      id: 'product-1',
      partnerId: 'partner-1',
      name: 'Replica Jersey',
      category: ProductCategory.kits,
      price: 5000,
      imageEmoji: '👕',
      bgColor: Colors.blue,
      stock: 10,
      isActive: true,
      isNew: false,
    );
    match = RsMatch(
      id: 'match-1',
      homeTeam: 'Rayon Sports',
      awayTeam: 'APR FC',
      competition: 'RPL',
      venue: 'Amahoro',
      matchDate: DateTime(2026, 4, 1),
      kickoffTime: '18:00',
      isOnSale: true,
      ticketGeneralPrice: 3000,
      ticketVipPrice: 6000,
      saleStartsAt: DateTime(2026, 3, 20),
      capacity: 1000,
    );
    ticket = RsTicket(
      id: 'ticket-1',
      matchId: match.id,
      match: match,
      userId: 'user-1',
      seatType: SeatType.general,
      amountPaid: 3000,
      qrCode: buildRayonTicketQrData(
        ticketId: 'ticket-1',
        matchId: match.id,
        purchasedAt: DateTime(2026, 3, 25),
        debugSecretOverride: 'test-ticket-qr-secret',
      ),
      momoReference: 'momo-1',
      status: TicketStatus.valid,
      purchasedAt: DateTime(2026, 3, 25),
    );
    homeData = RayonSportsData(
      partnerId: 'partner-1',
      membership: membership,
      joinedClubIds: const {'club-1'},
      registryMembers: [
        RsRegistryMember(
          userId: 'user-1',
          displayName: 'Alex Fan',
          membershipNumber: 'RS-2026-AAA111',
          points: 2200,
          tier: FanTier.gold,
          chapter: 'Kigali Central',
          joinedAt: DateTime(2026, 1, 1),
        ),
      ],
      achievements: const <RsAchievement>[],
      clubs: [club],
      products: [product],
      initiatives: const <RsInitiative>[],
      matches: [match],
      tickets: [ticket],
    );
    paymentRoute = const PartnerPaymentRoute(
      id: 'route-1',
      partnerId: 'partner-1',
      partnerName: 'Rayon Sports',
      partnerSlug: 'rayon-sports',
      countryCode: 'RW',
      providerId: 'mtn_rwanda',
      recipientCode: '060000',
      reconciliationLabel: 'Rayon Sports',
      status: PartnerPaymentRouteStatus.active,
    );

    repository = MockRayonSportsRepository();
    when(
      () => repository.getMembers(
        'partner-1',
        searchQuery: any(named: 'searchQuery'),
        filterTier: any(named: 'filterTier'),
        region: any(named: 'region'),
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      ),
    ).thenAnswer(
      (_) async => <RsRegistryMember>[
        RsRegistryMember(
          userId: 'user-1',
          displayName: 'Alex Fan',
          membershipNumber: 'RS-2026-AAA111',
          points: 3400,
          tier: FanTier.gold,
          chapter: 'Kigali Central',
          joinedAt: DateTime(2026, 2, 1),
        ),
        RsRegistryMember(
          userId: 'user-2',
          displayName: 'Jordan Blue',
          membershipNumber: 'RS-2026-BBB222',
          points: 1700,
          tier: FanTier.silver,
          chapter: 'Kigali North',
          joinedAt: DateTime(2026, 2, 4),
        ),
      ],
    );
  });

  testWidgets('rayon home command surface golden', (tester) async {
    await pumpGolden(
      tester,
      child: const RayonHomeScreen(),
      overrides: [
        currentUserProvider.overrideWith(
          (ref) => _fakeUser(fullName: 'Alex Fan'),
        ),
        rayonSportsDataProvider.overrideWith((ref) => AsyncData(homeData)),
        rayonMembershipProvider.overrideWith((ref) => AsyncData(membership)),
        rayonNextMatchProvider.overrideWith((ref) => AsyncData(match)),
        rayonActionLoadingProvider.overrideWith((ref) => false),
      ],
    );

    await expectGolden(tester, 'rayon_home_command_surface');
  });

  testWidgets('rayon fan clubs command surface golden', (tester) async {
    await pumpGolden(
      tester,
      child: const FanClubsScreen(),
      overrides: [
        rayonClubDirectoryProvider.overrideWith(
          (ref) => AsyncData(
            RayonClubDirectoryData(
              clubs: [club],
              joinedClubIds: const {'club-1'},
            ),
          ),
        ),
      ],
    );

    await expectGolden(tester, 'rayon_fan_clubs_command_surface');
  });

  testWidgets('rayon fan club detail command surface golden', (tester) async {
    final achievement = RsAchievement(
      id: 'achievement-1',
      userId: 'user-1',
      badgeType: 'chapter_lead',
      emoji: '🏆',
      name: 'Chapter Lead',
      description: 'Joined and led chapter mobilisation.',
      isEarned: true,
      earnedAt: DateTime(2026, 3, 1),
    );

    await pumpGolden(
      tester,
      child: const FanClubDetailScreen(clubId: 'club-1'),
      overrides: [
        rayonClubDirectoryProvider.overrideWith(
          (ref) => AsyncData(
            RayonClubDirectoryData(
              clubs: [club],
              joinedClubIds: const {'club-1'},
            ),
          ),
        ),
        rayonUserAchievementsProvider.overrideWith(
          (ref) async => <RsAchievement>[achievement],
        ),
      ],
    );

    await expectGolden(tester, 'rayon_fan_club_detail_command_surface');
  });

  testWidgets('rayon member registry command surface golden', (tester) async {
    await pumpGolden(
      tester,
      child: const MemberRegistryScreen(),
      overrides: [
        rayonSportsRepositoryProvider.overrideWithValue(repository),
        rayonPartnerIdProvider.overrideWith((ref) async => 'partner-1'),
      ],
    );

    await expectGolden(tester, 'rayon_member_registry_command_surface');
  });

  testWidgets('rayon club shop command surface golden', (tester) async {
    await pumpGolden(
      tester,
      child: const ClubShopScreen(),
      overrides: [
        rayonShopCatalogProvider.overrideWith(
          (ref) => AsyncData(
            RayonShopCatalogData(
              products: [product],
              membership: membership,
              cart: const {'product-1': 1},
            ),
          ),
        ),
        rayonPaymentRouteProvider.overrideWith((ref) async => paymentRoute),
      ],
    );

    await expectGolden(tester, 'rayon_club_shop_command_surface');
  });

  testWidgets('rayon tickets command surface golden', (tester) async {
    await pumpGolden(
      tester,
      child: const TicketsScreen(),
      overrides: [
        rayonTicketHubProvider.overrideWith(
          (ref) => AsyncData(
            RayonTicketHubData(
              membership: membership,
              matches: [match],
              tickets: [ticket],
            ),
          ),
        ),
        rayonPaymentRouteProvider.overrideWith((ref) async => paymentRoute),
      ],
    );

    await expectGolden(tester, 'rayon_tickets_command_surface');
  });

  testWidgets('rayon shop checkout command surface golden', (tester) async {
    await pumpGolden(
      tester,
      child: const ShopCheckoutScreen(),
      overrides: [
        rayonShopCatalogProvider.overrideWith(
          (ref) => AsyncData(
            RayonShopCatalogData(
              products: [product],
              membership: membership,
              cart: const {'product-1': 2},
            ),
          ),
        ),
        rayonPaymentRouteProvider.overrideWith((ref) async => paymentRoute),
      ],
    );

    await expectGolden(tester, 'rayon_shop_checkout_command_surface');
  });

  testWidgets('rayon ticket confirmation command surface golden', (
    tester,
  ) async {
    await pumpGolden(
      tester,
      child: const TicketConfirmationScreen(ticketId: 'ticket-1'),
      overrides: [
        rayonUserTicketsProvider.overrideWith(
          (ref) async => <RsTicket>[ticket],
        ),
      ],
    );

    await expectGolden(tester, 'rayon_ticket_confirmation_command_surface');
  });
}

Future<ByteData?> _handleMockAssetLoad(ByteData? message) async {
  if (message == null) return null;
  final key = utf8.decode(message.buffer.asUint8List());
  if (!key.startsWith('google_fonts/')) {
    return null;
  }

  final bytes = await File(key).readAsBytes();
  return ByteData.sublistView(Uint8List.fromList(bytes));
}

class _RayonGoldenAssetManifest implements AssetManifest {
  const _RayonGoldenAssetManifest();

  @override
  List<String> listAssets() => const <String>[
    'google_fonts/Barlow-Black.ttf',
    'google_fonts/Barlow-Regular.ttf',
    'google_fonts/Barlow-Medium.ttf',
    'google_fonts/Barlow-SemiBold.ttf',
    'google_fonts/Barlow-Bold.ttf',
    'google_fonts/Barlow-ExtraBold.ttf',
    'google_fonts/BarlowCondensed-Regular.ttf',
    'google_fonts/BarlowCondensed-Bold.ttf',
    'google_fonts/BarlowCondensed-ExtraBold.ttf',
    'google_fonts/BarlowCondensed-Black.ttf',
    'google_fonts/DMMono-Regular.ttf',
    'google_fonts/DMMono-Medium.ttf',
    'google_fonts/DMMono-Bold.ttf',
    'google_fonts/DMSans-Regular.ttf',
    'google_fonts/DMSans-Medium.ttf',
    'google_fonts/DMSans-Bold.ttf',
    'google_fonts/DMSans-ExtraBold.ttf',
  ];

  @override
  List<AssetMetadata>? getAssetVariants(String key) => null;
}
