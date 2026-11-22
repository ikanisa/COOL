part of 'collect_repository.dart';

mixin _CollectRepositoryProfile
    on
        StateNotifier<CollectState>,
        _CollectMemberHistory,
        _CollectRepositorySession,
        _CollectRepositorySnapshotSync,
        _CollectRepositoryOfflineSnapshot
    implements MemberAccountRepository {
  static final _publicIds = PublicIdGenerator(random: Random(491));
  final _profileSavesInFlight = <(String, int)>{};

  @override
  Future<CollectProfile> signInWithOtp({
    required String phone,
    required String otp,
    String? countryCode,
  }) async {
    if (otp.trim().length < 4) {
      throw const FormatException('Enter the phone verification code');
    }
    final normalized = PhoneNormalizer.normalizeRwanda(phone);
    final requestedCountry = CollectProfileCountryRules.normalizeCountryCode(
      countryCode,
    );
    final initialCountry =
        CollectProfileCountryRules.isSupportedCountry(requestedCountry)
        ? requestedCountry
        : CollectProfileCountryRules.inferCountryCodeFromPhone(normalized);
    final backend = _backend;
    final user = backend?.auth.currentUser;
    if (backend != null && user != null) {
      final session = _captureSession();
      bool current() =>
          _isCurrentSession(session) &&
          session.identity?.userId == user.id &&
          session.accessToken != null &&
          _signingOutIdentity != session.identity &&
          backend.auth.currentUser?.id == user.id;
      void requireCurrent() {
        if (!current()) {
          throw StateError('Account changed. Refresh before continuing.');
        }
      }

      requireCurrent();
      late final CollectProfile profile;
      try {
        profile = await _liveReader.ensureLiveProfile(
          user.id,
          normalized,
          countryCode: initialCountry,
          accessToken: session.accessToken!,
        );
      } catch (_) {
        requireCurrent();
        rethrow;
      }
      requireCurrent();
      state = state.copyWith(currentProfile: profile);
      unawaited(loadInitial());
      return profile;
    }
    if (!_allowLocalWrites) {
      throw StateError('Live phone sign-in is unavailable.');
    }

    final existingIds = state.currentProfile == null
        ? <String>{}
        : {state.currentProfile!.publicId};
    final existingProfile = state.currentProfile;
    final profile = existingProfile == null
        ? CollectProfile(
            id: _uuid.v4(),
            publicId: _publicIds.generate(existingIds),
            whatsappPhone: normalized,
            countryCode: initialCountry,
            currencyCode: CollectProfileCountryRules.currencyForCountry(
              initialCountry,
            ),
            momoProvider: initialCountry == 'RW'
                ? _defaultMomoProviderFromPhone(normalized)
                : '',
            momoNumber: initialCountry == 'RW'
                ? _defaultLocalMomoFromPhone(normalized)
                : '',
          )
        : existingProfile.countryCode.trim().isEmpty
        ? existingProfile.copyWith(
            countryCode: initialCountry,
            currencyCode: CollectProfileCountryRules.currencyForCountry(
              initialCountry,
            ),
          )
        : existingProfile;
    state = state.copyWith(currentProfile: profile);
    unawaited(
      _saveOfflineSnapshot().catchError((Object _) {
        // Optional encrypted cache failure never converts a successful server
        // read into a failed financial operation. No payload is logged.
      }),
    );
    return profile;
  }

  @override
  Future<CollectProfile> updateCurrentProfile({
    required String countryCode,
    String? momoProvider,
    String? momoNumber,
    String? momoPayCode,
  }) async {
    final current = _requireProfile();
    final cleanCountry = CollectProfileCountryRules.normalizeCountryCode(
      countryCode,
    );
    if (!CollectProfileCountryRules.isSupportedCountry(cleanCountry)) {
      throw const FormatException('Collect requires a Rwanda profile.');
    }
    final cleanMomoProvider = (momoProvider ?? '').trim().toLowerCase();
    final cleanMomoNumber = _normalizeLocalRwandaMomo(momoNumber ?? '');
    final cleanMomoPayCode = (momoPayCode ?? current.momoPayCode).trim();
    if (cleanMomoPayCode.isNotEmpty &&
        !RegExp(r'^[0-9]{4,9}$').hasMatch(cleanMomoPayCode)) {
      throw const FormatException('Enter a MoMo code with 4 to 9 digits.');
    }
    if (!const {'mtn_momo', 'airtel_money'}.contains(cleanMomoProvider)) {
      throw const FormatException('Choose MTN MoMo or Airtel Money.');
    }
    if (!(cleanMomoProvider == 'mtn_momo'
        ? RegExp(r'^07[89][0-9]{7}$').hasMatch(cleanMomoNumber)
        : RegExp(r'^07[23][0-9]{7}$').hasMatch(cleanMomoNumber))) {
      throw const FormatException(
        'The MoMo provider does not match that Rwanda mobile number.',
      );
    }
    final backend = _backend;
    final session = _captureSession();
    final profileAuthority = _profileSaveAuthorityGeneration;
    final saveKey = (current.id, session.generation);
    if (!_profileSavesInFlight.add(saveKey)) {
      throw StateError('Wait for your current profile update to finish.');
    }
    try {
      void requireCurrentOwner() {
        if (state.currentProfile?.id != current.id ||
            profileAuthority != _profileSaveAuthorityGeneration ||
            (backend != null && backend.auth.currentUser?.id != current.id)) {
          throw StateError('Profile account changed. Try again.');
        }
        if (backend != null) _requireCurrentMemberSession(session, current.id);
      }

      late final CollectProfile updated;
      if (backend != null && backend.auth.currentUser != null) {
        requireCurrentOwner();
        final (status, acknowledgement) = await backend.request(
          'POST',
          'v1/rpc/update_current_member_profile',
          body: {
            'p_country_code': cleanCountry,
            'p_momo_provider': cleanMomoProvider,
            'p_momo_number': cleanMomoNumber,
            'p_momo_pay_code': cleanMomoPayCode,
          },
          bearer: session.accessToken,
        );
        requireCurrentOwner();
        if (status < 200 || status >= 300) {
          throw collectApiFailure(status, acknowledgement);
        }
        if (status != 200) {
          throw StateError('Collect could not confirm the profile update.');
        }
        // The Supabase Cloud 200 contract returns null. The transport also maps a
        // 200 empty body to null, so readback proves only the current values,
        // not the particular mutation's commit provenance. Never retry a write.
        final isReadback = acknowledgement == null;
        final row = isReadback
            ? await backend
                  .rpc<dynamic>('get_current_member_profile')
                  .setHeader('Authorization', 'Bearer ${session.accessToken}')
            : acknowledgement;
        requireCurrentOwner();
        if (row is! Map || row.keys.any((key) => key is! String)) {
          throw StateError('Collect profile could not be updated.');
        }
        final values = Map<String, dynamic>.from(row);
        final storedCountry = values['country_code'];
        final storedCurrency = values['currency_code'];
        final storedProvider = values['momo_provider'];
        final storedNumber = values['momo_number'];
        final storedCode = values['momo_pay_code'];
        // Model defaults are useful for display, but cannot prove a write: a
        // missing MoMo number or country must not be inferred from the phone.
        if (storedCountry is! String ||
            CollectProfileCountryRules.normalizeCountryCode(storedCountry) !=
                cleanCountry ||
            ((isReadback || values.containsKey('currency_code')) &&
                (storedCurrency is! String ||
                    storedCurrency.trim().toUpperCase() !=
                        CollectProfileCountryRules.currencyForCountry(
                          cleanCountry,
                        ))) ||
            storedProvider is! String ||
            storedProvider.trim().toLowerCase() != cleanMomoProvider ||
            storedNumber is! String ||
            storedNumber.length > 40 ||
            !RegExp(r'^\+?[0-9 ()-]+$').hasMatch(storedNumber.trim()) ||
            (!values.containsKey('momo_pay_code') &&
                (isReadback ||
                    cleanMomoPayCode.isNotEmpty ||
                    current.momoPayCode.trim().isNotEmpty)) ||
            (storedCode != null && storedCode is! String) ||
            ((storedCode as String?)?.trim() ?? '') != cleanMomoPayCode) {
          throw const FormatException('Updated profile values do not match.');
        }
        final normalized = PhoneNormalizer.normalizeRwanda(storedNumber);
        if ('0${normalized.substring(4)}' != cleanMomoNumber) {
          throw const FormatException('Updated profile values do not match.');
        }
        final confirmed = CollectProfile.fromJson(values);
        if (confirmed.id != current.id ||
            confirmed.publicId != current.publicId ||
            confirmed.whatsappPhone != current.whatsappPhone) {
          throw const FormatException('Updated profile identity is invalid.');
        }
        // Existing mobile profile and SMS capture use local Rwanda digits.
        updated = confirmed.copyWith(
          countryCode: cleanCountry,
          momoProvider: cleanMomoProvider,
          momoNumber: cleanMomoNumber,
          momoPayCode: cleanMomoPayCode,
        );
      } else {
        if (!_allowLocalWrites) {
          throw StateError('Connect to Collect before updating your profile.');
        }
        updated = current.copyWith(
          countryCode: cleanCountry,
          currencyCode: CollectProfileCountryRules.currencyForCountry(
            cleanCountry,
          ),
          momoProvider: cleanMomoProvider,
          momoNumber: cleanMomoNumber,
          momoPayCode: cleanMomoPayCode,
        );
      }

      requireCurrentOwner();
      bool sameMomoNumber(String left, String right) {
        if (left.length > 40 ||
            !RegExp(r'^\+?[0-9 ()-]+$').hasMatch(left.trim())) {
          return false;
        }
        try {
          return PhoneNormalizer.normalizeRwanda(left) ==
              PhoneNormalizer.normalizeRwanda(right);
        } on FormatException {
          return false;
        }
      }

      // SMS capture is a separate member choice. A profile save must neither
      // disable it nor replay an earlier enabled state over a later opt-out.
      requireCurrentOwner();
      // Do not let a load that read the old profile before this confirmed save
      // later replace it. A fresh complete load still determines member access.
      if (backend != null) ++_loadGeneration;
      state = state.copyWith(currentProfile: updated, isLoading: false);
      requireCurrentOwner();
      final cacheSave = _saveOfflineSnapshot();
      if (backend != null &&
          _isCurrentSession(session) &&
          profileAuthority == _profileSaveAuthorityGeneration &&
          _signingOutIdentity != session.identity) {
        final refresh = loadInitial();
        final generation = _loadGeneration;
        unawaited(
          refresh.catchError((Object _) {
            if (!mounted ||
                generation != _loadGeneration ||
                !_isCurrentSession(session) ||
                profileAuthority != _profileSaveAuthorityGeneration ||
                _signingOutIdentity == session.identity) {
              return;
            }
            state = state.copyWith(
              isLoading: false,
              financialObservationUncertain: true,
              lastError:
                  'Profile data could not be refreshed. Please reconnect.',
            );
          }),
        );
      }
      await cacheSave;
      requireCurrentOwner();
      // A newer authoritative refresh may have completed while the protected
      // cache was saving. Do not return the older profile to an editor that
      // would otherwise hydrate it over the already-published newer values.
      final latest = state.currentProfile;
      if (latest == null ||
          latest.id != updated.id ||
          latest.publicId != updated.publicId ||
          latest.whatsappPhone != updated.whatsappPhone ||
          CollectProfileCountryRules.normalizeCountryCode(latest.countryCode) !=
              updated.countryCode ||
          latest.currencyCode.trim().toUpperCase() != updated.currencyCode ||
          latest.momoProvider.trim().toLowerCase() != updated.momoProvider ||
          !sameMomoNumber(latest.momoNumber, updated.momoNumber) ||
          latest.momoPayCode.trim() != updated.momoPayCode) {
        throw StateError(
          'Profile changed during the update. Refresh and try again.',
        );
      }
      return updated;
    } finally {
      _profileSavesInFlight.remove(saveKey);
    }
  }
}
