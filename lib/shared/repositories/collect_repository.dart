import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/security/hash_utils.dart';
import '../../core/security/phone_normalizer.dart';
import '../../core/security/public_id_generator.dart';
import '../../core/security/receiver_mode_channel.dart';
import '../../core/supabase/supabase_module.dart';
import '../models/collect_models.dart';

final collectRepositoryProvider =
    StateNotifierProvider<CollectRepository, CollectState>((ref) {
      final repository = CollectRepository.seeded(
        supabase: ref.watch(supabaseClientProvider),
      );
      unawaited(repository.loadInitial());
      return repository;
    });

final collectionSummariesProvider = Provider<Map<String, CollectionSummary>>((
  ref,
) {
  final contributions = ref.watch(
    collectRepositoryProvider.select((state) => state.contributions),
  );
  final totals = <String, ({int amountRaisedRwf, int supporterCount})>{};
  for (final contribution in contributions) {
    final current =
        totals[contribution.collectionId] ??
        (amountRaisedRwf: 0, supporterCount: 0);
    totals[contribution.collectionId] = (
      amountRaisedRwf: current.amountRaisedRwf + contribution.amountRwf,
      supporterCount: current.supporterCount + 1,
    );
  }
  return {
    for (final entry in totals.entries)
      entry.key: CollectionSummary(
        amountRaisedRwf: entry.value.amountRaisedRwf,
        supporterCount: entry.value.supporterCount,
      ),
  };
});

final homeCollectionsProvider = Provider<List<CollectCollection>>((ref) {
  return ref.watch(
    collectRepositoryProvider.select(
      (state) =>
          List<CollectCollection>.unmodifiable(state.collections.take(3)),
    ),
  );
});

final pendingPaymentCountProvider = Provider<int>((ref) {
  return ref.watch(
    collectRepositoryProvider.select(
      (state) =>
          state.paymentIntents.where((item) => item.status == 'pending').length,
    ),
  );
});

final raisedTotalProvider = Provider<int>((ref) {
  return ref.watch(
    collectRepositoryProvider.select(
      (state) =>
          state.contributions.fold<int>(0, (sum, item) => sum + item.amountRwf),
    ),
  );
});

final contributionsForCollectionProvider =
    Provider.family<List<Contribution>, String>((ref, collectionId) {
      final contributions = ref.watch(
        collectRepositoryProvider.select(
          (state) => [
            for (final item in state.contributions)
              if (item.collectionId == collectionId) item,
          ]..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        ),
      );
      return List<Contribution>.unmodifiable(contributions);
    });

class CollectState {
  const CollectState({
    required this.currentProfile,
    required this.collections,
    required this.paymentIntents,
    required this.contributions,
    this.receiverModeEnabled = false,
    this.isLoading = false,
    this.lastError,
  });

  final CollectProfile? currentProfile;
  final List<CollectCollection> collections;
  final List<PaymentIntentModel> paymentIntents;
  final List<Contribution> contributions;
  final bool receiverModeEnabled;
  final bool isLoading;
  final String? lastError;

  CollectState copyWith({
    CollectProfile? currentProfile,
    List<CollectCollection>? collections,
    List<PaymentIntentModel>? paymentIntents,
    List<Contribution>? contributions,
    bool? receiverModeEnabled,
    bool? isLoading,
    String? lastError,
  }) {
    return CollectState(
      currentProfile: currentProfile ?? this.currentProfile,
      collections: collections ?? this.collections,
      paymentIntents: paymentIntents ?? this.paymentIntents,
      contributions: contributions ?? this.contributions,
      receiverModeEnabled: receiverModeEnabled ?? this.receiverModeEnabled,
      isLoading: isLoading ?? this.isLoading,
      lastError: lastError,
    );
  }
}

class CollectRepository extends StateNotifier<CollectState> {
  CollectRepository({
    SupabaseClient? supabase,
    ReceiverModeChannel receiverModeChannel = const ReceiverModeChannel(),
  }) : this._(supabase, receiverModeChannel, _emptyState());

