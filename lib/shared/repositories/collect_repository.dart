import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/security/phone_normalizer.dart';
import '../../core/security/hash_utils.dart';
import '../../core/security/play_integrity_service.dart';
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
    CollectProfile? profileOverride,
    CollectOfflineCache? offlineCache,
  }) : this._(
         supabase,
         smsAccessChannel,
         seeded
             ? _fixtureCollectState(
                 fixtureNow: fixtureNow,
                 collectionCount: fixtureCollectionCount,
                 contributionCount: fixtureContributionCount,
                 profileOverride: profileOverride,
               )
             : _emptyCollectState(),
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
  String? _registeredNotificationProvider;
  String? _registeredNotificationToken;
  Future<int>? _smsSyncInFlight;
  bool _smsSyncRequested = false;

  static const _uuid = Uuid();
  static final _publicIds = PublicIdGenerator(random: Random(491));

  bool get isLive => _supabase?.auth.currentUser != null;

  Future<void> loadInitial({bool syncPendingSms = false}) async {
    final supabase = _supabase;
    final user = supabase?.auth.currentUser;
    if (supabase == null) return;

    if (user == null) {
      state = state.copyWith(isLoading: true, usingStaleCache: false);
      try {
        final publicCollections = await _liveReader.fetchPublicCollections();
        state = state.copyWith(
          currentProfile: null,
          collections: publicCollections,
          paymentIntents: const [],
          contributions: const [],
          collectionSummaries: const {},
          isLoading: false,
          usingStaleCache: false,
          lastSuccessfulSyncAt: DateTime.now().toUtc(),
        );
      } catch (error) {
        state = state.copyWith(
          isLoading: false,
          usingStaleCache: false,
          lastError: error.toString(),
        );
      }
      return;
    }

    state = state.copyWith(isLoading: true, usingStaleCache: false);
    try {
      final profile = await _liveReader.fetchProfile(user.id);
      final collections = await _liveReader.fetchCollections();
      final paymentIntents = await _liveReader.fetchPaymentIntents(profile);
      final contributions = await _liveReader.fetchContributions(profile);
      final collectionSummaries = await _liveReader.fetchCollectionSummaries(
        profile,
      );
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
        collectionSummaries: collectionSummaries,
        notificationEvents: notificationEvents,
        notificationPreferences: notificationPreferences,
        isLoading: false,
        usingStaleCache: false,
        lastSuccessfulSyncAt: DateTime.now().toUtc(),
      );
      unawaited(_offlineCache.save(_offlineSnapshotFromState()));
      _ensureRealtimeSync();
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
    final expectedUserId =
        _supabase?.auth.currentUser?.id ?? state.currentProfile?.id;
    if (expectedUserId != null && cached.currentProfile?.id != expectedUserId) {
      await _offlineCache.clear();
      return false;
    }
    state = state.copyWith(
      currentProfile: cached.currentProfile,
      collections: cached.collections,
      paymentIntents: cached.paymentIntents,
      contributions: cached.contributions,
      collectionSummaries: cached.collectionSummaries,
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
      collectionSummaries: state.collectionSummaries,
    );
  }

  Future<CollectProfile> signInWithOtp({
    required String phone,
    required String otp,
    String? countryCode,
  }) async {
    if (otp.trim().length < 4) {
      throw const FormatException('Enter the WhatsApp OTP code');
    }
    final normalized = PhoneNormalizer.normalizeInternational(phone);
    final requestedCountry = CollectProfileCountryRules.normalizeCountryCode(
      countryCode,
    );
    final initialCountry =
        CollectProfileCountryRules.isSupportedCountry(requestedCountry)
        ? requestedCountry
        : CollectProfileCountryRules.inferCountryCodeFromPhone(normalized);
    final supabase = _supabase;
    final user = supabase?.auth.currentUser;
    if (supabase != null && user != null) {
      final profile = await _liveReader.ensureLiveProfile(
        user.id,
        normalized,
        countryCode: initialCountry,
      );
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
    unawaited(_offlineCache.save(_offlineSnapshotFromState()));
    return profile;
  }

  Future<void> signOut() async {
    final supabase = _supabase;
    final provider = _registeredNotificationProvider;
    final token = _registeredNotificationToken;
    if (supabase != null &&
        supabase.auth.currentUser != null &&
        provider != null &&
        token != null) {
      try {
        await supabase.rpc<void>(
          'unregister_notification_device',
          params: {'p_provider': provider, 'p_token': token},
        );
      } catch (_) {
        // Server-side token reassignment prevents cross-account delivery if a
        // best-effort sign-out cleanup cannot reach the backend.
      }
    }
    final profile = state.currentProfile;
    if (profile != null) {
      try {
        await setSmsAccess(false);
      } catch (_) {
        // Privacy takes precedence over the server audit record when sign-out
        // happens while the backend is unavailable.
        await _smsAccessChannel.setEnabled(false, ownerUserId: profile.id);
      }
    }
    await _offlineCache.clear();
    await _supabase?.auth.signOut();
    _registeredNotificationProvider = null;
    _registeredNotificationToken = null;
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

  Future<CollectProfile> updateCurrentProfile({
    required String displayName,
    required String countryCode,
    String? momoProvider,
    String? momoNumber,
    String? revolutName,
    String? revolutLink,
    String? revolutAccount,
  }) async {
    final current = _requireProfile();
    final cleanDisplayName = displayName.trim();
    if (cleanDisplayName.length < 2 || cleanDisplayName.length > 80) {
      throw const FormatException('Enter a name between 2 and 80 characters.');
    }
    final cleanCountry = CollectProfileCountryRules.normalizeCountryCode(
      countryCode,
    );
    if (!CollectProfileCountryRules.isSupportedCountry(cleanCountry)) {
      throw const FormatException('Choose a supported profile country.');
    }
    final isRwanda = cleanCountry == 'RW';
    final cleanMomoProvider = (momoProvider ?? '').trim().toLowerCase();
    final cleanMomoNumber = isRwanda
        ? _normalizeLocalRwandaMomo(momoNumber ?? '')
        : '';
    final cleanRevolutName = revolutName?.trim() ?? '';
    final cleanRevolutLink = revolutLink?.trim() ?? '';
    final cleanRevolutAccount = revolutAccount?.trim() ?? '';
    if (isRwanda &&
        !const {'mtn_momo', 'airtel_money'}.contains(cleanMomoProvider)) {
      throw const FormatException('Choose MTN MoMo or Airtel Money.');
    }
    if (isRwanda &&
        !(cleanMomoProvider == 'mtn_momo'
            ? RegExp(r'^07[89][0-9]{7}$').hasMatch(cleanMomoNumber)
            : RegExp(r'^07[23][0-9]{7}$').hasMatch(cleanMomoNumber))) {
      throw const FormatException(
        'The MoMo provider does not match that Rwanda mobile number.',
      );
    }
    if (!isRwanda &&
        (cleanRevolutName.length < 2 ||
            cleanRevolutName.length > 100 ||
            Uri.tryParse(cleanRevolutLink)?.host.endsWith('revolut.me') !=
                true ||
            cleanRevolutAccount.length < 4 ||
            cleanRevolutAccount.length > 120)) {
      throw const FormatException(
        'Diaspora profiles need a Revolut name, Revolut.me link, and account details.',
      );
    }

    final supabase = _supabase;
    late final CollectProfile updated;
    if (supabase != null && supabase.auth.currentUser != null) {
      final row = await supabase.rpc<dynamic>(
        'update_current_profile',
        params: {
          'p_display_name': cleanDisplayName,
          'p_country_code': cleanCountry,
          'p_momo_provider': isRwanda ? cleanMomoProvider : null,
          'p_momo_number': isRwanda ? cleanMomoNumber : null,
          'p_revolut_name': isRwanda ? null : cleanRevolutName,
          'p_revolut_link': isRwanda ? null : cleanRevolutLink,
          'p_revolut_account': isRwanda ? null : cleanRevolutAccount,
        },
      );
      if (row is! Map) {
        throw StateError('Collect profile could not be updated.');
      }
      updated = CollectProfile.fromJson(Map<String, dynamic>.from(row));
    } else {
      if (!_allowLocalWrites) {
        throw StateError('Connect to Collect before updating your profile.');
      }
      updated = current.copyWith(
        displayName: cleanDisplayName,
        countryCode: cleanCountry,
        currencyCode: CollectProfileCountryRules.currencyForCountry(
          cleanCountry,
        ),
        momoProvider: isRwanda ? cleanMomoProvider : '',
        momoNumber: isRwanda ? cleanMomoNumber : '',
        revolutName: isRwanda ? '' : cleanRevolutName,
        revolutLink: isRwanda ? '' : cleanRevolutLink,
        revolutAccount: isRwanda ? '' : cleanRevolutAccount,
      );
    }

    if (current.isRwanda &&
        (!updated.isRwanda ||
            current.momoNumber != updated.momoNumber ||
            current.momoProvider != updated.momoProvider)) {
      await setSmsAccess(false);
    }
    state = state.copyWith(currentProfile: updated);
    await _offlineCache.save(_offlineSnapshotFromState());
    return updated;
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
    required String provider,
    required String token,
    required String environment,
  }) async {
    _requireProfile();
    final supabase = _supabase;
    if (supabase == null || supabase.auth.currentUser == null) return;
    await supabase.rpc<dynamic>(
      'register_notification_device',
      params: {
        'p_platform': platform,
        'p_provider': provider,
        'p_token': token,
        'p_environment': environment,
        'p_locale': 'en',
        'p_app_version': null,
      },
    );
    _registeredNotificationProvider = provider;
    _registeredNotificationToken = token;
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
      subject: 'Contribution review: $issueType',
      message: [
        'Group: ${collection.title}',
        'Transfer request: ${intent?.id ?? intentId}',
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
    CollectionType collectionType = CollectionType.ikimina,
    String? categorySubtype,
    String? purposeLabel,
    String? accentColorHex,
    String? imageUrl,
    String? receiverMomoNumber,
    String receiverProvider = 'mtn_momo',
    bool isPublic = false,
  }) async {
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
        'create_private_group_with_owner_attested',
        params: {
          ...groupRequest..remove('group_is_public'),
          'native_capability': verdict!.nativeCapability,
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
      accentColorHex: accentColorHex,
      isPublic: false,
      isRecurring: isRecurring,
      visibilityStatus: 'private',
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
    final now = DateTime.now();
    for (final intent in state.paymentIntents) {
      if (intent.collectionId == collection.id &&
          intent.expectedAmountRwf == draft.amountRwf &&
          intent.rail == contributionRail &&
          intent.isAwaitingTransfer &&
          now.isBefore(intent.expiresAt.toLocal())) {
        return intent;
      }
    }
    final supabase = _supabase;

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
      state = state.copyWith(
        paymentIntents: [intent, ...state.paymentIntents],
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
      await supabase.functions.invoke(
        'ingest-payment-sms',
        body: {
          'client_envelope_id': clientEnvelopeId ?? _uuid.v4(),
          'raw_sender': rawSender,
          'raw_body': body,
          'receiver_momo_number': profile!.momoNumber,
          'received_at_device': receivedAtDevice,
        },
      );
      if (refreshAfterIngest) await loadInitial();
    }
  }

  Future<BankTransferDestination> getBankTransferDestination() async {
    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      final response = await supabase.rpc<dynamic>(
        'get_bank_transfer_destination',
      );
      return BankTransferDestination.fromJson(
        Map<String, dynamic>.from(response as Map),
      );
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
        'join_group_by_share_code',
        params: {'p_group_code': normalizedSlug},
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

  Future<String> getGroupShareCode(String collectionId) async {
    final collection = _requireActiveCollection(collectionId);
    final profile = _requireProfile();
    if (!collection.isCurrentUserMember &&
        collection.creatorUserId != profile.id) {
      throw StateError('Join this group before sharing it.');
    }
    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      return supabase.rpc<String>(
        'get_group_share_code',
        params: {'p_collection_id': collectionId},
      );
    }
    if (!_allowLocalWrites) {
      throw StateError('Sign in before sharing a group.');
    }
    return collection.slug;
  }

  Future<String> rotateGroupShareCode(String collectionId) async {
    final collection = _requireActiveCollection(collectionId);
    _requireCollectionOwner(collection, action: 'rotate the group share link');
    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      return supabase.rpc<String>(
        'rotate_group_share_code',
        params: {'p_collection_id': collectionId},
      );
    }
    if (!_allowLocalWrites) {
      throw StateError('Sign in before rotating a group link.');
    }
    return _uuid.v4();
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
        throw StateError('Sign in before refreshing transfer status.');
      }
      return intentById(id);
    }
    final row = await supabase.rpc<dynamic>(
      'get_bank_transfer_intent',
      params: {'p_id': id},
    );
    final intent = PaymentIntentModel.fromJson(
      Map<String, dynamic>.from(row as Map),
    );
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
    collectionById(collectionId);
    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      final row = await supabase.rpc<dynamic>(
        'get_owner_group_health',
        params: {'collection': collectionId},
      );
      return OwnerGroupHealth.fromJson(Map<String, dynamic>.from(row as Map));
    }
    final destination = await getBankTransferDestination();
    return OwnerGroupHealth(
      collectionId: collectionId,
      smsAccessEnabled: state.smsAccessEnabled,
      receiverConfigured:
          destination.enabled &&
          !destination.isPlaceholder &&
          destination.iban.trim().isNotEmpty,
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
    final authoritative = state.collectionSummaries[collectionId];
    if (authoritative != null) return authoritative;
    final contributions = contributionsFor(collectionId);
    return CollectionSummary(
      amountRaisedRwf: contributions.fold(
        0,
        (sum, item) => sum + item.amountRwf,
      ),
      supporterCount: contributions.length,
      currentUserBalanceRwf: contributions
          .where((item) => item.isCurrentUserContribution)
          .fold(0, (sum, item) => sum + item.amountRwf),
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
