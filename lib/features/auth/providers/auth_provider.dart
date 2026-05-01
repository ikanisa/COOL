import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export 'auth_provider_support.dart'
    show
        AuthProfileData,
        currentUserCountryCodeProvider,
        resolveAuthStateCountryCode;

import '../../../core/auth/auth_user_contact.dart';
import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/providers/engagement_providers.dart';
import '../../../core/providers/supabase_client_provider.dart';
import '../../../core/services/crashlytics_service.dart';
import '../../../core/services/momo_service.dart';
import '../../../core/services/performance_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../biopay/providers/biopay_providers.dart';
import '../../momo/providers/momo_service_provider.dart';
import '../models/user_profile.dart';
import '../repositories/auth_repository.dart';
import 'auth_provider_support.dart';

part 'auth_provider_profile_ops.dart';
part 'auth_provider_state.dart';

const _log = AppLogger('Auth');

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(client: ref.read(supabaseClientProvider));
});

final initialAuthStateProvider = Provider<AuthState?>((ref) => null);

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

final currentUserProvider = Provider<UserProfile?>((ref) {
  return ref.watch(authProvider).user;
});

class AuthNotifier extends Notifier<AuthState> with _AuthProfileOperations {
  @override
  late final AuthRepository _repository;
  @override
  late final CrashlyticsService _crashlytics;
  @override
  late final PerformanceService _performance;
  @override
  late final MomoService _momoService;
  @override
  late final Future<void> Function()? _clearSensitiveData;

  @override
  AuthState build() {
    _repository = ref.watch(authRepositoryProvider);
    _crashlytics = ref.read(crashlyticsServiceProvider);
    _performance = ref.read(performanceServiceProvider);
    _momoService = ref.read(momoServiceProvider);
    _clearSensitiveData = () => ref.read(biopayCacheServiceProvider).clear();

    final initialState = ref.read(initialAuthStateProvider);
    final autoBootstrap = initialState == null;

    final startState =
        initialState ??
        AuthState(
          session: _repository.currentSession,
          profileRestoreState: _repository.currentSession == null
              ? AuthProfileRestoreState.available
              : AuthProfileRestoreState.pending,
        );

    if (autoBootstrap) {
      Future<void>.microtask(ensureReadyForAppStart);
    }

    return startState;
  }

  AuthState get snapshot => state;

  Future<void> ensureReadyForAppStart() async {
    if (_repository.currentSession != null) {
      await restoreCurrentUser();
      if (state.session == null) {
        throw StateError(state.error ?? 'Could not restore your session.');
      }
      return;
    }

    await signInAnonymously();
    if (state.session == null) {
      throw StateError(state.error ?? 'Could not establish a startup session.');
    }
  }

