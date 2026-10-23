part of 'collect_repository.dart';

/// Group/payment setup and receipt processing share the repository's state and
/// authenticated dependencies. Instance methods retain normal override behavior.
mixin _CollectContributionActions on StateNotifier<CollectState> {
  CollectCloudflareClient? get _backend;
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
  CollectProfile _requireProfile();
  CollectCollection _requireActiveCollection(String collectionId);
  CollectProfile _requireCollectionOwner(
    CollectCollection collection, {
    required String action,
  });

  /// Create group identity and owner membership. This does not grant a payment
  /// route or SMS permission. Retry the same uncertain draft with its requestId.
  Future<CollectCollection> createCollection({
    required String title,
    required String description,
    CollectionType collectionType = CollectionType.ikimina,
    String? categorySubtype,
    String? purposeLabel,
    String? accentColorHex,
    String? imageUrl,
    bool isPublic = false,
    required String requestId,
  }) async {
    final profile = _requireProfile();
    if (isPublic) {
      throw const FormatException('Member-created groups are private.');
    }
    final backend = _backend;
    if (backend != null && backend.auth.currentUser != null) {
      final user = backend.auth.currentUser!;
      final session = _captureSession();
      void current() => _requireCurrentMemberSession(session, user.id);
      current();
      final collectionId = await backend
          .rpc<String>(
            'create_private_group_metadata_v1',
            params: {
              'p_request_id': requestId,
              // Wire label only; metadata creation has no device attestation gate.
              'build_channel': 'android_group_metadata',
              'group_name': title.trim(),
              'group_description': description.trim(),
              'group_collection_type': collectionType.storageValue,
              'group_category_subtype': categorySubtype?.trim(),
              'group_purpose_label': purposeLabel?.trim(),
              'group_image_url': imageUrl,
              'group_accent_color_hex': accentColorHex,
              'group_is_public': false,
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
      if (collection.creatorUserId != user.id ||
          !collection.isCurrentUserMember ||
          collection.isPublic ||
          collection.isPlatformSponsored ||
          collection.primaryPaymentRail != 'unavailable' ||
          collection.receiverMomoNumber != null) {
        throw const FormatException('Created group metadata is invalid.');
      }
      await loadInitial();
      current();
      if (!state.collections.any((item) => item.id == collectionId)) {
        state = state.copyWith(collections: [collection, ...state.collections]);
      }
      return collection;
    }
    if (!_allowLocalWrites) {
      throw StateError('Sign in before creating a group.');
    }
    final collection = CollectCollection(
      id: requestId,
      slug: '${_slug(title)}-$requestId',
      creatorUserId: profile.id,
      title: title.trim(),
      description: description.trim(),
      collectionType: collectionType,
      categorySubtype: categorySubtype,
      purposeLabel: purposeLabel,
      accentColorHex: accentColorHex,
      imageUrl: imageUrl,
      receiverMomoNumber: null,
      receiverDisplayLabel: '',
      receiverNetwork: 'unknown',
      primaryPaymentRail: 'unavailable',
      isCurrentUserMember: true,
      isPublic: false,
      visibilityStatus: 'private',
      createdAt: DateTime.now(),
    );
    if (!state.collections.any((item) => item.id == requestId)) {
      state = state.copyWith(collections: [...state.collections, collection]);
    }
    return state.collections.singleWhere((item) => item.id == requestId);
  }

  /// Compatibility path for a receiver-bound, attested creation command. Its
  /// financial/device admission body remains unchanged in this proposal.
  Future<CollectCollection> createCollectionWithVerifiedReceiver({
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
    final backend = _backend;

    if (backend != null && backend.auth.currentUser != null) {
      final user = backend.auth.currentUser!;
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
      await backend
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
      final groupRequest = Map<String, Object?>.unmodifiable({
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
      });
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
        backend: backend,
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
      final collectionId = await backend
          .rpc<String>(
            'create_private_group_with_owner_media_attested',
            params: Map<String, dynamic>.unmodifiable({
              for (final entry in groupRequest.entries)
                if (entry.key != 'group_is_public') entry.key: entry.value,
              'p_request_id': nonce,
              'native_capability': verdict!.nativeCapability,
              'group_image_url': imageUrl,
              'group_accent_color_hex': accentColorHex,
            }),
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
    if (!_allowLocalWrites && backend != null) {
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
    final backend = _backend;

    if (backend != null && backend.auth.currentUser != null) {
      final session = _captureSession();
      final ownerId = state.currentProfile!.id;
      void current() => _requireCurrentMemberSession(session, ownerId);
      current();
      await backend
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
      clearImageUrl: imageUrl == '',
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
    final backend = _backend;
    final now = DateTime.now();
    for (final intent in state.paymentIntents) {
      // Live callers must recheck server-owned profile readiness even when
      // an older intent is cached (for example after another device edits it).
      if (backend == null &&
          intent.collectionId == collection.id &&
          intent.expectedAmountRwf == draft.amountRwf &&
          intent.rail == contributionRail &&
          intent.isAwaitingTransfer &&
          now.isBefore(intent.expiresAt.toLocal())) {
        return intent;
      }
    }
    if (backend != null && backend.auth.currentUser != null) {
      final session = _captureSession();
      if (session.identity?.userId != profile.id ||
          session.accessToken == null) {
        throw StateError('Refresh your signed-in profile before contributing.');
      }
      final response = await backend
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

  void _requireSmsOwner(String owner, CollectCloudflareClient client) {
    if (!mounted ||
        !identical(client, _backend) ||
        client.auth.currentUser?.id != owner ||
        state.currentProfile?.id != owner) {
      throw StateError('Account changed. Receipt remains queued.');
    }
  }

  Future<DurableSmsReceipt> _acceptSmsReceipt(
    String body, {
    required String expectedOwner,
    required String clientEnvelopeId,
    required String rawSender,
    required String? receivedAtDevice,
    String completeness = 'complete',
  }) async {
    final client = _backend;
    if (client == null) throw StateError('Connect before sending a receipt.');
    _requireSmsOwner(expectedOwner, client);
    if (body.trim().isEmpty) throw const FormatException('Receipt is empty.');
    void checkOwner() => _requireSmsOwner(expectedOwner, client);
    final status = await _smsAccessChannel.status();
    checkOwner();
    if (!status.enabled || !status.granted) {
      throw StateError('SMS access is off. The message remains queued.');
    }
    final response = await client.functions.invoke(
      'ingest-client-sms',
      body: {
        'client_envelope_id': clientEnvelopeId,
        'raw_sender': rawSender,
        'raw_body': body,
        'received_at_device': receivedAtDevice,
        'completeness': completeness,
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
    final backend = _backend;
    final owner = profile?.id;
    void requireCurrentOwner() {
      if (owner == null ||
          (backend != null && backend.auth.currentUser?.id != owner) ||
          state.currentProfile?.id != owner ||
          (expectedOwnerUserId != null && expectedOwnerUserId != owner)) {
        throw StateError('SMS access account changed. Try again.');
      }
    }

    requireCurrentOwner();
    final granted = await _smsAccessChannel.setEnabled(
      enabled,
      ownerUserId: owner,
    );
    if ((backend != null && backend.auth.currentUser?.id != owner) ||
        state.currentProfile?.id != owner) {
      await _smsAccessChannel.suspendUnlessOwner(backend?.auth.currentUser?.id);
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
      if (backend != null &&
          backend.auth.currentUser != null &&
          profile != null) {
        requireCurrentOwner();
        await backend.rpc<void>(
          'record_sms_access_consent',
          params: {
            'enabled': consentEnabled,
            'build_channel': 'android_sms_access',
            'device_label': 'flutter_app',
          },
        );
        requireCurrentOwner();
      } else if (enabled) {
        throw StateError('Sign in before allowing SMS access.');
      }
    } catch (_) {
      if (enabled) {
        await _smsAccessChannel.setEnabled(false, ownerUserId: owner);
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
    if (consentEnabled) {
      // Native capture can wake before the server records consent. Only after
      // that ACK may this foreground drain recover an earlier authorization wait.
      unawaited(
        Future<void>(() async {
          if (!mounted ||
              !state.smsAccessEnabled ||
              state.currentProfile?.id != owner ||
              backend?.auth.currentUser?.id != owner) {
            return;
          }
          try {
            await syncPendingSmsAccess();
          } catch (_) {
            // The drain preserves originals and publishes its needs-attention state.
          }
        }),
      );
    }
    return consentEnabled;
  }

  Future<SmsAccessStatus> refreshSmsAccessStatus() async {
    final nativeStatus = await _smsAccessChannel.status();
    if (nativeStatus.supported &&
        nativeStatus.declared &&
        nativeStatus.consentEnabled &&
        !nativeStatus.enabled &&
        !nativeStatus.queueUnavailable &&
        !nativeStatus.queueOverflowed &&
        !nativeStatus.queueNeedsReview &&
        state.currentProfile != null &&
        _backend?.auth.currentUser != null) {
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
          nativeStatus.queueOverflowed ||
          nativeStatus.queueNeedsReview,
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

  Future<int> retryRejectedSmsAccess({String? expectedOwnerUserId}) async {
    final owner = state.currentProfile?.id;
    final client = _backend;
    if (owner == null ||
        client == null ||
        expectedOwnerUserId != null && expectedOwnerUserId != owner) {
      throw StateError('Sign in to retry your SMS uploads.');
    }
    _requireSmsOwner(owner, client);
    final status = await _smsAccessChannel.status();
    _requireSmsOwner(owner, client);
    if (!status.enabled || !status.granted) {
      throw StateError('Allow SMS access before retrying uploads.');
    }
    final retried = await _smsAccessChannel.retryRejectedSms(
      ownerUserId: owner,
    );
    _requireSmsOwner(owner, client);
    if (!retried) throw StateError('SMS uploads remain queued for review.');
    final uploaded = await syncPendingSmsAccess();
    _requireSmsOwner(owner, client);
    return uploaded;
  }

  Future<int> _runPendingSmsAccessSync() async {
    final owner = state.currentProfile?.id;
    try {
      final ingested = await _drainPendingSmsAccess();
      final nativeStatus = await _smsAccessChannel.status();
      if (mounted &&
          state.currentProfile?.id == owner &&
          _backend?.auth.currentUser?.id == owner) {
        state = state.copyWith(
          smsSyncNeedsAttention:
              nativeStatus.queueUnavailable ||
              nativeStatus.queueOverflowed ||
              nativeStatus.queueNeedsReview ||
              (state.smsSyncNeedsAttention &&
                  (!nativeStatus.enabled || !nativeStatus.granted)),
        );
      }
      return ingested;
    } catch (_) {
      if (mounted &&
          state.currentProfile?.id == owner &&
          _backend?.auth.currentUser?.id == owner) {
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
    final client = _backend;
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
      if (item.needsReview) continue;
      late final DurableSmsReceipt receipt;
      try {
        receipt = await _acceptSmsReceipt(
          item.rawBody,
          expectedOwner: owner,
          clientEnvelopeId: item.id,
          rawSender: item.rawSender,
          receivedAtDevice: item.receivedAtDevice.trim().isEmpty
              ? null
              : item.receivedAtDevice,
          completeness: item.completeness,
        );
      } on CollectFunctionException catch (error) {
        _requireSmsOwner(owner, client);
        if (!const {400, 409, 413, 422}.contains(error.status)) rethrow;
        final parked = await _smsAccessChannel.parkPendingSms(
          ownerUserId: owner,
          id: item.id,
        );
        _requireSmsOwner(owner, client);
        if (!parked) throw StateError('SMS could not be retained for review.');
        state = state.copyWith(smsSyncNeedsAttention: true);
        continue;
      }
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
