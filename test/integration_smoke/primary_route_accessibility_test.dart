import 'dart:io';

import 'package:cool_app/core/providers/engagement_providers.dart';
import 'package:cool_app/core/services/app_access_service.dart';
import 'package:cool_app/core/services/fcm_service.dart';
import 'package:cool_app/core/services/location_service.dart';
import 'package:cool_app/core/status/models/cool_status.dart';
import 'package:cool_app/core/status/providers/cool_status_provider.dart';
import 'package:cool_app/core/status/repositories/cool_status_repository.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart';
import 'package:cool_app/features/credit/models/credit_dashboard.dart';
import 'package:cool_app/features/credit/providers/credit_provider.dart';
import 'package:cool_app/features/groups/models/group.dart';
import 'package:cool_app/features/groups/providers/groups_provider.dart';
import 'package:cool_app/features/groups/repositories/group_repository.dart';
import 'package:cool_app/features/groups/screens/groups_screen.dart';
import 'package:cool_app/features/home/models/home_dashboard_data.dart';
import 'package:cool_app/features/home/models/quick_action.dart';
import 'package:cool_app/features/home/providers/home_dashboard_provider.dart';
import 'package:cool_app/features/home/providers/quick_action_provider.dart';
import 'package:cool_app/features/home/screens/home_screen.dart';
import 'package:cool_app/features/mobility/models/driver_profile.dart';
import 'package:cool_app/features/mobility/models/subscription_status.dart';
import 'package:cool_app/features/mobility/models/trip_type.dart';
import 'package:cool_app/features/mobility/providers/driver_provider.dart';
import 'package:cool_app/features/mobility/providers/mobility_location_provider.dart';
import 'package:cool_app/features/mobility/providers/mobility_provider.dart';
import 'package:cool_app/features/mobility/repositories/mobility_repository.dart';
import 'package:cool_app/features/mobility/repositories/subscription_repository.dart';
import 'package:cool_app/features/mobility/screens/mobility_home_screen.dart';
import 'package:cool_app/features/momo/screens/momo_screen.dart';
import 'package:cool_app/features/partners/models/partner.dart';
import 'package:cool_app/features/partners/providers/partner_provider.dart';
import 'package:cool_app/features/partners/repositories/partner_repository.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/features/partners/screens/partners_screen.dart';
import 'package:cool_app/features/profile/screens/profile_screen.dart';
import 'package:cool_app/features/profile/widgets/profile_settings_widgets.dart';
import 'package:cool_app/shared/widgets/cool_button.dart';
import 'package:cool_app/shared/widgets/tab_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/core/status/providers/home_status_providers.dart';

import 'test_harness.dart';

class _MockPartnerRepository extends Mock implements PartnerRepository {}

class _MockGroupRepository extends Mock implements GroupRepository {}

class _MockCoolStatusRepository extends Mock implements CoolStatusRepository {}

class _MockMobilityRepository extends Mock implements MobilityRepository {}

class _MockSubscriptionRepository extends Mock
    implements SubscriptionRepository {}

class _MemoryFcmPreferenceStore implements FcmPreferenceStore {
  @override
  Future<bool> readEnabled() async => true;

  @override
  Future<void> writeEnabled(bool enabled) async {}
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

class _DisabledLocationService implements LocationService {
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.denied;

  @override
  double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    return 0;
  }

  @override
  Future<Position> getCurrentLocation({
    LocationAccuracy accuracy = LocationAccuracy.high,
    Duration? timeLimit,
  }) {
    throw StateError('Location unavailable in accessibility tests.');
  }

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async {
    return LocationAccuracyStatus.precise;
  }

  @override
  Future<Position?> getLastKnownLocation() async => null;

  @override
  Future<bool> isLocationServiceEnabled() async => false;

  @override
  bool isWithin10km(Position userPos, double targetLat, double targetLng) {
    return false;
  }

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.denied;

  @override
  Future<void> startLocationUpdates(void Function(Position) onUpdate) async {}

