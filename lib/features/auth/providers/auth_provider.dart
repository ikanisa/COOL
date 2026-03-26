import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_user_contact.dart';
import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/config/env_config.dart';
import '../../../core/providers/engagement_providers.dart';
import '../../../core/providers/supabase_client_provider.dart';
import '../../../core/services/crashlytics_service.dart';
import '../../../core/services/momo_service.dart';
import '../../../core/services/performance_service.dart';
import '../../biopay/providers/biopay_providers.dart';
import '../../momo/providers/momo_service_provider.dart';
import '../models/user_profile.dart';
import '../repositories/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(client: ref.read(supabaseClientProvider));
});

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  final crashlytics = ref.read(crashlyticsServiceProvider);
  final performance = ref.read(performanceServiceProvider);
  final momoService = ref.read(momoServiceProvider);
  return AuthNotifier(
    repository: repository,
    crashlytics: crashlytics,
    performance: performance,
    momoService: momoService,
    clearSensitiveData: () => ref.read(biopayCacheServiceProvider).clear(),
  );
});

final currentUserProvider = Provider<UserProfile?>((ref) {
  return ref.watch(authProvider).user;
});

final currentUserCountryCodeProvider = Provider<String>((ref) {
  return AppMarket.countryCode;
});

String resolveAuthStateCountryCode(AuthState authState) {
  return AppMarket.countryCode;
}

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

class AuthProfileData {
  const AuthProfileData({
    required this.fullName,
    required this.momoNumber,
    this.momoCode,
    this.momoRouteType,
    required this.momoProvider,
    required this.country,
    required this.languageCode,
    this.phone,
  });

  final String fullName;
  final String momoNumber;
  final String? momoCode;
  final MomoRecipientType? momoRouteType;
  final String momoProvider;
  final String country;
  final String languageCode;
  final String? phone;
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier({
    required AuthRepository repository,
    required CrashlyticsService crashlytics,
    required PerformanceService performance,
    required MomoService momoService,
    Future<void> Function()? clearSensitiveData,
  }) : _repository = repository,
       _crashlytics = crashlytics,
       _performance = performance,
       _momoService = momoService,
       _clearSensitiveData = clearSensitiveData,
       super(
         AuthState(
           session: repository.currentSession,
           profileRestoreState: repository.currentSession == null
               ? AuthProfileRestoreState.available
               : AuthProfileRestoreState.pending,
         ),
       ) {
    if (_repository.currentSession != null) {
      Future<void>.microtask(restoreCurrentUser);
    }
  }

  final AuthRepository _repository;
  final CrashlyticsService _crashlytics;
  final PerformanceService _performance;
  final MomoService _momoService;
  final Future<void> Function()? _clearSensitiveData;

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

