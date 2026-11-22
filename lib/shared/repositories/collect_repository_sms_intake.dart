part of 'collect_repository.dart';

abstract interface class MemberSmsIntake {
  Future<SmsAccessStatus> refreshSmsAccessStatus();
  Future<bool> setSmsAccess(bool enabled, {String? expectedOwnerUserId});
  Future<int> syncPendingSmsAccess();
  Future<int> retryRejectedSmsAccess({String? expectedOwnerUserId});
}

typedef MemberSmsIntakeSession = ({
  MemberSmsIntake intake,
  String? ownerId,
  int generation,
});

final memberSmsIntakeSessionProvider = Provider<MemberSmsIntakeSession>((ref) {
  final repository = ref.watch(collectRepositoryProvider.notifier);
  return ref.watch(
    collectRepositoryProvider.select(
      (state) => (
        intake: repository,
        ownerId: state.currentProfile?.id,
        generation: repository.sessionGeneration,
      ),
    ),
  );
});

class _MemberSmsDrain {
  _MemberSmsDrain(this.session);
  final _CollectSessionFence session;
  bool scanAgain = false;
  late final Future<int> result;
}

/// Native capture, consent and exact durable receipt acknowledgement for signed-in members.
mixin _CollectMemberSmsIntake on StateNotifier<CollectState>
    implements MemberSmsIntake {
  CollectCloudflareClient? get _backend;
  SmsAccessChannel get _smsAccessChannel;
  Uuid get _uuid;
  _CollectAuthIdentity? get _signingOutIdentity;
  _CollectSessionFence _captureSession();
  bool _isCurrentSession(_CollectSessionFence session);
  void _requireCurrentMemberSession(
    _CollectSessionFence session,
    String profileId,
  );
  Future<void> loadInitial();

  final _consentWrites = <String, Future<void>>{};
  final _smsDrains = <String, _MemberSmsDrain>{};
  int _smsAccessRevision = 0;
  int _smsStatusRead = 0;

  bool _currentSmsContext(_CollectSessionFence session, String? owner) =>
      _isCurrentSession(session) &&
      state.currentProfile?.id == owner &&
      (_backend == null || session.identity?.userId == owner) &&
      (session.identity == null || _signingOutIdentity != session.identity);

  Future<SmsAccessStatus> _receiptStatus(
    _CollectSessionFence session,
    String owner,
  ) async {
    _requireCurrentMemberSession(session, owner);
    var pending = _consentWrites[owner];
    while (pending != null) {
      await pending;
      _requireCurrentMemberSession(session, owner);
      pending = _consentWrites[owner];
    }
    final revision = _smsAccessRevision;
    final status = await _smsAccessChannel.status(ownerUserId: owner);
    _requireCurrentMemberSession(session, owner);
    if (revision != _smsAccessRevision) {
      throw StateError('SMS access changed. The message remains queued.');
    }
    return status;
  }

  Future<void> ingestBankNotificationSms(
    String body, {
    String? clientEnvelopeId,
    String rawSender = 'android_sms',
    String? receivedAtDevice,
    bool refreshAfterIngest = true,
  }) async {
    final owner = state.currentProfile?.id;
    if (owner == null) throw StateError('Sign in before sending a receipt.');
    final session = _captureSession();
    await _acceptSmsReceipt(
      body,
      session: session,
      expectedOwner: owner,
      clientEnvelopeId: clientEnvelopeId ?? _uuid.v4(),
      rawSender: rawSender,
      receivedAtDevice: receivedAtDevice,
    );
    _requireCurrentMemberSession(session, owner);
    if (refreshAfterIngest) await loadInitial();
  }

  Future<DurableSmsReceipt> _acceptSmsReceipt(
    String body, {
    required _CollectSessionFence session,
    required String expectedOwner,
    required String clientEnvelopeId,
    required String rawSender,
    required String? receivedAtDevice,
    String completeness = 'complete',
  }) async {
    final client = _backend;
    if (client == null) throw StateError('Connect before sending a receipt.');
    _requireCurrentMemberSession(session, expectedOwner);
    if (body.trim().isEmpty) throw const FormatException('Receipt is empty.');
    void checkOwner() => _requireCurrentMemberSession(session, expectedOwner);
    final status = await _receiptStatus(session, expectedOwner);
    checkOwner();
    if (!status.enabled || !status.granted) {
      throw StateError('SMS access is off. The message remains queued.');
    }
    final response = await client.functions.invoke(
      'ingest-client-sms',
      headers: {'Authorization': 'Bearer ${session.accessToken}'},
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

  @override
  Future<bool> setSmsAccess(bool enabled, {String? expectedOwnerUserId}) async {
    final owner = state.currentProfile?.id;
    final session = _captureSession();
    final backend = _backend;
    if (owner == null ||
        !_currentSmsContext(session, owner) ||
        (expectedOwnerUserId != null && expectedOwnerUserId != owner)) {
      throw StateError('SMS access account changed. Try again.');
    }
    if (enabled && (backend == null || session.identity == null)) {
      throw StateError('Sign in before allowing SMS access.');
    }

    final revision = ++_smsAccessRevision;
    final previous = _consentWrites[owner];
    final finished = Completer<void>();
    _consentWrites[owner] = finished.future;
    bool latest() => identical(_consentWrites[owner], finished.future);
    bool current() => latest() && _currentSmsContext(session, owner);
    void requireCurrent() {
      if (!current()) {
        throw StateError('SMS access account changed. Try again.');
      }
    }

    var granted = false;
    var confirmedStopped = false;
    try {
      // Android has one permission prompt. A later opt-in waits its turn;
      // a withdrawal reaches the device immediately and can cancel that prompt.
      if (enabled && previous != null) {
        await previous;
        requireCurrent();
      }
      granted = await _smsAccessChannel.setEnabled(enabled, ownerUserId: owner);
      if (!enabled &&
          mounted &&
          backend != null &&
          backend.auth.currentUser?.id != owner) {
        // Preserve the session transition's native suspension without addressing another owner's queue.
        await _smsAccessChannel.suspendUnlessOwner(
          backend.auth.currentUser?.id,
        );
      }
      requireCurrent();
      if (!enabled && !granted) {
        final nativeStatus = await _smsAccessChannel.status(ownerUserId: owner);
        requireCurrent();
        if ((SmsAccessChannel.requiresNativeBridge &&
                !nativeStatus.bridgeAvailable) ||
            nativeStatus.consentEnabled) {
          throw StateError('SMS capture could not be stopped on this device.');
        }
      }
      confirmedStopped = !enabled;
      // Stop local capture immediately. Write successive consent decisions for the same member in request order.
      if (!enabled && previous != null) await previous;
      requireCurrent();
      final consentEnabled = enabled && granted;
      if (backend != null && session.accessToken != null) {
        await backend
            .rpc<void>(
              'record_sms_access_consent',
              params: {
                'enabled': consentEnabled,
                'build_channel': 'android_sms_access',
                'device_label': 'flutter_app',
              },
            )
            .setHeader('Authorization', 'Bearer ${session.accessToken}')
            .retry(enabled: false);
        requireCurrent();
      }
      state = state.copyWith(
        smsAccessEnabled: consentEnabled,
        smsAccessDenied: enabled && !granted,
      );
      if (consentEnabled) {
        unawaited(
          Future<void>(() async {
            if (!_currentSmsContext(session, owner) ||
                _smsAccessRevision != revision ||
                !state.smsAccessEnabled) {
              return;
            }
            try {
              await syncPendingSmsAccess();
            } catch (_) {
              // The drain retains originals and reports attention for its current session.
            }
          }),
        );
      }
      return consentEnabled;
    } catch (_) {
      if (enabled && latest()) {
        // The native store checks the original owner and preserves the original envelopes.
        // A newer explicit opt-in for this owner owns its own native decision.
        confirmedStopped = await _smsAccessChannel.setEnabled(
          false,
          ownerUserId: owner,
        );
        if (!confirmedStopped && current()) {
          final observed = await _smsAccessChannel.status(ownerUserId: owner);
          confirmedStopped =
              observed.bridgeAvailable && !observed.consentEnabled;
          if (current() && !confirmedStopped) {
            state = state.copyWith(
              smsAccessEnabled: observed.bridgeAvailable
                  ? observed.enabled
                  : state.smsAccessEnabled,
              smsSyncNeedsAttention: true,
            );
          }
        }
      }
      if (current() && confirmedStopped) {
        state = state.copyWith(
          smsAccessEnabled: false,
          smsAccessDenied: enabled && !granted,
        );
      }
      rethrow;
    } finally {
      finished.complete();
      if (latest()) _consentWrites.remove(owner);
    }
  }

  @override
  Future<SmsAccessStatus> refreshSmsAccessStatus() async {
    final session = _captureSession();
    final owner = state.currentProfile?.id;
    final read = ++_smsStatusRead;
    var revision = _smsAccessRevision;
    bool current() =>
        _currentSmsContext(session, owner) &&
        revision == _smsAccessRevision &&
        read == _smsStatusRead;
    if (!current()) return const SmsAccessStatus.unavailable();
    final pendingConsent = _consentWrites[owner];
    if (pendingConsent != null) {
      await pendingConsent;
      if (!current()) return const SmsAccessStatus.unavailable();
    }
    var nativeStatus = await _smsAccessChannel.status(ownerUserId: owner ?? '');
    if (!current()) return const SmsAccessStatus.unavailable();
    if (nativeStatus.supported &&
        nativeStatus.declared &&
        nativeStatus.consentEnabled &&
        !nativeStatus.enabled &&
        !nativeStatus.queueUnavailable &&
        !nativeStatus.queueOverflowed &&
        !nativeStatus.queueNeedsReview &&
        owner != null &&
        session.identity != null) {
      ++revision;
      try {
        await setSmsAccess(false, expectedOwnerUserId: owner);
      } catch (_) {
        if (!current()) return const SmsAccessStatus.unavailable();
        rethrow;
      }
      if (!current()) return const SmsAccessStatus.unavailable();
      nativeStatus = await _smsAccessChannel.status(ownerUserId: owner);
      if (!current()) return const SmsAccessStatus.unavailable();
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

  @override
  Future<int> syncPendingSmsAccess() {
    final owner = state.currentProfile?.id;
    if (owner == null || _backend == null) return Future.value(0);
    final session = _captureSession();
    final previous = _smsDrains[owner];
    if (previous != null && _isCurrentSession(previous.session)) {
      previous.scanAgain = true;
      return previous.result;
    }
    final drain = _MemberSmsDrain(session);
    _smsDrains[owner] = drain;
    return drain.result = _drainMemberReceipts(owner, drain, previous);
  }

  @override
  Future<int> retryRejectedSmsAccess({String? expectedOwnerUserId}) async {
    final owner = state.currentProfile?.id;
    if (owner == null ||
        _backend == null ||
        (expectedOwnerUserId != null && expectedOwnerUserId != owner)) {
      throw StateError('Sign in to retry your SMS uploads.');
    }
    final session = _captureSession();
    void current() => _requireCurrentMemberSession(session, owner);
    current();
    final status = await _receiptStatus(session, owner);
    current();
    if (!status.enabled || !status.granted) {
      throw StateError('Allow SMS access before retrying uploads.');
    }
    final retried = await _smsAccessChannel.retryRejectedSms(
      ownerUserId: owner,
    );
    current();
    if (!retried) throw StateError('SMS uploads remain queued for review.');
    final uploaded = await syncPendingSmsAccess();
    current();
    return uploaded;
  }

  Future<int> _drainMemberReceipts(
    String owner,
    _MemberSmsDrain drain,
    _MemberSmsDrain? previous,
  ) async {
    final session = drain.session;
    try {
      if (previous != null) {
        // The earlier session may already have sent the immutable envelope. Give its
        // receipt a chance to settle, then start a fresh owner-scoped scan.
        try {
          await previous.result;
        } catch (_) {}
      }
      _requireCurrentMemberSession(session, owner);
      var ingested = 0;
      do {
        drain.scanAgain = false;
        ingested += await _syncPendingSmsAccessPass(session, owner);
        _requireCurrentMemberSession(session, owner);
        if (drain.scanAgain) continue;
        final status = await _smsAccessChannel.status(ownerUserId: owner);
        _requireCurrentMemberSession(session, owner);
        // An explicit retry can reopen a parked envelope during this native read.
        if (drain.scanAgain) continue;
        state = state.copyWith(
          smsSyncNeedsAttention:
              status.queueUnavailable ||
              status.queueOverflowed ||
              status.queueNeedsReview ||
              (state.smsSyncNeedsAttention &&
                  (!status.enabled || !status.granted)),
        );
      } while (drain.scanAgain);
      return ingested;
    } catch (_) {
      if (_currentSmsContext(session, owner)) {
        state = state.copyWith(smsSyncNeedsAttention: true);
      }
      rethrow;
    } finally {
      if (identical(_smsDrains[owner], drain)) _smsDrains.remove(owner);
    }
  }

  Future<int> _syncPendingSmsAccessPass(
    _CollectSessionFence session,
    String owner,
  ) async {
    _requireCurrentMemberSession(session, owner);
    final status = await _receiptStatus(session, owner);
    _requireCurrentMemberSession(session, owner);
    if (!status.enabled || !status.granted) return 0;
    final pending = await _smsAccessChannel.readPendingSms(ownerUserId: owner);
    _requireCurrentMemberSession(session, owner);
    var ingested = 0;
    for (final item in pending) {
      _requireCurrentMemberSession(session, owner);
      if (item.ownerUserId != owner || item.rawBody.trim().isEmpty) {
        // No disableAndClear call: an account mismatch is not consent to destroy evidence.
        throw StateError('Queued receipt ownership needs review.');
      }
      if (item.needsReview) continue;
      late final DurableSmsReceipt receipt;
      try {
        receipt = await _acceptSmsReceipt(
          item.rawBody,
          session: session,
          expectedOwner: owner,
          clientEnvelopeId: item.id,
          rawSender: item.rawSender,
          receivedAtDevice: item.receivedAtDevice.trim().isEmpty
              ? null
              : item.receivedAtDevice,
          completeness: item.completeness,
        );
      } on CollectFunctionException catch (error) {
        _requireCurrentMemberSession(session, owner);
        if (!const {400, 409, 413, 422}.contains(error.status)) rethrow;
        final parked = await _smsAccessChannel.parkPendingSms(
          ownerUserId: owner,
          id: item.id,
        );
        _requireCurrentMemberSession(session, owner);
        if (!parked) throw StateError('SMS could not be retained for review.');
        state = state.copyWith(smsSyncNeedsAttention: true);
        continue;
      }
      _requireCurrentMemberSession(session, owner);
      final acknowledged = await _smsAccessChannel.acknowledgeDurableReceipt(
        receipt,
      );
      _requireCurrentMemberSession(session, owner);
      if (!acknowledged) {
        throw StateError(
          'Receipt remains queued until acknowledgement can be verified.',
        );
      }
      ingested += 1;
    }
    if (ingested > 0) {
      _requireCurrentMemberSession(session, owner);
      await loadInitial();
      _requireCurrentMemberSession(session, owner);
    }
    return ingested;
  }
}
