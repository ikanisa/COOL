const reconTransactionId = '11111111-1111-4111-8111-111111111111';
const reconMemberId = '22222222-2222-4222-8222-222222222222';
const reconGroupId = '33333333-3333-4333-8333-333333333333';
const reconPayeeId = '44444444-4444-4444-8444-444444444444';
const reconActorId = '55555555-5555-4555-8555-555555555555';
const reconProposerId = '66666666-6666-4666-8666-666666666666';
const reconProposalId = '77777777-7777-4777-8777-777777777777';
const reconRequestId = '88888888-8888-4888-8888-888888888888';
const reconReviewId = '99999999-9999-4999-8999-999999999999';
const reconAllocationId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const reconTime = 1791198000;
Map<String, dynamic> reconSourceFacts() => {
  'transaction_reference': '456258123456789012',
  'reference_payer_last3_known': true,
  'reference_payee_last3_known': true,
  'reference_source_fact_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'reference_random_source': 'crypto_get_random_values',
  'source_fact_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'source_link_basis': 'public_reference',
  'source_review_id': null,
  'source_kind': 'receiver',
  'parser_version': 'rw_momo_en_v1',
  'source_extraction_status': 'parsed',
  'source_body_sha256': 'a' * 64,
  'source_payload_sha256': 'b' * 64,
  'source_parsed_at': reconTime,
  'payer_name': 'Alice Umuhoza',
  'payer_phone': '+250788123456',
  'payer_masked_phone': null,
  'payer_last3': '456',
  'payer_last3_known': true,
  'payee_momo_number': null,
  'payee_momo_code': '0041258',
  'payee_momo_number_or_code': '0041258',
  'momo_transaction_reference': 'MOMO-123456',
  'momo_timestamp_local': '2026-10-05T13:00:00',
  'momo_timezone_offset': '+02:00',
  'timezone_known': true,
  'source_amount_rwf': 1000,
  'wallet_balance_rwf': 50000,
  'source_network': 'mtn_momo',
  'direction': 'incoming',
  'is_payment': true,
  'payer_source_match_status': 'unique_recorded_match',
  'payer_insights_status': 'available',
  'provider_confirmation': false,
  'settlement_status': 'not_asserted',
};
Map<String, dynamic> reconSession({
  String role = 'staff',
  List<String>? permissions,
}) => {
  'user': {
    'id': reconActorId,
    'email': 'operator@example.test',
    'role': role,
    'sessionId': 'recon-session',
    'permissions':
        permissions ??
        [
          'overview.read',
          'account.manage',
          'reconciliations.read',
          'reconciliations.propose',
          if (role != 'staff') 'reconciliations.review',
        ],
  },
  'expiresAt': DateTime.now()
      .toUtc()
      .add(const Duration(hours: 1))
      .toIso8601String(),
};
Map<String, dynamic> reconTransaction({
  String verification = 'confirmation_recorded',
}) => {
  'id': reconTransactionId,
  'group_id': reconGroupId,
  'payee_id': reconPayeeId,
  'network': 'mtn_momo',
  'provider_reference': 'MOMO-123456',
  'rail': 'rwanda_momo',
  'currency': 'RWF',
  'amount_rwf': 1000,
  'sender_phone_sha256': null,
  'verification_status': verification,
  'verified_by_admin_id': verification == 'pending' ? null : reconProposerId,
  'verified_at': verification == 'pending' ? null : reconTime,
  'observed_at': reconTime,
  'created_at': reconTime,
  'version': 2,
  'recorded_by_admin_id': reconProposerId,
  'group_title': 'Savings group',
  'group_status': 'active',
  'group_version': 1,
  'payee_name': 'Receiver',
  'payee_momo': '0041258',
  'payee_status': 'active',
  'payee_version': 1,
  'allocated_amount_rwf': 0,
  'unallocated_amount_rwf': 1000,
  'pending_proposals': 1,
  'allocation_status': 'unallocated',
  'settlement_status': 'not_asserted',
  ...reconSourceFacts(),
};
Map<String, dynamic> reconIdentity() => {
  'display_name': 'Alice Umuhoza',
  'momo_provider': 'mtn_momo',
  'momo_number': '0788123456',
  'momo_pay_code': '008001',
};
Map<String, dynamic> reconMember() => {
  'member_user_id': reconMemberId,
  'member_version': 1,
  'member_type': 'direct',
  'public_id': '000123',
  ...reconIdentity(),
  'membership_version': 1,
  'membership_role': 'member',
  'group_id': reconGroupId,
  'group_title': 'Savings group',
  'group_version': 1,
  'payment_identity': reconIdentity(),
};
Map<String, dynamic> reconProposal({String proposer = reconProposerId}) => {
  'id': reconProposalId,
  'transaction_id': reconTransactionId,
  'group_id': reconGroupId,
  'member_user_id': reconMemberId,
  'amount_rwf': 400,
  'transaction_version': 2,
  'member_version': 1,
  'membership_version': 1,
  'group_version': 1,
  'payee_version': 1,
  'proposed_by_admin_id': proposer,
  'operation_request_id': reconRequestId,
  'reason': 'Member identity reviewed.',
  'created_at': reconTime,
  'status': 'pending',
  'version': 1,
  'review_id': null,
  'allocation_id': null,
  'reviewed_by_admin_id': null,
  'review_reason': null,
  'reviewed_at': null,
  'public_id': '000123',
  'current_display_name': 'Alice Umuhoza',
  'payment_identity': reconIdentity(),
  'payee_identity': {
    'payee_id': reconPayeeId,
    'network': 'mtn_momo',
    'momo_number_or_code': '0041258',
  },
};
Map<String, dynamic> reconPage(
  List<Map<String, dynamic>> rows, {
  int? total,
  int offset = 0,
  int limit = 25,
}) => {
  'rows': rows,
  'total': total ?? rows.length,
  'limit': limit,
  'offset': offset,
  'next_offset': offset + rows.length < (total ?? rows.length)
      ? offset + rows.length
      : null,
};
Map<String, dynamic> reconDetail({
  bool review = false,
  bool propose = true,
  List<Map<String, dynamic>>? proposals,
  Map<String, dynamic>? transaction,
  String? relation,
  int offset = 0,
}) => {
  'resource_type': 'reconciliations',
  'resource': transaction ?? reconTransaction(),
  'current_actor_id': reconActorId,
  'can_propose': propose,
  'can_review': review,
  'related': {
    for (final kind
        in relation == null
            ? [
                'evidence',
                'verification_reviews',
                'allocations',
                'proposals',
                'journals',
              ]
            : [relation])
      kind: reconPage(
        kind == 'proposals' ? (proposals ?? []) : [],
        offset: offset,
      ),
  },
};
Map<String, dynamic> reconReceipt({String status = 'pending'}) => {
  'request_id': reconRequestId,
  'status': 'succeeded',
  'resource_type': 'reconciliation_proposals',
  'resource_id': reconProposalId,
  'transaction_id': reconTransactionId,
  'version': status == 'pending' ? 1 : 2,
  'proposal_status': status,
  if (status != 'pending') ...{
    'review_id': reconReviewId,
    'allocation_id': status == 'approved' ? reconAllocationId : null,
    'transaction_version': status == 'approved' ? 3 : 2,
    'settlement_status': 'not_asserted',
  },
};
