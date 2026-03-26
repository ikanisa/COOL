import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart' show Box;
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cool_app/core/services/crashlytics_service.dart';
import 'package:cool_app/core/services/momo_service.dart';
import 'package:cool_app/core/services/performance_service.dart';
import 'package:cool_app/features/auth/models/user_profile.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart'
    as app_auth;
import 'package:cool_app/features/auth/repositories/auth_repository.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockSupabaseClient extends Mock implements SupabaseClient {}

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

void main() {
  late MockAuthRepository mockRepo;
  late app_auth.AuthNotifier notifier;
  late CrashlyticsService crashlytics;
  late PerformanceService performance;

  setUpAll(() {
    registerFallbackValue(_sampleUser());
  });

  setUp(() {
    mockRepo = MockAuthRepository();
    crashlytics = CrashlyticsService();
    performance = PerformanceService();
    when(() => mockRepo.currentSession).thenReturn(null);
    when(() => mockRepo.currentUserId).thenReturn(null);
    notifier = app_auth.AuthNotifier(
      repository: mockRepo,
      crashlytics: crashlytics,
      performance: performance,
      momoService: MomoService(
        client: MockSupabaseClient(),
        openBox: _noOpOpenBox,
      ),
    );
  });

  group('AuthNotifier initial state', () {
    test('starts with no user, no session, not loading, no error', () {
      expect(notifier.state.user, isNull);
      expect(notifier.state.session, isNull);
      expect(
        notifier.state.profileRestoreState,
        app_auth.AuthProfileRestoreState.available,
      );
      expect(notifier.state.isLoading, false);
      expect(notifier.state.error, isNull);
    });
  });

  group('AuthNotifier.restoreCurrentUser', () {
    test(
      'marks the profile as missing when session exists but no profile loads',
      () async {
        final session = _fakeSession();
        when(() => mockRepo.currentSession).thenReturn(session);
        when(() => mockRepo.getCurrentProfile()).thenAnswer((_) async => null);

        await notifier.restoreCurrentUser();

        expect(notifier.state.session?.user.id, session.user.id);
        expect(notifier.state.user, isNull);
        expect(
          notifier.state.profileRestoreState,
          app_auth.AuthProfileRestoreState.missing,
        );
        expect(notifier.state.error, isNull);
      },
    );

    test(
      'marks the profile as failed when profile restoration throws',
      () async {
        final session = _fakeSession();
        when(() => mockRepo.currentSession).thenReturn(session);
        when(
          () => mockRepo.getCurrentProfile(),
        ).thenThrow(StateError('temporary profile fetch failure'));

        await notifier.restoreCurrentUser();

        expect(notifier.state.session?.user.id, session.user.id);
        expect(
          notifier.state.profileRestoreState,
          app_auth.AuthProfileRestoreState.failed,
        );
        expect(
          notifier.state.error,
          contains('temporary profile fetch failure'),
        );
      },
    );
  });

  group('AuthNotifier.signInAnonymously', () {
    test('loads an existing profile on success', () async {
      final session = _fakeSession();
      final profile = _sampleUser();
      final states = <app_auth.AuthState>[];
      final removeListener = notifier.addListener(
        states.add,
        fireImmediately: false,
      );
      addTearDown(removeListener);

      when(() => mockRepo.signInAnonymously()).thenAnswer((_) async => session);
      when(
        () => mockRepo.getProfile(session.user.id),
      ).thenAnswer((_) async => profile);

      await notifier.signInAnonymously();

      expect(states.first.isLoading, true);
      expect(notifier.state.isLoading, false);
      expect(notifier.state.session?.user.id, session.user.id);
      expect(notifier.state.user, profile);
      expect(
        notifier.state.profileRestoreState,
        app_auth.AuthProfileRestoreState.available,
      );
      expect(notifier.state.error, isNull);
    });

    test('marks the profile as missing when no profile is returned', () async {
      final session = _fakeSession();
      when(() => mockRepo.signInAnonymously()).thenAnswer((_) async => session);
      when(
        () => mockRepo.getProfile(session.user.id),
      ).thenAnswer((_) async => null);

      await notifier.signInAnonymously();

      expect(notifier.state.session?.user.id, session.user.id);
      expect(notifier.state.user, isNull);
      expect(
        notifier.state.profileRestoreState,
        app_auth.AuthProfileRestoreState.missing,
      );
      expect(notifier.state.error, isNull);
    });

    test('sets error on failure', () async {
      when(
        () => mockRepo.signInAnonymously(),
      ).thenThrow(Exception('Network error'));

      await notifier.signInAnonymously();

      expect(notifier.state.isLoading, false);
      expect(notifier.state.error, contains('Network error'));
    });

    test('maps invalid Supabase function URLs to a config error', () async {
      when(() => mockRepo.signInAnonymously()).thenThrow(
        ArgumentError('No host specified in url/functions/v1/send-otp'),
      );

      await notifier.signInAnonymously();

      expect(notifier.state.isLoading, false);
      expect(notifier.state.error, contains('SUPABASE_URL'));
      expect(notifier.state.error, isNot(contains('No host specified')));
    });
  });

  group('AuthNotifier.signOut', () {
    test('clears user and session on success', () async {
      notifier.state = app_auth.AuthState(
        user: _sampleUser(),
        session: _fakeSession(),
      );
      when(() => mockRepo.signOut()).thenAnswer((_) async {});

      await notifier.signOut();

      expect(notifier.state.user, isNull);
      expect(notifier.state.session, isNull);
      expect(notifier.state.isLoading, false);
      expect(notifier.state.error, isNull);
    });

    test('sets error on sign-out failure', () async {
      when(() => mockRepo.signOut()).thenThrow(Exception('Sign out failed'));

      await notifier.signOut();

      expect(notifier.state.isLoading, false);
      expect(notifier.state.error, contains('Sign out failed'));
    });
  });

  group('AuthNotifier.createProfile', () {
    test('returns null and sets error when no session', () async {
      when(() => mockRepo.currentUserId).thenReturn(null);

      final result = await notifier.createProfile(
        const app_auth.AuthProfileData(
          fullName: 'Test',
          momoNumber: '0788000000',
          momoProvider: 'mtn_momo_rw',
          country: 'RW',
          languageCode: 'en',
        ),
      );

      expect(result, isNull);
      expect(notifier.state.error, contains('verified session is required'));
    });
  });

  group('AuthNotifier.updateProfile', () {
    test('returns true and updates state on success', () async {
      final original = _sampleUser();
      final updated = _sampleUser(
        officialName: 'Legal User',
        officialPhone: '0788123456',
      );

      notifier.state = app_auth.AuthState(
        user: original,
        session: _fakeSession(),
      );
      when(
        () => mockRepo.updateProfile(updated),
      ).thenAnswer((_) async => updated);

      final success = await notifier.updateProfile(updated);

      expect(success, true);
      expect(notifier.state.user, updated);
      expect(notifier.state.isLoading, false);
      expect(notifier.state.error, isNull);
    });

    test('returns false and sets error on failure', () async {
      final profile = _sampleUser();
      notifier.state = app_auth.AuthState(
        user: profile,
        session: _fakeSession(),
      );
      when(
        () => mockRepo.updateProfile(any()),
      ).thenThrow(Exception('Update failed'));

      final success = await notifier.updateProfile(profile);

      expect(success, false);
      expect(notifier.state.isLoading, false);
      expect(notifier.state.error, contains('Update failed'));
    });
  });

  group('AuthState.copyWith', () {
    test('updates fields with sentinel support', () {
      const initial = app_auth.AuthState(isLoading: true, error: 'some error');
      final updated = initial.copyWith(isLoading: false, error: null);

      expect(updated.isLoading, false);
      expect(updated.error, isNull);
    });

    test('preserves unchanged fields', () {
      const initial = app_auth.AuthState(isLoading: true, error: 'error');
      final updated = initial.copyWith();

      expect(updated.isLoading, true);
      expect(updated.error, 'error');
    });
  });
}

Future<Box<T>> _noOpOpenBox<T>(String name) =>
    throw UnimplementedError('Hive disabled in tests');
