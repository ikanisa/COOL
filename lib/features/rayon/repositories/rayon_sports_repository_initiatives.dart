part of 'rayon_sports_repository.dart';

extension RayonSportsInitiativeRepository on RayonSportsRepository {
  Future<String> supportInitiative({
    required String userId,
    required String initiativeId,
    required int amount,
    String? referralInviteId,
  }) async {
    if (amount <= 0) {
      throw StateError('Support amount must be greater than zero.');
    }

    return _openInitiativeContributionCheckout(
      component: 'rayon_support',
      userId: userId,
      initiativeId: initiativeId,
      amount: amount,
      referralInviteId: referralInviteId,
      successMessage: 'Rayon support checkout opened successfully.',
      failureMessage: 'Rayon support checkout failed before payment sync.',
    );
  }

  Future<List<RsInitiative>> getInitiatives(String partnerId) async {
    return _asListOfMaps(
      await _client
          .from('rs_initiatives')
          .select()
          .eq('partner_id', partnerId)
          .eq('is_active', true)
          .order('ends_at'),
    ).map(RsInitiative.fromJson).toList(growable: false);
  }

  Future<String> contribute({
    required String initiativeId,
    required String userId,
    required int amount,
    String? referralInviteId,
  }) async {
    if (amount <= 0) {
      throw StateError('Contribution amount must be greater than zero.');
    }

    return _openInitiativeContributionCheckout(
      component: 'rayon_support',
      userId: userId,
      initiativeId: initiativeId,
      amount: amount,
      referralInviteId: referralInviteId,
      successMessage: 'Rayon initiative checkout opened successfully.',
      failureMessage: 'Rayon initiative checkout failed before payment sync.',
    );
  }

  Future<List<RsJsonMap>> getRecentContributors(
    String initiativeId,
    int limit,
  ) async {
    return (await getRecentContributionActivity(initiativeId, limit))
        .map(
          (contribution) => <String, Object?>{
            'id': contribution.id,
            'userId': contribution.userId,
            'name': contribution.supporterName ?? 'Supporter',
            'amount': contribution.amount,
            'createdAt': contribution.createdAt.toIso8601String(),
            'status': contribution.status,
            'momoReference': contribution.momoReference,
          },
        )
        .toList(growable: false);
  }

  Future<List<RsInitiativeContribution>> getRecentContributionActivity(
    String initiativeId,
    int limit,
  ) async {
    final rows = _asListOfMaps(
      await _client
          .from('rs_initiative_contributions')
          .select(
            'id, user_id, amount, created_at, status, momo_reference, supporter_name',
          )
          .eq('initiative_id', initiativeId)
          .order('created_at', ascending: false)
          .limit(limit),
    );

    if (rows.isEmpty) return const [];

    return rows
        .map(
          (row) => RsInitiativeContribution.fromJson(<String, Object?>{
            ...row,
            'initiative_id': initiativeId,
            'supporter_name': _supporterNameForRow(row),
          }),
        )
        .toList(growable: false);
  }

  Future<String> _openInitiativeContributionCheckout({
    required String component,
    required String userId,
    required String initiativeId,
    required int amount,
    required String successMessage,
    required String failureMessage,
    String? referralInviteId,
  }) {
    return _checkoutService.openCheckout(
      component: component,
      userId: userId,
      referencePrefix: 'RS-SUPPORT',
      amount: amount,
      successMessage: successMessage,
      failureMessage: failureMessage,
      failureMetadata: <String, Object?>{
        'initiative_id': initiativeId,
        'amount': amount,
      },
      prepare: (reference) async {
        final rows = _asListOfMaps(
          await _client
              .from('rs_initiative_contributions')
              .insert(<String, Object?>{
                'initiative_id': initiativeId,
                'user_id': userId,
                'amount': amount,
                'momo_reference': reference,
                'referral_invite_id': referralInviteId,
                'status': 'pending',
              })
              .select('id'),
        );

        final contributionId = rows.first['id']?.toString() ?? reference;
        return RayonCheckoutResult<String>(
          value: contributionId,
          subjectType: 'rs_initiative_contributions',
          subjectId: contributionId,
          successMetadata: <String, Object?>{
            'initiative_id': initiativeId,
            'amount': amount,
          },
        );
      },
    );
  }
}
