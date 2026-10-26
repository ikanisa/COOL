import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/security/phone_normalizer.dart';
import '../../core/data/exact_json_values.dart';
import '../../core/security/hash_utils.dart';
import '../../core/security/play_integrity_service.dart';
import '../../core/security/public_id_generator.dart';
import '../../core/security/sms_access_channel.dart';
import '../../core/security/durable_sms_receipt.dart';
import '../../core/cloudflare/realtime_invalidation.dart';
import '../../core/cloudflare/cloudflare_module.dart';
import '../../features/privacy/privacy_providers.dart';
import '../models/collect_models.dart';
import '../models/member_history_page.dart';
import '../models/receipt_sms_consent.dart';
import 'receipt_sms_pending_store.dart';
import 'collect_offline_cache.dart';
import 'runtime_control_contract.dart';
import 'payment_help_pending_store.dart';

export '../models/member_history_page.dart';

part 'collect_repository_providers.dart';
part 'collect_repository_state.dart';
part 'collect_repository_live_reader.dart';
part 'collect_repository_helpers.dart';
part 'collect_repository_history.dart';
part 'collect_repository_contribution_actions.dart';
part 'collect_invitation_protection.dart';
part 'collect_repository_notification_actions.dart';
part 'collect_repository_receipt_sms_actions.dart';
part 'collect_repository_group_actions.dart';
part 'collect_repository_record_reads.dart';
part 'collect_repository_session_identity.dart';

