part of 'collect_repository.dart';

/// Group creation and contribution preparation use the current member authority.
mixin _CollectContributionActions on StateNotifier<CollectState> {
  CollectCloudflareClient? get _backend;
  _CollectLiveReader get _liveReader;
  bool get _allowLocalWrites;
  int get _loadGeneration;
  _CollectSessionFence _captureSession();
  void _requireCurrentMemberSession(
    _CollectSessionFence session,
    String profileId,
  );
  Uuid get _uuid;
  Future<SmsAccessStatus> refreshSmsAccessStatus();

  Future<void> loadInitial({bool syncPendingSms = false});
  Future<PaymentIntentModel> refreshPaymentIntent(String id);
  Future<PaymentIntentModel> prepareContributionIntent(
    PaymentIntentDraft draft,
  );
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
    if (state.memberScopeUncertain) {
      throw StateError('Refresh your groups before creating a group.');
    }
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
      // A retained creation response is not current membership. Refresh first,
      // then read this group again so a stale pre-refresh DTO cannot be put
      // back after the refresh has removed access.
      final refresh = loadInitial();
      final refreshGeneration = _loadGeneration;
      await refresh;
      void requireCurrentRefresh() {
        current();
        if (refreshGeneration != _loadGeneration ||
            state.isLoading ||
            state.usingStaleCache ||
            state.memberScopeUncertain ||
            state.financialObservationUncertain ||
            state.lastError != null) {
          throw StateError(
            'The group could not be confirmed. Refresh before continuing.',
          );
        }
      }

      requireCurrentRefresh();
      final collection = await _liveReader.fetchCollection(
        collectionId,
        accessToken: session.accessToken,
      );
      requireCurrentRefresh();
      if (collection.creatorUserId != user.id ||
          !collection.isCurrentUserMember ||
          collection.isPublic ||
          collection.isPlatformSponsored ||
          collection.isArchived ||
          collection.primaryPaymentRail != 'unavailable' ||
          collection.receiverMomoNumber != null) {
        throw const FormatException('Created group metadata is invalid.');
      }
      state = state.copyWith(
        collections: [
          collection,
          ...state.collections.where((item) => item.id != collectionId),
        ],
      );
      requireCurrentRefresh();
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

  /// Compatibility entry point. Authenticated creation uses the protected
  /// contribution command and can raise [ContributionRecoveryRequired] after
  /// an uncertain result; callers must check that original request instead of
  /// starting another. Explicit offline fixtures retain their synthetic path.
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
    // Preserve the public entry point but route every authenticated mutation
    // through protected request custody. An uncertain response must not create
    // a fresh request ID on the next explicit call.
    if (_backend?.auth.currentUser != null) {
      return prepareContributionIntent(draft);
    }
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
}
