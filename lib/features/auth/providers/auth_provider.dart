import 'dart:async';

import 'package:flutter/foundation.dart';
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
import '../../biopay/providers/biopay_providers.dart';
import '../../momo/providers/momo_service_provider.dart';
import '../models/user_profile.dart';
import '../repositories/auth_repository.dart';
import 'auth_provider_support.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(client: ref.read(supabaseClientProvider));
});

final initialAuthStateProvider = Provider<AuthState?>((ref) => null);

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  final crashlytics = ref.read(crashlyticsServiceProvider);
  final performance = ref.read(performanceServiceProvider);
  final momoService = ref.read(momoServiceProvider);
  final initialState = ref.watch(initialAuthStateProvider);
  return AuthNotifier(
    repository: repository,
    crashlytics: crashlytics,
    performance: performance,
    momoService: momoService,
    clearSensitiveData: () => ref.read(biopayCacheServiceProvider).clear(),
    initialState: initialState,
    autoBootstrapOnInit: initialState == null,
  );
});

final currentUserProvider = Provider<UserProfile?>((ref) {
  return ref.watch(authProvider).user;
});

enum AuthProfileRestoreState { available, missing, pending, failed }

class AuthState {
  const AuthState({
    this.user,
    this.session,
    this.profileRestoreState = AuthProfileRestoreState.available,
    this.isLoading = false,
    this.error,
  });

  static const _sentinel = Object();

  final UserProfile? user;
  final Session? session;
  final AuthProfileRestoreState profileRestoreState;
  final bool isLoading;
  final String? error;

  bool get hasResolvedProfile =>
      profileRestoreState != AuthProfileRestoreState.pending;