class CollectRepository extends StateNotifier<CollectState>
    with
        _CollectContributionActions,
        _CollectNotificationActions,
        _CollectReceiptSmsActions,
        _CollectGroupActions,
        _CollectRecordReads {
  CollectRepository({
    CollectCloudflareClient? backend,
    ReceiptSmsPendingStore? receiptSmsPendingStore,
    PaymentHelpPendingStore? paymentHelpPendingStore,
    SmsAccessChannel smsAccessChannel = const SmsAccessChannel(),
    CollectOfflineCache? offlineCache,
    void Function()? onSignOutStarted,
  }) : this._(
         backend,
         smsAccessChannel,
         _emptyCollectState(),
         false,
         offlineCache ?? const CollectOfflineCache.protected(),
         onSignOutStarted,
         receiptSmsPendingStore ?? const NativeReceiptSmsPendingStore(),
         paymentHelpPendingStore ?? PaymentHelpPendingStore(),
       );

  /// Test harness injection only. App entrypoints use the empty live constructor.
  /// Synthetic records belong outside lib and must be supplied explicitly.
  CollectRepository.fixture({
    required CollectState initialState,
    CollectCloudflareClient? backend,
    ReceiptSmsPendingStore? receiptSmsPendingStore,
    PaymentHelpPendingStore? paymentHelpPendingStore,
    SmsAccessChannel smsAccessChannel = const SmsAccessChannel(),
    Map<String, List<CollectMember>> fixtureAdditionalMembers = const {},
    CollectOfflineCache? offlineCache,
    void Function()? onSignOutStarted,
  }) : this._(
         backend,
         smsAccessChannel,
         initialState,
         true,
         offlineCache ?? const CollectOfflineCache(),
         onSignOutStarted,
         receiptSmsPendingStore ?? const NativeReceiptSmsPendingStore(),
         paymentHelpPendingStore ?? PaymentHelpPendingStore(),
         fixtureAdditionalMembers,
       );

  CollectRepository._(
    this._backend,
    this._smsAccessChannel,
    CollectState initialState,
    this._allowLocalWrites,
    this._offlineCache,
    this._onSignOutStarted,
    this._receiptSmsPendingStore,
    this._paymentHelpPendingStore, [
    Map<String, List<CollectMember>> fixtureAdditionalMembers = const {},
  ]) : _fixtureAdditionalMembers = Map.unmodifiable({
         for (final entry in fixtureAdditionalMembers.entries)
           entry.key: List<CollectMember>.unmodifiable(entry.value),
       }),
       super(initialState) {
    _observedAuthIdentity = _sessionIdentity(_backend?.auth.currentSession);
    _paymentHelpPendingStore.bindOwner(_observedAuthIdentity?.userId);
    _authSubscription = _backend?.auth.onAuthStateChange.listen((_) {
      final identity = _sessionIdentity(_backend.auth.currentSession);
      if (!mounted || identity == _observedAuthIdentity) return;
      final sameOwner =
          identity != null && identity.userId == _observedAuthIdentity?.userId;
      if (!sameOwner) _paymentHelpPendingStore.bindOwner(identity?.userId);
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
      _resetReceiptSmsConsent();
      _signingOutIdentity = null;
      ++_loadGeneration;
      _memberAuthorityDenied = false;
      _stopRealtimeSync();
      // Clear all financial data immediately. Same-owner session renewal is
      // already a pending reread, including the native/cache awaits below.
      state = _emptyCollectState().copyWith(isLoading: sameOwner);
      unawaited(_reloadAfterAccountChange(identity, generation));
    });
  }

  @override
  final CollectCloudflareClient? _backend;
  @override
  final ReceiptSmsPendingStore _receiptSmsPendingStore;
  @override
  late final _CollectLiveReader _liveReader = _CollectLiveReader(_backend);
  @override
  final SmsAccessChannel _smsAccessChannel;
  @override
  final bool _allowLocalWrites;
  final CollectOfflineCache _offlineCache;
  final PaymentHelpPendingStore _paymentHelpPendingStore;
  final void Function()? _onSignOutStarted;
  @override
  final Map<String, List<CollectMember>> _fixtureAdditionalMembers;
  @override
  CollectRepository get _groupRepository => this;
  StreamSubscription<CollectAuthState>? _authSubscription;
  _CollectAuthIdentity? _observedAuthIdentity;
  CollectSyncInvalidationSubscription? _realtimeSync;
  String? _realtimeOwnerId;
  @override
  _CollectAuthIdentity? _signingOutIdentity;
  int _authGeneration = 0;
  int _signOutGeneration = 0;
  @override
  int _loadGeneration = 0;

  static const _sharedUuid = Uuid();
  @override
  Uuid get _uuid => _sharedUuid;
  static final _publicIds = PublicIdGenerator(random: Random(491));

  bool get isLive => _backend?.auth.currentUser != null;

  /// A credential-free sticky lifecycle revision for dependent client views.
  int get sessionGeneration => _authGeneration;

  @override
  Future<void> loadInitial({bool syncPendingSms = false}) async {
    final generation = ++_loadGeneration;
    final preferencesSession = _captureSession();
    final preferencesGeneration = _notificationPreferencesGeneration;
    final backend = _backend;
    final user = backend?.auth.currentUser;
    if (backend == null) return;
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
      if (!readStillCurrent()) return;
      if (accessReduced || profile == null || _offlineRestoreSuspended) {
        // Remove the previous protected snapshot before any later offline read
        // can revive a group that the current scoped RPC no longer returns.
        try {
          await _offlineCache.clear();
          if (!readStillCurrent()) return;
          _offlineRestoreSuspended = false;
        } catch (_) {
          if (!readStillCurrent()) return;
          _offlineRestoreSuspended = true;
        }
      }
      if (!readStillCurrent()) return;
      // Only a complete accepted current-scope read restores member authority.
      if (profile != null) _memberAuthorityDenied = false;
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
          usingStaleCache: state.hasOfflineReadableData,
          lastError: error.toString(),
        );
      }
    }
  }

  bool _offlineRestoreSuspended = false;
  bool _memberAuthorityDenied = false;

  bool _isAccessFailure(Object error) =>
      error is _CollectAccessMismatch ||
      (error is CollectApiException &&
          const {
            '42501',
            '401',
            '403',
            'authentication_required',
            'invalid_token',
            'access_revoked',
            'unauthenticated',
            'session_changed',
            'fresh_auth_required',
            'mfa_required',
            'admin_required',
            'permission_denied',
            'origin_denied',
          }.contains(error.code)) ||
      (error is CollectAuthException &&
          (const {'401', '403'}.contains(error.statusCode) ||
              const {
                'invalid_session',
                'session_required',
                'session_changed',
                'invalid_token',
                'invalid_identity',
                'access_revoked',
                'authentication_required',
                'unauthenticated',
                'refresh_replay',
              }.contains(error.code)));

  Future<void> _reloadAfterAccountChange(
    _CollectAuthIdentity? identity,
    int generation,
  ) async {
    bool current() =>
        mounted &&
        generation == _authGeneration &&
        identity == _sessionIdentity(_backend?.auth.currentSession);
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
      _backend?.auth.currentUser?.id == userId;

  Future<MemberHistoryPage> fetchHistoryPage(
    MemberHistoryQuery query, {
    Map<String, dynamic>? cursor,
  }) async {
    if (_allowLocalWrites && !isLive) return localHistoryPage(query);
    if (_memberAuthorityDenied ||
        state.currentProfile == null ||
        state.usingStaleCache ||
        !isLive) {
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
    if (_memberAuthorityDenied || _offlineRestoreSuspended) return false;
    final generation = _loadGeneration;
    final initialUserId = _backend?.auth.currentUser?.id;
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
        initialUserId != _backend?.auth.currentUser?.id) {
      return false;
    }
    if (cached == null || !cached.hasReadableData) return false;
    final expectedUserId =
        _backend?.auth.currentUser?.id ?? state.currentProfile?.id;
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
    final backend = _backend;
    final user = backend?.auth.currentUser;
    if (backend != null && user != null) {
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
    final session = _backend?.auth.currentSession;
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
      session.identity == _sessionIdentity(_backend?.auth.currentSession);

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
    final backend = _backend;
    final accessToken = session.accessToken;
    if (backend == null || accessToken == null) return;
    try {
      // Revoke only this captured server session; do not mutate a new account.
      await backend.auth.revokeCapturedSession(accessToken);
    } on CollectAuthException catch (error) {
      if (!const {'401', '403', '404'}.contains(error.statusCode)) rethrow;
    }
  }

  Future<void> signOut() async {
    // Fence privacy verification before native capture, caches or HTTP can
    // await. A completed SDK sign-out event cannot announce this earlier intent.
    _onSignOutStarted?.call();
    final session = _captureSession();
    final operation = ++_signOutGeneration;
    ++_notificationRegistrationGeneration;
    _signingOutIdentity = session.identity;
    _resetReceiptSmsConsent(notify: true);
    final registration = _registeredNotification;
    _registeredNotification = null;
    final profile = state.currentProfile;
    final owner = session.identity?.userId ?? profile?.id;
    _paymentHelpPendingStore.bindOwner(null);
    final backend = _backend;
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
      if (backend != null && session.accessToken != null) {
        if (registration != null && registration.identity == session.identity) {
          try {
            await backend
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
            await backend
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
        await _paymentHelpPendingStore.ensureCleanup();
        if (!current()) return await _revokeCapturedSession(session);
        await _offlineCache.clear();
      } catch (_) {
        if (!current()) return await _revokeCapturedSession(session);
        _offlineRestoreSuspended = true;
        throw StateError('Local account data could not be cleared. Try again.');
      }
      if (!current()) return await _revokeCapturedSession(session);
      if (backend != null && session.identity != null) {
        // Collect clears its current session synchronously before its first
        // await and revokes only this captured server session.
        // Check immediately before invoking; do no account cleanup afterward.
        final logout = backend.auth.signOut(scope: CollectSignOutScope.local);
        if (mounted && backend.auth.currentSession == null) {
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
    void requireCurrentOwner() {
      if (state.currentProfile?.id != current.id ||
          (backend != null && backend.auth.currentUser?.id != current.id)) {
        throw StateError('Profile account changed. Try again.');
      }
      if (backend != null) _requireCurrentMemberSession(session, current.id);
    }

    late final CollectProfile updated;
    if (backend != null && backend.auth.currentUser != null) {
      requireCurrentOwner();
      final row = await backend
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

  Future<void> createSupportRequest({
    required String subject,
    required String message,
  }) async {
    _requireProfile();
    final backend = _backend;
    if (backend != null && backend.auth.currentUser != null) {
      await backend.rpc<void>(
        'create_mobile_support_request',
        params: {
          'request_subject': subject.trim(),
          'request_message': message.trim(),
        },
      );
    }
  }

  Future<PaymentHelpCheckpoint?> paymentHelpForIntent(String intentId) async {
    final profile = _requireProfile();
    final session = _captureSession();
    void current() => _requireCurrentMemberSession(session, profile.id);
    current();
    final intent = intentById(intentId);
    _paymentHelpPendingStore.bindOwner(profile.id);
    final record = await _paymentHelpPendingStore.read(
      ownerId: profile.id,
      collectionId: intent.collectionId,
      intentId: intentId,
    );
    current();
    return record;
  }

  /// Save first, then send the exact first command. A replacement sign-in reads
  /// the actor-scoped status before retrying; an absent snapshot never grants a
  /// fresh key or body. The old session may still commit after that read.
  Future<PaymentHelpCheckpoint> requestPaymentHelp({
    required String intentId,
    String? providerReference,
    String? note,
  }) async {
    final profile = _requireProfile();
    final session = _captureSession();
    void current() => _requireCurrentMemberSession(session, profile.id);
    current();
    final intent = intentById(intentId);
    _paymentHelpPendingStore.bindOwner(profile.id);
    final candidate = PaymentHelpCheckpoint(
      ownerId: profile.id,
      collectionId: intent.collectionId,
      intentId: intentId,
      requestId: _sharedUuid.v5(
        Namespace.url.value,
        'collect.payment-help.v1:${profile.id}:$intentId',
      ),
      reference: providerReference?.trim().isNotEmpty == true
          ? providerReference!.trim()
          : null,
      note: note?.trim().isNotEmpty == true ? note!.trim() : null,
    );
    final existing = await _paymentHelpPendingStore.read(
      ownerId: profile.id,
      collectionId: intent.collectionId,
      intentId: intentId,
    );
    current();
    final record = await _paymentHelpPendingStore.retain(candidate);
    current();
    if (record.received) return record;
    Future<PaymentHelpCheckpoint> acknowledge() async {
      current();
      final result = await _paymentHelpPendingStore.acknowledge(record);
      current();
      return result;
    }

    if (existing != null ||
        jsonEncode(record.command) != jsonEncode(candidate.command)) {
      if (await paymentHelpRequestReceived(record)) return acknowledge();
      current();
    }
    try {
      await createPaymentSupportReview(
        collectionId: record.collectionId,
        intentId: record.intentId,
        requestId: record.requestId,
        providerReference: record.reference,
        note: record.note,
      );
    } catch (_) {
      current();
      // Includes a late old-session commit racing the new-session retry. A
      // failed/unknown status read is never interpreted as absence or receipt.
      try {
        if (await paymentHelpRequestReceived(record)) return acknowledge();
      } catch (_) {
        current();
      }
      rethrow;
    }
    return acknowledge();
  }

  Future<bool> paymentHelpRequestReceived(PaymentHelpCheckpoint record) async {
    final profile = _requireProfile();
    final session = _captureSession();
    void current() => _requireCurrentMemberSession(session, profile.id);
    current();
    final backend = _backend;
    if (backend == null ||
        profile.id != record.ownerId ||
        intentById(record.intentId).collectionId != record.collectionId) {
      throw StateError('Connect to Collect to check this request.');
    }
    final result = await backend
        .rpc<dynamic>(
          'get_current_member_payment_review_request_v1',
          params: {
            'p_request_id': record.requestId,
            'p_collection_id': record.collectionId,
            'p_intent_id': record.intentId,
          },
        )
        .setHeader('Authorization', 'Bearer ${session.accessToken}')
        .retry(enabled: false);
    current();
    if (result is! Map ||
        result['id'] != record.requestId ||
        result['collection_id'] != record.collectionId ||
        result['intent_id'] != record.intentId ||
        !const {'received', 'absent'}.contains(result['status']) ||
        exactJsonInteger(
              result['financial_effects'],
              field: 'Payment check financial effects',
              minimum: 0,
            ) !=
            0) {
      throw const FormatException('Payment check could not be verified.');
    }
    return result['status'] == 'received';
  }

  Future<String> createPaymentSupportReview({
    required String collectionId,
    required String intentId,
    required String requestId,
    String? providerReference,
    String? note,
  }) async {
    final profile = _requireProfile();
    final backend = _backend;
    if (backend == null || backend.auth.currentUser == null) {
      throw StateError('Connect to Collect to request a payment check.');
    }
    final session = _captureSession();
    void current() => _requireCurrentMemberSession(session, profile.id);
    current();
    final intent = intentById(intentId);
    if (intent.collectionId != collectionId) {
      throw const FormatException('Payment request group is invalid.');
    }
    final reference = providerReference?.trim();
    final evidence = note?.trim();
    if (!RegExp(
          r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$',
          caseSensitive: false,
        ).hasMatch(requestId) ||
        (reference?.length ?? 0) > 160 ||
        (evidence?.length ?? 0) > 2000) {
      throw const FormatException('Payment check details are invalid.');
    }
    final result = await backend
        .rpc<dynamic>(
          'create_mobile_support_request',
          params: {
            'p_kind': 'payment_review',
            'p_collection_id': collectionId,
            'p_intent_id': intentId,
            'p_request_id': requestId,
            'p_provider_reference': reference?.isEmpty == true
                ? null
                : reference,
            'p_note': evidence?.isEmpty == true ? null : evidence,
          },
        )
        .setHeader('Authorization', 'Bearer ${session.accessToken}')
        .retry(enabled: false);
    current();
    if (result is! Map ||
        result['id'] != requestId ||
        result['status'] != 'received' ||
        result['collection_id'] != collectionId ||
        result['intent_id'] != intentId ||
        exactJsonInteger(
              result['financial_effects'],
              field: 'Payment check financial effects',
              minimum: 0,
            ) !=
            0) {
      throw const FormatException('Payment check could not be verified.');
    }
    return requestId;
  }

  Future<void> requestFreshGroupLink({
    required String slug,
    required String reason,
  }) async {
    final backend = _backend;
    if (state.currentProfile == null &&
        (backend == null || backend.auth.currentUser == null)) {
      return;
    }
    return createSupportRequest(
      subject: 'Fresh group link requested',
      message: 'Slug: ${slug.trim()}\nReason: ${reason.trim()}',
    );
  }

  void _ensureRealtimeSync() {
    final backend = _backend;
    final userId = backend?.auth.currentUser?.id;
    if (backend == null || userId == null) return;
    if (_realtimeSync != null && _realtimeOwnerId == userId) return;
    _stopRealtimeSync();
    _realtimeOwnerId = userId;
    final session = _captureSession();
    _realtimeSync = CollectSyncInvalidationSubscription(
      client: backend,
      // The locked SDK matches channel messages by topic. A departed join's
      // frame must not be routed into a replacement Auth scope's callback.
      topic: 'collect:mobile:invalidation:${const Uuid().v4()}',
      areas: collectMobileRealtimeAreas,
      ownerUserId: userId,
      onAuthorityDenied: (bearer) =>
          _memberSyncAuthorityDenied(session, bearer),
      onInvalidate: () async {
        if (_isCurrentSession(session) &&
            backend.auth.currentUser?.id == userId) {
          await loadInitial();
        }
      },
    )..start();
  }

  Future<void> _memberSyncAuthorityDenied(
    _CollectSessionFence captured,
    String deniedBearer,
  ) async {
    if (!_isCurrentSession(captured) ||
        _backend?.auth.currentSession?.accessToken != deniedBearer) {
      return;
    }
    // Advance the existing session revision used by history/roster/providers,
    // not merely the load counter. This fences same-account and A→B→A replies.
    ++_authGeneration;
    ++_loadGeneration;
    _memberAuthorityDenied = true;
    _offlineRestoreSuspended = true;
    _stopRealtimeSync();
    final current = _captureSession();
    state = _emptyCollectState().copyWith(
      lastError: 'Member access could not be verified. Reconnect and refresh.',
    );
    // clear() advances its write epoch synchronously. Enqueue it only while the
    // captured bearer/scope is current; the store itself serializes older saves.
    if (!_isCurrentSession(current) ||
        _backend?.auth.currentSession?.accessToken != deniedBearer) {
      return;
    }
    final clearing = _offlineCache.clear();
    try {
      await clearing;
    } catch (_) {
      /* Keep the in-memory denial latched. */
    }
    if (!_isCurrentSession(current)) return;
    await loadInitial();
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

  @override
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
