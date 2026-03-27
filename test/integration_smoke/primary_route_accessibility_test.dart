import 'dart:io';

import 'package:cool_app/core/providers/engagement_providers.dart';
import 'package:cool_app/core/services/app_access_service.dart';
import 'package:cool_app/core/services/fcm_service.dart';
import 'package:cool_app/core/status/models/cool_status.dart';
import 'package:cool_app/core/status/providers/cool_status_provider.dart';
import 'package:cool_app/core/status/repositories/cool_status_repository.dart';
import 'package:cool_app/features/groups/models/group.dart';
import 'package:cool_app/features/groups/providers/groups_provider.dart';
import 'package:cool_app/features/groups/repositories/group_repository.dart';
import 'package:cool_app/features/groups/screens/groups_screen.dart';
import 'package:cool_app/features/home/models/home_dashboard_data.dart';
import 'package:cool_app/features/home/providers/home_dashboard_provider.dart';
import 'package:cool_app/features/biopay/screens/biopay_home_screen.dart';
import 'package:cool_app/features/partners/models/partner.dart';
import 'package:cool_app/features/partners/providers/partner_provider.dart';
import 'package:cool_app/features/partners/providers/rayon_sports_provider.dart';
import 'package:cool_app/features/partners/repositories/partner_repository.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/features/home/screens/home_screen.dart';
import 'package:cool_app/features/partners/screens/partners_screen.dart';
import 'package:cool_app/features/profile/screens/profile_screen.dart';
import 'package:cool_app/l10n/app_localizations.dart';
import 'package:cool_app/shared/widgets/tab_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'test_harness.dart';

class _MockPartnerRepository extends Mock implements PartnerRepository {}

class _MockGroupRepository extends Mock implements GroupRepository {}

class _MockCoolStatusRepository extends Mock implements CoolStatusRepository {}

class _MemoryFcmPreferenceStore implements FcmPreferenceStore {
  @override
  Future<bool> readEnabled() async => true;

  @override
  Future<void> writeEnabled(bool enabled) async {}
}

class _MemoryFcmTopicPreferenceStore implements FcmTopicPreferenceStore {
  @override
  Future<Map<FcmTopicCategory, bool>> readPreferences() async {
    return const <FcmTopicCategory, bool>{
      FcmTopicCategory.matchAlerts: true,
      FcmTopicCategory.promotions: true,
      FcmTopicCategory.groupUpdates: true,
    };
  }

  @override
  Future<void> writePreference(FcmTopicCategory category, bool enabled) async {}
}

class _FakeFcmTokenRepository implements FcmTokenRepository {
  @override
  Future<void> deleteToken({
    required String userId,
    required String token,
  }) async {}

  @override
  Future<void> upsertToken({
    required String userId,
    required String token,
    required String platform,
  }) async {}
}

Widget _accessibleHarness(Widget child) {
  return Builder(
    builder: (context) {
      final mediaQuery = MediaQuery.of(context);
      return MediaQuery(
        data: mediaQuery.copyWith(
          textScaler: const TextScaler.linear(1.6),
          disableAnimations: true,
        ),
        child: child,
      );
    },
  );
}

void _expectTouchTarget(WidgetTester tester, Finder finder) {
  final size = tester.getSize(finder.first);
  expect(
    size.width >= 48 && size.height >= 48,
    isTrue,
    reason: 'Expected a touch target of at least 48x48dp.',
  );
}

void _expectNoCapturedException(WidgetTester tester) {
  final exception = tester.takeException();
  if (exception == null) {
    expect(exception, isNull);
    return;
  }

  debugPrint('Captured test exception: $exception');
  if (exception is FlutterError) {
    for (final diagnostic in exception.diagnostics) {
      debugPrint(diagnostic.toStringDeep());
    }
  }

  expect(exception, isNull);
}