  CollectRepository.seeded({
    SupabaseClient? supabase,
    ReceiverModeChannel receiverModeChannel = const ReceiverModeChannel(),
  }) : this._(supabase, receiverModeChannel, _seededState());

  CollectRepository._(
    this._supabase,
    this._receiverModeChannel,
    CollectState initialState,
  ) : super(initialState);

  final SupabaseClient? _supabase;
  final ReceiverModeChannel _receiverModeChannel;

  static const _uuid = Uuid();
  static final _publicIds = PublicIdGenerator(random: Random(491));

  bool get isLive => _supabase?.auth.currentUser != null;

  static CollectState _emptyState() {
    return const CollectState(
      currentProfile: null,
      collections: [],
      paymentIntents: [],
      contributions: [],
    );
  }

  static CollectState _seededState() {
    final now = DateTime.now();
    const user = CollectProfile(
      id: 'local-user',
      publicId: '038491',
      whatsappPhone: '+250788123456',
      displayName: 'Collect organizer',
      momoNumber: '+250788123456',
      anonymityDefault: 'public_id',
    );
    final church = CollectCollection(
      id: 'col-church',
      slug: 'st-michel-building-fund',
      creatorUserId: user.id,
      title: 'St Michel building fund',
      description:
          'Transparent support for materials, labor, and weekly updates from the building committee.',
      category: 'Church',
      targetAmountRwf: 2500000,
      publicStatus: 'public_approved',
      visibility: 'public_approved',
      receiverMomoNumber: '+250788123456',
      receiverDisplayLabel: 'St Michel treasury',
      createdAt: now.subtract(const Duration(days: 3)),
    );
    final team = CollectCollection(
      id: 'col-team',
      slug: 'kigali-lions-away-kit',
      creatorUserId: user.id,
      title: 'Kigali Lions away kit',
      description:
          'Fans are helping the team buy away jerseys and travel supplies for next month.',
      category: 'Sports team',
      targetAmountRwf: 900000,
      publicStatus: 'private',
      visibility: 'private',
      receiverMomoNumber: '+250788123456',
      createdAt: now.subtract(const Duration(days: 1)),
    );
    return CollectState(
      currentProfile: user,
      collections: [church, team],
      paymentIntents: const [],
      contributions: [
        Contribution(
          id: 'pay-1',
          collectionId: church.id,
          amountRwf: 25000,
          supporterLabel: 'Anonymous supporter',
          anonymityChoice: 'anonymous',
          createdAt: now.subtract(const Duration(hours: 5)),
          transactionId: 'MTN12345',
        ),
        Contribution(
          id: 'pay-2',
          collectionId: church.id,
          amountRwf: 10000,
          supporterLabel: 'User #126006',
          anonymityChoice: 'public_id',
          createdAt: now.subtract(const Duration(hours: 2)),
          transactionId: 'MTN12346',
        ),
      ],
    );
  }

  Future<void> loadInitial() async {
    final supabase = _supabase;
    final user = supabase?.auth.currentUser;
    if (supabase == null || user == null) return;

    state = state.copyWith(isLoading: true);
    try {
      final profile = await _fetchProfile(user.id);
      final collections = await _fetchCollections();
      final paymentIntents = await _fetchPaymentIntents();
      final contributions = await _fetchContributions();
      state = state.copyWith(
        currentProfile: profile,
        collections: collections,
        paymentIntents: paymentIntents,
        contributions: contributions,
        isLoading: false,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, lastError: error.toString());
    }
  }

  Future<CollectProfile> signInWithOtp({
    required String phone,
    required String otp,
  }) async {
    if (otp.trim().length < 4) {
      throw const FormatException('Enter the WhatsApp OTP code');
    }
    final normalized = PhoneNormalizer.normalizeRwanda(phone);
    final supabase = _supabase;
    final user = supabase?.auth.currentUser;
    if (supabase != null && user != null) {
      final profile =
          await _fetchProfile(user.id) ??
          CollectProfile(
            id: user.id,
            publicId: _publicIds.generate({}),
            whatsappPhone: normalized,
          );
      state = state.copyWith(currentProfile: profile);
      unawaited(loadInitial());
      return profile;
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
        );
    state = state.copyWith(currentProfile: profile);
    return profile;
  }

