part of 'cloudflare_admin_operating_pages.dart';

const _canonicalWritableOperations = {
  CloudflareOperation.createGroup,
  CloudflareOperation.updateGroup,
  CloudflareOperation.createUser,
  CloudflareOperation.updateUser,
  CloudflareOperation.createMembership,
  CloudflareOperation.updateMembership,
  CloudflareOperation.updatePayee,
  CloudflareOperation.createTransaction,
  CloudflareOperation.reverseTransaction,
};

List<_Field> _canonicalFieldsFor(
  CloudflareOperation operation,
) => switch (operation) {
  CloudflareOperation.createGroup || CloudflareOperation.updateGroup => [
    const _Field('title', 'Group name', minimum: 3, maximum: 160),
    if (operation == CloudflareOperation.createGroup)
      const _Field(
        'slug',
        'Group slug',
        minimum: 3,
        maximum: 100,
        hint: 'Lowercase letters, numbers and hyphens',
      ),
    const _Field('collection_type', 'Group type', choices: _groupTypes),
    const _Field(
      'visibility',
      'Visibility',
      choices: ['private', 'public_approved'],
    ),
    const _Field(
      'description',
      'Description',
      required: false,
      multiline: true,
      maximum: 2000,
    ),
    const _Field(
      'purpose_label',
      'Purpose',
      required: false,
      optionalNull: true,
      maximum: 120,
    ),
    _Field(
      'status',
      'Group status',
      choices: operation == CloudflareOperation.createGroup
          ? const ['active']
          : const ['active', 'suspended', 'archived'],
    ),
  ],
  CloudflareOperation.createUser || CloudflareOperation.updateUser => [
    const _Field(
      'display_name',
      'Recorded full name',
      minimum: 2,
      maximum: 120,
    ),
    if (operation == CloudflareOperation.createUser)
      const _Field('member_type', 'Member type', choices: ['app', 'direct']),
    const _Field(
      'momo_provider',
      'MoMo provider',
      choices: ['mtn_momo', 'airtel_money'],
    ),
    const _Field(
      'momo_number',
      'MoMo number',
      required: false,
      maximum: 10,
      hint: '078… or 072…',
    ),
    const _Field(
      'momo_pay_code',
      'MoMo code (optional)',
      required: false,
      maximum: 9,
    ),
    if (operation == CloudflareOperation.createUser) ...const [
      _Field(
        'email',
        'Email',
        required: false,
        optionalNull: true,
        maximum: 254,
      ),
      _Field(
        'phone_e164',
        'WhatsApp login number',
        required: false,
        optionalNull: true,
        maximum: 13,
        hint: '+25078…',
      ),
    ],
    const _Field('status', 'Account status', choices: ['active', 'suspended']),
  ],
  CloudflareOperation.createMembership ||
  CloudflareOperation.updateMembership => [
    if (operation == CloudflareOperation.createMembership) ...const [
      _Field('group_id', 'Group', lookup: 'groups'),
      _Field('user_id', 'Member', lookup: 'users'),
    ],
    const _Field('role', 'Group role', choices: ['member', 'admin']),
    const _Field(
      'status',
      'Membership status',
      choices: ['active', 'removed', 'left'],
    ),
  ],
  CloudflareOperation.updatePayee => const [
    _Field('label', 'Recorded receiver name', minimum: 2, maximum: 120),
    _Field('network', 'MoMo provider', choices: ['mtn_momo', 'airtel_money']),
    _Field(
      'momo_number_or_code',
      'Receiver MoMo number',
      minimum: 10,
      maximum: 13,
      hint: '078… or +25078…',
    ),
    _Field('status', 'Receiver status', choices: ['active']),
  ],
  CloudflareOperation.createTransaction => const [
    _Field('group_id', 'Group', lookup: 'groups'),
    _Field('payee_id', 'Recorded receiver', lookup: 'payees'),
    _Field(
      'provider_reference',
      'Evidence reference',
      required: false,
      optionalNull: true,
      maximum: 200,
    ),
    _Field('amount_rwf', 'Recorded amount (RWF)', money: true),
    _Field('observed_at', 'Observed at (UTC)', hint: '2026-10-15T12:00:00Z'),
    _Field('payer_name', 'Recorded payer name', required: false, maximum: 100),
  ],
  _ => [],
};

String _canonicalActionExplanation(
  CloudflareOperation operation,
) => switch (operation) {
  CloudflareOperation.createGroup =>
    'Select the group owner and recorded MoMo receiver. Groups are private by default; only authorized Admins can publish a sponsored public group. This records payment details without confirming provider settlement or identity.',
  CloudflareOperation.updateGroup =>
    'Changes use the current group version. Publishing retains its recorded owner and receiver and permanently locks the receiver. Public groups are platform sponsored; this does not confirm provider settlement or identity.',
  CloudflareOperation.updatePayee =>
    'Changing the recorded receiver cancels pending payment instructions. Earlier payment evidence keeps its original receiver.',
  CloudflareOperation.createTransaction =>
    'Retain the exact evidence text and recorded amount. This does not send money or confirm provider settlement. Member attribution requires independent reconciliation.',
  CloudflareOperation.reverseTransaction =>
    'Record an equal, opposite contribution entry and preserve the original evidence and history. This does not refund or move provider funds.',
  CloudflareOperation.updateUser =>
    'Update recorded profile information or suspend access. Verified sign-in identifiers require a separate verification workflow.',
  CloudflareOperation.createMembership ||
  CloudflareOperation.updateMembership =>
    'Assign an active App or Direct person as a member or group administrator. The active owner cannot be removed here.',
  _ => _actionExplanation(operation),
};

Map<String, dynamic> _operatingRecoveryIntent(Map<String, dynamic> body) {
  final evidence = body['evidence'];
  if (evidence is! String) return body;
  return {
    ...body,
    'evidence': {
      'kind': 'retained_operator_text',
      'reference': 'Exact text must be re-entered to retry after reloading',
      'sha256': sha256.convert(utf8.encode(evidence)).toString(),
    },
  };
}
