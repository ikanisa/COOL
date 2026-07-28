import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/security/hash_utils.dart';
import '../../core/security/phone_normalizer.dart';
import '../../core/security/public_id_generator.dart';
import '../../core/security/sms_access_channel.dart';
import '../../core/supabase/realtime_invalidation.dart';
import '../../core/supabase/supabase_module.dart';
import '../models/collect_models.dart';
import 'collect_offline_cache.dart';

part 'collect_repository_providers.dart';
part 'collect_repository_state.dart';
part 'collect_repository_fixture.dart';
part 'collect_repository_live_reader.dart';
part 'collect_repository_helpers.dart';

class CollectRepository extends StateNotifier<CollectState> {
  CollectRepository({
    SupabaseClient? supabase,
    SmsAccessChannel smsAccessChannel = const SmsAccessChannel(),
    CollectOfflineCache? offlineCache,
  }) : this._(
         supabase,
         smsAccessChannel,
         _emptyCollectState(),
         false,
         offlineCache ?? const CollectOfflineCache(),
       );

  CollectRepository.fixture({
    SupabaseClient? supabase,
    SmsAccessChannel smsAccessChannel = const SmsAccessChannel(),
    bool seeded = true,
    DateTime? fixtureNow,
    int fixtureCollectionCount = 2,
    int fixtureContributionCount = 2,
    CollectOfflineCache? offlineCache,
  }) : this._(
         supabase,
         smsAccessChannel,
         seeded
             ? _fixtureCollectState(
                 fixtureNow: fixtureNow,
                 collectionCount: fixtureCollectionCount,
                 contributionCount: fixtureContributionCount,
               )
             : _emptyCollectState(),
         true,
         offlineCache ?? const CollectOfflineCache(),
       );

  CollectRepository.appReviewDemo({
    SupabaseClient? supabase,
    SmsAccessChannel smsAccessChannel = const SmsAccessChannel(),
    CollectOfflineCache? offlineCache,
  }) : this._(
         supabase,
         smsAccessChannel,
         _emptyCollectState(),
         true,
         offlineCache ?? const CollectOfflineCache(),
       );

  CollectRepository._(
    this._supabase,
    this._smsAccessChannel,
    CollectState initialState,
    this._allowLocalWrites,
    this._offlineCache,
  ) : super(initialState);

  final SupabaseClient? _supabase;
  late final _CollectLiveReader _liveReader = _CollectLiveReader(_supabase);
  final SmsAccessChannel _smsAccessChannel;
  final bool _allowLocalWrites;
  final CollectOfflineCache _offlineCache;
  RealtimeInvalidationSubscription? _realtimeSync;

  static const _uuid = Uuid();
  static final _publicIds = PublicIdGenerator(random: Random(491));

  bool get isLive => _supabase?.auth.currentUser != null;

  Future<void> loadInitial() async {
    final supabase = _supabase;
    final user = supabase?.auth.currentUser;
    if (supabase == null || user == null) return;

    state = state.copyWith(isLoading: true, usingStaleCache: false);
    try {
      var profile = await _liveReader.fetchProfile(user.id);
      await _liveReader.ensureDeveloperAccountDataIfAvailable();
      profile = await _liveReader.fetchProfile(user.id) ?? profile;
      final collections = await _liveReader.fetchCollections();
      final paymentIntents = await _liveReader.fetchPaymentIntents();
      final contributions = await _liveReader.fetchContributions();
      final notificationPreferences = await _liveReader
          .fetchNotificationPreferences(profile);
      final notificationEvents = await _liveReader.fetchNotificationEvents(
        profile,
      );
      state = state.copyWith(
        currentProfile: profile,
        collections: collections,
        paymentIntents: paymentIntents,
        contributions: contributions,
        notificationEvents: notificationEvents,
        notificationPreferences: notificationPreferences,
        isLoading: false,
        usingStaleCache: false,
        lastSuccessfulSyncAt: DateTime.now().toUtc(),
      );
      unawaited(_offlineCache.save(_offlineSnapshotFromState()));
      _ensureRealtimeSync();
      unawaited(syncPendingSmsAccess());
    } catch (error) {
      final restored = await restoreOfflineSnapshot(reason: error.toString());
      if (!restored) {
        state = state.copyWith(
          isLoading: false,
          usingStaleCache: false,
          lastError: error.toString(),
        );
      }
    }
  }

