part of 'collect_repository.dart';

mixin _CollectReceiptSmsActions on StateNotifier<CollectState> {
  CollectCloudflareClient? get _backend;
  ReceiptSmsPendingStore get _receiptSmsPendingStore;
  Uuid get _uuid;
  _CollectAuthIdentity? get _signingOutIdentity;
  _CollectSessionFence _captureSession();
  bool _isCurrentSession(_CollectSessionFence session);
  void _requireCurrentMemberSession(
    _CollectSessionFence session,
    String profileId,
  );
  CollectProfile _requireProfile();
  final Map<String, ReceiptSmsConsentView> _receiptSmsViews = {};
  final Map<String, int> _receiptSmsReads = {};
  int _receiptSmsEpoch = 0;
  void _resetReceiptSmsConsent({bool notify = false}) {
    _receiptSmsEpoch++;
    _receiptSmsViews.clear();
    _receiptSmsReads.clear();
    if (notify && mounted) state = state.copyWith();
  }

  bool _receiptSmsCurrent(_CollectSessionFence session, int epoch) =>
      epoch == _receiptSmsEpoch &&
      _isCurrentSession(session) &&
      session.identity != null &&
      session.accessToken != null &&
      session.identity?.userId == state.currentProfile?.id &&
      _signingOutIdentity != session.identity;
  ReceiptSmsConsentView receiptSmsConsentFor(String group) =>
      _receiptSmsCurrent(_captureSession(), _receiptSmsEpoch)
      ? _receiptSmsViews[group] ?? const ReceiptSmsConsentView()
      : const ReceiptSmsConsentView();
  PendingReceiptSmsRequest? receiptSmsCurrentPending(String group) =>
      receiptSmsConsentFor(group).recovery.pending
          .where((r) => r.sessionId == _captureSession().identity?.sessionId)
          .singleOrNull;
  bool receiptSmsPendingBelongsToCurrentSession(String group) =>
      receiptSmsCurrentPending(group) != null;
  bool _receiptSmsMember(String group) => state.collections.any(
    (g) => g.id == group && g.isCurrentUserMember && !g.isArchived,
  );
  void _receiptSmsPublish(String group, ReceiptSmsConsentView value) {
    _receiptSmsViews[group] = value;
    state = state.copyWith();
  }

  ReceiptSmsConsentView _busy(ReceiptSmsConsentView old) =>
      ReceiptSmsConsentView(
        consent: old.consent,
        recovery: old.recovery,
        busy: true,
        recordedRevision: old.recordedRevision,
        recordedDecisionRevision: old.recordedDecisionRevision,
        acknowledgedRequest: old.acknowledgedRequest,
        unpersistedRequestIds: old.unpersistedRequestIds,
      );
  void _receiptSmsCanRead(
    String group,
    _CollectSessionFence session,
    String user,
  ) {
    receiptSmsUuid(group);
    _requireCurrentMemberSession(session, user);
    if (!_receiptSmsMember(group)) {
      throw StateError('Choose one of your current groups.');
    }
  }

  // A healthy journal may have been completed by another repository instance.
  // Missing known metadata is still an unknown outcome in this instance. Keep it
  // blocked until exact replay or explicit higher-head archival resolves custody.
  ReceiptSmsRecoveryState _receiptSmsMergeCustody(
    ReceiptSmsConsentView old,
    ReceiptSmsRecoveryState actual, {
    String? acknowledgedRequestId,
  }) {
    final byId = {
      for (final r in [
        ...actual.pending,
        ...actual.superseded.map((r) => r.request),
      ])
        r.requestId: r,
    };
    for (final known in [
      ...old.recovery.pending,
      ...old.recovery.superseded.map((r) => r.request),
    ]) {
      final retained = byId[known.requestId];
      if (retained != null && !retained.sameRequest(known)) {
        throw StateError('Retained receipt SMS metadata changed.');
      }
    }
    final pending = [
      ...actual.pending,
      ...old.recovery.pending.where(
        (r) =>
            !actual.retains(r.requestId) &&
            !old.unpersistedRequestIds.contains(r.requestId) &&
            old.acknowledgedRequest?.requestId != r.requestId &&
            acknowledgedRequestId != r.requestId,
      ),
    ];
    if (pending.length > 32) {
      throw StateError('Receipt SMS recovery capacity unavailable.');
    }
    return ReceiptSmsRecoveryState(
      pending: pending,
      superseded: actual.superseded,
    );
  }

  /// GET never sends a decision, retries an unknown request, or discards custody.
  Future<void> refreshReceiptSmsConsent(String group) async {
    final profile = _requireProfile(),
        session = _captureSession(),
        epoch = _receiptSmsEpoch;
    _receiptSmsCanRead(group, session, profile.id);
    final backend = _backend;
    if (backend == null) {
      throw StateError('Connect to load receipt SMS status.');
    }
    final old = receiptSmsConsentFor(group);
    if (old.busy) throw StateError('Wait for the current receipt SMS request.');
    final read = (_receiptSmsReads[group] ?? 0) + 1;
    _receiptSmsReads[group] = read;
    bool current() =>
        _receiptSmsCurrent(session, epoch) && _receiptSmsReads[group] == read;
    _receiptSmsPublish(group, _busy(old));
    var recovery = old.recovery;
    var storage = false;
    String? storageError;
    try {
      try {
        final actual = await _receiptSmsPendingStore.read(
          userId: profile.id,
          collectionId: group,
        );
        if (!current()) {
          throw StateError('Receipt SMS read belongs to an earlier sign-in.');
        }
        recovery = _receiptSmsMergeCustody(old, actual);
        storage = true;
      } catch (_) {
        if (!current()) rethrow;
        storageError =
            'Secure request recovery is unavailable. Changes are disabled; no retained request was discarded.';
      }
      final data = await backend
          .rpc<dynamic>(
            'get_assisted_sms_consent_v1',
            params: {'p_collection_id': group},
          )
          .setHeader('Authorization', 'Bearer ${session.accessToken}')
          .retry(enabled: false);
      if (!current()) {
        throw StateError('Receipt SMS read belongs to an earlier sign-in.');
      }
      final consent = ReceiptSmsConsent.decode(data, group);
      final minConsent = [
        old.recordedRevision ?? 0,
        old.consent?.revision ?? 0,
        ...recovery.pending.map((r) => r.expectedRevision),
      ].fold(0, (a, b) => a > b ? a : b);
      final minDecision = [
        old.recordedDecisionRevision ?? 0,
        old.consent?.decisionRevision ?? 0,
        ...recovery.pending.map((r) => r.expectedDecisionRevision),
        ...old.recovery.superseded.map((r) => r.observedDecisionRevision),
        ...recovery.superseded.map((r) => r.observedDecisionRevision),
      ].fold(0, (a, b) => a > b ? a : b);
      if (consent.revision < minConsent ||
          consent.decisionRevision < minDecision) {
        throw const FormatException(
          'Receipt SMS status is older than retained custody.',
        );
      }
      _receiptSmsPublish(
        group,
        ReceiptSmsConsentView(
          consent: consent,
          recovery: recovery,
          needsRefresh: false,
          storageAvailable: storage,
          refreshedPending: recovery.pending.isNotEmpty,
          error: storageError,
        ),
      );
    } catch (error) {
      if (!current()) {
        throw StateError('Receipt SMS read belongs to an earlier sign-in.');
      }
      final unsupported =
          error is CollectApiException && error.code == 'operation_unavailable';
      _receiptSmsPublish(
        group,
        ReceiptSmsConsentView(
          consent: old.consent,
          recovery: recovery,
          storageAvailable: storage,
          recordedRevision: old.recordedRevision,
          recordedDecisionRevision: old.recordedDecisionRevision,
          acknowledgedRequest: old.acknowledgedRequest,
          unpersistedRequestIds: old.unpersistedRequestIds,
          supportUnavailable: unsupported,
          error: unsupported
              ? 'Receipt SMS settings are not available from this service yet. No choice has been inferred.'
              : 'Current receipt SMS status could not be loaded. Connect and try Refresh status again.',
        ),
      );
      rethrow;
    }
  }

  (
    CollectProfile,
    _CollectSessionFence,
    ReceiptSmsConsentView,
    ReceiptSmsConsent,
  )
  _receiptSmsEditable(String group) {
    final profile = _requireProfile(), session = _captureSession();
    _receiptSmsCanRead(group, session, profile.id);
    final view = receiptSmsConsentFor(group), consent = view.consent;
    if (view.busy ||
        view.needsRefresh ||
        !view.storageAvailable ||
        view.supportUnavailable ||
        consent == null ||
        state.usingStaleCache) {
      throw StateError('Refresh current receipt SMS status before continuing.');
    }
    if (consent.revision > 999999998 ||
        consent.decisionRevision > 9007199254740990) {
      throw StateError('Receipt SMS revisions need support review.');
    }
    return (profile, session, view, consent);
  }

  PendingReceiptSmsRequest _receiptSmsRequest(
    String group,
    CollectProfile profile,
    _CollectSessionFence session,
    ReceiptSmsConsent consent,
    bool choice,
  ) => PendingReceiptSmsRequest(
    userId: profile.id,
    sessionId: receiptSmsUuid(session.identity!.sessionId),
    collectionId: group,
    requestId: _uuid.v4(),
    expectedRevision: consent.revision,
    expectedDecisionRevision: consent.decisionRevision,
    optIn: choice,
  );
  Future<void> setReceiptSmsConsent(String group, {required bool optIn}) async {
    final (profile, session, view, consent) = _receiptSmsEditable(group);
    if (view.recovery.pending.isNotEmpty) {
      throw StateError(
        'Resolve or fence the retained requests before another choice.',
      );
    }
    if (optIn && !consent.optInAvailable) {
      throw StateError(
        'Current phone verification and active membership are required.',
      );
    }
    await _submitReceiptSmsConsent(
      _receiptSmsRequest(group, profile, session, consent, optIn),
      session,
    );
  }

  /// A separate, intentional false decision; every older identity stays retained.
  Future<void> withdrawReceiptSmsAndRecover(String group) async {
    final (profile, session, view, consent) = _receiptSmsEditable(group);
    if (view.recovery.pending.isEmpty ||
        view.recovery.pending.any(
          (r) => r.sessionId == session.identity!.sessionId,
        )) {
      throw StateError(
        'Retry this sign-in\'s original request rather than creating another.',
      );
    }
    await _submitReceiptSmsConsent(
      _receiptSmsRequest(group, profile, session, consent, false),
      session,
      withdrawalFence: true,
    );
  }

  Future<void> retryReceiptSmsConsent(String group) async {
    final (profile, session, view, _) = _receiptSmsEditable(group);
    final request = view.recovery.pending
        .where(
          (r) =>
              r.userId == profile.id &&
              r.sessionId == session.identity?.sessionId,
        )
        .singleOrNull;
    if (request == null || !view.refreshedPending) {
      throw StateError('Refresh and retry under the original sign-in.');
    }
    await _submitReceiptSmsConsent(request, session);
  }

  /// A higher authenticated head fences future CAS; it never proves an outcome.
  Future<void> supersedeReceiptSmsRequests(String group) async {
    final (profile, session, view, consent) = _receiptSmsEditable(group);
    final epoch = _receiptSmsEpoch;
    if (!view.recovery.pending.any(
      (r) => r.expectedDecisionRevision < consent.decisionRevision,
    )) {
      throw StateError(
        'No retained request has been fenced by a later decision.',
      );
    }
    _receiptSmsPublish(group, _busy(view));
    try {
      final remaining = await _receiptSmsPendingStore.supersede(
        userId: profile.id,
        collectionId: group,
        knownRequests: view.recovery.pending,
        observedDecisionRevision: consent.decisionRevision,
      );
      if (!_receiptSmsCurrent(session, epoch)) {
        throw StateError('Receipt SMS recovery belongs to an earlier sign-in.');
      }
      _receiptSmsPublish(
        group,
        ReceiptSmsConsentView(
          consent: consent,
          recovery: remaining,
          storageAvailable: true,
        ),
      );
    } catch (_) {
      if (!_receiptSmsCurrent(session, epoch)) rethrow;
      _receiptSmsPublish(
        group,
        ReceiptSmsConsentView(
          consent: consent,
          recovery: view.recovery,
          error:
              'Secure recovery could not confirm the disposition. Retained identities were not discarded. Refresh before continuing.',
        ),
      );
      rethrow;
    }
  }

  Future<void> _submitReceiptSmsConsent(
    PendingReceiptSmsRequest request,
    _CollectSessionFence session, {
    bool withdrawalFence = false,
  }) async {
    final backend = _backend;
    if (backend == null) {
      throw StateError('Connect before changing receipt SMS.');
    }
    final group = request.collectionId,
        epoch = _receiptSmsEpoch,
        old = receiptSmsConsentFor(request.collectionId);
    final read = (_receiptSmsReads[group] ?? 0) + 1;
    _receiptSmsReads[group] = read;
    bool current() =>
        _receiptSmsCurrent(session, epoch) && _receiptSmsReads[group] == read;
    var recovery = old.recovery;
    if (!recovery.pending.any((r) => r.requestId == request.requestId)) {
      recovery = ReceiptSmsRecoveryState(
        pending: [...recovery.pending, request],
        superseded: recovery.superseded,
      );
    }
    _receiptSmsPublish(
      group,
      ReceiptSmsConsentView(
        consent: old.consent,
        recovery: recovery,
        busy: true,
      ),
    );
    var durable = false, sent = false;
    ReceiptSmsDecision? decision;
    try {
      final admitted = await _receiptSmsPendingStore.claim(
        request,
        withdrawalFence: withdrawalFence,
      );
      recovery = _receiptSmsMergeCustody(old, admitted);
      durable = true;
      if (!current()) {
        throw StateError('Receipt SMS request belongs to an earlier sign-in.');
      }
      if (!admitted.pending.any((r) => r.sameRequest(request))) {
        throw StateError(
          'A retained request must be recovered before another change.',
        );
      }
      _requireCurrentMemberSession(session, request.userId);
      sent = true;
      final (status, response) = await backend.request(
        'POST',
        'v1/rpc/set_assisted_sms_consent_v1',
        body: request.rpcParameters,
        bearer: session.accessToken,
      );
      if (!current()) {
        throw StateError('Receipt SMS result belongs to an earlier sign-in.');
      }
      if (status != 200) throw collectApiFailure(status, response);
      decision = ReceiptSmsDecision.decode(response, request);
      final remaining = await _receiptSmsPendingStore.complete(
        request,
        decision.decisionRevision,
      );
      recovery = _receiptSmsMergeCustody(
        old,
        remaining,
        acknowledgedRequestId: request.requestId,
      );
      if (!current()) {
        throw StateError(
          'Receipt SMS acknowledgement belongs to an earlier sign-in.',
        );
      }
      _receiptSmsPublish(
        group,
        ReceiptSmsConsentView(
          consent: old.consent,
          recovery: recovery,
          storageAvailable: true,
          recordedRevision: decision.revision,
          recordedDecisionRevision: decision.decisionRevision,
          acknowledgedRequest: request,
        ),
      );
    } catch (_) {
      if (!current()) {
        throw StateError('Receipt SMS request belongs to an earlier sign-in.');
      }
      _receiptSmsPublish(
        group,
        ReceiptSmsConsentView(
          consent: old.consent,
          recovery: recovery,
          storageAvailable: durable,
          recordedRevision: decision?.revision,
          recordedDecisionRevision: decision?.decisionRevision,
          acknowledgedRequest: decision == null ? null : request,
          unpersistedRequestIds: {
            ...old.unpersistedRequestIds,
            if (!durable) request.requestId,
          },
          error: decision != null
              ? 'Decision recorded, but secure recovery could not be updated. Retained identities remain; refresh before continuing.'
              : sent
              ? 'This change was not confirmed. Every original request is retained. Refresh before retrying the same request.'
              : 'No HTTP change was sent by this attempt. Secure recovery could not admit this request; refresh before continuing.',
        ),
      );
      rethrow;
    }
  }
}
