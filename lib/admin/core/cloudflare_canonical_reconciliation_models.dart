part of 'cloudflare_canonical_reconciliation_api.dart';

class CanonicalReconciliationDetail {
  const CanonicalReconciliationDetail(
    this.transaction,
    this.group,
    this.actorId,
    this.principalId,
    this.canPropose,
    this.canReview,
    this.related,
  );
  final Map<String, dynamic> transaction, group;
  final String actorId, principalId;
  final bool canPropose, canReview;
  final Map<String, ReconciliationPage<Map<String, dynamic>>> related;
  String get id => transaction['id'] as String;
  bool get eligibleForAttribution =>
      group['status'] == 'active' &&
      const {'recorded', 'ambiguous'}.contains(transaction['status']) &&
      transaction['member_user_id'] == null &&
      transaction['allocated_amount_rwf'] == 0;
  CanonicalReconciliationDetail merge(CanonicalReconciliationDetail page) {
    if (page.id != id ||
        page.actorId != actorId ||
        page.principalId != principalId ||
        page.transaction['version'] != transaction['version'] ||
        page.group['version'] != group['version']) {
      throw const FormatException(
        'The payment or group changed. Refresh before continuing.',
      );
    }
    return CanonicalReconciliationDetail(
      page.transaction,
      page.group,
      actorId,
      principalId,
      page.canPropose,
      page.canReview,
      Map.unmodifiable({...related, ...page.related}),
    );
  }
}

class CanonicalReconciliationProposal {
  CanonicalReconciliationProposal._(this.values, this.identity);
  final Map<String, dynamic> values;
  final ReconciliationPaymentIdentity? identity;
  String get id => values['id'] as String;
  bool get snapshotAvailable => values['snapshot_available'] as bool;
  factory CanonicalReconciliationProposal.parse(
    Map<String, dynamic> data, {
    required String transactionId,
    required String evidenceId,
  }) {
    _keys(data, const {
      'id',
      'payment_id',
      'member_user_id',
      'member_public_id',
      'status',
      'version',
      'expected_payment_version',
      'evidence_id',
      'proposed_by_principal_id',
      'reviewed_by_principal_id',
      'created_at',
      'reviewed_at',
      'request_id',
      'reason',
      'review_reason',
      'snapshot_available',
      'payment_identity',
      'member_version',
      'membership_version',
      'group_version',
      'receiver_identity',
    });
    if (!const [
          'id',
          'payment_id',
          'member_user_id',
          'evidence_id',
          'proposed_by_principal_id',
          'request_id',
        ].every((key) => _id(data[key])) ||
        data['payment_id'] != transactionId ||
        data['evidence_id'] != evidenceId ||
        data['member_public_id'] is! String ||
        !RegExp(r'^[0-9]{6}$').hasMatch(data['member_public_id'] as String) ||
        !const {
          'proposed',
          'approved',
          'rejected',
          'cancelled',
        }.contains(data['status']) ||
        !_int(data['expected_payment_version'], minimum: 1) ||
        data['snapshot_available'] is! bool ||
        data['version'] != (data['status'] == 'proposed' ? 1 : 2)) {
      _invalid();
    }
    _date(data['created_at']);
    for (final key in const ['reason', 'review_reason']) {
      if (data[key] != null &&
          (data[key] is! String || (data[key] as String).length > 500)) {
        _invalid();
      }
    }
    if (const {'approved', 'rejected'}.contains(data['status'])) {
      if (!_id(data['reviewed_by_principal_id']) ||
          data['reviewed_by_principal_id'] ==
              data['proposed_by_principal_id']) {
        _invalid();
      }
      _date(data['reviewed_at']);
    } else if (data['reviewed_by_principal_id'] != null ||
        data['reviewed_at'] != null) {
      _invalid();
    }
    ReconciliationPaymentIdentity? identity;
    if (data['snapshot_available'] == true) {
      if (!const [
        'member_version',
        'membership_version',
        'group_version',
      ].every((key) => _int(data[key], minimum: 1))) {
        _invalid();
      }
      identity = ReconciliationPaymentIdentity.parse(
        _map(data['payment_identity']),
      );
      _receiver(_map(data['receiver_identity']));
      data = {
        ...data,
        'payment_identity': Map<String, dynamic>.unmodifiable(
          _map(data['payment_identity']),
        ),
        'receiver_identity': Map<String, dynamic>.unmodifiable(
          _map(data['receiver_identity']),
        ),
      };
    } else if (const [
      'member_version',
      'membership_version',
      'group_version',
      'payment_identity',
      'receiver_identity',
    ].any((key) => data[key] != null)) {
      _invalid();
    }
    return CanonicalReconciliationProposal._(Map.unmodifiable(data), identity);
  }

  bool currentFor(
    CanonicalReconciliationDetail detail,
    ReconciliationMember? member,
  ) =>
      member != null &&
      identity != null &&
      snapshotAvailable &&
      values['status'] == 'proposed' &&
      detail.eligibleForAttribution &&
      values['payment_id'] == detail.id &&
      values['member_user_id'] == member.id &&
      values['member_version'] == member.memberVersion &&
      values['membership_version'] == member.membershipVersion &&
      values['group_version'] == member.values['group_version'] &&
      values['group_version'] == detail.group['version'] &&
      values['expected_payment_version'] == detail.transaction['version'] &&
      member.groupId == detail.transaction['group_id'] &&
      identity!.sameAs(member.identity) &&
      member.identity.eligible &&
      _map(values['receiver_identity']).entries.every(
        (entry) => _map(detail.group['receiver'])[entry.key] == entry.value,
      );
}
