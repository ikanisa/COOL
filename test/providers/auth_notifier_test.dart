import 'package:cool_app/core/providers/engagement_providers.dart';
import 'package:cool_app/core/services/crashlytics_service.dart';
import 'package:cool_app/core/services/momo_service.dart';
import 'package:cool_app/core/services/performance_service.dart';
import 'package:cool_app/features/auth/models/user_profile.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart'
    as app_auth;
import 'package:cool_app/features/auth/repositories/auth_repository.dart';
import 'package:cool_app/features/biopay/providers/biopay_providers.dart';
import 'package:cool_app/features/biopay/services/biopay_cache_service.dart';
import 'package:cool_app/features/momo/providers/momo_service_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FlutterAuthClientOptions, Session, SupabaseClient;

part 'auth_notifier_test_parts.dart';

void main() {
  late MockAuthRepository mockRepo;
  late ProviderContainer container;
  late app_auth.AuthNotifier notifier;

  setUpAll(() {
    registerFallbackValue(_sampleUser());
  });

  setUp(() {
    mockRepo = MockAuthRepository();
    when(() => mockRepo.currentSession).thenReturn(null);
    when(() => mockRepo.currentUserId).thenReturn(null);
    container = _buildContainer(mockRepo);
    notifier = container.read(app_auth.authProvider.notifier);
  });

  tearDown(() => container.dispose());

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

  group('AuthNotifier.ensureReadyForAppStart', () {
    test(
      'does not block startup when a session exists but profile restore fails',
      () async {
        final session = _fakeSession();
        when(() => mockRepo.currentSession).thenReturn(session);
        when(
          () => mockRepo.getCurrentProfile(),
        ).thenThrow(StateError('temporary profile fetch failure'));

        await notifier.ensureReadyForAppStart();

        expect(notifier.state.session?.user.id, session.user.id);
        expect(
          notifier.state.profileRestoreState,
          app_auth.AuthProfileRestoreState.failed,
        );
      },
    );

    test(
      'does not block startup when anonymous sign-in succeeds but profile load fails',
      () async {
        final session = _fakeSession();
        when(
          () => mockRepo.signInAnonymously(),
        ).thenAnswer((_) async => session);
        when(
          () => mockRepo.getProfile(session.user.id),
        ).thenThrow(StateError('temporary profile fetch failure'));

        await notifier.ensureReadyForAppStart();

        expect(notifier.state.session?.user.id, session.user.id);
        expect(
          notifier.state.profileRestoreState,
          app_auth.AuthProfileRestoreState.failed,
        );
      },
    );
  });

  group('AuthNotifier.signInAnonymously', () {
    test('loads an existing profile on success', () async {
      final session = _fakeSession();
      final profile = _sampleUser();
      final states = <app_auth.AuthState>[];
      final sub = container.listen(app_auth.authProvider, (prev, next) {
        states.add(next);
      });
      addTearDown(sub.close);

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
    test('re-establishes an anonymous session on success', () async {
      final session = _fakeSession();
      notifier.state = app_auth.AuthState(
        user: _sampleUser(),
        session: _fakeSession(),
      );
      when(() => mockRepo.signOut()).thenAnswer((_) async {});
      when(() => mockRepo.signInAnonymously()).thenAnswer((_) async => session);
      when(
        () => mockRepo.getProfile(session.user.id),
      ).thenAnswer((_) async => null);

      await notifier.signOut();

      expect(notifier.state.session?.user.id, session.user.id);
      expect(notifier.state.user, isNull);
      expect(
        notifier.state.profileRestoreState,
        app_auth.AuthProfileRestoreState.missing,
      );
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

  group('AuthNotifier.signInWithOtpSession', () {
    test('loads an existing profile after OTP session upgrade', () async {
      final session = _fakeSession();
      final profile = _sampleUser(officialPhone: '+250781234567');

      when(
        () => mockRepo.setSession(
          accessToken: 'access-token',
          refreshToken: 'refresh-token',
        ),
      ).thenAnswer((_) async => session);
      when(
        () => mockRepo.getProfile(session.user.id),
      ).thenAnswer((_) async => profile);

      final success = await notifier.signInWithOtpSession(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
      );

      expect(success, isTrue);
      expect(notifier.state.session?.user.id, session.user.id);
      expect(notifier.state.user, profile);
      expect(
        notifier.state.profileRestoreState,
        app_auth.AuthProfileRestoreState.available,
      );
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.error, isNull);
    });

    test(
      'auto-creates a profile when OTP session has phone but no profile',
      () async {
        final session = _fakeSession();
        final created = _sampleUser(officialPhone: '+250781234567');

        when(
          () => mockRepo.setSession(
            accessToken: 'access-token',
            refreshToken: 'refresh-token',
          ),
        ).thenAnswer((_) async => session);
        when(
          () => mockRepo.getProfile(session.user.id),
        ).thenAnswer((_) async => null);
        when(() => mockRepo.createProfile(any())).thenAnswer((
          invocation,
        ) async {
          final profile = invocation.positionalArguments.single as UserProfile;
          expect(profile.id, session.user.id);
          expect(profile.phone, '+250781234567');
          return created;
        });

        final success = await notifier.signInWithOtpSession(
          accessToken: 'access-token',
          refreshToken: 'refresh-token',
        );

        expect(success, isTrue);
        verify(() => mockRepo.createProfile(any())).called(1);
        expect(notifier.state.session?.user.id, session.user.id);
        expect(notifier.state.user, created);
        expect(
          notifier.state.profileRestoreState,
          app_auth.AuthProfileRestoreState.available,
        );
        expect(notifier.state.isLoading, isFalse);
        expect(notifier.state.error, isNull);
      },
    );

    test('preserves restore state when OTP session upgrade fails', () async {
      notifier.state = app_auth.AuthState(
        user: _sampleUser(),
        session: _fakeSession(),
        profileRestoreState: app_auth.AuthProfileRestoreState.available,
      );
      when(
        () => mockRepo.setSession(
          accessToken: 'bad-access',
          refreshToken: 'bad-refresh',
        ),
      ).thenThrow(StateError('OTP session failed'));

      final success = await notifier.signInWithOtpSession(
        accessToken: 'bad-access',
        refreshToken: 'bad-refresh',
      );

      expect(success, isFalse);
      expect(
        notifier.state.profileRestoreState,
        app_auth.AuthProfileRestoreState.available,
      );
      expect(notifier.state.user, isNotNull);
      expect(notifier.state.session, isNotNull);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.error, contains('OTP session failed'));
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

    test('does not send is_admin in the update payload', () async {
      final profile = _sampleUser();
      notifier.state = app_auth.AuthState(
        user: profile,
        session: _fakeSession(),
      );
      when(() => mockRepo.updateProfile(any())).thenAnswer((invocation) async {
        final updated = invocation.positionalArguments.single as UserProfile;
        final json = updated.toJson();
        // P2 RBAC alignment: is_admin must never be serialized back.
        expect(
          json.containsKey('is_admin'),
          isFalse,
          reason: 'UserProfile.toJson() must not include is_admin',
        );
        return updated;
      });

      await notifier.updateProfile(profile);

      verify(() => mockRepo.updateProfile(any())).called(1);
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
