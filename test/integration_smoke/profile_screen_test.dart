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
import 'package:cool_app/features/credit/models/credit_dashboard.dart';
import 'package:cool_app/features/credit/providers/credit_provider.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/features/profile/screens/profile_screen.dart';
import 'package:cool_app/features/profile/widgets/profile_settings_widgets.dart';

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
    });

    List<Override> overrides() {
      return <Override>[
        coolStatusRepositoryProvider.overrideWithValue(coolStatusRepository),
        creditDashboardProvider.overrideWith(
          (ref) async => const CreditDashboard(statementCount: 12, score: 712),
        ),
        fcmServiceProvider.overrideWithValue(
          FcmService(
            preferenceStore: MemoryFcmPreferenceStore(),
            tokenRepository: FakeFcmTokenRepository(),
            isFirebaseAvailable: () => false,
          ),
        ),
      ];
    }

    testWidgets(
      'shows all sections directly in flat layout',
      (tester) async {
        await pumpScopedApp(
          tester,
          child: const ProfileScreen(),
          session: fakeSession(),
          user: fakeUser().copyWith(
            publicUserId: '123456',
            officialName: 'Alex Fan',
            officialPhone: '+250788123456',
            kycStatus: 'verified',
          ),
          overrides: overrides(),
        );

        await settleTestApp(tester);

        expect(find.text('Profile'), findsOneWidget);
        expect(find.text('ACCOUNT'), findsOneWidget);
        expect(find.text('Personal Info'), findsOneWidget);
        expect(find.widgetWithText(ProfileSettingsRow, 'Mobility'), findsOneWidget);

        expect(find.text('Passenger'), findsAtLeastNWidgets(1));
        expect(find.text('MoMo Statements'), findsOneWidget);
        expect(find.text('App access'), findsOneWidget);
        expect(find.text('Support'), findsAtLeastNWidgets(1));
      },
    );

    testWidgets(
      'opens a dedicated travel role route with passenger and driver actions',
      (tester) async {
        await pumpRouterApp(
          tester,
          initialLocation: AppRoutes.profile,
          session: fakeSession(),
          user: fakeUser().copyWith(
            publicUserId: '123456',
            officialName: 'Alex Fan',
            officialPhone: '+250788123456',
            kycStatus: 'verified',
          ),
          overrides: overrides(),
        );

        await settleTestApp(tester);

        expect(find.widgetWithText(ProfileSettingsRow, 'Mobility'), findsOneWidget);

        await tester.tap(find.widgetWithText(ProfileSettingsRow, 'Mobility'));
        await tester.pumpAndSettle();

        expect(find.text('Passenger'), findsAtLeastNWidgets(1));
      },
    );

    testWidgets(
      'opens dedicated wallet and identity routes from primary rows',
      (tester) async {
        await pumpRouterApp(
          tester,
          initialLocation: AppRoutes.profile,
          session: fakeSession(),
          user: fakeUser().copyWith(
            publicUserId: '123456',
            officialName: 'Alex Fan',
            officialPhone: '+250788123456',
            kycStatus: 'verified',
          ),
          overrides: overrides(),
        );

        await settleTestApp(tester);

        await tester.tap(find.widgetWithText(ProfileSettingsRow, 'Wallet'));
        await tester.pumpAndSettle();

        expect(find.text('Mobile Money'), findsWidgets);

        await tester.tap(find.byType(BackButton).first);
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(ProfileSettingsRow, 'Personal Info'));
        await tester.pumpAndSettle();

        expect(find.text('Personal Info'), findsWidgets);
        expect(find.text('Choose document type'), findsOneWidget);
        expect(find.text('Front of ID'), findsOneWidget);
      },
    );

    testWidgets('shows driver setup state on the travel role route', (
      tester,
    ) async {
      await pumpRouterApp(
        tester,
        initialLocation: AppRoutes.profile,
        session: fakeSession(),
        user: fakeUser(isDriver: true, vehicleType: 'Cab').copyWith(
          publicUserId: '123456',
          officialName: 'Alex Fan',
          officialPhone: '+250788123456',
          kycStatus: 'verified',
        ),
        overrides: overrides(),
      );

      await settleTestApp(tester);

      expect(find.widgetWithText(ProfileSettingsRow, 'Mobility'), findsOneWidget);

      await tester.tap(find.widgetWithText(ProfileSettingsRow, 'Mobility'));
      await tester.pumpAndSettle();
      expect(find.text('Passenger'), findsWidgets);
      expect(find.text('Switch to driver'), findsNothing);
    });

    testWidgets('shows tools directly without toggle', (
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
          kycStatus: 'verified',
        ),
        overrides: overrides(),
      );

      await settleTestApp(tester);

      expect(find.text('Personal Info'), findsOneWidget);
      expect(find.text('MoMo QR'), findsOneWidget);
      expect(find.text('Cool Tokens'), findsOneWidget);
    });

    testWidgets(
      'shows admin panel directly for admin users',
      (tester) async {
        await pumpScopedApp(
          tester,
          child: const ProfileScreen(),
          session: fakeSession(),
          user: fakeUser(isAdmin: true).copyWith(
            publicUserId: '123456',
            officialName: 'Alex Fan',
            officialPhone: '+250788123456',
            kycStatus: 'verified',
          ),
          overrides: overrides(),
        );

        await settleTestApp(tester);

        expect(find.text('Admin panel'), findsOneWidget);
      },
    );

    testWidgets('shows admin panel for partner admin access', (
      tester,
    ) async {
      await pumpScopedApp(
        tester,
        child: const ProfileScreen(),
        session: fakeSession(
          appMetadata: const <String, dynamic>{
            'partner_admin_ids': ['partner-rayon'],
          },
        ),
        user: fakeUser().copyWith(
          publicUserId: '123456',
          officialName: 'Alex Fan',
          officialPhone: '+250788123456',
          kycStatus: 'verified',
        ),
        overrides: overrides(),
      );

      await settleTestApp(tester);

      expect(find.text('Admin panel'), findsOneWidget);
    });

    testWidgets('shows local momo number when stored value is E.164', (
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
          momoNumber: '+250795588248',
          kycStatus: 'verified',
        ),
        overrides: overrides(),
      );

      await settleTestApp(tester);

      expect(find.text('0795588248'), findsOneWidget);
      expect(find.text('+250 795 588 248'), findsNothing);
      expect(find.text('+250795588248'), findsNothing);
    });
  });
}