  Future<void> restoreCurrentUser() async {
    final session = _repository.currentSession;
    if (session == null) {
      await _clearSensitiveData?.call();
      state = state.copyWith(
        user: null,
        session: null,
        profileRestoreState: AuthProfileRestoreState.available,
        error: null,
      );
      return;
    }

    state = state.copyWith(
      session: session,
      profileRestoreState: AuthProfileRestoreState.pending,
      error: null,
    );

    final result = await AsyncValue.guard(
      () => _repository.getCurrentProfile().timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'Profile restore timed out. Check your network and try again.',
          const Duration(seconds: 15),
        ),
      ),
    );
    result.when(
      data: (user) {
        state = state.copyWith(
          user: user,
          profileRestoreState: user == null
              ? AuthProfileRestoreState.missing
              : AuthProfileRestoreState.available,
          error: null,
        );
      },
      error: (error, stack) {
        _crashlytics.recordError(
          error,
          stackTrace: stack,
          reason: 'profile_restore_failed',
        );
        state = state.copyWith(
          profileRestoreState: AuthProfileRestoreState.failed,
          error: describeAuthError(error),
        );
      },
      loading: () {},
    );
  }

  /// Signs in anonymously and auto-creates a minimal profile.
  @override
  Future<void> signInAnonymously() async {
    state = state.copyWith(isLoading: true, error: null);
    _performance.startTrace('auth_sign_in_anonymous');
    _crashlytics.log('auth: signing in anonymously');
    _log.debug('Anonymous sign-in');

    final result = await AsyncValue.guard(
      () => _repository.signInAnonymously().timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'Sign-in timed out. Check your network and try again.',
          const Duration(seconds: 15),
        ),
      ),
    );

    await result.when(
      data: (session) async {
        _log.info('Anonymous sign-in succeeded: ${session.user.id}');
        // Try to load an existing profile first.
        final profileResult = await AsyncValue.guard(
          () => _repository.getProfile(session.user.id),
        );

        UserProfile? profile;
        String? error;

        profileResult.when(
          data: (value) {
            profile = value;
          },
          error: (err, stack) {
            error = describeAuthError(err);
            _crashlytics.recordError(
              err,
              stackTrace: stack,
              reason: 'auth_load_profile_after_anon',
            );
          },
          loading: () {},
        );

        _performance.stopTrace('auth_sign_in_anonymous');
        _crashlytics.log(
          'auth: anonymous sign-in complete, profile loaded=${profile != null}',
        );

        state = AuthState(
          user: profile,
          session: session,
          profileRestoreState: error != null
              ? AuthProfileRestoreState.failed
              : profile == null
              ? AuthProfileRestoreState.missing
              : AuthProfileRestoreState.available,
          isLoading: false,
          error: error,
        );
      },
      error: (error, stack) async {
        _performance.stopTrace(
          'auth_sign_in_anonymous',
          attributes: {'error': error.runtimeType.toString()},
        );
        _crashlytics.recordError(
          error,
          stackTrace: stack,
          reason: 'auth_sign_in_anonymous',
        );
        _log.warn('Anonymous sign-in failed: $error\n$stack');
        state = state.copyWith(
          isLoading: false,
          profileRestoreState: AuthProfileRestoreState.failed,
          error: describeAuthError(error),
        );
      },
      loading: () async {},
    );
  }

  /// Signs in using the session tokens returned by the `verify-otp` Edge
  /// Function. This replaces the current anonymous session with a
  /// phone-verified one.
  Future<bool> signInWithOtpSession({
    required String accessToken,
    required String refreshToken,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    _performance.startTrace('auth_sign_in_otp');
    _crashlytics.log('auth: signing in with OTP session');
    _log.debug('OTP session sign-in');

    try {
      final response = await _repository.setSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );

      final session = response;
      if (session == null) {
        throw StateError('OTP session could not be established.');
      }

      _log.info('OTP session established: ${session.user.id}');

      // Load or auto-create a minimal profile.
      final profileResult = await AsyncValue.guard(
        () => _repository.getProfile(session.user.id),
      );

      UserProfile? profile;
      String? error;

      profileResult.when(
        data: (value) {
          profile = value;
        },
        error: (err, stack) {
          error = describeAuthError(err);
          _crashlytics.recordError(
            err,
            stackTrace: stack,
            reason: 'auth_load_profile_after_otp',
          );
        },
        loading: () {},
      );

      // Auto-create a minimal profile if none exists but phone is available.
      if (profile == null && error == null) {
        final phone = authSessionPhone(session);
        if (phone != null && phone.isNotEmpty) {
          final createResult = await AsyncValue.guard(
            () => _repository.createProfile(
              UserProfile(
                id: session.user.id,
                phone: phone,
                fullName: '',
                momoNumber: '',
                momoProvider: '',
                country: AppMarket.countryCode,
                languageCode: AppMarket.languageCode,
              ),
            ),
          );
          createResult.when(
            data: (value) {
              profile = value;
              _crashlytics.log('auth: auto-created profile after OTP');
            },
            error: (err, stack) {
              // Non-fatal — user verified but profile creation failed.
              _crashlytics.recordError(
                err,
                stackTrace: stack,
                reason: 'auth_auto_create_profile_after_otp',
              );
            },
            loading: () {},
          );
        }
      }

      _performance.stopTrace('auth_sign_in_otp');
      // After OTP verification, NEVER set profileRestoreState to 'failed' —
      // that would trigger the router to redirect to splash, trapping the user.
      // Use 'available' even if profile is missing; the gate already verified.
      state = AuthState(
        user: profile,
        session: session,
        profileRestoreState: AuthProfileRestoreState.available,
        isLoading: false,
        error: error,
      );
      return true;
    } catch (error, stack) {
      _performance.stopTrace(
        'auth_sign_in_otp',
        attributes: {'error': error.runtimeType.toString()},
      );
      _crashlytics.recordError(
        error,
        stackTrace: stack,
        reason: 'auth_sign_in_otp',
      );
      _log.warn('OTP sign-in failed: $error\n$stack');
      // Preserve the previous profileRestoreState — the user still has
      // their old session and should not be trapped on splash.
      state = state.copyWith(isLoading: false, error: describeAuthError(error));
      return false;
    }
  }
}
