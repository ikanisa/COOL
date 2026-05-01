part of 'auth_provider.dart';

mixin _AuthProfileOperations on Notifier<AuthState> {
  AuthRepository get _repository;
  CrashlyticsService get _crashlytics;
  PerformanceService get _performance;
  MomoService get _momoService;
  Future<void> Function()? get _clearSensitiveData;
  Future<void> signInAnonymously();

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
