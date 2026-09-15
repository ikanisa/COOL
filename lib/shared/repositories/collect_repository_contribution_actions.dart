part of 'collect_repository.dart';

/// Group/payment setup and receipt processing share the repository's state and
/// authenticated dependencies. Instance methods retain normal override behavior.
mixin _CollectContributionActions on StateNotifier<CollectState> {
  SupabaseClient? get _supabase;
  _CollectLiveReader get _liveReader;
  SmsAccessChannel get _smsAccessChannel;
  bool get _allowLocalWrites;
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
      final profile = state.currentProfile;
      if (profile == null || profile.id != user.id) {
        throw StateError(
          'Refresh your signed-in profile before creating a group.',
        );
      }
      final smsStatus = await refreshSmsAccessStatus();
      if (!smsStatus.enabled || !smsStatus.granted) {
        throw StateError(
          'Enable MoMo receipt SMS access before creating a group.',
        );
      }
      await supabase.rpc<void>(
        'record_sms_access_consent',
        params: {
          'enabled': true,
          'momo_number_hash': receiverHash,
          'build_channel': 'android_group_create_attested',
          'device_label': 'flutter_android_play_integrity',
        },
      );
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
      );
      if (verdict?.hasUsableNativeCapability != true) {
        throw StateError('Android device verification did not pass.');
      }
      final collectionId = await supabase.rpc<String>(
        'create_private_group_with_owner_media_attested',
        params: {
          ...groupRequest..remove('group_is_public'),
          'native_capability': verdict!.nativeCapability,
          'group_image_url': imageUrl,
          'group_accent_color_hex': accentColorHex,
        },
      );
      final collection = await _liveReader.fetchCollection(collectionId);
      await loadInitial();
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
      await supabase.rpc<void>(
        'update_bank_transfer_group_profile',
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
      );
      final collection = await _liveReader.fetchCollection(collectionId);
      await loadInitial();
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
    if (draft.amountRwf <= 0) {
      throw const FormatException('Contribution amount must be above zero');
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
      final response = contributionRail == 'rwanda_momo'
          ? await supabase.rpc<dynamic>(
              'create_contribution_intent',
              params: {
                'collection': draft.collectionId,
                'p_expected_amount_rwf': draft.amountRwf,
                'p_sender_phone_hash': HashUtils.phoneHash(profile.momoNumber),
              },
            )
          : await supabase.rpc<dynamic>(
              'create_bank_transfer_intent',
              params: {
                'p_collection_id': draft.collectionId,
                'p_amount_minor': draft.amountMinor,
              },
            );
      final responseRow = response is List && response.isNotEmpty
          ? response.first
          : response;
      final intent = PaymentIntentModel.fromJson(
        Map<String, dynamic>.from(responseRow as Map),
      );
      if (!mounted || supabase.auth.currentUser?.id != profile.id) {
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

    final intent = contributionRail == 'rwanda_momo'
        ? PaymentIntentModel(
            id: _uuid.v4(),
            collectionId: collection.id,
            expectedAmountRwf: draft.amountRwf,
            rail: 'rwanda_momo',
            receiverMomoNumber: collection.receiverMomoNumber ?? '',
            receiverMomoLabel: collection.receiverDisplayLabel,
            momoNetwork: collection.receiverNetwork,
            senderPhoneHash: HashUtils.phoneHash(profile.momoNumber),
            currency: 'RWF',
            status: 'pending',
            createdAt: DateTime.now(),
            expiresAt: DateTime.now().add(const Duration(hours: 24)),
          )
        : PaymentIntentModel(
            id: _uuid.v4(),
            collectionId: collection.id,
            expectedAmountMinor: draft.amountMinor,
            transferReference:
                'COL-${_uuid.v4().replaceAll('-', '').substring(0, 10).toUpperCase()}',
            destination: const BankTransferDestination(
              id: 'fixture-bank',
              beneficiaryName: 'IKANISA Collect',
              iban: 'DE89370400440532013000',
              ibanMasked: 'DE89••••3000',
              bic: 'COBADEFFXXX',
              bankName: 'Collect Bank',
              status: 'active',
              enabled: true,
            ),
            status: 'awaiting_transfer',
            createdAt: DateTime.now(),
            expiresAt: DateTime.now().add(const Duration(hours: 48)),
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

  Future<void> ingestBankNotificationSms(
    String body, {
    String? clientEnvelopeId,
    String rawSender = 'android_sms',
    String? receivedAtDevice,
    bool refreshAfterIngest = true,
  }) async {
    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      final profile = state.currentProfile;
      if (profile?.isRwanda != true) return;
      final user = supabase.auth.currentUser!;
      final cleanBody = body.trim();
      final cleanSender = rawSender.trim();
      final envelopeId = clientEnvelopeId ?? _uuid.v4();
      final parsedReceivedAt = DateTime.tryParse(
        receivedAtDevice?.trim() ?? '',
      );
      final cleanReceivedAt = parsedReceivedAt == null
          ? null
          : receivedAtDevice!.trim();
      final receiverHash = HashUtils.phoneHash(profile!.momoNumber);
      await supabase.rpc<void>(
        'record_sms_access_consent',
        params: {
          'enabled': true,
          'momo_number_hash': receiverHash,
          'build_channel': 'android_sms_ingest_attested',
          'device_label': 'flutter_android_play_integrity',
        },
      );
      final nonce = _uuid.v4();
      const integrity = PlayIntegrityService();
      final requestHash = integrity.buildSmsIngestionRequestHash(
        subjectId: user.id,
        nonce: nonce,
        receiverMomoNumberHash: receiverHash,
        clientEnvelopeId: envelopeId,
        rawSender: cleanSender,
        rawBody: cleanBody,
        receivedAtDevice: cleanReceivedAt,
      );
      final token = await integrity.requestStandardToken(
        requestHash: requestHash,
      );
      if (token == null || token.isEmpty) {
        throw StateError(
          'Install the approved Android build to verify MoMo receipt SMS.',
        );
      }
      final verdict = await integrity.verifySmsWithServer(
        supabase: supabase,
        requestHash: requestHash,
        integrityToken: token,
        subjectId: user.id,
        nonce: nonce,
        receiverMomoNumberHash: receiverHash,
        clientEnvelopeId: envelopeId,
        rawSender: cleanSender,
        rawBody: cleanBody,
        receivedAtDevice: cleanReceivedAt,
      );
      if (verdict?.hasUsableNativeCapability != true) {
        throw StateError('Android receipt verification did not pass.');
      }
      await supabase.functions.invoke(
        'ingest-payment-sms',
        body: {
          'native_capability': verdict!.nativeCapability,
          'client_envelope_id': envelopeId,
          'raw_sender': cleanSender,
          'raw_body': cleanBody,
          'receiver_momo_number': profile.momoNumber,
          'received_at_device': cleanReceivedAt,
        },
      );
      if (refreshAfterIngest) await loadInitial();
    }
  }

  Future<BankTransferDestination> getBankTransferDestination() async {
    final supabase = _supabase;
    if (supabase != null) {
      if (supabase.auth.currentUser == null) {
        throw StateError('Sign in to load approved bank details.');
      }
      final response = await supabase.rpc<dynamic>(
        'get_bank_transfer_destination',
      );
      return BankTransferDestination.fromJson(
        Map<String, dynamic>.from(response as Map),
      );
    }
    if (!_allowLocalWrites) {
      throw StateError('Connect to load approved bank details.');
    }
    return const BankTransferDestination(
      id: 'fixture-bank',
      beneficiaryName: 'IKANISA Collect',
      iban: 'DE89370400440532013000',
      ibanMasked: 'DE89••••3000',
      bic: 'COBADEFFXXX',
      bankName: 'Collect Bank',
      status: 'active',
      enabled: true,
    );
  }

  Future<void> markBankTransferHandoffOpened(String intentId) async {
    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      await supabase.rpc<void>(
        'mark_bank_transfer_handoff_opened',
        params: {'p_intent_id': intentId},
      );
      await loadInitial();
      return;
    }
    final intents = [
      for (final intent in state.paymentIntents)
        if (intent.id == intentId)
          PaymentIntentModel(
            id: intent.id,
            collectionId: intent.collectionId,
            expectedAmountMinor: intent.expectedAmountMinor,
            transferReference: intent.transferReference,
            destination: intent.destination,
            currency: intent.currency,
            status: 'handoff_opened',
            createdAt: intent.createdAt,
            expiresAt: intent.expiresAt,
          )
        else
          intent,
    ];
    state = state.copyWith(paymentIntents: intents);
  }

  Future<bool> setSmsAccess(bool enabled) async {
    final profile = state.currentProfile;
    if (enabled && (profile == null || !profile.isRwanda)) {
      throw StateError(
        'MoMo receipt SMS access is available only for Rwanda profiles.',
      );
    }
    final supabase = _supabase;
    final granted = await _smsAccessChannel.setEnabled(
      enabled,
      ownerUserId: profile?.id,
    );
    final consentEnabled = enabled && granted;
    try {
      if (supabase != null &&
          supabase.auth.currentUser != null &&
          profile != null) {
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
      } else if (enabled) {
        throw StateError('An authenticated Rwanda session is required.');
      }
    } catch (_) {
      if (enabled) {
        await _smsAccessChannel.setEnabled(false, ownerUserId: profile?.id);
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
    try {
      final ingested = await _drainPendingSmsAccess();
      state = state.copyWith(smsSyncNeedsAttention: false);
      return ingested;
    } catch (_) {
      state = state.copyWith(smsSyncNeedsAttention: true);
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
    if (profile == null) return 0;
    final status = await refreshSmsAccessStatus();
    if (!status.enabled) return 0;
    final pending = await _smsAccessChannel.readPendingSms();
    var ingested = 0;
    for (final item in pending) {
      if (item.rawBody.trim().isEmpty) continue;
      if (item.ownerUserId != profile.id) {
        await _smsAccessChannel.setEnabled(false, ownerUserId: profile.id);
        throw StateError(
          'Queued SMS belongs to a different account and was quarantined.',
        );
      }
      await ingestBankNotificationSms(
        item.rawBody,
        clientEnvelopeId: item.id,
        rawSender: item.rawSender,
        receivedAtDevice: item.receivedAtDevice.trim().isEmpty
            ? null
            : item.receivedAtDevice,
        refreshAfterIngest: false,
      );
      final acknowledged = await _smsAccessChannel.acknowledgePendingSms([
        item.id,
      ]);
      if (!acknowledged) break;
      ingested += 1;
    }
    if (ingested > 0 && _supabase?.auth.currentUser != null) {
      await loadInitial(syncPendingSms: false);
    }
    return ingested;
  }
}