  AuthState copyWith({
    Object? user = _sentinel,
    Object? session = _sentinel,
    AuthProfileRestoreState? profileRestoreState,
    bool? isLoading,
    Object? error = _sentinel,
  }) {
    return AuthState(
      user: user == _sentinel ? this.user : user as UserProfile?,
      session: session == _sentinel ? this.session : session as Session?,
      profileRestoreState: profileRestoreState ?? this.profileRestoreState,
      isLoading: isLoading ?? this.isLoading,
      error: error == _sentinel ? this.error : error as String?,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier({
    required AuthRepository repository,
    required CrashlyticsService crashlytics,
    required PerformanceService performance,
    required MomoService momoService,
    Future<void> Function()? clearSensitiveData,
    AuthState? initialState,
    bool autoBootstrapOnInit = false,
  }) : _repository = repository,
       _crashlytics = crashlytics,
       _performance = performance,
       _momoService = momoService,
       _clearSensitiveData = clearSensitiveData,
       super(
         initialState ??
             AuthState(
               session: repository.currentSession,
               profileRestoreState: repository.currentSession == null
                   ? AuthProfileRestoreState.available
                   : AuthProfileRestoreState.pending,
             ),
       ) {
    if (autoBootstrapOnInit) {
      Future<void>.microtask(ensureReadyForAppStart);
    }
  }

  final AuthRepository _repository;
  final CrashlyticsService _crashlytics;
  final PerformanceService _performance;
  final MomoService _momoService;
  final Future<void> Function()? _clearSensitiveData;

  AuthState get snapshot => state;

  Future<void> ensureReadyForAppStart() async {
    if (_repository.currentSession != null) {
      await restoreCurrentUser();
      if (state.session == null) {
        throw StateError(state.error ?? 'Could not restore your session.');
      }
      if (state.profileRestoreState == AuthProfileRestoreState.failed) {
        throw StateError(state.error ?? 'Could not restore your account.');
      }
      return;
    }

    await signInAnonymously();
    if (state.session == null) {
      throw StateError(state.error ?? 'Could not establish a startup session.');
    }
    if (state.profileRestoreState == AuthProfileRestoreState.failed) {
      throw StateError(state.error ?? 'Could not finish startup.');
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
  Future<void> signInAnonymously() async {
    state = state.copyWith(isLoading: true, error: null);
    _performance.startTrace('auth_sign_in_anonymous');
    _crashlytics.log('auth: signing in anonymously');
    debugPrint('[Auth] ➜ Anonymous sign-in');

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
        debugPrint('[Auth] ✓ Anonymous sign-in succeeded: ${session.user.id}');
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
        debugPrint('[Auth] ❌ Anonymous sign-in failed: $error\n$stack');
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
    debugPrint('[Auth] ➜ OTP session sign-in');

    try {
      final response = await _repository.setSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );

      final session = response;
      if (session == null) {
        throw StateError('OTP session could not be established.');
      }

      debugPrint('[Auth] ✓ OTP session established: ${session.user.id}');

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
      debugPrint('[Auth] ❌ OTP sign-in failed: $error\n$stack');
      // Preserve the previous profileRestoreState — the user still has
      // their old session and should not be trapped on splash.
      state = state.copyWith(isLoading: false, error: describeAuthError(error));
      return false;
    }
  }

  Future<UserProfile?> createProfile(AuthProfileData data) async {
    final session = state.session ?? _repository.currentSession;
    final userId = _repository.currentUserId ?? session?.user.id;
    final phone = data.phone ?? state.user?.phone ?? authSessionPhone(session);

    if (userId == null || (phone ?? '').isEmpty) {
      state = state.copyWith(
        error: 'A verified session is required before creating a profile.',
      );
      return null;
    }

    ({
      String momoNumber,
      String? momoCode,
      MomoRecipientType? momoRouteType,
      String momoProvider,
      String country,
    })
    normalizedIdentity;
    try {
      normalizedIdentity = await normalizeMomoIdentity(
        momoService: _momoService,
        momoNumber: data.momoNumber,
        momoCode: data.momoCode,
        preferredRouteType: data.momoRouteType,
        fallbackCountry: data.country,
        fallbackProviderId: data.momoProvider,
      );
    } catch (error, stack) {
      _crashlytics.recordError(
        error,
        stackTrace: stack,
        reason: 'auth_normalize_momo_identity',
      );
      state = state.copyWith(error: describeAuthError(error));
      return null;
    }

    state = state.copyWith(isLoading: true, error: null);
    _performance.startTrace('auth_create_profile');
    _crashlytics.log('auth: creating profile for user');

    final result = await AsyncValue.guard(
      () => _repository.createProfile(
        UserProfile(
          id: userId,
          phone: phone!,
          fullName: data.fullName,
          momoNumber: normalizedIdentity.momoNumber,
          momoCode: normalizedIdentity.momoCode,
          momoRouteType: normalizedIdentity.momoRouteType,
          momoProvider: normalizedIdentity.momoProvider,
          country: AppMarket.countryCode,
          languageCode: AppMarket.languageCode,
        ),
      ),
    );

    UserProfile? profile;

    result.when(
      data: (value) {
        profile = value;
        _performance.stopTrace('auth_create_profile');
        _crashlytics.log('auth: profile created successfully');
        state = AuthState(
          user: value,
          session: session,
          profileRestoreState: AuthProfileRestoreState.available,
          isLoading: false,
          error: null,
        );
      },
      error: (error, stack) {
        _performance.stopTrace(
          'auth_create_profile',
          attributes: {'error': error.runtimeType.toString()},
        );
        _crashlytics.recordError(
          error,
          stackTrace: stack,
          reason: 'auth_create_profile',
        );
        state = state.copyWith(
          isLoading: false,
          error: describeAuthError(error),
        );
      },
      loading: () {},
    );

    return profile;
  }

  Future<bool> updateMomoInfo({
    required String momoNumber,
    String? momoCode,
    MomoRecipientType? momoRouteType,
    String? momoProvider,
    String? country,
  }) async {
    final user = state.user;
    if (user == null) {
      state = state.copyWith(error: 'No user profile loaded.');
      return false;
    }

    ({
      String momoNumber,
      String? momoCode,
      MomoRecipientType? momoRouteType,
      String momoProvider,
      String country,
    })
    normalizedIdentity;
    try {
      normalizedIdentity = await normalizeMomoIdentity(
        momoService: _momoService,
        momoNumber: momoNumber,
        momoCode: momoCode,
        preferredRouteType: momoRouteType,
        fallbackCountry: country ?? resolveAuthStateCountryCode(state),
        fallbackProviderId: momoProvider ?? user.momoProvider,
      );
    } catch (error, stack) {
      _crashlytics.recordError(
        error,
        stackTrace: stack,
        reason: 'normalize_update_momo_info',
      );
      state = state.copyWith(error: describeAuthError(error));
      return false;
    }

    state = state.copyWith(isLoading: true, error: null);

    final result = await AsyncValue.guard(
      () => _repository.updateMomoInfo(
        user.id,
        momoNumber: normalizedIdentity.momoNumber,
        momoCode: normalizedIdentity.momoCode,
        momoRouteType: normalizedIdentity.momoRouteType,
        momoProvider: normalizedIdentity.momoProvider,
        country: AppMarket.countryCode,
      ),
    );

    bool success = false;
    result.when(
      data: (value) {
        success = true;
        state = state.copyWith(user: value, isLoading: false, error: null);
      },
      error: (error, stack) {
        _crashlytics.recordError(
          error,
          stackTrace: stack,
          reason: 'update_momo_info',
        );
        state = state.copyWith(
          isLoading: false,
          error: describeAuthError(error),
        );
      },
      loading: () {},
    );

    return success;
  }

  Future<bool> updateProfile(UserProfile profile) async {
    state = state.copyWith(isLoading: true, error: null);

    final result = await AsyncValue.guard(
      () => _repository.updateProfile(profile),
    );

    var success = false;
    result.when(
      data: (value) {
        success = true;
        state = state.copyWith(user: value, isLoading: false, error: null);
      },
      error: (error, stack) {
        _crashlytics.recordError(
          error,
          stackTrace: stack,
          reason: 'update_profile',
        );
        state = state.copyWith(
          isLoading: false,
          error: describeAuthError(error),
        );
      },
      loading: () {},
    );

    return success;
  }

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true, error: null);

    final result = await AsyncValue.guard(() async {
      await _repository.signOut();
      await _clearSensitiveData?.call();
    });

    await result.when(
      data: (_) async {
        await signInAnonymously();
      },
      error: (error, _) {
        state = state.copyWith(
          isLoading: false,
          error: describeAuthError(error),
        );
      },
      loading: () {},
    );
  }

  Future<void> deleteAccount() async {
    state = state.copyWith(isLoading: true, error: null);

    final result = await AsyncValue.guard(() async {
      await _repository.deleteAccount();
      await _clearSensitiveData?.call();
    });

    await result.when(
      data: (_) async {
        await signInAnonymously();
      },
      error: (error, _) {
        state = state.copyWith(
          isLoading: false,
          error: describeAuthError(error),
        );
      },
      loading: () {},
    );
  }
}
