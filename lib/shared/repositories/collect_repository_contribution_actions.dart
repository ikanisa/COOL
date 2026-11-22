part of 'collect_repository.dart';

mixin _CollectContributionActions on StateNotifier<CollectState> {
  CollectCloudflareClient? get _backend;
  bool get _allowLocalWrites;
  Uuid get _uuid;
  Future<PaymentIntentModel> prepareContributionIntent(
    PaymentIntentDraft draft,
  );
  CollectProfile _requireReadyProfile();
  CollectCollection _requireActiveCollection(String collectionId);

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
