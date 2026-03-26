import 'package:cool_app/core/services/app_lifecycle_coordinator.dart';
import 'package:cool_app/core/services/app_session_coordinator.dart';
import 'package:cool_app/core/services/app_update_service.dart';
import 'package:cool_app/core/services/crashlytics_service.dart';
import 'package:cool_app/core/services/deep_link_coordinator.dart';
import 'package:cool_app/core/services/engagement_tracker.dart';
import 'package:cool_app/core/services/momo_service.dart';
import 'package:cool_app/core/services/performance_service.dart';
import 'package:cool_app/features/auth/models/user_profile.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart' as auth;
import 'package:cool_app/features/momo/services/momo_sms_autoread_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart' show Box;
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FlutterAuthClientOptions, Session, SupabaseClient;

class MockEngagementTracker extends Mock implements EngagementTracker {}

class MockCrashlyticsService extends Mock implements CrashlyticsService {}

class MockPerformanceService extends Mock implements PerformanceService {}

class MockAppSessionCoordinator extends Mock implements AppSessionCoordinator {}

class MockDeepLinkCoordinator extends Mock implements DeepLinkCoordinator {}

class MockAppUpdateService extends Mock implements AppUpdateService {}

class MockMomoSmsAutoreadService extends Mock
    implements MomoSmsAutoreadService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(const auth.AuthState());
  });

  group('AppLifecycleCoordinator', () {
    late MockEngagementTracker engagementTracker;
    late MockCrashlyticsService crashlytics;
    late MockPerformanceService performance;
    late MockAppSessionCoordinator sessionCoordinator;
    late MockDeepLinkCoordinator deepLinkCoordinator;
    late MockAppUpdateService appUpdateService;
    late MockMomoSmsAutoreadService momoSmsAutoreadService;
    late List<String> events;
    late auth.AuthState authState;
    late AppLifecycleCoordinator coordinator;

    setUp(() {
      engagementTracker = MockEngagementTracker();
      crashlytics = MockCrashlyticsService();
      performance = MockPerformanceService();
      sessionCoordinator = MockAppSessionCoordinator();
      deepLinkCoordinator = MockDeepLinkCoordinator();
      appUpdateService = MockAppUpdateService();
      momoSmsAutoreadService = MockMomoSmsAutoreadService();
      events = <String>[];
      authState = auth.AuthState(session: _fakeSession(), user: _fakeUser());

      when(() => engagementTracker.initialize()).thenAnswer((_) async {
        events.add('engagement.initialize');
      });
      when(() => crashlytics.initialize()).thenAnswer((_) async {
        events.add('crashlytics.initialize');
      });
      when(() => performance.initialize()).thenAnswer((_) async {
        events.add('performance.initialize');
      });
      when(() => engagementTracker.trackAppOpened()).thenAnswer((_) async {
        events.add('engagement.trackAppOpened');
      });
      when(() => sessionCoordinator.bootstrap(any())).thenAnswer((
        invocation,
      ) async {
        events.add('session.bootstrap');
      });
      when(
        () => sessionCoordinator.handleAuthStateChanged(any(), any()),
      ).thenAnswer((_) async {});
      when(() => deepLinkCoordinator.start()).thenAnswer((_) async {
        events.add('deepLink.start');
      });
      when(() => deepLinkCoordinator.dispose()).thenAnswer((_) {
        events.add('deepLink.dispose');
      });
      when(() => momoSmsAutoreadService.refresh()).thenAnswer((_) async {});
      when(() => appUpdateService.checkForUpdate()).thenAnswer((_) async {});

      coordinator = AppLifecycleCoordinator(
        refreshFeatureFlags: () async {
          events.add('featureFlags.refresh');
        },
        refreshSupportedCountries: () async {
          events.add('supportedCountries.refresh');
        },
        readAuthState: () => authState,
        engagementTracker: engagementTracker,
        crashlytics: crashlytics,
        performance: performance,
        sessionCoordinator: sessionCoordinator,
        deepLinkCoordinator: deepLinkCoordinator,
        momoSmsAutoreadService: momoSmsAutoreadService,
        momoService: _buildTestMomoService(),
        appUpdateService: appUpdateService,
      );
    });

    test('start runs the startup sequence once', () async {
      await coordinator.start();
      await coordinator.start();

      expect(events, <String>[
        'featureFlags.refresh',
        'supportedCountries.refresh',
        'engagement.initialize',
        'crashlytics.initialize',
        'performance.initialize',
        'engagement.trackAppOpened',
        'session.bootstrap',
        'deepLink.start',
      ]);
      verify(() => sessionCoordinator.bootstrap(authState)).called(1);
      verify(() => deepLinkCoordinator.start()).called(1);
      verify(() => appUpdateService.checkForUpdate()).called(1);
    });

    test('auth changes and resume events are delegated', () async {
      const previous = auth.AuthState();
      final next = auth.AuthState(session: _fakeSession(), user: _fakeUser());

      await coordinator.handleAuthStateChanged(previous, next);
      coordinator.handleAppResumed();

      verify(
        () => sessionCoordinator.handleAuthStateChanged(previous, next),
      ).called(1);
      verify(() => appUpdateService.checkForUpdate()).called(1);
    });

    test('dispose tears down child coordinators and allows restart', () async {
      await coordinator.start();

      coordinator.dispose();
      await coordinator.start();

      verify(() => deepLinkCoordinator.dispose()).called(1);
      verify(() => deepLinkCoordinator.start()).called(2);
    });
  });
}

MomoService _buildTestMomoService() {
  return MomoService(
    client: SupabaseClient(
      'http://127.0.0.1:54321',
      'test-anon-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    ),
    openBox: _noOpOpenBox,
  );
}

Future<Box<T>> _noOpOpenBox<T>(String name) =>
    throw UnimplementedError('Hive disabled in tests');

Session _fakeSession({
  String userId = 'user-1',
  String phone = '+250788123456',
  String country = 'RW',
}) {
  return Session.fromJson(<String, dynamic>{
    'access_token': 'token-$userId',
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'refresh-$userId',
    'user': <String, dynamic>{
      'id': userId,
      'phone': phone,
      'user_metadata': <String, dynamic>{'phone': phone, 'country': country},
      'app_metadata': const <String, dynamic>{},
      'aud': 'authenticated',
      'created_at': DateTime(2026).toIso8601String(),
    },
  })!;
}

UserProfile _fakeUser() {
  return const UserProfile(
    id: 'user-1',
    phone: '+250788123456',
    fullName: 'Alex Fan',
    momoNumber: '0788123456',
    momoCode: '123456',
    momoProvider: 'mtn_rwanda',
    country: 'RW',
    languageCode: 'en',
  );
}
