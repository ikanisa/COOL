import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_radius.dart';
import '../shared/components/admin_data_table.dart';
import '../shared/components/admin_empty_state.dart';
import '../shared/components/admin_loading_state.dart';
import '../shared/components/admin_page.dart';
import 'admin_account_api.dart';
import 'admin_pending_attempt_store.dart';
import 'admin_display_formatters.dart';
import 'admin_repository_base.dart';
import 'cloudflare_admin_repository.dart';
import 'cloudflare_admin_session.dart';
import 'cloudflare_admin_sms_api.dart';

part 'cloudflare_admin_operating_form.dart';
part 'cloudflare_admin_operating_requests.dart';
part 'cloudflare_admin_operating_detail.dart';
part 'cloudflare_admin_operating_fields.dart';
part 'cloudflare_admin_operating_confirmation.dart';

String operatingLabel(String value) => value
    .split('_')
    .map(
      (part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}',
    )
    .join(' ');

/// Exact whole RWF only. The upper bound also keeps web integer arithmetic exact.
int? parseOperatingRwf(String input, {bool allowZero = false}) {
  if (!RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(input.trim())) return null;
  final number = int.tryParse(input.trim());
  if (number == null ||
      number > 9007199254740991 ||
      number < (allowZero ? 0 : 1)) {
    return null;
  }
  return number;
}

class _OperatingPanel extends StatelessWidget {
  const _OperatingPanel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: context.collectColors.surfaceReadable,
      border: Border.all(color: context.collectColors.border),
      borderRadius: CollectRadius.cardBorder,
    ),
    child: child,
  );
}

class _OperatingMessage extends StatelessWidget {
  const _OperatingMessage(this.message, {this.error = false});
  final String message;
  final bool error;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        message,
        style: TextStyle(
          color: error ? Theme.of(context).colorScheme.error : null,
        ),
      ),
    ),
  );
}

String _safeOperatingError(Object error) => error is AdminAccountException
    ? error.message
    : error is FormatException
    ? 'The service response could not be verified. Refresh the record before continuing.'
    : 'The service could not be reached. Please try again.';

class _Field {
  const _Field(
    this.key,
    this.label, {
    this.required = true,
    this.choices,
    this.lookup,
    this.minimum = 1,
    this.maximum = 1000,
    this.money = false,
    this.optionalNull = false,
    this.multiline = false,
    this.hint,
  });
  final String key, label;
  final bool required, money, optionalNull, multiline;
  final List<String>? choices;
  final String? lookup, hint;
  final int minimum, maximum;
}

const _groupTypes = ['ikimina', 'sport', 'church', 'wedding', 'other'];
const _groupStatuses = ['draft', 'active', 'suspended', 'archived'];
const _userStatuses = ['invited', 'active', 'suspended', 'closed'];
const _memberRoles = [
  'owner',
  'admin',
  'receiver',
  'member',
  'contributor',
  'viewer',
];
const _memberStatuses = ['active', 'invited', 'removed', 'left'];
const _evidenceKinds = [
  'operator_observation',
  'payer_receipt',
  'receiver_statement',
  'provider_statement',
];

String _actionTitle(CloudflareOperation action) => switch (action) {
  CloudflareOperation.createGroup => 'Create group',
  CloudflareOperation.updateGroup => 'Edit group',
  CloudflareOperation.createUser => 'Create person',
  CloudflareOperation.updateUser => 'Edit person',
  CloudflareOperation.createMembership => 'Add group member',
  CloudflareOperation.updateMembership => 'Edit membership',
  CloudflareOperation.createPayee => 'Add payee',
  CloudflareOperation.updatePayee => 'Edit payee',
  CloudflareOperation.createAccount => 'Create ledger account',
  CloudflareOperation.updateAccount => 'Edit ledger account',
  CloudflareOperation.createTransaction => 'Record payment evidence',
  CloudflareOperation.addEvidence => 'Add evidence',
  CloudflareOperation.verifyTransaction => 'Review evidence',
  CloudflareOperation.allocateTransaction => 'Allocate payment',
  CloudflareOperation.createJournal => 'Create journal draft',
  CloudflareOperation.updateJournal => 'Replace journal draft',
  CloudflareOperation.postJournal => 'Post journal',
};

