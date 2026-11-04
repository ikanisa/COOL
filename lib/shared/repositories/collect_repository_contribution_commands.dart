part of 'collect_repository.dart';

/// Original command custody stays separate from historical intent reads.
/// Authenticated callers of the compatibility entry point use this flow too.
mixin _CollectContributionCommands on StateNotifier<CollectState> {
  // An in-flight response and the gap before the native launch must both fit
  // inside this monotonic window. It is not a guarantee about provider state.
  static const _handoffReviewWindow = Duration(seconds: 5);
  CollectCloudflareClient? get _backend;
  ContributionCommandJournal get _contributionCommandJournal;
  _CollectAuthIdentity? get _signingOutIdentity;
  Uuid get _uuid;
  _CollectSessionFence _captureSession();
  bool _isCurrentSession(_CollectSessionFence session);
  CollectProfile _requireReadyProfile();
  CollectCollection _requireActiveCollection(String collectionId);

  ContributionCommandOwner _contributionOwner() {
    final backend = _backend, auth = backend?.auth.currentSession;
    final project = backend?.supabaseConfiguration?.project;
    if (auth == null || project == null) {
      throw StateError(
        'Sign in to the current Collect service before contributing.',
      );
    }
    return ContributionCommandOwner(
      projectOrigin: project.origin,
      principalId: auth.user.id,
      authSubject: auth.authSubject,
    );
  }

  bool _contributionCurrent(
    _CollectSessionFence session,
    ContributionCommandOwner owner,
  ) {
    if (!_isCurrentSession(session) ||
        session.identity == null ||
        _signingOutIdentity == session.identity ||
        state.currentProfile?.id != owner.principalId) {
      return false;
    }
    try {
      return _contributionOwner().sameOwner(owner);
    } catch (_) {
      return false;
    }
  }

  bool _contributionSenderCurrent(String expectedHash) {
    final profile = state.currentProfile;
    if (profile == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedHash)) {
      return false;
    }
    try {
      return HashUtils.phoneHash(profile.momoNumber) == expectedHash;
    } catch (_) {
      return false;
    }
  }

  // Local state can only withhold a handoff. A matching snapshot is never a
  // substitute for the separate server review of the current intent.
  bool _contributionObservationCompatible(
    CollectState snapshot,
    PaymentIntentModel prepared,
    ContributionCommandOwner owner,
  ) {
    if (snapshot.isLoading ||
        snapshot.usingStaleCache ||
        snapshot.financialObservationUncertain ||
        snapshot.lastSuccessfulSyncAt == null) {
      return false;
    }
    final profile = snapshot.currentProfile;
    if (profile == null ||
        profile.id != owner.principalId ||
        !profile.isRwanda) {
      return false;
    }
    try {
      if (HashUtils.phoneHash(profile.momoNumber) != prepared.senderPhoneHash) {
        return false;
      }
    } catch (_) {
      return false;
    }
    final groups = snapshot.collections
        .where((group) => group.id == prepared.collectionId)
        .take(2)
        .toList();
    final intents = snapshot.paymentIntents
        .where((intent) => intent.id == prepared.id)
        .take(2)
        .toList();
    if (groups.length != 1 || intents.length != 1) return false;
    final group = groups.single;
    return !group.isArchived &&
        group.isCurrentUserMember &&
        group.contributionRailFor(profile) == 'rwanda_momo' &&
        group.receiverMomoNumber?.trim() == prepared.receiverMomoNumber &&
        group.receiverNetwork == prepared.momoNetwork &&
        group.receiverRouteLabel?.trim() == prepared.receiverMomoLabel &&
        preparedMomoIntentStillActionable(
          prepared,
          intents.single,
          now: DateTime.now(),
        );
  }

  Future<ContributionSessionWitness> _contributionWitness(
    _CollectSessionFence fence,
    ContributionCommandOwner owner,
  ) async {
    if (!_contributionCurrent(fence, owner) || fence.accessToken == null) {
      throw StateError('Account changed. Sign in again.');
    }
    final response = await _backend!
        .rpc<dynamic>(
          'get_current_member_contribution_session_v1',
          params: const {'p_contract_version': 1},
        )
        .setHeader('Authorization', 'Bearer ${fence.accessToken}')
        .retry(enabled: false);
    if (!_contributionCurrent(fence, owner)) {
      throw StateError('Account changed. Sign in again.');
    }
    return ContributionSessionWitness.fromWire(
      response,
      expectedOwner: owner,
      now: DateTime.now(),
    );
  }

  /// Local ownership selects encrypted recovery only. It grants no dispatch,
  /// lookup or payment authority and never deletes another account's partition.
  Future<ContributionCommandCheckpoint?> restoreContributionCommand(
    String collectionId,
  ) async {
    final owner = _contributionOwner(), fence = _captureSession();
    final result = await _contributionCommandJournal.latestUnresolved(
      owner,
      collectionId,
    );
    if (!_contributionCurrent(fence, owner)) {
      throw StateError('Account changed. Sign in again.');
    }
    return result;
  }

  Future<PaymentIntentModel> prepareContributionIntent(
    PaymentIntentDraft draft,
  ) async {
    exactJsonInteger(draft.amountRwf, field: 'contribution.amount', minimum: 1);
    contributionUuid(draft.collectionId);
    final profile = _requireReadyProfile(),
        collection = _requireActiveCollection(draft.collectionId);
    if (collection.contributionRailFor(profile) != 'rwanda_momo' ||
        !profile.isRwanda) {
      throw StateError('This group has no active Rwanda MoMo route.');
    }
    if (!collection.isPublic &&
        !collection.isCurrentUserMember &&
        collection.creatorUserId != profile.id) {
      throw StateError('Join this group before contributing.');
    }
    final owner = _contributionOwner(), fence = _captureSession();
    final body = ContributionCommandBody(
      collectionId: draft.collectionId,
      amountRwf: draft.amountRwf,
      senderPhoneHash: HashUtils.phoneHash(profile.momoNumber),
      requestId: _uuid.v4(),
    );
    bool current() =>
        _contributionCurrent(fence, owner) &&
        _contributionSenderCurrent(body.senderPhoneHash);
    var witness = await _contributionWitness(fence, owner);
    var checkpoint = await _contributionCommandJournal.prepare(
      witness,
      body,
      isCurrent: current,
    );
    try {
      witness = await _contributionWitness(fence, owner);
      if (witness.sessionId != checkpoint.originalSessionId) {
        throw ContributionRecoveryRequired(checkpoint);
      }
      checkpoint = await _contributionCommandJournal.claimDispatch(
        witness,
        body.requestId,
        isCurrent: current,
      );
      if (!current() || !witness.usableAt(DateTime.now())) {
        throw ContributionRecoveryRequired(checkpoint);
      }
      final response = await _backend!
          .rpc<dynamic>('create_contribution_intent', params: body.toJson())
          .setHeader('Authorization', 'Bearer ${fence.accessToken}')
          .retry(enabled: false);
      if (!current()) throw ContributionRecoveryRequired(checkpoint);
      final row = contributionObject(response, const {
        'id',
        'collection_id',
        'amount_minor',
        'currency',
        'rail',
        'status',
        'receiver_momo_number',
        'network',
        'receiver_label',
        'receiver_momo_number_hash',
        'sender_phone_hash',
        'originating_session_id',
        'created_at',
        'expires_at',
      });
      final intent = PaymentIntentModel.fromJson(row);
      if (contributionUuid(intent.id) != intent.id ||
          intent.collectionId != body.collectionId ||
          intent.expectedAmountRwf != body.amountRwf ||
          intent.senderPhoneHash != body.senderPhoneHash ||
          intent.status != 'pending' ||
          row['originating_session_id'] != checkpoint.originalSessionId ||
          !intent.isRwandaMomo ||
          intent.receiverMomoNumber.isEmpty ||
          !const {'mtn_momo', 'airtel_money'}.contains(intent.momoNetwork)) {
        throw const FormatException(
          'Contribution receipt does not match the original request.',
        );
      }
      witness = await _contributionWitness(fence, owner);
      if (witness.sessionId != checkpoint.originalSessionId) {
        throw ContributionRecoveryRequired(checkpoint);
      }
      checkpoint = await _contributionCommandJournal.retainReceipt(
        witness,
        body.requestId,
        intent.id,
        isCurrent: current,
      );
      if (!current()) throw ContributionRecoveryRequired(checkpoint);
      state = state.copyWith(
        paymentIntents: [
          intent,
          ...state.paymentIntents.where((r) => r.id != intent.id).take(49),
        ],
        collections: [
          for (final row in state.collections)
            if (row.id == collection.id && collection.isPublic)
              row.copyWith(isCurrentUserMember: true)
            else
              row,
        ],
      );
      return intent;
    } catch (_) {
      // Every uncertain response/ACK retains the original key/body. A failed
      // local acknowledgement never grants dispatch or a replacement key.
      throw ContributionRecoveryRequired(checkpoint);
    }
  }

  Future<ContributionCommandCheckpoint> checkContributionCommand(
    String requestId,
  ) async {
    final owner = _contributionOwner(), fence = _captureSession();
    bool current() => _contributionCurrent(fence, owner);
    final original = await _contributionCommandJournal.find(
      owner,
      contributionUuid(requestId),
    );
    final witness = await _contributionWitness(fence, owner);
    final result = await _backend!
        .rpc<dynamic>(
          'get_current_member_contribution_command_v1',
          params: {
            'p_contract_version': 1,
            'p_original_request_id': original.body.requestId,
            'p_original_session_id': original.originalSessionId,
            'p_collection_id': original.body.collectionId,
            'p_original_body': original.body.toJson(),
          },
        )
        .setHeader('Authorization', 'Bearer ${fence.accessToken}')
        .retry(enabled: false);
    if (!current()) throw StateError('Account changed. Sign in again.');
    final observation = ContributionCommandObservation.fromWire(
      result,
      original,
    );
    // Re-witness before the custody mutation. A newer session may observe the
    // old command, but its original session/body never changes.
    final fresh = await _contributionWitness(fence, owner);
    if (fresh.sessionId != witness.sessionId) {
      throw StateError('Session changed. Check the original request again.');
    }
    return _contributionCommandJournal.retainObservation(
      fresh,
      original.body.requestId,
      observation,
      isCurrent: current,
    );
  }

  Future<ContributionIntentReview> reviewContributionIntent(
    PaymentIntentModel prepared,
  ) async {
    final owner = _contributionOwner(), fence = _captureSession();
    final records = await _contributionCommandJournal.read(owner);
    if (!_contributionCurrent(fence, owner)) {
      throw StateError('Account changed. Sign in again.');
    }
    final matching = records.where((r) => r.intentId == prepared.id);
    if (matching.length != 1) {
      throw StateError('Check the original contribution request.');
    }
    final command = matching.single;
    if (command.phase != ContributionCommandPhase.receiptRetained ||
        command.providerHandoffPossible ||
        command.committedContributionObserved) {
      throw ContributionRecoveryRequired(command);
    }
    final witness = await _contributionWitness(fence, owner);
    if (witness.sessionId != command.originalSessionId ||
        command.body.collectionId != prepared.collectionId ||
        command.body.amountRwf != prepared.expectedAmountRwf ||
        command.body.senderPhoneHash != prepared.senderPhoneHash ||
        !_contributionSenderCurrent(command.body.senderPhoneHash)) {
      throw ContributionRecoveryRequired(command);
    }
    return _fetchContributionReview(
      prepared,
      witness,
      fence,
      owner,
      command.body.senderPhoneHash,
    );
  }

  Future<ContributionIntentReview> _fetchContributionReview(
    PaymentIntentModel prepared,
    ContributionSessionWitness witness,
    _CollectSessionFence fence,
    ContributionCommandOwner owner,
    String senderHash,
  ) async {
    if (prepared.senderPhoneHash != senderHash ||
        !_contributionSenderCurrent(senderHash)) {
      throw const ContributionReviewChanged();
    }
    if (!_contributionCurrent(fence, owner) ||
        !witness.usableAt(DateTime.now())) {
      throw StateError('Account changed. Sign in again.');
    }
    final response = await _backend!
        .rpc<dynamic>(
          'review_current_member_contribution_intent_v1',
          params: {
            'p_contract_version': 1,
            'p_intent_id': prepared.id,
            'p_collection_id': prepared.collectionId,
          },
        )
        .setHeader('Authorization', 'Bearer ${fence.accessToken}')
        .retry(enabled: false);
    if (!_contributionCurrent(fence, owner) ||
        !witness.usableAt(DateTime.now())) {
      throw StateError('Account changed. Sign in again.');
    }
    final review = ContributionIntentReview.fromWire(
      response,
      collectionId: prepared.collectionId,
      intentId: prepared.id,
      sessionId: witness.sessionId,
    );
    if (!_contributionSenderCurrent(senderHash) ||
        review.intent.senderPhoneHash != senderHash ||
        !reviewedMomoIntentStillActionable(
          prepared,
          review,
          now: DateTime.now(),
        )) {
      throw const ContributionReviewChanged();
    }
    return review;
  }

  Future<ContributionLaunchPermit> claimContributionHandoff(
    PaymentIntentModel prepared,
    ContributionIntentReview review,
  ) async {
    final owner = _contributionOwner(), fence = _captureSession();
    bool current() => _contributionCurrent(fence, owner);
    final witness = await _contributionWitness(fence, owner);
    if (witness.sessionId != review.sessionId ||
        !reviewedMomoIntentStillActionable(
          prepared,
          review,
          now: DateTime.now(),
        )) {
      throw const ContributionReviewChanged();
    }
    final records = await _contributionCommandJournal.read(owner);
    if (!current()) throw StateError('Account changed. Sign in again.');
    final matches = records.where((r) => r.intentId == prepared.id);
    if (matches.length != 1) {
      throw StateError('Check the original contribution request.');
    }
    final command = matches.single;
    if (command.body.senderPhoneHash != prepared.senderPhoneHash ||
        !_contributionSenderCurrent(command.body.senderPhoneHash)) {
      throw const ContributionReviewChanged();
    }
    var observationInvalidated = false;
    final removeObservation = addListener((snapshot) {
      if (!_contributionObservationCompatible(snapshot, prepared, owner)) {
        observationInvalidated = true;
      }
    }, fireImmediately: false);
    Timer? expiry;
    var observationClosed = false;
    void closeObservation() {
      if (observationClosed) return;
      observationClosed = true;
      expiry?.cancel();
      removeObservation();
    }

    bool stillBound() =>
        !observationInvalidated &&
        current() &&
        _contributionSenderCurrent(command.body.senderPhoneHash) &&
        _contributionObservationCompatible(state, prepared, owner);
    try {
      if (!stillBound()) throw const ContributionReviewChanged();
      await _contributionCommandJournal.claimProviderHandoff(
        witness,
        command.body.requestId,
        prepared.id,
        isCurrent: stillBound,
      );
      // Storage may await arbitrarily long. The final server review remains
      // mandatory, and a newer local contradiction stays invalid even if an
      // older response arrives afterward or the local value changes back.
      final reviewAge = Stopwatch()..start();
      final freshReview = await _fetchContributionReview(
        prepared,
        witness,
        fence,
        owner,
        command.body.senderPhoneHash,
      );
      if (!stillBound() ||
          reviewAge.elapsed >= _handoffReviewWindow ||
          freshReview.collectionRevision != review.collectionRevision ||
          !reviewedMomoIntentStillActionable(
            prepared,
            freshReview,
            now: DateTime.now(),
          )) {
        throw const ContributionReviewChanged();
      }
      expiry = Timer(
        _handoffReviewWindow - reviewAge.elapsed,
        closeObservation,
      );
      return ContributionLaunchPermit(
        review: freshReview,
        isCurrent: () {
          final allowed =
              !observationClosed &&
              stillBound() &&
              witness.usableAt(DateTime.now()) &&
              reviewAge.elapsed < _handoffReviewWindow &&
              reviewedMomoIntentStillActionable(
                prepared,
                freshReview,
                now: DateTime.now(),
              );
          closeObservation();
          return allowed;
        },
      );
    } catch (_) {
      closeObservation();
      rethrow;
    }
  }

  /// Only a server-confirmed posted contribution permits another genuine
  /// contribution. Cancelled/expired/absent requests remain uncertain and retained.
  Future<void> acknowledgeCommittedContribution(
    PaymentIntentModel intent,
  ) async {
    if (!intent.hasCommittedContribution) return;
    final owner = _contributionOwner(), fence = _captureSession();
    final records = await _contributionCommandJournal.read(owner);
    if (!_contributionCurrent(fence, owner)) {
      throw StateError('Account changed. Sign in again.');
    }
    final matches = records.where((r) => r.intentId == intent.id);
    if (matches.isEmpty) {
      return; // Older history has no new command journal row.
    }
    if (matches.length != 1) {
      throw StateError('Contribution recovery identities conflict.');
    }
    final witness = await _contributionWitness(fence, owner);
    await _contributionCommandJournal.retainCommittedContribution(
      witness,
      matches.single.body.requestId,
      intent,
      isCurrent: () => _contributionCurrent(fence, owner),
    );
  }
}
