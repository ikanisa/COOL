import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/security/phone_normalizer.dart';
import '../../core/data/exact_json_values.dart';
import '../../core/security/hash_utils.dart';
import '../../core/security/play_integrity_service.dart';
import '../../core/security/public_id_generator.dart';
import '../../core/security/sms_access_channel.dart';
import '../../core/security/durable_sms_receipt.dart';
import '../../core/supabase/realtime_invalidation.dart';
import '../../core/supabase/supabase_module.dart';
import '../models/collect_models.dart';
import '../models/member_history_page.dart';
import 'collect_offline_cache.dart';
import 'runtime_control_contract.dart';

export '../models/member_history_page.dart';

part 'collect_repository_providers.dart';
part 'collect_repository_state.dart';
part 'collect_repository_live_reader.dart';
part 'collect_repository_helpers.dart';
part 'collect_repository_history.dart';
part 'collect_repository_contribution_actions.dart';
part 'collect_invitation_protection.dart';

class CollectRepository extends StateNotifier<CollectState>
    with _CollectContributionActions {
  CollectRepository({
    SupabaseClient? supabase,
    SmsAccessChannel smsAccessChannel = const SmsAccessChannel(),
    CollectOfflineCache? offlineCache,
  }) : this._(
         supabase,
         smsAccessChannel,
         _emptyCollectState(),
         false,
         offlineCache ?? const CollectOfflineCache.protected(),
       );

  /// Test harness injection only. App entrypoints use the empty live constructor.
  /// Synthetic records belong outside lib and must be supplied explicitly.
  CollectRepository.fixture({
    required CollectState initialState,
    SupabaseClient? supabase,
    SmsAccessChannel smsAccessChannel = const SmsAccessChannel(),
    Map<String, List<CollectMember>> fixtureAdditionalMembers = const {},
    CollectOfflineCache? offlineCache,
  }) : this._(
         supabase,
         smsAccessChannel,
         initialState,
         true,
         offlineCache ?? const CollectOfflineCache(),
         fixtureAdditionalMembers,
       );

  CollectRepository._(
    this._supabase,
    this._smsAccessChannel,
    CollectState initialState,
    this._allowLocalWrites,
    this._offlineCache, [
    Map<String, List<CollectMember>> fixtureAdditionalMembers = const {},
  ]) : _fixtureAdditionalMembers = Map.unmodifiable({
         for (final entry in fixtureAdditionalMembers.entries)
           entry.key: List<CollectMember>.unmodifiable(entry.value),
       }),
       super(initialState) {
    _observedAuthIdentity = _sessionIdentity(_supabase?.auth.currentSession);
    _authSubscription = _supabase?.auth.onAuthStateChange.listen((_) {
      final identity = _sessionIdentity(_supabase.auth.currentSession);
      if (!mounted || identity == _observedAuthIdentity) return;
      _observedAuthIdentity = identity;
      final generation = ++_authGeneration;
      ++_notificationRegistrationGeneration;
      ++_notificationPreferencesGeneration;
      ++_notificationPreferencesReadGeneration;
      _notificationPreferencesRevision = null;
      _notificationPreferencesIntent = null;
      _notificationPreferencesNeedsRefresh = false;
      _notificationPreferencesSaveOperation = null;
      _registeredNotification = null;
      _signingOutIdentity = null;
      ++_loadGeneration;
      _stopRealtimeSync();
      state = _emptyCollectState();
      unawaited(_reloadAfterAccountChange(identity, generation));
    });
  }

  @override
  final SupabaseClient? _supabase;
  @override
  late final _CollectLiveReader _liveReader = _CollectLiveReader(_supabase);
  @override
  final SmsAccessChannel _smsAccessChannel;
  @override
  final bool _allowLocalWrites;
  final CollectOfflineCache _offlineCache;
  final Map<String, List<CollectMember>> _fixtureAdditionalMembers;
  StreamSubscription<AuthState>? _authSubscription;
  _CollectAuthIdentity? _observedAuthIdentity;
  RealtimeInvalidationSubscription? _realtimeSync;
  String? _realtimeOwnerId;
  _CollectNotificationRegistration? _registeredNotification;
  _CollectAuthIdentity? _signingOutIdentity;
  int _authGeneration = 0;
  int _notificationRegistrationGeneration = 0;
  int _notificationPreferencesGeneration = 0;
  int _notificationPreferencesReadGeneration = 0;
  int? _notificationPreferencesRevision;
  int? _notificationPreferencesSaveOperation;
  NotificationPreferences? _notificationPreferencesIntent;
  bool _notificationPreferencesNeedsRefresh = false;

  int? get notificationPreferencesRevision => _notificationPreferencesRevision;
  NotificationPreferences? get pendingNotificationPreferences =>
      _notificationPreferencesIntent;
  bool get notificationPreferencesNeedsRefresh =>
      !(_supabase == null && _allowLocalWrites) &&
      (_notificationPreferencesNeedsRefresh ||
          _notificationPreferencesRevision == null);

  /// Discard an unsaved choice without granting permission to retry an
  /// uncertain write. The current server revision still requires refresh.
  void discardPendingNotificationPreferences() {
    if (_notificationPreferencesSaveOperation != null) {
      throw StateError(
        'Wait for the notification preference save before discarding.',
      );
    }
    _notificationPreferencesIntent = null;
    state = state.copyWith();
  }

  int _signOutGeneration = 0;
  final Map<String, List<CollectMember>> _fixtureRosterOverrides = {};
  int _loadGeneration = 0;

  static const _sharedUuid = Uuid();
  @override
  Uuid get _uuid => _sharedUuid;
  static final _publicIds = PublicIdGenerator(random: Random(491));

  bool get isLive => _supabase?.auth.currentUser != null;

  /// A credential-free sticky lifecycle revision for dependent client views.
  int get sessionGeneration => _authGeneration;

  @override
  Future<void> loadInitial({bool syncPendingSms = false}) async {
    final generation = ++_loadGeneration;
    final preferencesSession = _captureSession();
    final preferencesGeneration = _notificationPreferencesGeneration;
    final supabase = _supabase;
    final user = supabase?.auth.currentUser;
    if (supabase == null) return;
    bool readStillCurrent() =>
        _acceptLoad(generation, user?.id) &&
        _isCurrentSession(preferencesSession);
    final nativeOwnerSynced = await _smsAccessChannel.suspendUnlessOwner(
      user?.id,
    );
    if (!nativeOwnerSynced) {
      final nativeStatus = await _smsAccessChannel.status();
      if (mounted &&
          ((SmsAccessChannel.requiresNativeBridge &&
                  !nativeStatus.bridgeAvailable) ||
              nativeStatus.consentEnabled)) {
        state = state.copyWith(smsSyncNeedsAttention: true);
      }
    }
    if (!readStillCurrent()) return;
    if (_realtimeOwnerId != null && _realtimeOwnerId != user?.id) {
      _stopRealtimeSync();
    }
    if (state.currentProfile != null && state.currentProfile!.id != user?.id) {
      state = _emptyCollectState();
    }

    if (user == null) {
      state = state.copyWith(isLoading: true, usingStaleCache: false);
      try {
        final publicCollections = await _liveReader.fetchPublicCollections();
        if (!readStillCurrent()) return;
        state = state.copyWith(
          currentProfile: null,
          collections: publicCollections,
          paymentIntents: const [],
          contributions: const [],
          collectionSummaries: const {},
          historyPage: null,
          pendingIntentCount: 0,
          isLoading: false,
          usingStaleCache: false,
          lastSuccessfulSyncAt: DateTime.now().toUtc(),
        );
      } catch (error) {
        if (!readStillCurrent()) return;
        state = state.copyWith(
          isLoading: false,
          usingStaleCache: false,
          lastError: error.toString(),
        );
      }
      return;
    }

    state = state.copyWith(isLoading: true, usingStaleCache: false);
    int? preferencesReadAttempt;
    try {
      final profile = await _liveReader.fetchProfile(
        user.id,
        accessToken: preferencesSession.accessToken,
      );
      if (!readStillCurrent()) return;
      final collections = await _liveReader.fetchCollections(
        accessToken: preferencesSession.accessToken,
      );
      if (!readStillCurrent()) return;
      final intents = await _liveReader.fetchRecentIntents(
        accessToken: preferencesSession.accessToken,
      );
      if (!readStillCurrent()) return;
      final history = await _liveReader.fetchHistoryPage(
        const MemberHistoryQuery(),
        accessToken: preferencesSession.accessToken,
      );
      if (!readStillCurrent()) return;
      final collectionSummaries = await _liveReader.fetchCollectionSummaries(
        accessToken: preferencesSession.accessToken,
      );
      if (!readStillCurrent()) return;
      final preferencesRead = ++_notificationPreferencesReadGeneration;
      preferencesReadAttempt = preferencesRead;
      final notificationPreferences = await _liveReader
          .fetchNotificationPreferences(
            profile,
            accessToken: preferencesSession.accessToken,
          );
      if (!readStillCurrent()) return;
      final notificationEvents = await _liveReader.fetchNotificationEvents(
        profile,
        accessToken: preferencesSession.accessToken,
      );
      if (!readStillCurrent()) return;
      final acceptPreferences =
          !_notificationPreferencesNeedsRefresh &&
          _acceptNotificationPreferencesRead(
            preferencesSession,
            preferencesGeneration,
            preferencesRead,
          );
      if (acceptPreferences) {
        _notificationPreferencesRevision = notificationPreferences?.revision;
      }
      final visibleCollectionIds = collections.map((item) => item.id).toSet();
      if (collectionSummaries.keys.any(
        (id) => !visibleCollectionIds.contains(id),
      )) {
        throw const _CollectAccessMismatch();
      }
      final priorCollectionIds = state.collections
          .map((item) => item.id)
          .toSet();
      final accessReduced = priorCollectionIds.any(
        (id) => !visibleCollectionIds.contains(id),
      );
      state = state.copyWith(
        currentProfile: profile,
        collections: collections,
        paymentIntents: intents.items,
        pendingIntentCount: intents.pendingCount,
        contributions: history.items,
        historyPage: history,
        collectionSummaries: collectionSummaries,
        notificationEvents: notificationEvents,
        notificationPreferences: acceptPreferences
            ? notificationPreferences?.preferences ??
                  NotificationPreferences.defaults
            : state.notificationPreferences,
        isLoading: false,
        usingStaleCache: false,
        lastSuccessfulSyncAt: DateTime.now().toUtc(),
      );
      if (accessReduced || profile == null || _offlineRestoreSuspended) {
        // Remove the previous protected snapshot before any later offline read
        // can revive a group that the current scoped RPC no longer returns.
        try {
          await _offlineCache.clear();
          _offlineRestoreSuspended = false;
        } catch (_) {
          _offlineRestoreSuspended = true;
        }
      }
      if (!readStillCurrent()) return;
      unawaited(
        _offlineCache.save(_offlineSnapshotFromState()).catchError((Object _) {
          // Optional encrypted cache failure never converts a successful server
          // read into a failed financial operation. No payload is logged.
        }),
      );
      _ensureRealtimeSync();
    } catch (error) {
      if (!readStillCurrent()) return;
      if (!_isAccessFailure(error) &&
          (preferencesGeneration != _notificationPreferencesGeneration ||
              (preferencesReadAttempt != null &&
                  preferencesReadAttempt !=
                      _notificationPreferencesReadGeneration))) {
        state = state.copyWith(isLoading: false);
        return;
      }
      _notificationPreferencesRevision = null;
      _notificationPreferencesNeedsRefresh = true;
      if (_isAccessFailure(error)) {
        _stopRealtimeSync();
        state = _emptyCollectState().copyWith(
          lastError:
              'Member access could not be verified. Reconnect and refresh.',
        );
        _offlineRestoreSuspended = true;
        try {
          await _offlineCache.clear();
        } catch (_) {
          // Retain the in-memory deny even when protected storage is locked.
        }
        return;
      }
      final restored = await restoreOfflineSnapshot(reason: error.toString());
      if (!readStillCurrent()) return;
      if (!restored) {
        state = state.copyWith(
          isLoading: false,
          usingStaleCache: false,
          lastError: error.toString(),
        );
      }
    }
  }

  bool _offlineRestoreSuspended = false;

  bool _isAccessFailure(Object error) =>
      error is _CollectAccessMismatch ||
      (error is PostgrestException &&
          const {
            '28000',
            '42501',
            'PGRST301',
            '401',
            '403',
          }.contains(error.code)) ||
      (error is AuthException &&
          const {'401', '403'}.contains(error.statusCode));

  Future<void> _reloadAfterAccountChange(
    _CollectAuthIdentity? identity,
    int generation,
  ) async {
    bool current() =>
        mounted &&
        generation == _authGeneration &&
        identity == _sessionIdentity(_supabase?.auth.currentSession);
    if (!current()) return;
    final userId = identity?.userId;
    final nativeOwnerSynced = await _smsAccessChannel.suspendUnlessOwner(
      userId,
    );
    if (!current()) return;
    if (!nativeOwnerSynced) {
      final nativeStatus = await _smsAccessChannel.status();
      if (current() &&
          ((SmsAccessChannel.requiresNativeBridge &&
                  !nativeStatus.bridgeAvailable) ||
              nativeStatus.consentEnabled)) {
        state = state.copyWith(smsSyncNeedsAttention: true);
      }
    }
    if (!current()) return;
    try {
      await _offlineCache.clear();
      if (current()) _offlineRestoreSuspended = false;
    } catch (_) {
      if (current()) _offlineRestoreSuspended = true;
    }
    if (current() && userId != null) {
      await loadInitial();
    }
  }

  bool _acceptLoad(int generation, String? userId) =>
      mounted &&
      generation == _loadGeneration &&
      _supabase?.auth.currentUser?.id == userId;

  Future<MemberHistoryPage> fetchHistoryPage(
    MemberHistoryQuery query, {
    Map<String, dynamic>? cursor,
  }) async {
    if (_allowLocalWrites && !isLive) return localHistoryPage(query);
    if (state.usingStaleCache || !isLive) {
      throw StateError('Connect to load history');
    }
    final session = _captureSession();
    final page = await _liveReader.fetchHistoryPage(
      query,
      cursor: cursor,
      accessToken: session.accessToken,
    );
    if (!_isCurrentSession(session)) {
      throw StateError('Account changed');
    }
    return page;
  }

  MemberHistoryPage localHistoryPage(MemberHistoryQuery query) {
    final titles = {for (final c in state.collections) c.id: c.title};
    final needle = query.search.toLowerCase();
    final rows = state.contributions
        .where(
          (c) =>
              (query.collectionId == null ||
                  c.collectionId == query.collectionId) &&
              (needle.isEmpty ||
                  c.supporterLabel.toLowerCase().contains(needle) ||
                  (c.transactionId ?? '').toLowerCase().contains(needle) ||
                  (titles[c.collectionId] ?? '').toLowerCase().contains(
                    needle,
                  )),
        )
        .toList();
    rows.sort((a, b) {
      if (query.sort == 'highest' || query.sort == 'lowest') {
        final currency = a.currency.compareTo(b.currency);
        if (currency != 0) return currency;
        final amount = query.sort == 'highest'
            ? b.amountMinor.compareTo(a.amountMinor)
            : a.amountMinor.compareTo(b.amountMinor);
        if (amount != 0) return amount;
      }
      final date = query.sort == 'oldest'
          ? a.createdAt.compareTo(b.createdAt)
          : b.createdAt.compareTo(a.createdAt);
      return date != 0 ? date : a.id.compareTo(b.id);
    });
    final totals = <String, int>{}, own = <String, int>{};
    final groups = <String>{};
    for (final row in rows) {
      totals.update(
        row.currency,
        (v) => v + row.amountMinor,
        ifAbsent: () => row.amountMinor,
      );
      if (row.isCurrentUserContribution ||
          (state.currentProfile != null &&
              _contributionBelongsToProfile(row, state.currentProfile!))) {
        own.update(
          row.currency,
          (v) => v + row.amountMinor,
          ifAbsent: () => row.amountMinor,
        );
        groups.add(row.collectionId);
      }
    }
    return MemberHistoryPage(
      items: rows,
      totalCount: rows.length,
      totals: totals,
      ownTotals: own,
      ownCollectionIds: groups,
      revision: '00000000000000000000000000000000',
    );
  }

  Future<bool> restoreOfflineSnapshot({required String reason}) async {
    if (_offlineRestoreSuspended) return false;
    final generation = _loadGeneration;
    final initialUserId = _supabase?.auth.currentUser?.id;
    CollectOfflineSnapshot? cached;
    try {
      cached = await _offlineCache.read(ownerUserId: initialUserId);
    } catch (_) {
      // Key unavailable or clear failed: do not expose plaintext or turn a cache
      // problem into a second unhandled failure of the live refresh operation.
      return false;
    }
    if (!mounted ||
        generation != _loadGeneration ||
        initialUserId != _supabase?.auth.currentUser?.id) {
      return false;
    }
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
      historyPage: cached.historyPage,
      pendingIntentCount: cached.pendingIntentCount,
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
      historyPage: state.historyPage,
      pendingIntentCount: state.pendingIntentCount,
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
    final normalized = PhoneNormalizer.normalizeRwanda(phone);
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
    unawaited(
      _offlineCache.save(_offlineSnapshotFromState()).catchError((Object _) {
        // Optional encrypted cache failure never converts a successful server
        // read into a failed financial operation. No payload is logged.
      }),
    );
    return profile;
  }

  @override
  _CollectSessionFence _captureSession() {
    final session = _supabase?.auth.currentSession;
    return (
      identity: _sessionIdentity(session),
      accessToken: session?.accessToken,
      generation: _authGeneration,
    );
  }

  @override
  bool _isCurrentSession(_CollectSessionFence session) =>
      mounted &&
      session.generation == _authGeneration &&
      session.identity == _sessionIdentity(_supabase?.auth.currentSession);

  @override
  void _requireCurrentMemberSession(
    _CollectSessionFence session,
    String profileId,
  ) {
    if (!_isCurrentSession(session) ||
        session.identity?.userId != profileId ||
        session.accessToken == null ||
        _signingOutIdentity == session.identity ||
        state.currentProfile?.id != profileId) {
      throw StateError('Account changed. Refresh before continuing.');
    }
  }

  Future<void> _revokeCapturedSession(_CollectSessionFence session) async {
    final supabase = _supabase;
    final accessToken = session.accessToken;
    if (supabase == null || accessToken == null) return;
    try {
      // This method only revokes the captured server session. The SDK admin
      // method defaults to GLOBAL, so an explicit LOCAL scope is essential.
      await supabase.auth.admin.signOut(accessToken, scope: SignOutScope.local);
    } on AuthException catch (error) {
      if (!const {'401', '403', '404'}.contains(error.statusCode)) rethrow;
    }
  }

  Future<void> signOut() async {
    final session = _captureSession();
    final operation = ++_signOutGeneration;
    ++_notificationRegistrationGeneration;
    _signingOutIdentity = session.identity;
    final registration = _registeredNotification;
    _registeredNotification = null;
    final profile = state.currentProfile;
    final owner = session.identity?.userId ?? profile?.id;
    final supabase = _supabase;
    bool current() =>
        operation == _signOutGeneration && _isCurrentSession(session);
    ++_loadGeneration;
    _stopRealtimeSync();
    try {
      // Native disable is bound to the original owner; never suspend whichever
      // account happens to be active after an RPC or platform await completes.
      final stopped = owner == null
          ? await _smsAccessChannel.suspendUnlessOwner(null)
          : await _smsAccessChannel.setEnabled(false, ownerUserId: owner);
      if (!current()) return await _revokeCapturedSession(session);
      if (!stopped) {
        final nativeStatus = await _smsAccessChannel.status();
        if (!current()) return await _revokeCapturedSession(session);
        if ((SmsAccessChannel.requiresNativeBridge &&
                !nativeStatus.bridgeAvailable) ||
            nativeStatus.consentEnabled) {
          throw StateError('SMS capture could not be stopped before sign-out.');
        }
      }
      if (supabase != null && session.accessToken != null) {
        if (registration != null && registration.identity == session.identity) {
          try {
            await supabase
                .rpc<void>(
                  'unregister_notification_device',
                  params: {
                    'p_provider': registration.provider,
                    'p_token': registration.token,
                  },
                )
                .setHeader('Authorization', 'Bearer ${session.accessToken}');
          } catch (_) {
            // Session-bound Auth revocation is still required below. Migration
            // 141 revokes its devices, including a registration completing late.
          }
        }
        if (!current()) return await _revokeCapturedSession(session);
        if (profile != null && profile.id == owner) {
          try {
            await supabase
                .rpc<void>(
                  'record_sms_access_consent',
                  params: {
                    'enabled': false,
                    'momo_number_hash': profile.momoNumber.trim().isEmpty
                        ? null
                        : HashUtils.phoneHash(profile.momoNumber),
                    'build_channel': 'android_sms_access',
                    'device_label': 'flutter_app',
                  },
                )
                .setHeader('Authorization', 'Bearer ${session.accessToken}');
          } catch (_) {
            // Offline audit failure does not re-enable native capture. Never
            // retry through a newly active account or mutate its UI state.
          }
        }
      }
      if (!current()) return await _revokeCapturedSession(session);
      // CollectOfflineCache serializes this clear ahead of all later saves.
      // A newer session's reload waits for those cache operations before saving.
      try {
        await _offlineCache.clear();
      } catch (_) {
        if (!current()) return await _revokeCapturedSession(session);
        _offlineRestoreSuspended = true;
        throw StateError('Local account data could not be cleared. Try again.');
      }
      if (!current()) return await _revokeCapturedSession(session);
      if (supabase != null && session.identity != null) {
        // Pinned GoTrue 2.27.1 clears its current session synchronously before
        // its first await and captures its token for the later LOCAL HTTP call.
        // Check immediately before invoking; do no account cleanup afterward.
        final logout = supabase.auth.signOut(scope: SignOutScope.local);
        if (mounted && supabase.auth.currentSession == null) {
          state = _emptyCollectState();
        }
        await logout;
      } else {
        state = _emptyCollectState();
      }
    } finally {
      if (operation == _signOutGeneration &&
          _signingOutIdentity == session.identity) {
        _signingOutIdentity = null;
      }
    }
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
    final supabase = _supabase;
    final session = _captureSession();
    void requireCurrentOwner() {
      if (state.currentProfile?.id != current.id ||
          (supabase != null && supabase.auth.currentUser?.id != current.id)) {
        throw StateError('Profile account changed. Try again.');
      }
      if (supabase != null) _requireCurrentMemberSession(session, current.id);
    }

    late final CollectProfile updated;
    if (supabase != null && supabase.auth.currentUser != null) {
      requireCurrentOwner();
      final row = await supabase
          .rpc<dynamic>(
            'update_current_member_profile',
            params: {
              'p_country_code': cleanCountry,
              'p_momo_provider': cleanMomoProvider,
              'p_momo_number': cleanMomoNumber,
              'p_momo_pay_code': cleanMomoPayCode,
            },
          )
          .setHeader('Authorization', 'Bearer ${session.accessToken}')
          .retry(enabled: false);
      if (row is! Map) {
        throw StateError('Collect profile could not be updated.');
      }
      requireCurrentOwner();
      updated = CollectProfile.fromJson(Map<String, dynamic>.from(row));
      if (updated.id != current.id ||
          updated.publicId != current.publicId ||
          updated.whatsappPhone != current.whatsappPhone) {
        throw const FormatException('Updated profile identity is invalid.');
      }
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
    if (current.momoNumber != updated.momoNumber ||
        current.momoProvider != updated.momoProvider) {
      await setSmsAccess(false, expectedOwnerUserId: current.id);
    }
    requireCurrentOwner();
    state = state.copyWith(currentProfile: updated);
    await _offlineCache.save(_offlineSnapshotFromState());
    requireCurrentOwner();
    return updated;
  }

  bool _acceptNotificationPreferencesRead(
    _CollectSessionFence session,
    int mutation,
    int read,
  ) =>
      _isCurrentSession(session) &&
      _signingOutIdentity != session.identity &&
      mutation == _notificationPreferencesGeneration &&
      read == _notificationPreferencesReadGeneration;

  /// User-requested refresh acknowledges the current server revision. Pending
  /// intended changes remain available for review; this never retries a save.
  Future<void> refreshNotificationPreferences() async {
    final profile = _requireProfile();
    final session = _captureSession();
    if (session.identity?.userId != profile.id ||
        session.accessToken == null ||
        _signingOutIdentity == session.identity) {
      throw StateError('Sign in and refresh notification preferences.');
    }
    if (_notificationPreferencesSaveOperation != null) {
      throw StateError(
        'Wait for the notification preference save before refreshing.',
      );
    }
    _notificationPreferencesRevision = null;
    _notificationPreferencesNeedsRefresh = true;
    state = state.copyWith();
    final mutation = _notificationPreferencesGeneration;
    final read = ++_notificationPreferencesReadGeneration;
    try {
      final receipt = await _liveReader.fetchNotificationPreferences(
        profile,
        accessToken: session.accessToken,
      );
      if (!_acceptNotificationPreferencesRead(session, mutation, read) ||
          receipt == null) {
        throw StateError(
          'Notification preference refresh belongs to an earlier operation.',
        );
      }
      _notificationPreferencesRevision = receipt.revision;
      _notificationPreferencesNeedsRefresh = false;
      state = state.copyWith(notificationPreferences: receipt.preferences);
    } catch (_) {
      if (!_acceptNotificationPreferencesRead(session, mutation, read)) {
        throw StateError(
          'Notification preference refresh belongs to an earlier operation.',
        );
      }
      rethrow;
    }
  }

  Future<void> updateNotificationPreferences(
    NotificationPreferences preferences,
  ) async {
    final profile = _requireProfile();
    final supabase = _supabase;
    if (supabase == null) {
      if (!_allowLocalWrites) {
        throw StateError('Connect before saving notification preferences.');
      }
      state = state.copyWith(notificationPreferences: preferences);
      return;
    }
    final session = _captureSession();
    if (session.identity?.userId != profile.id ||
        session.accessToken == null ||
        _signingOutIdentity == session.identity) {
      throw StateError('Sign in and refresh notification preferences.');
    }
    _notificationPreferencesIntent = preferences;
    final revision = _notificationPreferencesRevision;
    if (revision == null || _notificationPreferencesNeedsRefresh) {
      _notificationPreferencesNeedsRefresh = true;
      state = state.copyWith();
      throw StateError('Refresh notification preferences before saving.');
    }
    if (_notificationPreferencesSaveOperation != null) {
      state = state.copyWith();
      throw StateError('A notification preference save is still pending.');
    }
    final operation = ++_notificationPreferencesGeneration;
    ++_notificationPreferencesReadGeneration;
    _notificationPreferencesSaveOperation = operation;
    bool current() =>
        _isCurrentSession(session) &&
        _signingOutIdentity != session.identity &&
        operation == _notificationPreferencesGeneration;
    try {
      final response = await supabase
          .rpc<dynamic>(
            'set_notification_preferences_v2',
            params: {
              'p_preferences': preferences.toJson(),
              'p_expected_revision': revision,
            },
          )
          .setHeader('Authorization', 'Bearer ${session.accessToken}');
      if (!current()) {
        throw StateError(
          'Notification preference save belongs to an earlier session.',
        );
      }
      final acknowledgedRevision = notificationPreferenceSaveRevision(
        response,
        userId: profile.id,
        expectedRevision: revision,
      );
      // A reload can start during the request. Its older server snapshot must
      // never replace an acknowledged write, even when the session is unchanged.
      ++_notificationPreferencesReadGeneration;
      _notificationPreferencesRevision = acknowledgedRevision;
      if (jsonEncode(_notificationPreferencesIntent?.toJson()) ==
          jsonEncode(preferences.toJson())) {
        _notificationPreferencesIntent = null;
      }
      state = state.copyWith(notificationPreferences: preferences);
    } catch (_) {
      if (!current()) {
        throw StateError(
          'Notification preference save belongs to an earlier session.',
        );
      }
      // An uncertain/malformed/conflicting reply requires an explicit refresh;
      // neither cached defaults nor a background reload authorizes an overwrite.
      _notificationPreferencesRevision = null;
      _notificationPreferencesNeedsRefresh = true;
      state = state.copyWith();
      rethrow;
    } finally {
      if (_notificationPreferencesSaveOperation == operation) {
        _notificationPreferencesSaveOperation = null;
      }
    }
  }

  Future<void> markNotificationRead(String eventId) async {
    final cleanEventId = exactJsonIdentifier(eventId, field: 'notification.id');
    final supabase = _supabase;
    final profile = _requireProfile();
    final session = _captureSession();
    if (supabase != null && supabase.auth.currentUser != null) {
      _requireCurrentMemberSession(session, profile.id);
      await supabase
          .rpc<void>(
            'mark_notification_event_read',
            params: {'p_event_id': cleanEventId},
          )
          .setHeader('Authorization', 'Bearer ${session.accessToken}')
          .retry(enabled: false);
      _requireCurrentMemberSession(session, profile.id);
    } else if (!_allowLocalWrites) {
      throw StateError('Sign in before updating notifications.');
    }
    final now = DateTime.now();
    state = state.copyWith(
      notificationEvents: [
        for (final event in state.notificationEvents)
          event.id == cleanEventId && event.userId == profile.id
              ? event.copyWith(status: 'read', readAt: now)
              : event,
      ],
    );
  }

  /// Only an acknowledged registration for the current session is connected.
  bool isNotificationDeviceRegistered({
    required String provider,
    required String token,
  }) {
    final registration = _registeredNotification;
    return mounted &&
        registration != null &&
        registration.identity ==
            _sessionIdentity(_supabase?.auth.currentSession) &&
        registration.identity != _signingOutIdentity &&
        registration.provider == provider &&
        registration.token == token;
  }

  Future<void> registerNotificationDevice({
    required String platform,
    required String provider,
    required String token,
    required String environment,
  }) async {
    final profile = _requireProfile();
    final supabase = _supabase;
    final session = _captureSession();
    if (supabase == null ||
        session.identity == null ||
        session.accessToken == null) {
      return;
    }
    if (profile.id != session.identity!.userId ||
        _signingOutIdentity == session.identity) {
      throw StateError(
        'Notification registration requires the current signed-in session.',
      );
    }
    final operation = ++_notificationRegistrationGeneration;
    try {
      final acknowledgedDevice = await supabase
          .rpc<dynamic>(
            'register_notification_device',
            params: {
              'p_platform': platform,
              'p_provider': provider,
              'p_token': token,
              'p_environment': environment,
              'p_locale': 'en',
              'p_app_version': null,
            },
          )
          .setHeader('Authorization', 'Bearer ${session.accessToken}');
      if (acknowledgedDevice is! String ||
          !RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          ).hasMatch(acknowledgedDevice.trim().toLowerCase())) {
        throw StateError('Notifications could not connect. Try again.');
      }
    } on PostgrestException catch (error) {
      if (!_isCurrentSession(session) ||
          operation != _notificationRegistrationGeneration) {
        return;
      }
      if (error.message == 'notification_registration_session_stale') {
        const message =
            'Sign in again to register notifications on this device.';
        state = state.copyWith(lastError: message);
        throw StateError(message);
      }
      rethrow;
    }
    if (!_isCurrentSession(session) ||
        operation != _notificationRegistrationGeneration ||
        _signingOutIdentity == session.identity) {
      if (_sessionIdentity(supabase.auth.currentSession) != session.identity) {
        try {
          // An already-sent registration cannot be cancelled. Cleanup remains
          // bound to the old server session; migration 141 cannot disable a
          // row already reassigned to the newer session.
          await supabase
              .rpc<void>(
                'unregister_notification_device',
                params: {'p_provider': provider, 'p_token': token},
              )
              .setHeader('Authorization', 'Bearer ${session.accessToken}');
        } catch (_) {
          // Server ordering/session revocation is authoritative when offline.
        }
      }
      return;
    }
    _registeredNotification = (
      identity: session.identity!,
      provider: provider,
      token: token,
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
    _requireReadyProfile();
    final supabase = _supabase;

    final ownerId = supabase?.auth.currentUser?.id;
    if (supabase != null && ownerId != null) {
      final session = _captureSession();
      final generation = _loadGeneration;
      void requireOriginalSession() {
        _requireCurrentMemberSession(session, ownerId);
        if (!mounted ||
            generation != _loadGeneration ||
            supabase.auth.currentUser?.id != ownerId ||
            state.currentProfile?.id != ownerId) {
          throw StateError('Account changed during group join.');
        }
      }

      requireOriginalSession();
      final response = await supabase
          .rpc<dynamic>(
            'join_group_by_share_code',
            params: {'p_group_code': normalizedSlug},
          )
          .setHeader('Authorization', 'Bearer ${session.accessToken}')
          .retry(enabled: false);
      requireOriginalSession();
      final id = exactJsonIdentifier(response, field: 'joined_group.id');
      final collection = await _liveReader.fetchCollection(
        id,
        accessToken: session.accessToken,
      );
      requireOriginalSession();
      if (!collection.isCurrentUserMember &&
          collection.creatorUserId != ownerId) {
        throw const FormatException('Joined group membership is invalid.');
      }
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
    final authority = captureGroupInvitationAuthority(collectionId);
    final session = _captureSession();
    try {
      final supabase = _supabase;
      if (supabase != null) {
        final code = await supabase
            .rpc<dynamic>(
              'get_group_share_code',
              params: {'p_collection_id': collectionId},
            )
            .setHeader('Authorization', 'Bearer ${session.accessToken}');
        authority.check();
        if (code is! String || !_invitationUuid.hasMatch(code)) {
          throw const FormatException(
            'The invitation could not be verified. Refresh before sharing.',
          );
        }
        // A deliberate server refresh resolves the display before a new
        // rotation can replace an uncertain prior operation.
        _pendingInvitationRequests(this).removeWhere(
          (key, _) =>
              key.startsWith('${session.identity!.userId}:$collectionId:'),
        );
        return code;
      }
      return _requireActiveCollection(collectionId).slug;
    } finally {
      authority.dispose();
    }
  }

  Future<String> rotateGroupShareCode(String collectionId) async {
    final authority = captureGroupInvitationAuthority(
      collectionId,
      requireOwner: true,
    );
    final session = _captureSession();
    try {
      final supabase = _supabase;
      if (supabase != null) {
        final pending = _pendingInvitationRequests(this);
        final key =
            '${session.identity!.userId}:$collectionId:${session.identity!.sessionId}:${session.generation}';
        final requestId = pending.putIfAbsent(key, _uuid.v4);
        final result = await supabase
            .rpc<dynamic>(
              'rotate_group_share_code_v2',
              params: {
                'p_collection_id': collectionId,
                'p_request_id': requestId,
              },
            )
            .retry(enabled: false)
            .setHeader('Authorization', 'Bearer ${session.accessToken}');
        authority.check();
        const fields = {
          'contract_version',
          'ok',
          'collection_id',
          'request_id',
          'share_code',
        };
        if (result is! Map ||
            result.length != fields.length ||
            !result.keys.toSet().containsAll(fields) ||
            result['contract_version'] is! int ||
            result['contract_version'] != 1 ||
            result['ok'] != true ||
            result['collection_id'] != collectionId ||
            result['request_id'] != requestId ||
            result['share_code'] is! String ||
            !_invitationUuid.hasMatch(result['share_code'] as String)) {
          throw const FormatException(
            'The invitation replacement was not acknowledged. Refresh the invitation before replacing it again.',
          );
        }
        if (pending[key] == requestId) pending.remove(key);
        return result['share_code'] as String;
      }
      return _uuid.v4();
    } finally {
      authority.dispose();
    }
  }

  PaymentIntentModel intentById(String id) =>
      state.paymentIntents.singleWhere((intent) => intent.id == id);

  PaymentIntentModel? maybeIntentById(String id) {
    final matches = state.paymentIntents
        .where((intent) => intent.id == id)
        .toList();
    return matches.length == 1 ? matches.single : null;
  }

  @override
  Future<PaymentIntentModel> refreshPaymentIntent(String id) async {
    final supabase = _supabase;
    if (supabase == null || supabase.auth.currentUser == null) {
      if (!_allowLocalWrites) {
        throw StateError('Sign in before refreshing transfer status.');
      }
      return intentById(id);
    }
    final session = _captureSession();
    final prior = maybeIntentById(id);
    final result = await _liveReader.fetchRecentIntents(
      intentId: id,
      accessToken: session.accessToken,
    );
    if (!_isCurrentSession(session)) {
      throw StateError('Account changed');
    }
    final matches = result.items.where((item) => item.id == id).toList();
    if (matches.length != 1) {
      throw StateError('Payment intent is unavailable');
    }
    final intent = matches.single;
    if (prior != null &&
        (intent.collectionId != prior.collectionId ||
            intent.expectedAmountMinor != prior.expectedAmountMinor ||
            intent.rail != prior.rail ||
            intent.currency != prior.currency)) {
      throw const FormatException(
        'Intent identity does not match the existing request',
      );
    }
    state = state.copyWith(
      paymentIntents: [
        intent,
        ...state.paymentIntents.where((old) => old.id != id).take(49),
      ],
      pendingIntentCount: result.pendingCount,
    );
    return intent;
  }

  Future<List<CollectMember>> membersForCollection(String collectionId) async {
    final collection = maybeCollectionById(collectionId);
    if (collection == null) return const [];
    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      final session = _captureSession();
      final publicId = state.currentProfile?.publicId;
      final rows = await supabase
          .rpc<dynamic>(
            'list_current_member_group_roster',
            params: {'p_collection_id': collectionId},
          )
          .setHeader('Authorization', 'Bearer ${session.accessToken}');
      if (!_isCurrentSession(session) ||
          state.currentProfile?.publicId != publicId ||
          maybeCollectionById(collectionId) == null) {
        throw StateError('Account or group access changed');
      }
      if (rows is! List || rows.any((row) => row is! Map)) {
        throw const FormatException('Member roster is unavailable');
      }
      final ids = <String>{};
      final members = <CollectMember>[];
      for (final row in rows) {
        final member = CollectMember.fromJson(
          Map<String, dynamic>.from(row as Map),
        );
        if (!ids.add(member.publicId) ||
            (member.amountScope == 'own' && member.publicId != publicId)) {
          throw const FormatException('Invalid member roster');
        }
        members.add(member);
      }
      return List<CollectMember>.unmodifiable(members);
    }
    if (!_allowLocalWrites || supabase != null) {
      throw StateError('Sign in to view members.');
    }
    final fixtureRoster = _fixtureRosterOverrides[collectionId];
    if (fixtureRoster != null) return List.unmodifiable(fixtureRoster);
    final profile = state.currentProfile;
    final summary = summaryFor(collectionId);
    return [
      if (profile != null &&
          (collection.creatorUserId == profile.id ||
              collection.isCurrentUserMember))
        CollectMember(
          publicId: profile.publicId,
          role: collection.creatorUserId == profile.id ? 'owner' : 'member',
          status: 'active',
          joinedAt: collection.createdAt,
          amountScope: 'own',
          contributionTotals: {
            for (final entry
                in summary?.ownBalancesByCurrency.entries ??
                    const <MapEntry<String, int>>[])
              if (entry.value > 0) entry.key: entry.value,
          },
        ),
      ...?_fixtureAdditionalMembers[collectionId],
    ];
  }

  // Kept as a Dart compatibility name; this promotes an active member directly,
  // not an invitation or platform Admin enrollment.
  Future<void> inviteCollectionAdmin({
    required String collectionId,
    required String publicId,
  }) async {
    final collection = _requireActiveCollection(collectionId);
    final profile = _requireCollectionOwner(
      collection,
      action: 'add a group admin',
    );
    if (collection.isPlatformSponsored || collection.isPublic) {
      throw StateError('Manage this group in Admin.');
    }
    final cleanPublicId = publicId.trim();
    if (!RegExp(r'^[0-9]{6}$').hasMatch(cleanPublicId)) {
      throw const FormatException('Enter a 6 digit Collect ID.');
    }
    if (cleanPublicId == profile.publicId) {
      throw const FormatException(
        'Enter another member’s Collect ID. You already own this group.',
      );
    }
    final supabase = _supabase;
    if (supabase != null) {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null || userId != profile.id) {
        throw StateError('Sign in before adding a group admin.');
      }
      final session = _captureSession();
      _requireCurrentMemberSession(session, userId);
      dynamic result;
      try {
        result = await supabase
            .rpc<dynamic>(
              'add_group_admin',
              params: {
                'collection': collectionId,
                'member_public_id': cleanPublicId,
              },
            )
            .setHeader('Authorization', 'Bearer ${session.accessToken}')
            .retry(enabled: false);
      } on PostgrestException catch (error) {
        if (error.code == '22023') {
          throw const FormatException('Choose another active group member.');
        }
        if (error.code == '42501') {
          throw StateError('Only the current owner can add a group admin.');
        }
        rethrow;
      }
      _requireCurrentMemberSession(session, userId);
      if (result is! Map ||
          result.length != 4 ||
          result['collection_id'] != collectionId ||
          result['public_id'] != cleanPublicId ||
          result['role'] != 'admin' ||
          result['status'] != 'active') {
        throw const FormatException(
          'Group admin update could not be verified.',
        );
      }
    } else {
      if (!_allowLocalWrites) {
        throw StateError('Sign in before adding a group admin.');
      }
      final roster = await membersForCollection(collectionId);
      if (!roster.any(
        (member) =>
            member.publicId == cleanPublicId && member.status == 'active',
      )) {
        throw const FormatException('Choose another active group member.');
      }
      _fixtureRosterOverrides[collectionId] = [
        for (final member in roster)
          if (member.publicId == cleanPublicId)
            CollectMember(
              publicId: member.publicId,
              role: 'admin',
              status: member.status,
              joinedAt: member.joinedAt,
              amountScope: member.amountScope,
              contributionTotals: member.contributionTotals,
            )
          else
            member,
      ];
    }
    // Invalidate the account-scoped roster provider. A live roster is fetched
    // from the server, never optimistically forged from the entered ID.
    state = state.copyWith(collections: [...state.collections]);
  }

  Future<void> archiveCollection(String collectionId) async {
    final collection = _requireActiveCollection(collectionId);
    final profile = _requireCollectionOwner(
      collection,
      action: 'archive this group',
    );
    if (collection.isPlatformSponsored || collection.isPublic) {
      throw StateError('Manage this group in Admin.');
    }
    final supabase = _supabase;
    if (supabase != null && supabase.auth.currentUser != null) {
      final session = _captureSession();
      _requireCurrentMemberSession(session, profile.id);
      await supabase
          .rpc<void>('archive_group', params: {'collection': collectionId})
          .setHeader('Authorization', 'Bearer ${session.accessToken}')
          .retry(enabled: false);
      _requireCurrentMemberSession(session, profile.id);
      await loadInitial();
      _requireCurrentMemberSession(session, profile.id);
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
    if (collection.isPlatformSponsored || collection.isPublic) {
      throw StateError('Manage this group in Admin.');
    }
    final cleanPublicId = publicId.trim();
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
      final session = _captureSession();
      _requireCurrentMemberSession(session, profile.id);
      await supabase
          .rpc<void>(
            'transfer_group_ownership',
            params: {
              'collection': collectionId,
              'new_owner_public_id': cleanPublicId,
            },
          )
          .setHeader('Authorization', 'Bearer ${session.accessToken}')
          .retry(enabled: false);
      _requireCurrentMemberSession(session, profile.id);
      await loadInitial();
      _requireCurrentMemberSession(session, profile.id);
      return;
    }
    if (!_allowLocalWrites) {
      throw StateError('Sign in before transferring ownership.');
    }
    final previousRoster = await membersForCollection(collectionId);
    _fixtureRosterOverrides[collectionId] = [
      for (final member in previousRoster)
        if (member.publicId != cleanPublicId)
          CollectMember(
            publicId: member.publicId,
            role: member.publicId == profile.publicId ? 'admin' : member.role,
            status: member.status,
            joinedAt: member.joinedAt,
            amountScope: member.amountScope,
            contributionTotals: member.contributionTotals,
          ),
      CollectMember(
        publicId: cleanPublicId,
        role: 'owner',
        status: 'active',
        joinedAt: DateTime.now().toUtc(),
      ),
    ];
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
      final session = _captureSession();
      final row = await supabase
          .rpc<dynamic>(
            'get_owner_group_health',
            params: {'collection': collectionId},
          )
          .setHeader('Authorization', 'Bearer ${session.accessToken}');
      if (!_isCurrentSession(session) ||
          maybeCollectionById(collectionId) == null) {
        throw StateError('Account or group access changed');
      }
      if (row is! Map || row.keys.any((key) => key is! String)) {
        throw const FormatException('Group health is unavailable');
      }
      final health = OwnerGroupHealth.fromJson(Map<String, dynamic>.from(row));
      if (health.collectionId != collectionId) {
        throw const FormatException('Group health does not match the request');
      }
      return health;
    }
    if (!_allowLocalWrites) {
      throw StateError('Connect to load group health');
    }
    return OwnerGroupHealth(
      collectionId: collectionId,
      smsAccessEnabled: state.smsAccessEnabled,
      receiverConfigured: collectionById(collectionId).supportsRwandaMomo,
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
    final userId = supabase?.auth.currentUser?.id;
    if (supabase == null || userId == null) return;
    if (_realtimeSync != null && _realtimeOwnerId == userId) return;
    _stopRealtimeSync();
    _realtimeOwnerId = userId;
    final session = _captureSession();
    _realtimeSync = RealtimeInvalidationSubscription(
      client: supabase,
      // The locked SDK matches channel messages by topic. A departed join's
      // frame must not be routed into a replacement Auth scope's callback.
      topic: 'collect:mobile:invalidation:${const Uuid().v4()}',
      areas: collectMobileRealtimeAreas,
      ownerUserId: userId,
      onInvalidate: () async {
        if (_isCurrentSession(session) &&
            supabase.auth.currentUser?.id == userId) {
          await loadInitial();
        }
      },
    )..start();
  }

  void _stopRealtimeSync() {
    final subscription = _realtimeSync;
    _realtimeSync = null;
    _realtimeOwnerId = null;
    if (subscription != null) unawaited(subscription.dispose());
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    _stopRealtimeSync();
    super.dispose();
  }

  /// A recent history page cannot establish a complete group or own balance.
  CollectionSummary? summaryFor(String collectionId) =>
      state.collectionSummaries[collectionId];

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

  @override
  CollectProfile _requireReadyProfile() {
    final profile = _requireProfile();
    if (!profile.isComplete) {
      throw const FormatException('Complete your Rwanda MoMo profile first.');
    }
    return profile;
  }

  @override
  CollectCollection _requireActiveCollection(String collectionId) {
    final collection = collectionById(collectionId);
    if (collection.isArchived) {
      throw StateError(
        'This group is archived. New contributions and group changes are off.',
      );
    }
    return collection;
  }

  @override
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

// JWT claims here distinguish local lifecycle operations only; server Auth/RLS
// remains authoritative. Access-token fallback keeps malformed/legacy sessions
// isolated; such tokens do not bypass the server's required session_id check.
typedef _CollectAuthIdentity = ({String userId, String sessionId});
typedef _CollectSessionFence = ({
  _CollectAuthIdentity? identity,
  String? accessToken,
  int generation,
});
typedef _CollectNotificationRegistration = ({
  _CollectAuthIdentity identity,
  String provider,
  String token,
});

_CollectAuthIdentity? _sessionIdentity(Session? session) {
  if (session == null) return null;
  var identity = session.accessToken;
  try {
    final parts = session.accessToken.split('.');
    if (parts.length == 3) {
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (claims is Map &&
          claims['session_id'] is String &&
          (claims['session_id'] as String).isNotEmpty) {
        identity = claims['session_id'] as String;
      }
    }
  } catch (_) {
    // Do not expose token contents in exceptions or diagnostics.
  }
  return (userId: session.user.id, sessionId: identity);
}