    final result = await AsyncValue.guard(_repository.getCurrentProfile);
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
          error: _errorMessage(error),
        );
      },
      loading: () {},
    );
  }

  Future<void> sendOtp(String phone, String language) async {
    state = state.copyWith(isLoading: true, error: null);
    _performance.startTrace('auth_send_otp');
    _crashlytics.log('auth: sending OTP to ${phone.substring(0, 4)}***');

    final result = await AsyncValue.guard(
      () => _repository.sendOtp(phone, language),
    );

    result.when(
      data: (_) {
        _performance.stopTrace('auth_send_otp');
        state = state.copyWith(isLoading: false, error: null);
      },
      error: (error, stack) {
        _performance.stopTrace(
          'auth_send_otp',
          attributes: {'error': error.runtimeType.toString()},
        );
        _crashlytics.recordError(
          error,
          stackTrace: stack,
          reason: 'auth_send_otp',
        );
        state = state.copyWith(isLoading: false, error: _errorMessage(error));
      },
      loading: () {},
    );
  }

  Future<void> verifyOtp(String phone, String code) async {
    state = state.copyWith(isLoading: true, error: null);
    _performance.startTrace('auth_verify_otp');
    _crashlytics.log('auth: verifying OTP for ${phone.substring(0, 4)}***');

    final result = await AsyncValue.guard(
      () => _repository.verifyOtp(phone, code),
    );

    await result.when(
      data: (session) async {
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
            error = _errorMessage(err);
            _crashlytics.recordError(
              err,
              stackTrace: stack,
              reason: 'auth_load_profile_after_otp',
            );
          },
          loading: () {},
        );

        _performance.stopTrace('auth_verify_otp');
        _crashlytics.log(
          'auth: OTP verified, profile loaded=${profile != null}',
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
          'auth_verify_otp',
          attributes: {'error': error.runtimeType.toString()},
        );
        _crashlytics.recordError(
          error,
          stackTrace: stack,
          reason: 'auth_verify_otp',
        );
        state = state.copyWith(isLoading: false, error: _errorMessage(error));
      },
      loading: () async {},
    );
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
      normalizedIdentity = await _normalizeMomoIdentity(
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
      state = state.copyWith(error: _errorMessage(error));
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
        state = state.copyWith(isLoading: false, error: _errorMessage(error));
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
      normalizedIdentity = await _normalizeMomoIdentity(
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
      state = state.copyWith(error: _errorMessage(error));
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
        state = state.copyWith(isLoading: false, error: _errorMessage(error));
      },
      loading: () {},
    );

    return success;
  }

  Future<bool> updateOfficialIdentity({
    required String officialName,
    required String officialPhone,
  }) async {
    final user = state.user;
    if (user == null) {
      state = state.copyWith(error: 'No user profile loaded.');
      return false;
    }

    final trimmedName = officialName.trim();
    final trimmedPhone = officialPhone.trim();
    String? normalizedOfficialPhone;

    if (trimmedPhone.isNotEmpty) {
      try {
        final resolvedCountry = CoolCountryCatalog.resolve(
          country: AppMarket.countryCode,
          phone: user.phone,
          providerId: user.momoProvider,
        );
        normalizedOfficialPhone = resolvedCountry.normalizeNationalPhone(
          trimmedPhone,
        );
      } catch (error, stack) {
        _crashlytics.recordError(
          error,
          stackTrace: stack,
          reason: 'normalize_official_identity_phone',
        );
        state = state.copyWith(error: _errorMessage(error));
        return false;
      }
    }

    final updatedProfile = user.copyWith(
      officialName: trimmedName.isEmpty ? null : trimmedName,
      officialPhone: normalizedOfficialPhone,
    );

    state = state.copyWith(isLoading: true, error: null);

    final result = await AsyncValue.guard(
      () => _repository.updateProfile(updatedProfile),
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
          reason: 'update_official_identity',
        );
        state = state.copyWith(isLoading: false, error: _errorMessage(error));
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
        state = state.copyWith(isLoading: false, error: _errorMessage(error));
      },
      loading: () {},
    );

    return success;
  }

  Future<
    ({
      String momoNumber,
      String? momoCode,
      MomoRecipientType? momoRouteType,
      String momoProvider,
      String country,
    })
  >
  _normalizeMomoIdentity({
    required String momoNumber,
    String? momoCode,
    MomoRecipientType? preferredRouteType,
    String? fallbackCountry,
    String? fallbackProviderId,
  }) async {
    final trimmedMomoNumber = momoNumber.trim();
    final trimmedMomoCode = momoCode?.trim() ?? '';
    if (trimmedMomoNumber.isEmpty && trimmedMomoCode.isEmpty) {
      throw const FormatException('Add a MoMo number or code.');
    }

    final seedCountry = await _momoService.resolveCountry(
      countryCode: fallbackCountry ?? AppMarket.countryCode,
      phone: trimmedMomoNumber.isEmpty ? null : trimmedMomoNumber,
      providerId: fallbackProviderId,
    );
    final resolvedCountry = await _momoService.resolveCountry(
      countryCode: seedCountry.isoCode,
      phone: trimmedMomoNumber.isEmpty ? null : trimmedMomoNumber,
      providerId: fallbackProviderId ?? seedCountry.providerId,
    );
    final normalizedMomoNumber = trimmedMomoNumber.isEmpty
        ? ''
        : resolvedCountry.normalizeNationalPhone(trimmedMomoNumber);
    final normalizedMomoCode = trimmedMomoCode.isEmpty
        ? null
        : resolvedCountry.normalizeMerchantCode(trimmedMomoCode);
    final momoRouteType = switch (preferredRouteType) {
      MomoRecipientType.phoneNumber =>
        normalizedMomoNumber.isEmpty
            ? throw const FormatException(
                'MoMo number is required for the selected default route.',
              )
            : MomoRecipientType.phoneNumber,
      MomoRecipientType.code =>
        normalizedMomoCode == null
            ? throw const FormatException(
                'MoMo code is required for the selected default route.',
              )
            : MomoRecipientType.code,
      null =>
        normalizedMomoNumber.isNotEmpty
            ? MomoRecipientType.phoneNumber
            : normalizedMomoCode == null
            ? null
            : MomoRecipientType.code,
    };

    return (
      momoNumber: normalizedMomoNumber,
      momoCode: normalizedMomoCode,
      momoRouteType: momoRouteType,
      momoProvider: resolvedCountry.providerId,
      country: resolvedCountry.isoCode,
    );
  }

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true, error: null);

    final result = await AsyncValue.guard(() async {
      await _repository.signOut();
      await _clearSensitiveData?.call();
    });

    result.when(
      data: (_) {
        state = const AuthState(
          profileRestoreState: AuthProfileRestoreState.available,
        );
      },
      error: (error, _) {
        state = state.copyWith(isLoading: false, error: _errorMessage(error));
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

    result.when(
      data: (_) {
        state = const AuthState(
          profileRestoreState: AuthProfileRestoreState.available,
        );
      },
      error: (error, _) {
        state = state.copyWith(isLoading: false, error: _errorMessage(error));
      },
      loading: () {},
    );
  }

  String _errorMessage(Object error) {
    final raw = error.toString();
    if (raw.contains('No host specified') && raw.contains('/functions/')) {
      return EnvConfig.criticalConfigurationError ??
          'This build is missing a valid Supabase backend configuration. '
              'Rebuild with a valid SUPABASE_URL and SUPABASE_ANON_KEY.';
    }

    if (raw.startsWith('StateError: ')) {
      return raw.substring('StateError: '.length);
    }

    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length);
    }

    return raw;
  }
}