String _actionExplanation(CloudflareOperation action) => switch (action) {
  CloudflareOperation.updateGroup =>
    'Suspending a group is reversible. Archiving it is permanent. An active group requires an active owner and payee.',
  CloudflareOperation.updateUser =>
    'Suspending an account is reversible. Closing it is permanent. Transfer active-group ownership before suspending or closing its owner.',
  CloudflareOperation.updateMembership =>
    'An active group must retain its owner. Suspend the group before changing ownership, then reactivate it after assigning the new owner.',
  CloudflareOperation.createGroup =>
    'Create a private draft, or select its owner and recorded MoMo receiver to create an active private group. Only Admin can publish groups.',
  CloudflareOperation.createUser =>
    'Record an App or Direct person using their actual MoMo name and payment identity. App authentication is separate; Direct members do not need WhatsApp.',
  CloudflareOperation.createMembership =>
    'Assign an existing active App or Direct person to this group. Invited membership status does not send an email.',
  CloudflareOperation.createPayee =>
    'The payment route is permanent. Change a route by deactivating its payee and adding a new one.',
  CloudflareOperation.updatePayee =>
    'To deactivate the only active payee of an active group, first suspend the group. Update the payee status, then ensure a payee is active before reactivating the group. The MoMo route is permanent.',
  CloudflareOperation.createTransaction || CloudflareOperation.addEvidence =>
    'Record the reference and SHA-256 digest of an artifact you reviewed. This records your evidence claim; it does not send money or confirm provider settlement.',
  CloudflareOperation.verifyTransaction =>
    'A different administrator must review the evidence. Confirmation needs a receiver or provider statement and a reviewer different from the payment recorder.',
  CloudflareOperation.allocateTransaction =>
    'Allocate only confirmed funds. The saved amount and member cannot be changed.',
  CloudflareOperation.createJournal || CloudflareOperation.updateJournal =>
    'Use active accounts in one group. Enter equal positive debit and credit totals in whole Rwandan francs.',
  CloudflareOperation.postJournal =>
    'Posting is permanent. A different administrator from the draft creator and latest editor must post. Use a new correcting journal for later corrections.',
  _ =>
    'Changes use the current record version and are recorded with your reason.',
};

List<_Field> _fieldsFor(CloudflareOperation action) => switch (action) {
  CloudflareOperation.createGroup || CloudflareOperation.updateGroup => [
    const _Field('title', 'Group name', minimum: 3, maximum: 160),
    if (action == CloudflareOperation.createGroup)
      const _Field(
        'slug',
        'Group slug',
        minimum: 3,
        maximum: 100,
        hint: 'Lowercase letters, numbers and hyphens',
      ),
    const _Field('collection_type', 'Group type', choices: _groupTypes),
    const _Field(
      'description',
      'Description',
      required: false,
      multiline: true,
    ),
    const _Field(
      'category_subtype',
      'Category subtype',
      required: false,
      optionalNull: true,
      maximum: 120,
    ),
    const _Field(
      'purpose_label',
      'Purpose',
      required: false,
      optionalNull: true,
      maximum: 120,
    ),
    const _Field(
      'visibility',
      'Visibility',
      choices: ['private', 'public_approved'],
    ),
    const _Field(
      'is_platform_sponsored',
      'Platform sponsored',
      choices: ['false', 'true'],
    ),
    const _Field(
      'recurring_cadence',
      'Recurring cadence',
      required: false,
      optionalNull: true,
      choices: ['weekly', 'monthly', 'quarterly', 'annually'],
    ),
    const _Field(
      'suggested_amount_rwf',
      'Suggested amount (RWF)',
      required: false,
      optionalNull: true,
      money: true,
    ),
    _Field(
      'status',
      'Group status',
      choices: action == CloudflareOperation.createGroup
          ? const ['draft', 'active']
          : _groupStatuses,
    ),
  ],
  CloudflareOperation.createUser || CloudflareOperation.updateUser => const [
    _Field('display_name', 'Full name on MoMo', minimum: 2, maximum: 120),
    _Field('member_type', 'Member type', choices: ['app', 'direct']),
    _Field(
      'momo_provider',
      'MoMo provider',
      choices: ['mtn_momo', 'airtel_money', 'unknown'],
    ),
    _Field(
      'momo_number',
      'MoMo number',
      required: false,
      maximum: 10,
      hint: '078… or 072…',
    ),
    _Field(
      'momo_pay_code',
      'MoMo code (optional)',
      required: false,
      maximum: 9,
    ),
    _Field('email', 'Email', required: false, optionalNull: true, maximum: 254),
    _Field(
      'phone_e164',
      'WhatsApp login number',
      required: false,
      optionalNull: true,
      maximum: 13,
      hint: '+25078…',
    ),
    _Field('status', 'Account status', choices: _userStatuses),
  ],
  CloudflareOperation.createMembership ||
  CloudflareOperation.updateMembership => [
    if (action == CloudflareOperation.createMembership) ...const [
      _Field('group_id', 'Group', lookup: 'groups'),
      _Field('user_id', 'Member', lookup: 'users'),
    ],
    const _Field('role', 'Group role', choices: _memberRoles),
    const _Field('status', 'Membership status', choices: _memberStatuses),
  ],
  CloudflareOperation.createPayee || CloudflareOperation.updatePayee => [
    if (action == CloudflareOperation.createPayee)
      const _Field('group_id', 'Group', lookup: 'groups'),
    const _Field('label', 'Payee label', minimum: 2, maximum: 120),
    if (action == CloudflareOperation.createPayee) ...const [
      _Field('network', 'Network', choices: ['mtn_momo', 'airtel_money']),
      _Field(
        'momo_number_or_code',
        'MoMo number or merchant code',
        minimum: 4,
        maximum: 12,
        hint: '4–12 digits',
      ),
    ],
    const _Field('status', 'Payee status', choices: ['active', 'inactive']),
  ],
  CloudflareOperation.createAccount || CloudflareOperation.updateAccount => [
    if (action == CloudflareOperation.createAccount) ...const [
      _Field('group_id', 'Group', lookup: 'groups'),
      _Field('code', 'Account code', maximum: 40),
    ],
    const _Field('name', 'Account name', minimum: 2, maximum: 120),
    if (action == CloudflareOperation.createAccount) ...const [
      _Field(
        'account_type',
        'Account type',
        choices: ['asset', 'liability', 'equity', 'income', 'expense'],
      ),
      _Field('normal_side', 'Normal side', choices: ['debit', 'credit']),
    ],
    if (action == CloudflareOperation.updateAccount)
      const _Field('status', 'Account status', choices: ['active', 'closed']),
  ],
  CloudflareOperation.createTransaction => const [
    _Field('group_id', 'Group', lookup: 'groups'),
    _Field('payee_id', 'Payee', lookup: 'payees'),
    _Field('provider_reference', 'Provider reference', maximum: 160),
    _Field('amount_rwf', 'Payment amount (RWF)', money: true),
    _Field('observed_at', 'Observed at (UTC)', hint: '2026-10-04T12:00:00Z'),
  ],
  CloudflareOperation.addEvidence || CloudflareOperation.postJournal => [],
  CloudflareOperation.verifyTransaction => const [
    _Field('evidence_id', 'Evidence to review', lookup: 'evidence'),
    _Field(
      'outcome',
      'Review outcome',
      choices: [
        'confirmation_recorded',
        'rejection_recorded',
        'evidence_conflict',
      ],
    ),
  ],
  CloudflareOperation.allocateTransaction => const [
    _Field(
      'member_user_id',
      'Group member',
      required: false,
      optionalNull: true,
      lookup: 'members',
      hint: 'Leave empty for an unattributed group contribution',
    ),
    _Field('amount_rwf', 'Amount to allocate (RWF)', money: true),
  ],
  CloudflareOperation.createJournal || CloudflareOperation.updateJournal => [
    if (action == CloudflareOperation.createJournal)
      const _Field('group_id', 'Group', lookup: 'groups'),
    const _Field(
      'description',
      'Journal description',
      minimum: 3,
      maximum: 1000,
      multiline: true,
    ),
    if (action == CloudflareOperation.createJournal)
      const _Field(
        'allocation_id',
        'Payment allocation',
        required: false,
        optionalNull: true,
        lookup: 'allocations',
        hint: 'Open a transaction to create a draft for its allocation',
      ),
  ],
};