  @override
  Future<void> stopLocationUpdates() async {}
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
    size.width >= 48 || size.height >= 48,
    isTrue,
    reason: 'Expected a touch target of at least 48dp in one dimension.',
  );
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
  late _MockMobilityRepository mobilityRepository;
  late _MockSubscriptionRepository subscriptionRepository;

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

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('cool_accessibility');
    Hive.init(hiveDir.path);
    registerFallbackValue(TripType.passenger);
  });

  tearDown(() async {
    for (final boxName in <String>[
      AppAccessService.boxName,
      'mobility_location_cache',
    ]) {
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
    mobilityRepository = _MockMobilityRepository();
    subscriptionRepository = _MockSubscriptionRepository();

    when(
      () => partnerRepository.fetchAll(country: any(named: 'country')),
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

    when(() => mobilityRepository.getDriverProfile(any())).thenAnswer(
      (_) async => const DriverProfile(
        userId: 'user-1',
        fullName: 'Alex Driver',
        vehicleType: 'Cab',
        isOnline: true,
      ),
    );
    when(
      () => mobilityRepository.getMyTrips(any()),
    ).thenAnswer((_) async => const []);
    when(
      () => mobilityRepository.getNearbyDrivers(any(), any(), any(), any()),
    ).thenAnswer((_) async => const []);
    when(
      () => mobilityRepository.getScheduledTrips(
        any(),
        any(),
        any(),
        any(),
        any(),
      ),
    ).thenAnswer((_) async => const []);
    when(() => subscriptionRepository.getSubscriptionStatus(any())).thenAnswer(
      (_) async =>
          SubscriptionStatus.freeTier(driverId: 'user-1', tripsUsed: 0),
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
          user: fakeUser(),
          overrides: <Override>[
            homeDashboardProvider.overrideWith(
              (ref) async => HomeDashboardData(
                totalBalance: 120000,
                monthlyNetChange: 15000,
                memberCount: 3,
                recentTransactions: <HomeDashboardTransaction>[
                  HomeDashboardTransaction(
                    title: 'Contribution',
                    type: 'credit',
                    amount: 5000,
                    currency: 'RWF',
                    recordedAt: DateTime(2026, 3, 12, 10),
                  ),
                ],
              ),
            ),
            currentCountryQuickActionsProvider.overrideWith(
              (ref) async => const <QuickAction>[
                QuickAction(
                  id: 'momo',
                  title: 'MoMo',
                  subtitle: 'Pay and statements',
                  route: '/momo',
                ),
              ],
            ),
            activeSeasonProvider.overrideWith((ref) async => null),
            questsProvider.overrideWith((ref) => const []),
          ],
        );

        expect(find.bySemanticsLabel('Home'), findsWidgets);
        _expectTouchTarget(
          tester,
          find.ancestor(
            of: find.text('Statements'),
            matching: find.byType(ConstrainedBox),
          ),
        );
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('MoMo route supports large text and button hit areas', (
      tester,
    ) async {
      await _runWithSemantics(tester, () async {
        await pumpScopedApp(
          tester,
          child: _accessibleHarness(const MomoScreen()),
          session: fakeSession(),
          user: fakeUser(momoNumber: '0788123456'),
        );

        expect(find.bySemanticsLabel('Mobile Money'), findsWidgets);
        _expectTouchTarget(tester, find.byType(CoolButton));
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('Groups route supports large text and touch targets', (
      tester,
    ) async {
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

        expect(find.bySemanticsLabel('Groups'), findsWidgets);
        _expectTouchTarget(
          tester,
          find.ancestor(
            of: find.text('Create a new group'),
            matching: find.byType(GestureDetector),
          ),
        );
        expect(find.byType(TabPill), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('Mobility route supports large text and touch targets', (
      tester,
    ) async {
      await _runWithSemantics(tester, () async {
        await pumpScopedApp(
          tester,
          child: _accessibleHarness(const MobilityHomeScreen()),
          session: fakeSession(),
          user: fakeUser(isDriver: true, vehicleType: 'Cab'),
          overrides: <Override>[
            mobilityRepositoryProvider.overrideWithValue(mobilityRepository),
            subscriptionRepositoryProvider.overrideWithValue(
              subscriptionRepository,
            ),
            locationServiceProvider.overrideWithValue(
              _DisabledLocationService(),
            ),
          ],
        );

        await settleTestApp(tester);

        expect(find.bySemanticsLabel('Mobility'), findsWidgets);
        _expectTouchTarget(tester, find.byType(CoolButton));
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('Partners route supports large text and touch targets', (
      tester,
    ) async {
      await _runWithSemantics(tester, () async {
        await pumpScopedApp(
          tester,
          child: _accessibleHarness(const PartnersScreen()),
          session: fakeSession(),
          user: fakeUser(),
          overrides: <Override>[
            partnerRepositoryProvider.overrideWithValue(partnerRepository),
            currentUserCountryCodeProvider.overrideWith((ref) => 'RW'),
          ],
        );

        expect(find.bySemanticsLabel('Partners'), findsWidgets);
        _expectTouchTarget(
          tester,
          find.byKey(const ValueKey('partner_feature_fan_registry')),
        );
        expect(tester.takeException(), isNull);
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
            kycStatus: 'verified',
          ),
          overrides: <Override>[
            coolStatusRepositoryProvider.overrideWithValue(
              coolStatusRepository,
            ),
            creditDashboardProvider.overrideWith(
              (ref) async =>
                  const CreditDashboard(score: 712, statementCount: 12),
            ),
            fcmServiceProvider.overrideWithValue(
              FcmService(
                preferenceStore: _MemoryFcmPreferenceStore(),
                tokenRepository: _FakeFcmTokenRepository(),
                isFirebaseAvailable: () => false,
              ),
            ),
          ],
        );

        expect(find.bySemanticsLabel('Profile'), findsWidgets);
        _expectTouchTarget(tester, find.byType(ProfileSectionToggleCard));
        expect(tester.takeException(), isNull);
      });
    });
  });
}