  Future<void> updateProfile({
    required String displayName,
    required String momoNumber,
    required String anonymityDefault,
    String? avatarUrl,
  }) async {
    final profile = _requireProfile();
    final normalizedMomo = momoNumber.trim().isEmpty
        ? null
        : PhoneNormalizer.normalizeRwanda(momoNumber);
    final supabase = _supabase;

    if (supabase != null && supabase.auth.currentUser != null) {
      await supabase
          .from('profiles')
          .update({
            'display_name': displayName.trim(),
            'momo_number': normalizedMomo,
            'momo_number_hash': normalizedMomo == null
                ? null
                : HashUtils.phoneHash(normalizedMomo),
            'anonymity_default': anonymityDefault,
            'avatar_url': avatarUrl?.trim().isEmpty == true
                ? null
                : avatarUrl?.trim(),
          })
          .eq('id', profile.id);
      state = state.copyWith(currentProfile: await _fetchProfile(profile.id));
      return;
    }

    state = state.copyWith(
      currentProfile: profile.copyWith(
        displayName: displayName.trim(),
        momoNumber: normalizedMomo,
        anonymityDefault: anonymityDefault,
        avatarUrl: avatarUrl?.trim().isEmpty == true ? null : avatarUrl?.trim(),
      ),
    );
  }

  Future<CollectCollection> createCollection({
    required String title,
    required String description,
    required String category,
    int? targetAmountRwf,
    required String receiverMomoNumber,
    bool isRecurring = false,
    String? coverImageUrl,
  }) async {
    final profile = _requireProfile();
    final normalizedReceiver = PhoneNormalizer.normalizeRwanda(
      receiverMomoNumber,
    );
    final supabase = _supabase;

    if (supabase != null && supabase.auth.currentUser != null) {
      final collectionId = await supabase.rpc<String>(
        'create_collection_with_owner',
        params: {
          'title': title.trim(),
          'description': description.trim(),
          'category': category,
          'target_amount_rwf': targetAmountRwf,
          'receiver_momo_number': normalizedReceiver,
          'receiver_momo_number_hash': HashUtils.phoneHash(normalizedReceiver),
          'receiver_label': 'Primary MOMO receiver',
          'cover_image_url': coverImageUrl?.trim(),
          'is_recurring': isRecurring,
          'recurring_rule': isRecurring
              ? {
                  'frequency': 'monthly',
                  'start_date': DateTime.now().toIso8601String(),
                }
              : null,
        },
      );
      final collection = await _fetchCollection(collectionId);
      await loadInitial();
      return collection;
    }

    final slug = _slug(title);
    final collection = CollectCollection(
      id: _uuid.v4(),
      slug: '$slug-${DateTime.now().millisecondsSinceEpoch}',
      creatorUserId: profile.id,
      title: title.trim(),
      description: description.trim(),
      category: category,
      targetAmountRwf: targetAmountRwf,
      coverImageUrl: coverImageUrl?.trim().isEmpty == true
          ? null
          : coverImageUrl?.trim(),
      isRecurring: isRecurring,
      recurringRule: isRecurring
          ? {'frequency': 'monthly', 'reminders': 'configured_later'}
          : null,
      receiverMomoNumber: normalizedReceiver,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(collections: [...state.collections, collection]);
    return collection;
  }

  Future<void> requestPublic(String collectionId) async {
    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      await supabase.functions.invoke(
        'request-public-collection',
        body: {'collection_id': collectionId},
      );
      await loadInitial();
      return;
    }

    final collection = collectionById(collectionId);
    _replaceCollection(
      collection.copyWith(
        visibility: 'public_requested',
        publicStatus: 'public_requested',
      ),
    );
  }