Future<void> _runWithSemantics(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final semantics = tester.ensureSemantics();
  final originalErrorWidgetBuilder = ErrorWidget.builder;
  try {
    await body();
  } finally {
    ErrorWidget.builder = originalErrorWidgetBuilder;
    semantics.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDir;
  late _MockPartnerRepository partnerRepository;
  late _MockGroupRepository groupRepository;
  late _MockCoolStatusRepository coolStatusRepository;

  const sampleGroup = Group(
    id: 'group-1',
    creatorId: 'user-1',
    name: 'Kigali Savers',
    type: 'saving',
    visibility: 'public',
    amount: 250000,
    targetAmount: 500000,
    country: 'RW',
    memberCount: 12,
    inviteCode: 'GROUP1',
  );

  const samplePartner = Partner(
    id: 'urwego',
    name: 'Urwego Finance',
    slug: 'urwego',
    category: PartnerCategory.bank,
    country: 'RW',
    subtitle: 'Community banking',
    fanCount: 0,
    clubCount: 0,
    gameCount: 0,
  );

  FanMembership sampleMembership() {
    return FanMembership(
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
  }

  RsMatch sampleMatch() {
    return RsMatch(
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
  }

  RayonSportsData sampleRayonData() {
    final membership = sampleMembership();
    final match = sampleMatch();

    return RayonSportsData(
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
      clubs: const [
        RsFanClub(
          id: 'club-1',
          partnerId: 'partner-1',
          name: 'Kigali Blue',
          region: 'Kigali',
          description: 'Main chapter',
          memberCount: 120,
          eventCount: 5,
          rating: 4.8,
          bannerEmoji: '🥁',
        ),
      ],
      products: const [
        RsProduct(
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
        ),
      ],
      initiatives: const [
        RsInitiative(
          id: 'initiative-1',
          partnerId: 'partner-1',
          title: 'Youth Academy',
          description: 'Back the academy pipeline.',
          category: InitiativeCategory.youth,
          targetAmount: 1000000,
          raisedAmount: 125000,
          supporterCount: 42,
          isActive: true,
          endsAt: null,
        ),
      ],
      matches: [match],
      tickets: const <RsTicket>[],
    );
  }

  HomeDashboardData sampleDashboardData() {
    return const HomeDashboardData(
      totalBalance: 12450,
      monthlyNetChange: 200,
      memberCount: 2,
    );
  }

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('cool_accessibility');
    Hive.init(hiveDir.path);
  });

  tearDown(() async {
    for (final boxName in <String>[AppAccessService.boxName]) {
      if (Hive.isBoxOpen(boxName)) {
        await Hive.box<dynamic>(boxName).clear();
        await Hive.box<dynamic>(boxName).close();
      }
      await Hive.deleteBoxFromDisk(boxName);
    }
  });

  tearDownAll(() async {
    await hiveDir.delete(recursive: true);
  });

  setUp(() {
    partnerRepository = _MockPartnerRepository();
    groupRepository = _MockGroupRepository();
    coolStatusRepository = _MockCoolStatusRepository();

    when(
      () => partnerRepository.fetchAll(),
    ).thenAnswer((_) async => const <Partner>[samplePartner]);

    when(
      () => groupRepository.getMyGroups(any(), country: any(named: 'country')),
    ).thenAnswer((_) async => const <Group>[sampleGroup]);
    when(
      () => groupRepository.getPublicGroups(any()),
    ).thenAnswer((_) async => const <Group>[sampleGroup]);

    when(() => coolStatusRepository.getOrCreateStatus(any())).thenAnswer(
      (_) async => CoolStatus(
        id: 'status-1',
        userId: 'user-1',
        totalPoints: 120,
        tier: FanTier.blue,
        currentStreak: 2,
        longestStreak: 4,
        streakGraceRemaining: 1,
        seasonPoints: 80,
        updatedAt: DateTime(2026, 3, 12),
        createdAt: DateTime(2026, 3, 1),
      ),
    );
  });

  group('Primary route accessibility', () {
    testWidgets('Home route supports large text and accessible actions', (
      tester,
    ) async {
      await _runWithSemantics(tester, () async {
        await pumpScopedApp(
          tester,
          child: _accessibleHarness(const HomeScreen()),
          session: fakeSession(),
          user: fakeUser(fullName: 'Alex Fan'),
          overrides: <Override>[
            rayonSportsDataProvider.overrideWith(
              (ref) => AsyncData(sampleRayonData()),
            ),
            rayonMembershipProvider.overrideWith(
              (ref) => AsyncData(sampleMembership()),
            ),
            rayonNextMatchProvider.overrideWith(
              (ref) => AsyncData(sampleMatch()),
            ),
            rayonActionLoadingProvider.overrideWith((ref) => false),
            homeDashboardProvider.overrideWith((ref) => sampleDashboardData()),
          ],
        );

        await settleTestApp(tester);

        expect(find.text('QUICK SERVICES'), findsOneWidget);
        _expectTouchTarget(
          tester,
          find.ancestor(
            of: find.text('GROUPS'),
            matching: find.byType(InkWell),
          ),
        );
        _expectNoCapturedException(tester);
      });
    });

    testWidgets('BioPay route supports large text and button hit areas', (
      tester,
    ) async {
      await _runWithSemantics(tester, () async {
        await pumpScopedApp(
          tester,
          child: _accessibleHarness(const BiopayHomeScreen()),
          session: fakeSession(),
          user: fakeUser(momoNumber: '0788123456'),
        );

        expect(find.text('BioPay Hub'), findsOneWidget);
        _expectTouchTarget(
          tester,
          find.ancestor(
            of: find.text('FACE\nSCAN'),
            matching: find.byType(InkWell),
          ),
        );
        _expectNoCapturedException(tester);
      });
    });

    testWidgets('Groups route supports large text and touch targets', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await _runWithSemantics(tester, () async {
        await pumpScopedApp(
          tester,
          child: _accessibleHarness(const GroupsScreen()),
          session: fakeSession(),
          user: fakeUser(),
          overrides: <Override>[
            groupRepositoryProvider.overrideWithValue(groupRepository),
          ],
        );

        await settleTestApp(tester);

        expect(find.bySemanticsLabel(l10n.navGroups), findsWidgets);
        _expectTouchTarget(tester, find.byType(TabPill).first);
        expect(find.byType(TabPill), findsWidgets);
        _expectNoCapturedException(tester);
      });
    });

    testWidgets('Partners route supports large text and touch targets', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await _runWithSemantics(tester, () async {
        await pumpScopedApp(
          tester,
          child: _accessibleHarness(const PartnersScreen()),
          session: fakeSession(),
          user: fakeUser(),
          overrides: <Override>[
            partnerRepositoryProvider.overrideWithValue(partnerRepository),
          ],
        );

        expect(find.text(l10n.partnersTitle.toUpperCase()), findsOneWidget);
        _expectTouchTarget(
          tester,
          find.ancestor(
            of: find.text(samplePartner.name.toUpperCase()),
            matching: find.byType(GestureDetector),
          ),
        );
        _expectNoCapturedException(tester);
      });
    });

    testWidgets('Profile route supports large text and touch targets', (
      tester,
    ) async {
      await _runWithSemantics(tester, () async {
        await pumpScopedApp(
          tester,
          child: _accessibleHarness(const ProfileScreen()),
          session: fakeSession(),
          user: fakeUser().copyWith(
            publicUserId: '123456',
            officialName: 'Alex Fan',
            officialPhone: '+250788123456',
          ),
          overrides: <Override>[
            rayonSportsDataProvider.overrideWith(
              (ref) => AsyncData(sampleRayonData()),
            ),
            rayonMembershipProvider.overrideWith(
              (ref) => AsyncData(sampleMembership()),
            ),
            coolStatusRepositoryProvider.overrideWithValue(
              coolStatusRepository,
            ),
            fcmServiceProvider.overrideWithValue(
              FcmService(
                preferenceStore: _MemoryFcmPreferenceStore(),
                topicPreferenceStore: _MemoryFcmTopicPreferenceStore(),
                tokenRepository: _FakeFcmTokenRepository(),
                isFirebaseAvailable: () => false,
              ),
            ),
          ],
        );

        expect(find.text('SETTINGS'), findsOneWidget);
        _expectTouchTarget(
          tester,
          find.ancestor(
            of: find.text('ACHIEVEMENTS'),
            matching: find.byType(InkWell),
          ),
        );
        _expectNoCapturedException(tester);
      });
    });
  });
}
