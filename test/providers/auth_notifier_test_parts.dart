part of 'auth_notifier_test.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockSupabaseClient extends Mock implements SupabaseClient {}

class _NoOpBiopayCacheService extends BiopayCacheService {
  @override
  Future<void> clear({String? ownerUserId}) async {}
}

Session _fakeSession() {
  return Session.fromJson({
    'access_token': 'header.payload.signature',
    'expires_in': 3600,
    'refresh_token': 'refresh-token',
    'token_type': 'bearer',
    'user': {
      'id': 'user-123',
      'app_metadata': {'provider': 'phone'},
      'user_metadata': {'phone': '+250781234567'},
      'aud': 'authenticated',
      'phone': '+250781234567',
      'created_at': '2026-03-11T00:00:00.000Z',
    },
  })!;
}

UserProfile _sampleUser({String? officialName, String? officialPhone}) {
  return UserProfile(
    id: 'user-123',
    phone: '+250788123456',
    fullName: 'Public User',
    momoNumber: '0788123456',
    momoProvider: 'mtn_momo_rw',
    country: 'RW',
    languageCode: 'en',
    officialName: officialName,
    officialPhone: officialPhone,
  );
}

ProviderContainer _buildContainer(MockAuthRepository mockRepo) {
  final supabaseClient = SupabaseClient(
    'http://127.0.0.1:54321',
    'test-anon-key',
    authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
  );

  return ProviderContainer(
    overrides: <Override>[
      app_auth.authRepositoryProvider.overrideWithValue(mockRepo),
      crashlyticsServiceProvider.overrideWithValue(CrashlyticsService()),
      performanceServiceProvider.overrideWithValue(PerformanceService()),
      momoServiceProvider.overrideWithValue(
        MomoService(client: supabaseClient),
      ),
      biopayCacheServiceProvider.overrideWithValue(_NoOpBiopayCacheService()),
      app_auth.initialAuthStateProvider.overrideWithValue(
        const app_auth.AuthState(),
      ),
    ],
  );
}
