import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/core/providers/engagement_providers.dart';
import 'package:cool_app/core/services/fcm_service.dart';
import 'package:cool_app/core/status/models/cool_status.dart';
import 'package:cool_app/core/status/providers/cool_status_provider.dart';
import 'package:cool_app/core/status/repositories/cool_status_repository.dart';
import 'package:cool_app/features/credit/models/credit_dashboard.dart';
import 'package:cool_app/features/credit/providers/credit_provider.dart';
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

class FakeFcmTokenRepository implements FcmTokenRepository {
  @override
  Future<void> deleteToken({required String userId, required String token}) async {}

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
          (ref) async => const CreditDashboard(
            statementCount: 12,
            score: 712,
          ),
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

    testWidgets('shows primary actions and hides secondary tools by default', (
      tester,
    ) async {
      await pumpScopedApp(
        tester,
        child: const ProfileScreen(),
        session: fakeSession(),
        user: fakeUser().copyWith(
          officialName: 'Alex Fan',
          officialPhone: '+250788123456',
          kycStatus: 'verified',
        ),
        overrides: overrides(),
      );

      await settleTestApp(tester);

      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Official name'), findsOneWidget);
      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('Identity'), findsOneWidget);
      expect(find.text('Mobile Money'), findsOneWidget);
      expect(find.text('Credit score'), findsOneWidget);
      expect(find.text('Preferences'), findsOneWidget);
      expect(find.text('More tools'), findsOneWidget);

      expect(find.text('Credit readiness'), findsNothing);
      expect(find.text('MoMo QR code'), findsNothing);
      expect(find.text('COOL status'), findsNothing);
    });

    testWidgets('reveals secondary shortcuts when more tools expands', (
      tester,
    ) async {
      await pumpScopedApp(
        tester,
        child: const ProfileScreen(),
        session: fakeSession(),
        user: fakeUser().copyWith(
          officialName: 'Alex Fan',
          officialPhone: '+250788123456',
          kycStatus: 'verified',
        ),
        overrides: overrides(),
      );

      await tester.tap(find.text('More tools'));
      await settleTestApp(tester);

      expect(find.text('Credit readiness'), findsOneWidget);
      expect(find.text('MoMo QR code'), findsOneWidget);
      expect(find.text('COOL status'), findsOneWidget);
    });
  });
}