  Future<bool> restoreOfflineSnapshot({required String reason}) async {
    final cached = await _offlineCache.read();
    if (cached == null || !cached.hasReadableData) return false;
    state = state.copyWith(
      currentProfile: cached.currentProfile,
      collections: cached.collections,
      paymentIntents: cached.paymentIntents,
      contributions: cached.contributions,
      isLoading: false,
      usingStaleCache: true,
      lastSuccessfulSyncAt: cached.savedAt,
      lastError: reason,
    );
    return true;
  }

  CollectOfflineSnapshot _offlineSnapshotFromState() {
    return CollectOfflineSnapshot(
      savedAt: state.lastSuccessfulSyncAt ?? DateTime.now().toUtc(),
      currentProfile: state.currentProfile,
      collections: state.collections,
      paymentIntents: state.paymentIntents,
      contributions: state.contributions,
    );
  }

  Future<CollectProfile> signInWithOtp({
    required String phone,
    required String otp,
  }) async {
    if (otp.trim().length < 4) {
      throw const FormatException('Enter the WhatsApp OTP code');
    }
    final normalized = PhoneNormalizer.normalizeInternational(phone);
    final supabase = _supabase;
    final user = supabase?.auth.currentUser;
    if (supabase != null && user != null) {
      var profile = await _liveReader.ensureLiveProfile(user.id, normalized);
      await _liveReader.ensureDeveloperAccountDataIfAvailable();
      profile = await _liveReader.fetchProfile(user.id) ?? profile;
      state = state.copyWith(currentProfile: profile);
      unawaited(loadInitial());
      return profile;
    }
    if (!_allowLocalWrites) {
      throw StateError('Live WhatsApp sign-in is unavailable.');
    }

    final existingIds = state.currentProfile == null
        ? <String>{}
        : {state.currentProfile!.publicId};
    final profile =
        state.currentProfile ??
        CollectProfile(
          id: _uuid.v4(),
          publicId: _publicIds.generate(existingIds),
          whatsappPhone: normalized,
          momoNumber: PhoneNormalizer.tryNormalizeMtnMomoLocal(normalized),
        );
    state = state.copyWith(currentProfile: profile);
    return profile;
  }

  Future<void> updateProfile({String? momoNumber, String? momoPayCode}) async {
    final profile = _requireProfile();
    final normalizedMomo = momoNumber == null
        ? profile.momoNumber
        : momoNumber.trim().isEmpty
        ? null
        : PhoneNormalizer.normalizeMtnMomoLocal(momoNumber);
    final normalizedMomoPayCode = momoPayCode == null
        ? profile.momoPayCode
        : momoPayCode.trim().isEmpty
        ? null
        : _normalizeMomoPayCode(momoPayCode);
    final supabase = _supabase;

    if (supabase != null && supabase.auth.currentUser != null) {
      await supabase
          .from('profiles')
          .update({
            'momo_number': normalizedMomo,
            'momo_number_hash': normalizedMomo == null
                ? null
                : HashUtils.phoneHash(normalizedMomo),
            'momo_pay_code': normalizedMomoPayCode,
          })
          .eq('id', profile.id);
      state = state.copyWith(
        currentProfile: await _liveReader.fetchProfile(profile.id),
      );
      return;
    }
    if (!_allowLocalWrites) {
      throw StateError('Sign in before updating your profile.');
    }

    state = state.copyWith(
      currentProfile: profile.copyWith(
        momoNumber: normalizedMomo,
        momoPayCode: normalizedMomoPayCode,
      ),
    );
  }

  Future<void> signOut() async {
    await _supabase?.auth.signOut();
    state = _emptyCollectState();
  }