  Future<PaymentIntentModel> createPaymentIntent(
    PaymentIntentDraft draft,
  ) async {
    if (draft.amountRwf <= 0) {
      throw const FormatException('Contribution amount must be above zero');
    }
    final collection = collectionById(draft.collectionId);
    final supabase = _supabase;

    if (supabase != null && supabase.auth.currentUser != null) {
      final response = await supabase.rpc<dynamic>(
        'create_payment_intent_with_instructions',
        params: {
          'collection': draft.collectionId,
          'p_expected_amount_rwf': draft.amountRwf,
          'p_sender_phone_hash':
              draft.senderPhone?.trim().isEmpty == true ||
                  draft.senderPhone == null
              ? null
              : HashUtils.phoneHash(draft.senderPhone!),
          'p_anonymity_choice': draft.anonymityChoice,
        },
      );
      final row = _singleRpcRow(response);
      final intent = PaymentIntentModel.fromJson(
        Map<String, dynamic>.from(row),
      );
      state = state.copyWith(paymentIntents: [...state.paymentIntents, intent]);
      return intent;
    }

    final receiver = collection.receiverMomoNumber;
    if (receiver == null) throw StateError('Collection has no MOMO receiver');
    final code = _shortCode();
    final intent = PaymentIntentModel(
      id: _uuid.v4(),
      collectionId: collection.id,
      contributionCode: code,
      expectedAmountRwf: draft.amountRwf,
      receiverMomoNumber: receiver,
      receiverLabel: collection.receiverDisplayLabel,
      instructionBody:
          'Use your mobile-money USSD menu, send ${draft.amountRwf} RWF to $receiver, and include $code as the reference when supported.',
      status: 'pending',
      anonymityChoice: draft.anonymityChoice,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(hours: 24)),
    );
    state = state.copyWith(paymentIntents: [...state.paymentIntents, intent]);
    return intent;
  }

  Future<CollectionInvite> createInvite({
    required String collectionId,
    required String target,
    String role = 'member',
  }) async {
    final trimmed = target.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Enter a phone number or Collect user ID');
    }
    final isPublicId = RegExp(r'^[0-9]{6}$').hasMatch(trimmed);
    final phoneHash = isPublicId
        ? null
        : HashUtils.phoneHash(PhoneNormalizer.normalizeRwanda(trimmed));
    final supabase = _supabase;

    if (supabase != null && supabase.auth.currentUser != null) {
      final response = await supabase.rpc<dynamic>(
        'create_collection_invite',
        params: {
          'collection': collectionId,
          'target_phone_hash': phoneHash,
          'target_public_id': isPublicId ? trimmed : null,
          'invite_role': role,
        },
      );
      return CollectionInvite.fromJson(
        Map<String, dynamic>.from(_singleRpcRow(response)),
        collectionId: collectionId,
        invitedTarget: isPublicId ? 'User #$trimmed' : trimmed,
      );
    }

    return CollectionInvite(
      id: _uuid.v4(),
      collectionId: collectionId,
      inviteToken: _uuid.v4().replaceAll('-', ''),
      role: role,
      expiresAt: DateTime.now().add(const Duration(days: 14)),
      invitedTarget: isPublicId ? 'User #$trimmed' : trimmed,
    );
  }

  Future<Contribution?> markIntentPaid(
    String intentId, {
    String? transactionId,
  }) async {
    final intent = state.paymentIntents.firstWhere(
      (item) => item.id == intentId,
    );
    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      await supabase.rpc<void>(
        'report_payment_intent_paid',
        params: {'intent': intentId, 'transaction_id': transactionId?.trim()},
      );
      state = state.copyWith(
        paymentIntents: [
          for (final item in state.paymentIntents)
            item.id == intentId
                ? PaymentIntentModel(
                    id: item.id,
                    collectionId: item.collectionId,
                    contributionCode: item.contributionCode,
                    expectedAmountRwf: item.expectedAmountRwf,
                    receiverMomoNumber: item.receiverMomoNumber,
                    receiverLabel: item.receiverLabel,
                    network: item.network,
                    instructionTitle: item.instructionTitle,
                    instructionBody: item.instructionBody,
                    status: item.status,
                    anonymityChoice: item.anonymityChoice,
                    reportedTransactionId: transactionId,
                    createdAt: item.createdAt,
                    expiresAt: item.expiresAt,
                  )
                : item,
        ],
      );
      return null;
    }

    final profile = state.currentProfile;
    final label = switch (intent.anonymityChoice) {
      'display_name' when profile?.displayName?.trim().isNotEmpty == true =>
        profile!.displayName!,
      'public_id' when profile != null => 'User #${profile.publicId}',
      _ => 'Anonymous supporter',
    };
    final contribution = Contribution(
      id: _uuid.v4(),
      collectionId: intent.collectionId,
      amountRwf: intent.expectedAmountRwf,
      supporterLabel: label,
      anonymityChoice: intent.anonymityChoice,
      createdAt: DateTime.now(),
      transactionId: transactionId?.trim().isEmpty == true
          ? null
          : transactionId?.trim(),
    );
    state = state.copyWith(
      paymentIntents: [
        for (final item in state.paymentIntents)
          if (item.id == intentId)
            PaymentIntentModel(
              id: item.id,
              collectionId: item.collectionId,
              contributionCode: item.contributionCode,
              expectedAmountRwf: item.expectedAmountRwf,
              receiverMomoNumber: item.receiverMomoNumber,
              receiverLabel: item.receiverLabel,
              network: item.network,
              instructionTitle: item.instructionTitle,
              instructionBody: item.instructionBody,
              status: 'matched',
              anonymityChoice: item.anonymityChoice,
              reportedTransactionId: transactionId,
              createdAt: item.createdAt,
              expiresAt: item.expiresAt,
            )
          else
            item,
      ],
      contributions: [...state.contributions, contribution],
    );
    return contribution;
  }

  Future<ParsedPaymentEvent> ingestManualSms(
    String body, {
    String rawSender = 'manual_paste',
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

    final amountMatch = RegExp(
      r'([0-9][0-9, ]*)\s*RWF',
      caseSensitive: false,
    ).firstMatch(body);
    final txnMatch = RegExp(
      r'(?:TxId|transaction|ID)[:\s#-]*([A-Z0-9-]{4,})',
      caseSensitive: false,
    ).firstMatch(body);
    final amount = amountMatch == null
        ? 0
        : int.tryParse(
                amountMatch.group(1)!.replaceAll(RegExp(r'[^0-9]'), ''),
              ) ??
              0;
    final event = ParsedPaymentEvent(
      id: _uuid.v4(),
      amountRwf: amount,
      transactionId: txnMatch?.group(1),
      senderLabel: 'Manual SMS paste',
      allocationStatus: amount > 0 ? 'needs_review' : 'ignored',
      confidence: amount > 0 ? .74 : .2,
      createdAt: DateTime.now(),
    );
    return event;
  }

  Future<void> setReceiverMode(bool enabled) async {
    final profile = state.currentProfile;
    final supabase = _supabase;
    if (supabase != null &&
        supabase.auth.currentUser != null &&
        profile != null) {
      await supabase.rpc<void>(
        'record_receiver_mode_consent',
        params: {
          'enabled': enabled,
          'momo_number_hash': profile.momoNumber == null
              ? null
              : HashUtils.phoneHash(profile.momoNumber!),
          'build_channel': 'internal_receiver',
          'device_label': 'flutter_app',
        },
      );
    }
    await _receiverModeChannel.setEnabled(enabled);
    state = state.copyWith(receiverModeEnabled: enabled);
  }

  Future<int> syncPendingReceiverSms() async {
    final profile = _requireProfile();
    final pending = await _receiverModeChannel.drainPendingSms();
    var ingested = 0;
    for (final item in pending) {
      if (item.rawBody.trim().isEmpty) continue;
      await ingestManualSms(
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

  PaymentIntentModel intentById(String id) =>
      state.paymentIntents.firstWhere((intent) => intent.id == id);

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

  List<CollectCollection> get publicCollections =>
      state.collections.where((item) => item.isPublicApproved).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  CollectProfile _requireProfile() {
    final profile = state.currentProfile;
    if (profile == null) throw StateError('Sign in first');
    return profile;
  }

  void _replaceCollection(CollectCollection updated) {
    state = state.copyWith(
      collections: [
        for (final collection in state.collections)
          collection.id == updated.id ? updated : collection,
      ],
    );
  }

  Future<CollectProfile?> _fetchProfile(String userId) async {
    final supabase = _supabase;
    if (supabase == null) return null;
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null || currentUser.id != userId) return null;
    final row = await supabase.rpc<dynamic>('get_current_profile');
    if (row == null) return null;
    return CollectProfile.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<List<CollectCollection>> _fetchCollections() async {
    final rows = await _supabase!
        .from('member_collections_view')
        .select()
        .order('created_at', ascending: false);
    final mappedRows = [
      for (final row in rows) Map<String, dynamic>.from(row as Map),
    ];
    final collections = [
      for (final row in mappedRows) CollectCollection.fromJson(row),
    ];
    return _attachAuthorizedReceivers(collections);
  }

  Future<CollectCollection> _fetchCollection(String id) async {
    final row = await _supabase!
        .from('member_collections_view')
        .select()
        .eq('id', id)
        .single();
    final collections = await _attachAuthorizedReceivers([
      CollectCollection.fromJson(Map<String, dynamic>.from(row)),
    ]);
    return collections.single;
  }

  Future<List<CollectCollection>> _attachAuthorizedReceivers(
    List<CollectCollection> collections,
  ) async {
    if (collections.isEmpty) return collections;
    final collectionIds = [for (final collection in collections) collection.id];
    final rows = await _supabase!
        .from('collection_receivers')
        .select('collection_id, momo_number, label')
        .inFilter('collection_id', collectionIds)
        .eq('is_active', true);
    final receiversByCollection = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final mapped = Map<String, dynamic>.from(row as Map);
      receiversByCollection.putIfAbsent(
        mapped['collection_id'] as String,
        () => mapped,
      );
    }
    return [
      for (final collection in collections)
        if (receiversByCollection[collection.id] case final receiver?)
          collection.copyWith(
            receiverMomoNumber: receiver['momo_number'] as String?,
            receiverDisplayLabel: receiver['label'] as String?,
          )
        else
          collection,
    ];
  }

  Future<List<PaymentIntentModel>> _fetchPaymentIntents() async {
    final rows = await _supabase!
        .from('payment_intents')
        .select()
        .order('created_at', ascending: false)
        .limit(100);
    return [
      for (final row in rows)
        PaymentIntentModel.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  Future<List<Contribution>> _fetchContributions() async {
    final supabase = _supabase!;
    final safeRows = await supabase
        .from('public_contributions_view')
        .select()
        .order('posted_at', ascending: false)
        .limit(200);
    final memberRows = await supabase
        .from('member_contributions_view')
        .select()
        .order('created_at', ascending: false)
        .limit(200);

    final byId = <String, Contribution>{};
    for (final row in safeRows) {
      final contribution = Contribution.fromJson(
        Map<String, dynamic>.from(row as Map),
      );
      byId[contribution.id] = contribution;
    }
    for (final row in memberRows) {
      final contribution = Contribution.fromJson(
        Map<String, dynamic>.from(row as Map),
      );
      byId[contribution.id] = contribution;
    }
    final contributions = byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return contributions;
  }

  static String _slug(String title) {
    final slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return slug.isEmpty ? 'collection' : slug;
  }

  static String _shortCode() {
    final source = _uuid.v4().replaceAll('-', '').toUpperCase();
    return source.substring(0, 6);
  }

  static Map<String, dynamic> _singleRpcRow(dynamic response) {
    if (response is List && response.isNotEmpty) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }
    throw StateError('Expected one RPC result row');
  }
}
