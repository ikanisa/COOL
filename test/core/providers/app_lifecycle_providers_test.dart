import 'package:cool_app/core/providers/app_lifecycle_providers.dart';
import 'package:cool_app/core/services/app_lifecycle_coordinator.dart';
import 'package:cool_app/core/services/crashlytics_service.dart';
import 'package:cool_app/core/services/performance_service.dart';
import 'package:cool_app/features/auth/models/user_profile.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart' as auth;
import 'package:cool_app/features/auth/repositories/auth_repository.dart';
import 'package:cool_app/core/services/momo_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart' show Box;
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FlutterAuthClientOptions, Session, SupabaseClient;

class MockAuthRepository extends Mock implements AuthRepository {}

class MockAppLifecycleCoordinator extends Mock
    implements AppLifecycleCoordinator {}

class MutableAuthNotifier extends auth.AuthNotifier {
  MutableAuthNotifier({
    required super.repository,
    required super.crashlytics,
    required super.performance,
    required super.momoService,
    required auth.AuthState initialState,
  }) {
    state = initialState;
  }

  void setAuthState(auth.AuthState value) {
    state = value;
  }

  @override
  Future<void> restoreCurrentUser() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(const auth.AuthState());
  });

  testWidgets(
    'appLifecycleBindingProvider starts the coordinator and forwards events',
    (tester) async {
      final authRepository = MockAuthRepository();
      final coordinator = MockAppLifecycleCoordinator();
      const initialState = auth.AuthState();
      final nextState = auth.AuthState(
        session: _fakeSession(),
        user: _fakeUser(),
      );

      when(() => authRepository.currentSession).thenReturn(null);
      when(() => coordinator.start()).thenAnswer((_) async {});
      when(
        () => coordinator.handleAuthStateChanged(any(), any()),
      ).thenAnswer((_) async {});
      when(() => coordinator.handleAppResumed()).thenAnswer((_) {});

      final container = ProviderContainer(
        overrides: <Override>[
          appLifecycleCoordinatorProvider.overrideWithValue(coordinator),
          auth.authRepositoryProvider.overrideWithValue(authRepository),
          auth.authProvider.overrideWith(
            (ref) => MutableAuthNotifier(
              repository: authRepository,
              crashlytics: CrashlyticsService(),
              performance: PerformanceService(),
              momoService: _buildTestMomoService(),
              initialState: initialState,
            ),
          ),
        ],
      );
      var disposed = false;
      addTearDown(() {
        if (!disposed) {
          container.dispose();
        }
      });

      container.read(appLifecycleBindingProvider);
      await tester.pump();

      verify(() => coordinator.start()).called(1);

      final notifier =
          container.read(auth.authProvider.notifier) as MutableAuthNotifier;
      notifier.setAuthState(nextState);
      await tester.pump();

      verify(
        () => coordinator.handleAuthStateChanged(initialState, nextState),
      ).called(1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      verify(() => coordinator.handleAppResumed()).called(1);

      disposed = true;
      container.dispose();
      clearInteractions(coordinator);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      verifyNever(() => coordinator.handleAppResumed());
    },
  );
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
