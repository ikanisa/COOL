part of 'collect_repository.dart';

/// Group/payment setup and receipt processing share the repository's state and
/// authenticated dependencies. Instance methods retain normal override behavior.
mixin _CollectContributionActions on StateNotifier<CollectState> {
  SupabaseClient? get _supabase;
  _CollectLiveReader get _liveReader;
  SmsAccessChannel get _smsAccessChannel;
  bool get _allowLocalWrites;
  _CollectSessionFence _captureSession();
  bool _isCurrentSession(_CollectSessionFence session);
  void _requireCurrentMemberSession(
    _CollectSessionFence session,
    String profileId,
  );
  Uuid get _uuid;
  Future<int>? _smsSyncInFlight;
  bool _smsSyncRequested = false;

  Future<void> loadInitial({bool syncPendingSms = false});
  Future<PaymentIntentModel> refreshPaymentIntent(String id);
  CollectProfile _requireReadyProfile();
  CollectCollection _requireActiveCollection(String collectionId);
  CollectProfile _requireCollectionOwner(
    CollectCollection collection, {
    required String action,
  });

  Future<CollectCollection> createCollection({
    required String title,
    required String description,
    CollectionType collectionType = CollectionType.ikimina,
    String? categorySubtype,
    String? purposeLabel,
    String? accentColorHex,
    String? imageUrl,
    String? receiverMomoNumber,
    String receiverProvider = 'mtn_momo',
    bool isPublic = false,
  }) async {
    final creatorProfile = _requireReadyProfile();
    if (!creatorProfile.isRwanda) {
      throw const FormatException(
        'Group creation requires a Rwanda MoMo profile.',
      );
    }
    final normalizedReceiver = _normalizeLocalRwandaMomo(
      receiverMomoNumber ?? state.currentProfile?.momoNumber ?? '',
    );
    final normalizedProvider = receiverProvider == 'airtel_money'
        ? 'airtel_money'
        : 'mtn_momo';
    final normalizedLabel = normalizedProvider == 'airtel_money'
        ? 'Airtel Money receiver'
        : 'MTN MoMo receiver';
    final receiverHash = HashUtils.phoneHash(normalizedReceiver);
    final supabase = _supabase;

    if (supabase != null && supabase.auth.currentUser != null) {
      final user = supabase.auth.currentUser!;
      final session = _captureSession();
      void current() => _requireCurrentMemberSession(session, user.id);
      current();
      final profile = state.currentProfile;
      if (profile == null || profile.id != user.id) {
        throw StateError(
          'Refresh your signed-in profile before creating a group.',
        );
      }
      final smsStatus = await refreshSmsAccessStatus();
      current();
      if (!smsStatus.enabled || !smsStatus.granted) {
        throw StateError(
          'Enable MoMo receipt SMS access before creating a group.',
        );
      }
      await supabase
          .rpc<void>(
            'record_sms_access_consent',
            params: {
              'enabled': true,
              'momo_number_hash': receiverHash,
              'build_channel': 'android_group_create_attested',
              'device_label': 'flutter_android_play_integrity',
            },
          )
          .setHeader('Authorization', 'Bearer ${session.accessToken}')
          .retry(enabled: false);
      current();
      final nonce = _uuid.v4();
      final groupRequest = <String, Object?>{
        'group_name': title.trim(),
        'group_description': description.trim(),
        'receiver_momo_number': normalizedReceiver,
        'receiver_momo_number_hash': receiverHash,
        'receiver_label': normalizedLabel,
        'group_collection_type': collectionType.storageValue,
        'group_category_subtype': categorySubtype?.trim().isEmpty == true
            ? null
            : categorySubtype?.trim(),
        'group_purpose_label': purposeLabel?.trim().isEmpty == true
            ? null
            : purposeLabel?.trim(),
        'group_is_public': false,
      };
      const integrity = PlayIntegrityService();
      final requestHash = integrity.buildGroupCreationRequestHash(
        subjectId: user.id,
        nonce: nonce,
        receiverMomoNumberHash: receiverHash,
        smsPermissionGranted: true,
        smsAccessEnabled: true,
        groupRequest: groupRequest,
      );
      final token = await integrity.requestStandardToken(
        requestHash: requestHash,
      );
      current();
      if (token == null || token.isEmpty) {
        throw StateError(
          'Install the approved Android build before creating a group.',
        );
      }
      final verdict = await integrity.verifyWithServer(
        supabase: supabase,
        requestHash: requestHash,
        integrityToken: token,
        subjectId: user.id,
        nonce: nonce,
        receiverMomoNumberHash: receiverHash,
        groupRequest: groupRequest,
        accessToken: session.accessToken,
      );
      current();
      if (verdict?.hasUsableNativeCapability != true) {
        throw StateError('Android device verification did not pass.');
      }
      final collectionId = await supabase
          .rpc<String>(
            'create_private_group_with_owner_media_attested',
            params: {
              ...groupRequest..remove('group_is_public'),
              'native_capability': verdict!.nativeCapability,
              'group_image_url': imageUrl,
              'group_accent_color_hex': accentColorHex,
            },
          )
          .setHeader('Authorization', 'Bearer ${session.accessToken}')
          .retry(enabled: false);
      current();
      final collection = await _liveReader.fetchCollection(
        collectionId,
        accessToken: session.accessToken,
      );
      current();
      if (collection.creatorUserId != user.id) {
        throw const FormatException('Created group owner is invalid.');
      }
      await loadInitial();
      current();
      // Read the authoritative media saved in the same transaction as creation.
      final hydratedCollection = collection;
      if (!state.collections.any((item) => item.id == collectionId)) {
        state = state.copyWith(
          collections: [hydratedCollection, ...state.collections],
        );
      }
      return hydratedCollection;
    }
    if (!_allowLocalWrites && supabase != null) {
      throw StateError('Unable to create group on this device right now.');
    }

    final creatorUserId = state.currentProfile?.id ?? 'local-group-owner';
    final slug = _slug(title);
    final collection = CollectCollection(
      id: _uuid.v4(),
      slug: '$slug-${DateTime.now().millisecondsSinceEpoch}',
      creatorUserId: creatorUserId,
      title: title.trim(),
      description: description.trim(),
      collectionType: collectionType,
      categorySubtype: categorySubtype?.trim().isEmpty == true
          ? null
          : categorySubtype?.trim(),
      purposeLabel: purposeLabel?.trim().isEmpty == true
          ? null
          : purposeLabel?.trim(),
      receiverMomoNumber: normalizedReceiver,
      receiverDisplayLabel: normalizedLabel,
      receiverNetwork: normalizedProvider,
      accentColorHex: accentColorHex,
      imageUrl: imageUrl,
      isPublic: false,
      visibilityStatus: 'private',
      createdAt: DateTime.now(),
    );
    state = state.copyWith(collections: [...state.collections, collection]);
    return collection;
  }

  Future<CollectCollection> updateCollectionProfile({
    required String collectionId,
    required String title,
    required String description,
    required String recurringCadence,
    CollectionType? collectionType,
    String? categorySubtype,
    String? purposeLabel,
    String? accentColorHex,
    String? imageUrl,
    required bool isPublic,
    bool isRecurring = true,
  }) async {
    final collection = _requireActiveCollection(collectionId);
    _requireCollectionOwner(collection, action: 'update group details');
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw const FormatException('Group name is required.');
    }
    final cadence = recurringCadence.trim().isEmpty
        ? 'monthly'
        : recurringCadence.trim();
    final supabase = _supabase;

    if (supabase != null && supabase.auth.currentUser != null) {
      final session = _captureSession();
      final ownerId = state.currentProfile!.id;
      void current() => _requireCurrentMemberSession(session, ownerId);
      current();
      await supabase
          .rpc<void>(
            'update_rwanda_momo_group_profile',
            params: {
              'p_collection_id': collectionId,
              'p_group_name': cleanTitle,
              'p_group_description': description.trim(),
              'p_group_image_url': imageUrl,
              'p_group_accent_color_hex': accentColorHex,
              'p_group_is_public': isPublic,
              'p_group_recurring_cadence': cadence,
              'p_group_collection_type': collectionType?.storageValue,
              'p_group_category_subtype': categorySubtype?.trim(),
              'p_group_purpose_label': purposeLabel?.trim(),
              'p_group_is_recurring': isRecurring,
            },
          )
          .setHeader('Authorization', 'Bearer ${session.accessToken}')
          .retry(enabled: false);
      current();
      final collection = await _liveReader.fetchCollection(
        collectionId,
        accessToken: session.accessToken,
      );
      current();
      if (collection.creatorUserId != ownerId) {
        throw const FormatException('Updated group owner is invalid.');
      }
      await loadInitial();
      current();
      return collection;
    }
    if (!_allowLocalWrites) {
      throw StateError('Sign in before updating group details.');
    }

    final collections = [...state.collections];
    final index = collections.indexWhere((item) => item.id == collectionId);
    if (index == -1) throw StateError('Group not found');
    collections[index] = collections[index].copyWith(
      title: cleanTitle,
      description: description.trim(),
      receiverDisplayLabel: collection.receiverDisplayLabel,
      collectionType: collectionType,
      categorySubtype: categorySubtype?.trim().isEmpty == true
          ? null
          : categorySubtype?.trim(),
      purposeLabel: purposeLabel?.trim().isEmpty == true
          ? null
          : purposeLabel?.trim(),
      imageUrl: imageUrl,
      clearImageUrl: imageUrl == null,
      accentColorHex: accentColorHex,
      isPublic: collection.isPublic,
      isPlatformSponsored: collection.isPlatformSponsored,
      isRecurring: isRecurring,
      visibilityStatus: collection.visibilityStatus,
      recurringCadence: cadence,
    );
    state = state.copyWith(collections: collections);
    return collections[index];
  }

  Future<PaymentIntentModel> createPaymentIntent(
    PaymentIntentDraft draft,
  ) async {
    exactJsonInteger(
      draft.amountRwf,
      field: 'contribution.amount_rwf',
      minimum: 1,
    );
    exactJsonIdentifier(
      draft.collectionId,
      field: 'contribution.collection_id',
    );
    final profile = _requireReadyProfile();
    final collection = _requireActiveCollection(draft.collectionId);
    final contributionRail = collection.contributionRailFor(profile);
    if (contributionRail == 'unavailable') {
      throw StateError('This group has no active payment route.');
    }
    if (contributionRail == 'rwanda_momo' && !profile.isRwanda) {
      throw StateError(
        'This group accepts Rwanda MoMo contributions. Use a verified Rwanda MoMo profile.',
      );
    }
    if (!collection.isPublic &&
        !collection.isCurrentUserMember &&
        collection.creatorUserId != profile.id) {
      throw StateError('Join this group before contributing.');
    }
    final supabase = _supabase;
    final now = DateTime.now();
    for (final intent in state.paymentIntents) {
      // Live callers must recheck server-owned profile readiness even when
      // an older intent is cached (for example after another device edits it).
      if (supabase == null &&
          intent.collectionId == collection.id &&
          intent.expectedAmountRwf == draft.amountRwf &&
          intent.rail == contributionRail &&
          intent.isAwaitingTransfer &&
          now.isBefore(intent.expiresAt.toLocal())) {
        return intent;
      }
    }
    if (supabase != null && supabase.auth.currentUser != null) {
      final session = _captureSession();
      if (session.identity?.userId != profile.id ||
          session.accessToken == null) {
        throw StateError('Refresh your signed-in profile before contributing.');
      }
      final response = await supabase
          .rpc<dynamic>(
            'create_contribution_intent',
            params: {
              'collection': draft.collectionId,
              'p_expected_amount_rwf': draft.amountRwf,
              'p_sender_phone_hash': HashUtils.phoneHash(profile.momoNumber),
            },
          )
          .setHeader('Authorization', 'Bearer ${session.accessToken}')
          .retry(enabled: false);
      if (response is List && response.length != 1) {
        throw const FormatException('Invalid contribution response');
      }
      final responseRow = response is List ? response.single : response;
      if (responseRow is! Map ||
          responseRow.keys.any((key) => key is! String)) {
        throw const FormatException('Invalid contribution response');
      }
      final intent = PaymentIntentModel.fromJson(
        Map<String, dynamic>.from(responseRow),
      );
      if (intent.collectionId != draft.collectionId ||
          intent.expectedAmountRwf != draft.amountRwf ||
          intent.rail != contributionRail ||
          intent.currency != 'RWF') {
        throw const FormatException(
          'Contribution response does not match the request',
        );
      }
      if (!_isCurrentSession(session) ||
          state.currentProfile?.id != profile.id) {
        throw StateError('Account changed');
      }
      state = state.copyWith(
        paymentIntents: [
          intent,
          ...state.paymentIntents.where((old) => old.id != intent.id).take(49),
        ],
        collections: [
          for (final item in state.collections)
            if (item.id == collection.id && collection.isPublic)
              item.copyWith(isCurrentUserMember: true)
            else
              item,
        ],
      );
      // The server may have reused an older active intent, so do not guess a
      // pending count from the recent window or increment it optimistically.
      unawaited(
        refreshPaymentIntent(intent.id).catchError((Object _) => intent),
      );
      return intent;
    }
    if (!_allowLocalWrites) {
      throw StateError('Sign in before starting a contribution.');
    }

    final intent = PaymentIntentModel(
      id: _uuid.v4(),
      collectionId: collection.id,
      expectedAmountRwf: draft.amountRwf,
      receiverMomoNumber: collection.receiverMomoNumber ?? '',
      receiverMomoLabel: collection.receiverDisplayLabel,
      momoNetwork: collection.receiverNetwork,
      senderPhoneHash: HashUtils.phoneHash(profile.momoNumber),
      status: 'pending',
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(hours: 24)),
    );
    state = state.copyWith(
      paymentIntents: [...state.paymentIntents, intent],
      collections: [
        for (final item in state.collections)
          if (item.id == collection.id && collection.isPublic)
            item.copyWith(isCurrentUserMember: true)
          else
            item,
      ],
    );
    return intent;
  }

  // Preserve the public wrapper for existing direct callers. A no-op is never
  // success: all successful returns are backed by a validated durable receipt.
  Future<void> ingestBankNotificationSms(
    String body, {
    String? clientEnvelopeId,
    String rawSender = 'android_sms',
    String? receivedAtDevice,
    bool refreshAfterIngest = true,
  }) async {
    final owner = state.currentProfile?.id;
    if (owner == null) throw StateError('Sign in before sending a receipt.');
    await _acceptSmsReceipt(
      body,
      expectedOwner: owner,
      clientEnvelopeId: clientEnvelopeId ?? _uuid.v4(),
      rawSender: rawSender,
      receivedAtDevice: receivedAtDevice,
    );
    if (refreshAfterIngest) await loadInitial();
  }

  void _requireSmsOwner(String owner, SupabaseClient client) {
    if (!mounted ||
        !identical(client, _supabase) ||
        client.auth.currentUser?.id != owner ||
        state.currentProfile?.id != owner ||
        state.currentProfile?.isRwanda != true) {
      throw StateError('Account changed. Receipt remains queued.');
    }
  }

  Future<DurableSmsReceipt> _acceptSmsReceipt(
    String body, {
    required String expectedOwner,
    required String clientEnvelopeId,
    required String rawSender,
    required String? receivedAtDevice,
  }) async {
    final client = _supabase;
    if (client == null) throw StateError('Connect before sending a receipt.');
    _requireSmsOwner(expectedOwner, client);
    if (body.trim().isEmpty) throw const FormatException('Receipt is empty.');
    final profile = state.currentProfile!;
    final momoNumber = profile.momoNumber;
    void checkOwner() {
      _requireSmsOwner(expectedOwner, client);
      if (state.currentProfile?.momoNumber != momoNumber) {
        throw StateError('Receiving account changed. Receipt remains queued.');
      }
    }

    final status = await _smsAccessChannel.status();
    checkOwner();
    if (!status.enabled || !status.granted) {
      throw StateError('Receipt access unavailable. Receipt remains queued.');
    }
    final sender = rawSender.trim();
    final receiverHash = HashUtils.phoneHash(momoNumber);
    await client.rpc<void>(
      'record_sms_access_consent',
      params: {
        'enabled': true,
        'momo_number_hash': receiverHash,
        'build_channel': 'android_sms_ingest_attested',
        'device_label': 'flutter_android_play_integrity',
      },
    );
    checkOwner();
    final nonce = _uuid.v4();
    const integrity = PlayIntegrityService();
    final requestHash = integrity.buildSmsIngestionRequestHash(
      subjectId: expectedOwner,
      nonce: nonce,
      receiverMomoNumberHash: receiverHash,
      clientEnvelopeId: clientEnvelopeId,
      rawSender: sender,
      rawBody: body,
      receivedAtDevice: receivedAtDevice,
    );
    final token = await integrity.requestStandardToken(
      requestHash: requestHash,
    );
    checkOwner();
    if (token == null || token.isEmpty) {
      throw StateError('Receipt verification is unavailable.');
    }
    final verdict = await integrity.verifySmsWithServer(
      supabase: client,
      requestHash: requestHash,
      integrityToken: token,
      subjectId: expectedOwner,
      nonce: nonce,
      receiverMomoNumberHash: receiverHash,
      clientEnvelopeId: clientEnvelopeId,
      rawSender: sender,
      rawBody: body,
      receivedAtDevice: receivedAtDevice,
    );
    checkOwner();
    if (verdict?.hasUsableNativeCapability != true) {
      throw StateError('Receipt verification did not pass.');
    }
    final response = await client.functions.invoke(
      'ingest-payment-sms',
      body: {
        'native_capability': verdict!.nativeCapability,
        'client_envelope_id': clientEnvelopeId,
        'raw_sender': sender,
        'raw_body': body,
        'receiver_momo_number': momoNumber,
        'received_at_device': receivedAtDevice,
      },
    );
    checkOwner();
    if (response.status < 200 || response.status >= 300) {
      throw StateError('Receipt is not acknowledged. Try again.');
    }
    return DurableSmsReceipt.decode(
      response.data,
      expectedOwner: expectedOwner,
      expectedEnvelope: clientEnvelopeId,
      rawBody: body,
    );
  }

  Future<bool> setSmsAccess(bool enabled, {String? expectedOwnerUserId}) async {
    final profile = state.currentProfile;
    final supabase = _supabase;
    final owner = profile?.id;
    void requireCurrentOwner() {
      if (owner == null ||
          (supabase != null && supabase.auth.currentUser?.id != owner) ||
          state.currentProfile?.id != owner ||
          (expectedOwnerUserId != null && expectedOwnerUserId != owner)) {
        throw StateError('SMS access account changed. Try again.');
      }
    }

    if (enabled && (profile == null || !profile.isRwanda)) {
      throw StateError(
        'MoMo receipt SMS access is available only for Rwanda profiles.',
      );
    }
    requireCurrentOwner();
    final granted = await _smsAccessChannel.setEnabled(
      enabled,
      ownerUserId: owner,
    );
    if ((supabase != null && supabase.auth.currentUser?.id != owner) ||
        state.currentProfile?.id != owner) {
      await _smsAccessChannel.suspendUnlessOwner(
        supabase?.auth.currentUser?.id,
      );
      throw StateError('SMS access account changed. Try again.');
    }
    if (!enabled && !granted) {
      final nativeStatus = await _smsAccessChannel.status();
      if ((SmsAccessChannel.requiresNativeBridge &&
              !nativeStatus.bridgeAvailable) ||
          nativeStatus.consentEnabled) {
        throw StateError('SMS capture could not be stopped on this device.');
      }
    }
    final consentEnabled = enabled && granted;
    try {
      if (supabase != null &&
          supabase.auth.currentUser != null &&
          profile != null) {
        requireCurrentOwner();
        await supabase.rpc<void>(
          'record_sms_access_consent',
          params: {
            'enabled': consentEnabled,
            'momo_number_hash': profile.momoNumber.trim().isEmpty
                ? null
                : HashUtils.phoneHash(profile.momoNumber),
            'build_channel': 'android_sms_access',
            'device_label': 'flutter_app',
          },
        );
        requireCurrentOwner();
      } else if (enabled) {
        throw StateError('An authenticated Rwanda session is required.');
      }
    } catch (_) {
      if (enabled) {
        await _smsAccessChannel.suspendUnlessOwner(
          supabase?.auth.currentUser?.id,
        );
      }
      state = state.copyWith(
        smsAccessEnabled: false,
        smsAccessDenied: enabled && !granted,
      );
      rethrow;
    }
    state = state.copyWith(
      smsAccessEnabled: consentEnabled,
      smsAccessDenied: enabled && !granted,
    );
    return consentEnabled;
  }

  Future<SmsAccessStatus> refreshSmsAccessStatus() async {
    final nativeStatus = await _smsAccessChannel.status();
    if (nativeStatus.supported &&
        nativeStatus.declared &&
        !nativeStatus.enabled &&
        !nativeStatus.queueUnavailable &&
        !nativeStatus.queueOverflowed &&
        state.currentProfile != null &&
        _supabase?.auth.currentUser != null) {
      await setSmsAccess(false);
      return _smsAccessChannel.status();
    }
    state = state.copyWith(
      smsAccessEnabled: nativeStatus.enabled,
      smsAccessDenied:
          nativeStatus.permanentlyDenied ||
          (nativeStatus.requestedBefore && !nativeStatus.granted),
      smsQueueOverflowed: nativeStatus.queueOverflowed,
      smsSyncNeedsAttention:
          state.smsSyncNeedsAttention ||
          nativeStatus.queueUnavailable ||
          nativeStatus.queueOverflowed,
    );
    return nativeStatus;
  }

  Future<int> syncPendingSmsAccess() {
    final existing = _smsSyncInFlight;
    if (existing != null) {
      _smsSyncRequested = true;
      return existing;
    }
    final sync = _runPendingSmsAccessSync();
    _smsSyncInFlight = sync;
    return sync.whenComplete(() {
      if (identical(_smsSyncInFlight, sync)) _smsSyncInFlight = null;
    });
  }

  Future<int> _runPendingSmsAccessSync() async {
    final owner = state.currentProfile?.id;
    try {
      final ingested = await _drainPendingSmsAccess();
      final nativeStatus = await _smsAccessChannel.status();
      if (mounted &&
          state.currentProfile?.id == owner &&
          _supabase?.auth.currentUser?.id == owner) {
        state = state.copyWith(
          smsSyncNeedsAttention:
              nativeStatus.queueUnavailable ||
              nativeStatus.queueOverflowed ||
              (state.smsSyncNeedsAttention &&
                  (!nativeStatus.enabled || !nativeStatus.granted)),
        );
      }
      return ingested;
    } catch (_) {
      if (mounted &&
          state.currentProfile?.id == owner &&
          _supabase?.auth.currentUser?.id == owner) {
        state = state.copyWith(smsSyncNeedsAttention: true);
      }
      rethrow;
    }
  }

  Future<int> _drainPendingSmsAccess() async {
    var ingested = 0;
    do {
      _smsSyncRequested = false;
      ingested += await _syncPendingSmsAccessPass();
    } while (_smsSyncRequested && mounted);
    return ingested;
  }

  Future<int> _syncPendingSmsAccessPass() async {
    final profile = state.currentProfile;
    final client = _supabase;
    if (profile == null || client == null) return 0;
    final owner = profile.id;
    _requireSmsOwner(owner, client);
    final status = await _smsAccessChannel.status();
    _requireSmsOwner(owner, client);
    if (!status.enabled || !status.granted) return 0;
    final pending = await _smsAccessChannel.readPendingSms(ownerUserId: owner);
    _requireSmsOwner(owner, client);
    var ingested = 0;
    for (final item in pending) {
      _requireSmsOwner(owner, client);
      if (item.ownerUserId != owner || item.rawBody.trim().isEmpty) {
        // No disableAndClear call: an account mismatch is not consent to destroy evidence.
        throw StateError('Queued receipt ownership needs review.');
      }
      final receipt = await _acceptSmsReceipt(
        item.rawBody,
        expectedOwner: owner,
        clientEnvelopeId: item.id,
        rawSender: item.rawSender,
        receivedAtDevice: item.receivedAtDevice.trim().isEmpty
            ? null
            : item.receivedAtDevice,
      );
      _requireSmsOwner(owner, client);
      final acknowledged = await _smsAccessChannel.acknowledgeDurableReceipt(
        receipt,
      );
      _requireSmsOwner(owner, client);
      if (!acknowledged) {
        throw StateError(
          'Receipt remains queued until acknowledgement can be verified.',
        );
      }
      ingested += 1;
    }
    if (ingested > 0) {
      _requireSmsOwner(owner, client);
      await loadInitial(syncPendingSms: false);
    }
    return ingested;
  }
}
