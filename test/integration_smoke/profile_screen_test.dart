import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/core/providers/engagement_providers.dart';
import 'package:cool_app/core/services/fcm_service.dart';
import 'package:cool_app/core/router/app_routes.dart';
import 'package:cool_app/core/status/models/cool_status.dart';
import 'package:cool_app/core/status/providers/cool_status_provider.dart';
import 'package:cool_app/core/status/repositories/cool_status_repository.dart';
import 'package:cool_app/features/biopay/providers/biopay_providers.dart';
import 'package:cool_app/features/partners/providers/rayon_sports_provider.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/features/profile/screens/profile_screen.dart';

import 'test_harness.dart';

class MockCoolStatusRepository extends Mock implements CoolStatusRepository {}

class MemoryFcmPreferenceStore implements FcmPreferenceStore {
  bool _enabled = true;

  @override
  Future<bool> readEnabled() async => _enabled;

  @override
  Future<void> writeEnabled(bool enabled) async {
    _enabled = enabled;
  }
}

class MemoryFcmTopicPreferenceStore implements FcmTopicPreferenceStore {
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

class FakeFcmTokenRepository implements FcmTokenRepository {
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

void main() {
  group('Profile smoke', () {
    late MockCoolStatusRepository coolStatusRepository;
    late CoolStatus coolStatus;
    late RsFanMembership rayonMembership;

    setUp(() {
      coolStatusRepository = MockCoolStatusRepository();
      coolStatus = CoolStatus(
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
      );

      when(
        () => coolStatusRepository.getOrCreateStatus(any()),
      ).thenAnswer((_) async => coolStatus);

      rayonMembership = FanMembership(
        id: 'membership-1',
        userId: 'user-1',
        partnerId: 'partner-rayon',
        displayName: 'Alex Fan',
        tier: FanTier.gold,
        points: 2200,
        chapter: 'Kigali Central',
        membershipNumber: 'RS-2026-AAA111',
        joinedAt: DateTime(2026, 1, 1),
      );
    });

    List<Override> overrides() {
      return <Override>[
        coolStatusRepositoryProvider.overrideWithValue(coolStatusRepository),
        fcmServiceProvider.overrideWithValue(
          FcmService(
            preferenceStore: MemoryFcmPreferenceStore(),
            topicPreferenceStore: MemoryFcmTopicPreferenceStore(),
            tokenRepository: FakeFcmTokenRepository(),
            isFirebaseAvailable: () => false,
          ),
        ),
        rayonMembershipProvider.overrideWith(
          (ref) => AsyncValue<RsFanMembership?>.data(rayonMembership),
        ),
        rayonSportsDataProvider.overrideWith(
          (ref) => AsyncValue<RayonSportsData>.data(
            RayonSportsData(
              partnerId: 'partner-rayon',
              membership: rayonMembership,
              joinedClubIds: const <String>{},
              registryMembers: const <RsRegistryMember>[],
              achievements: const <RsAchievement>[],
              clubs: const <RsFanClub>[],
              products: const <RsProduct>[],
              initiatives: const <RsInitiative>[],
              matches: const <RsMatch>[],
              tickets: const <RsTicket>[],
            ),
          ),
        ),
        biopayProfileProvider.overrideWith((ref) async => null),
      ];
    }

    testWidgets('shows the current settings deck and support actions', (
      tester,
    ) async {
      await pumpScopedApp(
        tester,
        child: const ProfileScreen(),
        session: fakeSession(),
        user: fakeUser().copyWith(
          publicUserId: '123456',
          officialName: 'Alex Fan',
          officialPhone: '+250788123456',
        ),
        overrides: overrides(),
      );

      await settleTestApp(tester);

      expect(find.text('SETTINGS'), findsOneWidget);
      expect(find.text('FAN IDENTITY'), findsWidgets);
      expect(find.text('MY TICKETS'), findsOneWidget);
      expect(find.text('ACCOUNT DETAILS'), findsOneWidget);
      expect(find.text('FACE ID REGISTER'), findsOneWidget);
      expect(find.text('NOTIFICATIONS'), findsOneWidget);
      expect(find.text('PRIVACY & SECURITY'), findsOneWidget);
      expect(find.text('HELP CENTER'), findsOneWidget);
      expect(find.text('ABOUT RAYON APP'), findsOneWidget);
      expect(find.text('LOGOUT'), findsOneWidget);
    });

    testWidgets(
      'opens account, Face ID, and notification routes from settings rows',
      (tester) async {
        await pumpRouterApp(
          tester,
          initialLocation: AppRoutes.profile,
          session: fakeSession(),
          user: fakeUser().copyWith(
            publicUserId: '123456',
            officialName: 'Alex Fan',
            officialPhone: '+250788123456',
          ),
          overrides: overrides(),
        );

        await settleTestApp(tester);

        await tester.tap(find.text('ACCOUNT DETAILS'));
        await settleTestApp(tester);

        expect(find.text('ACCOUNT'), findsOneWidget);
        expect(find.text('PERSONAL INFORMATION'), findsOneWidget);
        expect(find.text('MEMBER ID'), findsOneWidget);
        expect(find.text('PHONE'), findsOneWidget);
        expect(find.text('PAYMENTS'), findsOneWidget);
        expect(find.text('PAYMENT STATUS'), findsOneWidget);
        expect(find.text('RECEIVE ROUTE'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.arrow_back_rounded).first);
        await settleTestApp(tester);

        await tester.tap(find.text('FACE ID REGISTER'));
        await settleTestApp(tester);

        expect(find.text('Register My Face'), findsOneWidget);
        expect(find.text('Receive With'), findsOneWidget);
        expect(find.text('Number'), findsOneWidget);
        expect(find.text('Code'), findsOneWidget);
        expect(find.text('MoMo Number'), findsOneWidget);
        expect(find.text('MoMo Code'), findsNothing);
        expect(find.text('CONTINUE'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.arrow_back_rounded).first);
        await settleTestApp(tester);

        await tester.tap(find.text('NOTIFICATIONS'));
        await settleTestApp(tester);

        expect(find.text('ALL NOTIFICATIONS'), findsOneWidget);
        expect(find.text('MATCH ALERTS'), findsOneWidget);
        expect(find.text('GROUP UPDATES'), findsOneWidget);
      },
    );

    testWidgets('opens help and about routes from support rows', (
      tester,
    ) async {
      await pumpRouterApp(
        tester,
        initialLocation: AppRoutes.profile,
        session: fakeSession(),
        user: fakeUser().copyWith(
          publicUserId: '123456',
          officialName: 'Alex Fan',
          officialPhone: '+250788123456',
        ),
        overrides: overrides(),
      );

      await settleTestApp(tester);

      await tester.tap(find.text('HELP CENTER'));
      await settleTestApp(tester);

      expect(find.text('HELP'), findsOneWidget);
      expect(find.text('SUPPORT CENTER'), findsOneWidget);
      expect(find.text('EMAIL SUPPORT'), findsOneWidget);
      expect(find.text('WHATSAPP SUPPORT'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded).first);
      await settleTestApp(tester);

      await tester.tap(find.text('ABOUT RAYON APP'));
      await settleTestApp(tester);

      expect(find.text('ABOUT'), findsOneWidget);
      expect(find.text('RAYON SPORTS APP'), findsOneWidget);
    });

    testWidgets('shows local momo number when stored value is E.164', (
      tester,
    ) async {
      await pumpRouterApp(
        tester,
        initialLocation: AppRoutes.profile,
        session: fakeSession(),
        user: fakeUser().copyWith(
          publicUserId: '123456',
          officialName: 'Alex Fan',
          officialPhone: '+250788123456',
          momoNumber: '+250795588248',
        ),
        overrides: overrides(),
      );

      await settleTestApp(tester);

      await tester.tap(find.text('ACCOUNT DETAILS'));
      await settleTestApp(tester);

      expect(find.text('0795588248'), findsOneWidget);
      expect(find.text('+250 795 588 248'), findsNothing);
      expect(find.text('+250795588248'), findsNothing);
    });
  });
}