CloudflareAdminRepository _repository(WidgetRef ref) =>
    ref.read(adminRepositoryProvider) as CloudflareAdminRepository;

class CloudflareOperatingCreatePage extends StatelessWidget {
  const CloudflareOperatingCreatePage({
    required this.area,
    this.backPath,
    super.key,
  });
  final CloudflareCoreArea area;
  final String? backPath;
  @override
  Widget build(BuildContext context) => AdminPage(
    title: _actionTitle(area.createOperation),
    subtitle: _actionExplanation(area.createOperation),
    leading: IconButton(
      tooltip: 'Back to ${area.title}',
      onPressed: () => context.go(backPath ?? area.path),
      icon: const Icon(Icons.arrow_back),
    ),
    child: Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: CloudflareOperatingForm(operation: area.createOperation),
      ),
    ),
  );
}

class _JournalLine {
  _JournalLine({
    this.accountId,
    int debit = 0,
    int credit = 0,
    String description = '',
  }) : debit = TextEditingController(text: debit == 0 ? '' : '$debit'),
       credit = TextEditingController(text: credit == 0 ? '' : '$credit'),
       description = TextEditingController(text: description);
  String? accountId;
  final TextEditingController debit, credit, description;
  void dispose() {
    debit.dispose();
    credit.dispose();
    description.dispose();
  }
}

String? _payeeGroupPath(CloudflareOperatingDetail? detail) {
  final id = detail?.resource['group_id'];
  if (id is! String ||
      !RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        caseSensitive: false,
      ).hasMatch(id)) {
    return null;
  }
  return '/admin/groups/$id';
}

class _PayeeGroupGuidance extends StatelessWidget {
  const _PayeeGroupGuidance({
    required this.detail,
    required this.canReadGroup,
    required this.onOpen,
  });
  final CloudflareOperatingDetail? detail;
  final bool canReadGroup;
  final VoidCallback? onOpen;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _OperatingMessage(_actionExplanation(CloudflareOperation.updatePayee)),
      if (canReadGroup && _payeeGroupPath(detail) != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: onOpen, child: const Text('Open group')),
        ),
    ],
  );
}