  Future<void> requestAccountDeletion({required String reason}) async {
    final profile = _requireProfile();
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw const FormatException('Select at least one deletion reason.');
    }
    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      await supabase.rpc<void>(
        'request_account_deletion',
        params: {'request_reason': cleanReason},
      );
      return;
    }
    if (!_allowLocalWrites) {
      throw StateError(
        'Connect to Collect before submitting an account deletion request.',
      );
    }
    state = state.copyWith(currentProfile: profile);
  }

  Future<void> updateNotificationPreferences(
    NotificationPreferences preferences,
  ) async {
    final profile = _requireProfile();
    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      await supabase.from('notification_preferences').upsert({
        'user_id': profile.id,
        ...preferences.toJson(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
    state = state.copyWith(notificationPreferences: preferences);
  }

  Future<void> markNotificationRead(String eventId) async {
    final cleanEventId = eventId.trim();
    if (cleanEventId.isEmpty) return;
    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      await supabase.rpc<void>(
        'mark_notification_event_read',
        params: {'p_event_id': cleanEventId},
      );
    }
    final now = DateTime.now();
    state = state.copyWith(
      notificationEvents: [
        for (final event in state.notificationEvents)
          event.id == cleanEventId
              ? event.copyWith(status: 'read', readAt: now)
              : event,
      ],
    );
  }

  Future<void> registerNotificationDevice({
    required String platform,
    required String tokenHash,
    String? tokenLastFour,
  }) async {
    _requireProfile();
    final supabase = _supabase;
    if (supabase == null || supabase.auth.currentUser == null) return;
    await supabase.rpc<void>(
      'register_notification_device',
      params: {
        'p_platform': platform,
        'p_token_hash': tokenHash,
        'p_token_last_four': tokenLastFour,
      },
    );
  }

  Future<void> createSupportRequest({
    required String subject,
    required String message,
  }) async {
    _requireProfile();
    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      await supabase.rpc<void>(
        'create_mobile_support_request',
        params: {
          'request_subject': subject.trim(),
          'request_message': message.trim(),
        },
      );
    }
  }

  Future<void> createPaymentSupportReview({
    required String collectionId,
    required String intentId,
    required String issueType,
    required String note,
  }) {
    final collection = collectionById(collectionId);
    PaymentIntentModel? intent;
    try {
      intent = intentById(intentId);
    } catch (_) {
      intent = null;
    }
    return createSupportRequest(
      subject: 'Payment review: $issueType',
      message: [
        'Group: ${collection.title}',
        'Intent: ${intent?.id ?? intentId}',
        if (intent != null) 'Amount: ${intent.expectedAmountRwf}',
        if (intent != null) 'Status: ${intent.status}',
        'Note: ${note.trim()}',
      ].join('\n'),
    );
  }

  Future<void> requestFreshGroupLink({
    required String slug,
    required String reason,
  }) async {
    final supabase = _supabase;
    if (state.currentProfile == null &&
        (supabase == null || supabase.auth.currentUser == null)) {
      return;
    }
    return createSupportRequest(
      subject: 'Fresh group link requested',
      message: 'Slug: ${slug.trim()}\nReason: ${reason.trim()}',
    );
  }

  Future<CollectCollection> createCollection({
    required String title,
    required String description,
    required String receiverMomoNumber,
    CollectionType collectionType = CollectionType.ikimina,
    String? categorySubtype,
    String? purposeLabel,
    String receiverLabel = 'Primary MoMo receiver',
    bool receiverIsMomoPayCode = false,
    String? accentColorHex,
    String? imageUrl,
  }) async {
    final normalizedReceiver = receiverIsMomoPayCode
        ? _normalizeMomoPayCode(receiverMomoNumber)
        : PhoneNormalizer.normalizeMtnMomoLocal(receiverMomoNumber);
    final normalizedLabel = receiverLabel.trim().isEmpty
        ? receiverIsMomoPayCode
              ? 'MoMo code'
              : 'Primary MoMo receiver'
        : receiverLabel.trim();
    final supabase = _supabase;

    if (supabase != null && supabase.auth.currentUser != null) {
      final collectionId = await supabase.rpc<String>(
        'create_group_with_owner',
        params: {
          'group_name': title.trim(),
          'group_description': description.trim(),
          'receiver_momo_number': normalizedReceiver,
          'receiver_momo_number_hash': HashUtils.phoneHash(normalizedReceiver),
          'receiver_label': normalizedLabel,
          'group_collection_type': collectionType.storageValue,
          'group_category_subtype': categorySubtype?.trim(),
          'group_purpose_label': purposeLabel?.trim(),
        },
      );
      final collection = await _liveReader.fetchCollection(collectionId);
      await loadInitial();
      final hydratedCollection = collection.copyWith(
        accentColorHex: accentColorHex,
        imageUrl: imageUrl,
      );
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
      accentColorHex: accentColorHex,
      imageUrl: imageUrl,
      isPublic: false,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(collections: [...state.collections, collection]);
    return collection;
  }

  Future<CollectCollection> updateCollectionReceiver({
    required String collectionId,
    required String receiverMomoNumber,
    String receiverLabel = 'Primary MoMo receiver',
    bool receiverIsMomoPayCode = false,
  }) async {
    final collection = _requireActiveCollection(collectionId);
    _requireCollectionOwner(
      collection,
      action: 'update group receiver details',
    );
    final normalizedReceiver = receiverIsMomoPayCode
        ? _normalizeMomoPayCode(receiverMomoNumber)
        : PhoneNormalizer.normalizeMtnMomoLocal(receiverMomoNumber);
    final cleanReceiverLabel = receiverLabel.trim().isEmpty
        ? receiverIsMomoPayCode
              ? 'MoMo code'
              : 'Primary MoMo receiver'
        : receiverLabel.trim();
    final supabase = _supabase;

    if (supabase != null && supabase.auth.currentUser != null) {
      await supabase.rpc<void>(
        'update_collection_receiver',
        params: {
          'collection': collectionId,
          'receiver_momo_number': normalizedReceiver,
          'receiver_momo_number_hash': HashUtils.phoneHash(normalizedReceiver),
          'receiver_label': cleanReceiverLabel,
        },
      );
      final collection = await _liveReader.fetchCollection(collectionId);
      await loadInitial();
      return collection;
    }
    if (!_allowLocalWrites) {
      throw StateError('Sign in before updating group receiver details.');
    }

    final collections = [...state.collections];
    final index = collections.indexWhere((item) => item.id == collectionId);
    if (index == -1) throw StateError('Group not found');
    collections[index] = collections[index].copyWith(
      receiverMomoNumber: normalizedReceiver,
      receiverDisplayLabel: cleanReceiverLabel,
    );
    state = state.copyWith(collections: collections);
    return collections[index];
  }

  Future<CollectCollection> updateCollectionProfile({
    required String collectionId,
    required String title,
    required String description,
    required String receiverMomoNumber,
    required String receiverLabel,
    required String recurringCadence,
    CollectionType? collectionType,
    String? categorySubtype,
    String? purposeLabel,
    String? accentColorHex,
    String? imageUrl,
    required bool isPublic,
    bool receiverIsMomoPayCode = false,
  }) async {
    final collection = _requireActiveCollection(collectionId);
    _requireCollectionOwner(collection, action: 'update group details');
    final normalizedReceiver = receiverIsMomoPayCode
        ? _normalizeMomoPayCode(receiverMomoNumber)
        : PhoneNormalizer.normalizeMtnMomoLocal(receiverMomoNumber);
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw const FormatException('Group name is required.');
    }
    final cleanReceiverLabel = receiverLabel.trim().isEmpty
        ? receiverIsMomoPayCode
              ? 'MoMo code'
              : 'Primary MoMo receiver'
        : receiverLabel.trim();
    final cadence = recurringCadence.trim().isEmpty
        ? 'monthly'
        : recurringCadence.trim();
    final supabase = _supabase;

    if (supabase != null && supabase.auth.currentUser != null) {
      await supabase.rpc<void>(
        'update_collection_profile',
        params: {
          'collection': collectionId,
          'group_name': cleanTitle,
          'group_description': description.trim(),
          'group_image_url': imageUrl,
          'group_accent_color_hex': accentColorHex,
          'group_is_public': isPublic,
          'group_recurring_cadence': cadence,
          'group_collection_type': collectionType?.storageValue,
          'group_category_subtype': categorySubtype?.trim(),
          'group_purpose_label': purposeLabel?.trim(),
        },
      );
      await updateCollectionReceiver(
        collectionId: collectionId,
        receiverMomoNumber: normalizedReceiver,
        receiverLabel: cleanReceiverLabel,
        receiverIsMomoPayCode: receiverIsMomoPayCode,
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
      receiverMomoNumber: normalizedReceiver,
      receiverDisplayLabel: cleanReceiverLabel,
      collectionType: collectionType,
      categorySubtype: categorySubtype?.trim().isEmpty == true
          ? null
          : categorySubtype?.trim(),
      purposeLabel: purposeLabel?.trim().isEmpty == true
          ? null
          : purposeLabel?.trim(),
      imageUrl: imageUrl,
      accentColorHex: accentColorHex,
      isPublic: isPublic,
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
    final profile = _requireProfile();
    final contributorMomoNumber = profile.momoNumber?.trim();
    if (contributorMomoNumber == null || contributorMomoNumber.isEmpty) {
      throw StateError('Link your MoMo number before contributing.');
    }
    final collection = _requireActiveCollection(draft.collectionId);
    final now = DateTime.now();
    for (final intent in state.paymentIntents) {
      if (intent.collectionId == collection.id &&
          intent.expectedAmountRwf == draft.amountRwf &&
          intent.status == 'pending' &&
          now.isBefore(intent.expiresAt)) {
        return intent;
      }
    }
    final senderPhoneHash = HashUtils.phoneHash(contributorMomoNumber);
    final supabase = _supabase;

    if (supabase != null && supabase.auth.currentUser != null) {
      final response = await supabase.rpc<dynamic>(
        'create_contribution_intent',
        params: {
          'collection': draft.collectionId,
          'p_expected_amount_rwf': draft.amountRwf,
          'p_sender_phone_hash': senderPhoneHash,
        },
      );
      final row = _singleRpcRow(response);
      final intent = PaymentIntentModel.fromJson(
        Map<String, dynamic>.from(row),
      );
      state = state.copyWith(paymentIntents: [...state.paymentIntents, intent]);
      return intent;
    }
    if (!_allowLocalWrites) {
      throw StateError('Sign in before starting a contribution.');
    }

    final receiver = collection.receiverMomoNumber;
    if (receiver == null) throw StateError('Group has no MoMo receiver');
    final intent = PaymentIntentModel(
      id: _uuid.v4(),
      collectionId: collection.id,
      expectedAmountRwf: draft.amountRwf,
      receiverMomoNumber: receiver,
      receiverLabel: collection.receiverDisplayLabel,
      senderPhoneHash: senderPhoneHash,
      status: 'pending',
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(hours: 24)),
    );
    state = state.copyWith(paymentIntents: [...state.paymentIntents, intent]);
    return intent;
  }

  Future<void> ingestReceiverSms(
    String body, {
    String rawSender = 'android_sms',
    String? receiverMomoNumber,
  }) async {
    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      await supabase.functions.invoke(
        'ingest-payment-sms',
        body: {
          'raw_sender': rawSender,
          'raw_body': body,
          'receiver_momo_number': receiverMomoNumber,
        },
      );
      await loadInitial();
    }
  }

  Future<bool> setSmsAccess(bool enabled) async {
    final profile = state.currentProfile;
    final supabase = _supabase;
    final granted = await _smsAccessChannel.setEnabled(enabled);
    final consentEnabled = enabled && granted;
    if (supabase != null &&
        supabase.auth.currentUser != null &&
        profile != null) {
      await supabase.rpc<void>(
        'record_sms_access_consent',
        params: {
          'enabled': consentEnabled,
          'momo_number_hash': profile.momoNumber == null
              ? null
              : HashUtils.phoneHash(profile.momoNumber!),
          'build_channel': 'android_sms_access',
          'device_label': 'flutter_app',
        },
      );
    }
    state = state.copyWith(
      smsAccessEnabled: consentEnabled,
      smsAccessDenied: enabled && !granted,
    );
    return consentEnabled;
  }

  Future<int> syncPendingSmsAccess() async {
    final profile = state.currentProfile;
    if (profile == null) return 0;
    final enabled =
        state.smsAccessEnabled || await _smsAccessChannel.isEnabled();
    if (!enabled) return 0;
    final pending = await _smsAccessChannel.drainPendingSms();
    var ingested = 0;
    for (final item in pending) {
      if (item.rawBody.trim().isEmpty) continue;
      await ingestReceiverSms(
        item.rawBody,
        rawSender: item.rawSender,
        receiverMomoNumber: profile.momoNumber,
      );
      ingested += 1;
    }
    return ingested;
  }

  CollectCollection collectionById(String id) =>
      state.collections.firstWhere((collection) => collection.id == id);

  CollectCollection? maybeCollectionById(String id) {
    for (final collection in state.collections) {
      if (collection.id == id) return collection;
    }
    return null;
  }

  CollectCollection collectionBySlug(String slug) =>
      state.collections.firstWhere((collection) => collection.slug == slug);

  CollectCollection? maybeCollectionBySlug(String slug) {
    for (final collection in state.collections) {
      if (collection.slug == slug) return collection;
    }
    return null;
  }

  Future<CollectCollection> joinGroupBySlug(String slug) async {
    final normalizedSlug = slug.trim();
    if (normalizedSlug.isEmpty) {
      throw const FormatException('Group link is invalid');
    }
    final supabase = _supabase;

    if (supabase != null && supabase.auth.currentUser != null) {
      final response = await supabase.rpc<dynamic>(
        'join_group_by_slug',
        params: {'group_slug': normalizedSlug},
      );
      final collection = await _liveReader.fetchCollection(response as String);
      final existing = state.collections.indexWhere(
        (item) => item.id == collection.id,
      );
      final collections = [...state.collections];
      if (existing == -1) {
        collections.insert(0, collection);
      } else {
        collections[existing] = collection;
      }
      state = state.copyWith(collections: collections);
      return collection;
    }
    if (!_allowLocalWrites) {
      throw StateError('Sign in before joining a group.');
    }

    return collectionBySlug(normalizedSlug);
  }

  PaymentIntentModel intentById(String id) =>
      state.paymentIntents.firstWhere((intent) => intent.id == id);

  PaymentIntentModel? maybeIntentById(String id) {
    for (final intent in state.paymentIntents) {
      if (intent.id == id) return intent;
    }
    return null;
  }

  Future<PaymentIntentModel> refreshPaymentIntent(String id) async {
    final supabase = _supabase;
    if (supabase == null || supabase.auth.currentUser == null) {
      if (!_allowLocalWrites) {
        throw StateError('Sign in before refreshing payment status.');
      }
      return intentById(id);
    }
    final row = await supabase
        .from('payment_intents')
        .select()
        .eq('id', id)
        .single();
    final intent = PaymentIntentModel.fromJson(Map<String, dynamic>.from(row));
    final intents = [...state.paymentIntents];
    final index = intents.indexWhere((item) => item.id == id);
    if (index == -1) {
      intents.insert(0, intent);
    } else {
      intents[index] = intent;
    }
    state = state.copyWith(paymentIntents: intents);
    return intent;
  }

  Future<List<CollectMember>> membersForCollection(String collectionId) async {
    final collection = maybeCollectionById(collectionId);
    if (collection == null) return const [];
    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      final rows = await supabase.rpc<List<dynamic>>(
        'list_collection_collect_ids',
        params: {'collection': collectionId},
      );
      return [
        for (final row in rows)
          CollectMember.fromJson(Map<String, dynamic>.from(row as Map)),
      ];
    }
    final profile = state.currentProfile;
    return [
      if (profile != null)
        CollectMember(
          publicId: profile.publicId,
          role: collection.creatorUserId == profile.id ? 'owner' : 'member',
          status: 'active',
          joinedAt: collection.createdAt,
        ),
    ];
  }

  Future<void> inviteCollectionAdmin({
    required String collectionId,
    required String publicId,
  }) async {
    final collection = _requireActiveCollection(collectionId);
    final profile = _requireCollectionOwner(
      collection,
      action: 'invite an admin',
    );
    final cleanPublicId = publicId.replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^[0-9]{6}$').hasMatch(cleanPublicId)) {
      throw const FormatException('Enter a 6 digit Collect ID.');
    }
    if (cleanPublicId == profile.publicId) {
      throw const FormatException(
        'Enter another member’s Collect ID. You already own this group.',
      );
    }
    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      await supabase.rpc<dynamic>(
        'create_collection_invite',
        params: {
          'collection': collectionId,
          'target_public_id': cleanPublicId,
          'invite_role': 'admin',
        },
      );
      return;
    }
    if (!_allowLocalWrites) {
      throw StateError('Sign in before adding an admin.');
    }
    state = state.copyWith(
      collections: [
        for (final item in state.collections)
          if (item.id == collection.id) item else item,
      ],
    );
  }

  Future<void> archiveCollection(String collectionId) async {
    final collection = _requireActiveCollection(collectionId);
    _requireCollectionOwner(collection, action: 'archive this group');
    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      await supabase.rpc<void>(
        'archive_group',
        params: {'collection': collectionId},
      );
      await loadInitial();
      return;
    }
    if (!_allowLocalWrites) {
      throw StateError('Sign in before archiving a group.');
    }
    state = state.copyWith(
      collections: [
        for (final item in state.collections)
          if (item.id == collection.id)
            item.copyWith(moderationStatus: 'archived', isPublic: false)
          else
            item,
      ],
    );
  }

  Future<void> transferCollectionOwnership({
    required String collectionId,
    required String publicId,
  }) async {
    final collection = _requireActiveCollection(collectionId);
    final profile = _requireCollectionOwner(
      collection,
      action: 'transfer group ownership',
    );
    final cleanPublicId = publicId.replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^[0-9]{6}$').hasMatch(cleanPublicId)) {
      throw const FormatException('Enter a 6 digit Collect ID.');
    }
    if (cleanPublicId == profile.publicId) {
      throw const FormatException(
        'Enter another member’s Collect ID. You already own this group.',
      );
    }
    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      await supabase.rpc<void>(
        'transfer_group_ownership',
        params: {
          'collection': collectionId,
          'new_owner_public_id': cleanPublicId,
        },
      );
      await loadInitial();
      return;
    }
    if (!_allowLocalWrites) {
      throw StateError('Sign in before transferring ownership.');
    }
    state = state.copyWith(
      collections: [
        for (final item in state.collections)
          if (item.id == collection.id)
            item.copyWith(creatorUserId: 'collect-id-$cleanPublicId')
          else
            item,
      ],
    );
  }

  Future<OwnerGroupHealth> ownerHealthFor(String collectionId) async {
    final collection = collectionById(collectionId);
    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      final row = await supabase.rpc<dynamic>(
        'get_owner_group_health',
        params: {'collection': collectionId},
      );
      return OwnerGroupHealth.fromJson(Map<String, dynamic>.from(row as Map));
    }
    return OwnerGroupHealth(
      collectionId: collectionId,
      smsAccessEnabled: state.smsAccessEnabled,
      receiverConfigured: collection.receiverMomoNumber?.isNotEmpty == true,
      pendingPaymentIntents: state.paymentIntents
          .where(
            (item) =>
                item.collectionId == collectionId && item.status == 'pending',
          )
          .length,
      needsReviewEvents: 0,
      lastSyncedAt: null,
    );
  }

  void _ensureRealtimeSync() {
    final supabase = _supabase;
    if (_realtimeSync != null ||
        supabase == null ||
        supabase.auth.currentUser == null) {
      return;
    }
    _realtimeSync = RealtimeInvalidationSubscription(
      client: supabase,
      topic: 'collect:mobile:invalidation',
      areas: collectMobileRealtimeAreas,
      onInvalidate: () {
        if (mounted) unawaited(loadInitial());
      },
    )..start();
  }

  @override
  void dispose() {
    unawaited(_realtimeSync?.dispose());
    super.dispose();
  }

  CollectionSummary summaryFor(String collectionId) {
    final contributions = contributionsFor(collectionId);
    return CollectionSummary(
      amountRaisedRwf: contributions.fold(
        0,
        (sum, item) => sum + item.amountRwf,
      ),
      supporterCount: contributions.length,
    );
  }

  List<Contribution> contributionsFor(String collectionId) =>
      state.contributions
          .where((item) => item.collectionId == collectionId)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  CollectProfile _requireProfile() {
    final profile = state.currentProfile;
    if (profile == null) throw StateError('Sign in first');
    return profile;
  }

  CollectCollection _requireActiveCollection(String collectionId) {
    final collection = collectionById(collectionId);
    if (collection.isArchived) {
      throw StateError(
        'This group is archived. New contributions and group changes are off.',
      );
    }
    return collection;
  }

  CollectProfile _requireCollectionOwner(
    CollectCollection collection, {
    required String action,
  }) {
    final profile = _requireProfile();
    if (collection.creatorUserId != profile.id) {
      throw StateError('Only the group owner can $action.');
    }
    return profile;
  }
}
