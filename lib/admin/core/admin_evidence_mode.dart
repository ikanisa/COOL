import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/phone_normalizer.dart';
import 'admin_auth_guard.dart';
import 'admin_repository_base.dart';
import 'admin_review_credentials.dart';

export 'admin_review_credentials.dart';

List<Override> adminEvidenceOverrides() {
  if (!adminPwaEvidenceMode) return const [];
  return [
    adminAuthGuardProvider.overrideWithValue(
      const AdminAuthGuard(isAuthorized: true),
    ),
    adminIdentityProvider.overrideWith((ref) async => _evidenceAdmin),
    adminRepositoryProvider.overrideWithValue(const AdminEvidenceRepository()),
  ];
}

const _evidenceAdmin = AdminIdentity(
  userId: '00000000-0000-0000-0000-00000000e001',
  displayName: 'Collect evidence admin',
  phoneMasked: '+250***6816',
  roles: ['admin'],
  permissions: [
    'overview.read',
    'public_requests.read',
    'collections.read',
    'collections.moderate',
    'users.read',
    'payments.read',
    'payments.allocate',
    'payment_events.read',
    'ledger.read',
    'receivers.read',
    'receivers.manage',
    'sms.metadata.read',
    'sms.raw.read',
    'sms.raw.reveal',
    'bank_details.read',
    'bank_details.propose',
    'bank_details.approve',
    'bank_transactions.read',
    'bank_evidence.read',
    'bank_evidence.raw.reveal',
    'bank_reconciliation.read',
    'bank_reconciliation.manage',
    'bank_allocations.propose',
    'bank_allocations.approve',
    'notifications.read',
    'notifications.manage',
    'audit.read',
    'feature_flags.read',
    'feature_flags.manage',
    'settings.read',
    'system_health.read',
    'admin_users.read',
    'admin_users.manage',
  ],
);

class AdminEvidenceRepository extends AdminRepositoryBase {
  const AdminEvidenceRepository();

  @override
  Future<Map<String, dynamic>> action(
    String rpcName,
    Map<String, dynamic> params,
  ) async {
    if (rpcName == 'admin_get_whatsapp_approval') {
      final granted = '${params['p_user_id']}'.startsWith('admin-user-');
      return {
        'user_id': params['p_user_id'],
        'phone_masked': '+***6816',
        'status': granted ? 'approved' : 'not_approved',
        'approved': granted,
        'role_granted': granted,
        'admin_access': granted,
      };
    }
    if (rpcName == 'admin_reveal_raw_bank_evidence') {
      return {
        'sender': 'Bank evidence',
        'body': 'Raw bank evidence hidden in route evidence.',
      };
    }
    if (rpcName == 'admin_reveal_raw_sms') {
      return {
        'message':
            'You have received RWF 25,000 from Evidence payer. Transaction ID 681601.',
      };
    }
    return {'status': 'queued'};
  }

  @override
  Future<AdminIdentity?> currentIdentity() async => _evidenceAdmin;

  @override
  Future<Map<String, dynamic>> detail(String rpcName, String id) async {
    const createdAt = '2026-08-20T06:30:00Z';
    return switch (rpcName) {
      'admin_get_collect_transaction' => {
        'id': id,
        'transaction_id': '681601',
        'payment_route': id.startsWith('diaspora:')
            ? 'Diaspora account'
            : 'Rwanda MoMo',
        'raw_sms_id': id.startsWith('momo:')
            ? '00000000-0000-0000-0000-000000006816'
            : null,
        'sms_sender': id.startsWith('momo:') ? 'MTN MoMo' : null,
        'sender_masked': id.startsWith('momo:') ? '078•••4321' : null,
        'parse_status': 'parsed',
        'sender_name': 'Evidence payer',
        'network': id.startsWith('momo:') ? 'MTN MoMo' : 'Diaspora account',
        'reference': 'COLLECT-AB1234-6816',
        'amount': id.startsWith('momo:') ? 'RWF 25,000' : 'EUR 24.50',
        'payee': id.startsWith('momo:')
            ? 'St Michael group payee ••6816'
            : 'Collect diaspora payee ••6816',
        'group_name': 'St Michael building fund',
        'allocation_status': 'allocated',
        'status': 'allocated',
        'received_at': createdAt,
      },
      'admin_get_payment_intent' => {
        'id': id,
        'collection_id': 'collection-1',
        'contributor_user_id': 'member-evidence-1',
        'contribution_code': 'COL-RW-6816',
        'expected_amount_rwf': 25000,
        'reported_transaction_id': null,
        'status': 'pending',
        'created_at': createdAt,
        'expires_at': '2026-08-20T06:45:00Z',
      },
      'admin_get_payment' => {
        'id': id,
        'collection_id': 'collection-1',
        'payment_intent_id': 'momo-intent-1',
        'transaction_id': '123456789012',
        'source': 'momo_sms',
        'amount_rwf': 25000,
        'currency': 'RWF',
        'status': 'posted',
        'created_at': createdAt,
      },
      'admin_get_payment_event' => {
        'id': id,
        'provider': 'mtn_momo',
        'transaction_id': '123456789012',
        'sender_phone_masked': '+250***4321',
        'receiver_phone_masked': '+250***6816',
        'amount_rwf': 25000,
        'currency': 'RWF',
        'parse_status': 'parsed',
        'allocation_status': 'needs_review',
        'received_at': createdAt,
      },
      'admin_get_receiver' => {
        'id': id,
        'collection_id': 'collection-1',
        'receiver_user_id': 'member-evidence-1',
        'momo_number_masked': '+250***6816',
        'network': 'mtn_momo',
        'label': 'Primary MoMo receiver',
        'is_active': true,
        'created_at': createdAt,
      },
      'admin_get_sms_metadata' => {
        'id': id,
        'sender_masked': 'MTN MoMo',
        'body_hash': 'sha256:••••6816',
        'parse_status': 'parsed',
        'received_at': createdAt,
        'raw_body': 'Hidden; audited permission required',
      },
      'admin_get_bank_destination' => {
        'id': id,
        'version': 2,
        'beneficiary_name': 'Collect Europe Operations',
        'iban_masked': 'LT•• •••• •••• 6816',
        'bic': 'REVOLT21',
        'bank_name': 'Revolut Bank UAB',
        'currency': 'EUR',
        'supports_instant': true,
        'status': 'active',
        'approved_at': createdAt,
      },
      'admin_get_bank_destination_change_request' => {
        'id': id,
        'beneficiary_name': 'Collect Europe Operations',
        'iban_masked': 'LT•• •••• •••• 6816',
        'bic': 'REVOLT21',
        'bank_name': 'Revolut Bank UAB',
        'supports_instant': true,
        'reason': 'Activate verified production beneficiary details',
        'proposed_by': 'Maker A.',
        'reviewed_by': 'Checker B.',
        'status': 'pending',
      },
      'admin_get_bank_transfer_intent' => {
        'id': id,
        'transfer_reference': 'COLLECT-AB1234-6816',
        'collection_title': 'St Michael building fund',
        'contributor_user_id': 'member-evidence-1',
        'amount_minor': 24500,
        'currency': 'EUR',
        'status': 'received_unreconciled',
        'expires_at': '2026-08-27T06:30:00Z',
        'evidence_received_at': createdAt,
        'reconciled_at': null,
      },
      'admin_get_bank_transaction' => {
        'id': id,
        'bank_transaction_id': 'REV-20260820-6816',
        'end_to_end_id': 'E2E-6816-20260820',
        'transfer_reference': 'COLLECT-AB1234-6816',
        'payer_name': 'Masked payer ••4321',
        'amount_minor': 24500,
        'currency': 'EUR',
        'value_date': '2026-08-20',
        'status': 'received',
      },
      'admin_get_bank_evidence' => {
        'id': id,
        'channel': 'email',
        'sender': 'bank-notification@••••',
        'transfer_reference': 'COLLECT-AB1234-6816',
        'bank_transaction_id': 'REV-20260820-6816',
        'amount_minor': 24500,
        'currency': 'EUR',
        'confidence': 'exact',
        'parse_status': 'parsed',
        'allocation_status': 'needs_review',
        'received_at': createdAt,
      },
      'admin_get_reconciliation_run' => {
        'id': id,
        'run_date': '2026-08-20',
        'currency': 'EUR',
        'statement_line_count': 18,
        'matched_count': 16,
        'exception_count': 2,
        'matched_total_minor': 184250,
        'status': 'completed_with_exceptions',
        'completed_at': createdAt,
      },
      'admin_get_reconciliation_exception' => {
        'id': id,
        'exception_type': 'unmatched_statement_line',
        'bank_transaction_id': 'bank-transaction-evidence-1',
        'bank_transfer_intent_id': null,
        'details': 'Reference requires controlled operator review.',
        'status': 'open',
        'resolution_note': null,
        'resolved_at': null,
      },
      'admin_get_bank_allocation_request' => {
        'id': id,
        'bank_transaction_id': 'bank-transaction-evidence-1',
        'bank_transfer_intent_id': 'bank-intent-evidence-1',
        'reason': 'Exact EUR amount and member reference verified',
        'proposed_by': 'Maker A.',
        'reviewed_by': null,
        'status': 'pending',
        'created_at': createdAt,
      },
      'admin_get_journal_entry' => {
        'id': id,
        'entry_type': 'bank_receipt',
        'currency': 'EUR',
        'total_debit_minor': 24500,
        'total_credit_minor': 24500,
        'reference': 'COLLECT-AB1234-6816',
        'posted_at': createdAt,
        'status': 'posted',
      },
      'admin_get_collection' => {
        'id': id,
        'name': id == 'collection-1'
            ? 'Buri Munsi'
            : id == 'collection-2'
            ? 'Gikundiro'
            : 'Private community group',
        'title': id == 'collection-1'
            ? 'Buri Munsi'
            : id == 'collection-2'
            ? 'Gikundiro'
            : 'Private community group',
        'public_id': 'AB1234',
        'visibility': id == 'collection-1' || id == 'collection-2'
            ? 'public_approved'
            : 'private',
        'public_status': id == 'collection-1' || id == 'collection-2'
            ? 'public_approved'
            : 'private',
        'status': 'active',
        'is_platform_sponsored': id == 'collection-1' || id == 'collection-2',
        'description': id == 'collection-2'
            ? 'Official Rayon Sports supporter group open to everyone.'
            : 'Group savings open to everyone.',
        'collection_type': id == 'collection-2' ? 'sport' : 'ikimina',
        'category_subtype': id == 'collection-2'
            ? 'team_support'
            : 'group_savings',
        'purpose_label': id == 'collection-2'
            ? 'Team support'
            : 'Group savings',
        'receiver_display_label': id == 'collection-2'
            ? 'Rayon Sports FC'
            : 'IKANISA LTD',
        'receiver_momo_code': id == 'collection-2' ? '008000' : '41258',
        'receiver_network': 'mtn_momo',
        'member_count': id == 'collection-2' ? 12 : 11,
        'total_raised': 'RWF 1,842,500',
        'created_at': createdAt,
      },
      'admin_get_user' => {
        'id': id,
        'collect_id': 'CM6816',
        'display_name': 'Evidence member',
        'phone_masked': '+250***4321',
        'country_code': 'RW',
        'momo_masked': '078•••••11',
        'payment_profile': '078•••••11',
        'active_groups': id == 'user-1' ? 0 : 2,
        'status': 'active',
        'created_at': createdAt,
      },
      'admin_get_admin_user' => {
        'id': id,
        'public_id': 'CA6816',
        'phone_masked': '+250***6816',
        'status': 'active',
        'active_roles': ['admin'],
        'created_at': createdAt,
      },
      'admin_get_notification' => {
        'id': id,
        'type': 'bank_contribution_reconciled',
        'title': 'Bank contribution reconciled',
        'collect_id': 'AB1234',
        'status': 'failed',
        'delivery_statuses': 'failed: 1',
        'retryable_count': 1,
        'last_error_code': 'provider_unavailable',
        'created_at': createdAt,
      },
      'admin_system_health' => {
        'id': id,
        'database': 'reachable',
        'auth': 'authenticated',
        'bank_evidence_pending': 2,
        'reconciliation_exceptions': 3,
        'allocation_approvals_pending': 4,
        'queued_notifications': 4,
        'processing_notifications': 1,
        'failed_notifications': 2,
        'checked_at': createdAt,
      },
      _ => {'id': id, 'status': 'active', 'created_at': createdAt},
    };
  }

  @override
  Future<AdminListResult> list(
    String rpcName, {
    String? search,
    String? status,
    int? limit,
    int? offset,
    String? sortBy,
    String? countryCode,
  }) async {
    final allRows = [
      for (var index = 1; index <= _rowCount(rpcName); index += 1)
        AdminTableRowData(
          id: _rowId(rpcName, index),
          title: _rowTitle(rpcName, index),
          subtitle: _rowSubtitle(rpcName, index),
          status: _rowStatus(rpcName, index),
          amount: _rowAmount(rpcName, index),
          createdAt: _rowCreatedAt(index),
          extra: {
            'sender_masked': _maskedPayer(index),
            'reference': 'COLLECT-AB${1200 + index}-${6800 + index}',
            'age': _rowAge(index),
            'allocated_to': 'St Michael building fund',
            'operator': index.isEven ? 'Checker B.' : 'Maker A.',
            'rail': rpcName == 'admin_list_collect_payees'
                ? 'rw_momo'
                : index.isEven
                ? 'diaspora_account'
                : 'rw_momo',
            'event_id': '00000000-0000-0000-0000-00000000681$index',
            'transaction_id': '00000000-0000-0000-0000-00000000781$index',
            'collection_id': rpcName == 'admin_list_platform_payee_candidates'
                ? _rowId(rpcName, index)
                : '00000000-0000-0000-0000-00000000881$index',
            'payment_intent_id': '00000000-0000-0000-0000-00000000981$index',
            ..._rowCountryExtra(rpcName, index),
            ..._rowExtra(rpcName, index),
          },
        ),
    ];
    final normalizedSearch = search?.trim().toLowerCase() ?? '';
    final normalizedStatus = status?.trim().toLowerCase() ?? '';
    final normalizedCountry = countryCode?.trim().toUpperCase() ?? '';
    final filtered = allRows
        .where((row) {
          final matchesSearch =
              normalizedSearch.isEmpty ||
              row.title.toLowerCase().contains(normalizedSearch) ||
              row.subtitle.toLowerCase().contains(normalizedSearch) ||
              row.id.toLowerCase().contains(normalizedSearch);
          final matchesStatus =
              normalizedStatus.isEmpty ||
              row.status.toLowerCase() == normalizedStatus;
          final rowCountry = '${row.extra['country_code'] ?? ''}'
              .trim()
              .toUpperCase();
          final matchesCountry = switch (normalizedCountry) {
            '' => true,
            'OTHER' =>
              rowCountry.isNotEmpty && rowCountry != 'RW' && rowCountry != 'MT',
            _ => rowCountry == normalizedCountry,
          };
          return matchesSearch && matchesStatus && matchesCountry;
        })
        .toList(growable: false);
    final start = (offset ?? 0).clamp(0, filtered.length);
    final end = (start + (limit ?? 25)).clamp(start, filtered.length);
    return AdminListResult(
      total: filtered.length,
      rows: filtered.sublist(start, end),
    );
  }

  @override
  Future<List<AdminMetric>> overviewMetrics() async => const [
    AdminMetric(
      label: 'Open reconciliations',
      value: '3',
      status: 'needs_review',
    ),
    AdminMetric(
      label: 'Unallocated transactions',
      value: '2',
      status: 'pending',
    ),
    AdminMetric(label: 'Balanced ledgers', value: '10', status: 'active'),
    AdminMetric(label: 'Active payees', value: '2', status: 'active'),
  ];

  @override
  Future<AdminQueueSla?> queueSla(String queueKey) async => const AdminQueueSla(
    target: '< 1 business day',
    owner: 'Collect operations',
    escalation: 'Escalate unresolved allocations to the platform owner',
  );

  @override
  Future<void> sendOtp({required String phone}) async {
    _requireReviewPhone(phone);
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<AdminIdentity?> verifyOtp({
    required String phone,
    required String otp,
  }) async {
    _requireReviewPhone(phone);
    if (otp.trim() != adminEvidenceOtp) {
      throw const FormatException('Developer OTP token is invalid.');
    }
    return _evidenceAdmin;
  }
}

void _requireReviewPhone(String phone) {
  final normalized = PhoneNormalizer.normalizeInternational(phone);
  if (normalized != adminEvidenceWhatsAppPhone) {
    throw const FormatException(
      'Use the dedicated developer admin WhatsApp phone.',
    );
  }
}

int _rowCount(String rpcName) => switch (rpcName) {
  'admin_list_collect_payees' => 2,
  'admin_list_platform_payee_candidates' => 1,
  'admin_list_collect_transactions' => 12,
  'admin_list_collect_reconciliations' => 4,
  'admin_list_collect_ledgers' => 10,
  'admin_list_members' => 21,
  'admin_list_non_member_users' => 4,
  'admin_list_payment_intents' => 12,
  'admin_list_payments' => 10,
  'admin_list_payment_events' => 8,
  'admin_list_allocations' => 8,
  'admin_list_unallocated' => 3,
  'admin_list_ledger' => 10,
  'admin_list_receivers' => 6,
  'admin_list_sms_metadata' => 8,
  'admin_list_bank_destinations' => 2,
  'admin_list_bank_destination_change_requests' => 4,
  'admin_list_bank_transfer_intents' => 12,
  'admin_list_bank_transactions' => 8,
  'admin_list_bank_evidence' => 8,
  'admin_list_reconciliation_runs' => 7,
  'admin_list_reconciliation_exceptions' => 3,
  'admin_list_bank_allocation_requests' => 4,
  'admin_list_journal_entries' => 10,
  'admin_list_notifications' => 4,
  'admin_list_audit_logs' => 8,
  'admin_list_settings' => 4,
  'admin_list_feature_flags' => 4,
  'admin_list_admin_users' => 2,
  _ => 30,
};

String _rowId(String rpcName, int index) => switch (rpcName) {
  'admin_list_collect_payees' =>
    'momo:00000000-0000-0000-0000-00000000${index == 1 ? '4125' : '8000'}',
  'admin_list_platform_payee_candidates' =>
    '00000000-0000-0000-0000-00000000c001',
  'admin_list_collect_transactions' =>
    '${index.isEven ? 'diaspora' : 'momo'}:transaction-$index',
  'admin_list_collect_reconciliations' =>
    '${index.isEven ? 'diaspora' : 'momo'}:exception-$index',
  'admin_list_collect_ledgers' => 'ledger-$index',
  'admin_list_users' ||
  'admin_list_members' ||
  'admin_list_non_member_users' => 'user-$index',
  'admin_list_collections' => 'collection-$index',
  'admin_list_payment_intents' => 'momo-intent-$index',
  'admin_list_payments' => 'momo-transaction-$index',
  'admin_list_payment_events' => 'momo-event-$index',
  'admin_list_allocations' => 'momo-allocation-$index',
  'admin_list_unallocated' => 'momo-exception-$index',
  'admin_list_ledger' => 'momo-ledger-$index',
  'admin_list_receivers' => 'momo-receiver-$index',
  'admin_list_sms_metadata' => 'momo-sms-$index',
  'admin_list_bank_destinations' => 'bank-destination-$index',
  'admin_list_bank_destination_change_requests' => 'destination-request-$index',
  'admin_list_bank_transfer_intents' => 'bank-intent-$index',
  'admin_list_bank_transactions' => 'bank-transaction-$index',
  'admin_list_bank_evidence' => 'bank-evidence-$index',
  'admin_list_reconciliation_runs' => 'reconciliation-run-$index',
  'admin_list_reconciliation_exceptions' => 'reconciliation-exception-$index',
  'admin_list_bank_allocation_requests' => 'allocation-request-$index',
  'admin_list_journal_entries' => 'journal-entry-$index',
  'admin_list_admin_users' => 'admin-user-$index',
  'admin_list_notifications' => 'notification-$index',
  _ => 'admin-row-$index',
};

String _rowTitle(String rpcName, int index) => switch (rpcName) {
  'admin_list_collect_payees' => index == 1 ? 'IKANISA LTD' : 'Rayon Sports FC',
  'admin_list_platform_payee_candidates' => 'Sponsored group awaiting payee',
  'admin_list_collect_transactions' => 'Transaction ${681600 + index}',
  'admin_list_collect_reconciliations' =>
    'Unallocated transaction ${681600 + index}',
  'admin_list_collect_ledgers' => 'Ledger entry ${681600 + index}',
  'admin_list_users' ||
  'admin_list_members' ||
  'admin_list_non_member_users' => 'Collect ID ${38490 + index}',
  'admin_list_collections' => switch (index) {
    1 => 'Buri Munsi',
    2 => 'Gikundiro',
    _ => 'Verified group $index',
  },
  'admin_list_payment_intents' => 'MoMo intent COL-RW-${6800 + index}',
  'admin_list_payments' => 'MoMo transaction ${681600 + index}',
  'admin_list_payment_events' => 'Parsed MoMo receipt ${681600 + index}',
  'admin_list_allocations' => 'MoMo allocation ${681600 + index}',
  'admin_list_unallocated' => 'Unallocated MoMo receipt ${681600 + index}',
  'admin_list_ledger' => 'Rwanda ledger posting ${681600 + index}',
  'admin_list_receivers' => 'MoMo receiver ••${6800 + index}',
  'admin_list_sms_metadata' => 'Receipt SMS metadata ${681600 + index}',
  'admin_list_bank_destinations' => 'EUR beneficiary version $index',
  'admin_list_bank_destination_change_requests' =>
    'Beneficiary approval request $index',
  'admin_list_bank_transfer_intents' => 'Transfer request ${1200 + index}',
  'admin_list_bank_transactions' => 'Incoming bank transfer ${6800 + index}',
  'admin_list_bank_evidence' => 'Bank evidence event ${6800 + index}',
  'admin_list_reconciliation_runs' =>
    'Daily reconciliation 2026-08-${21 - index}',
  'admin_list_reconciliation_exceptions' =>
    'Unmatched statement line ${6800 + index}',
  'admin_list_bank_allocation_requests' =>
    'Manual allocation approval ${6800 + index}',
  'admin_list_journal_entries' => 'Balanced bank receipt ${6800 + index}',
  'admin_list_admin_users' => '+250 78•••${6800 + index}',
  'admin_list_notifications' => 'Bank contribution reconciled',
  'admin_list_audit_logs' => switch (index % 4) {
    1 => 'Payee activated',
    2 => 'Allocation approved',
    3 => 'Group updated',
    _ => 'Admin role updated',
  },
  'admin_list_settings' => switch (index) {
    1 => 'Rwanda MoMo receipts',
    2 => 'Diaspora bank transfers',
    3 => 'Reconciliation window',
    _ => 'Notification retries',
  },
  'admin_list_feature_flags' => switch (index) {
    1 => 'Diaspora bank transfers',
    2 => 'Android private groups',
    3 => 'WhatsApp onboarding',
    _ => 'Notification retries',
  },
  _ => 'Operational record $index',
};

String _rowSubtitle(String rpcName, int index) => switch (rpcName) {
  'admin_list_collect_payees' =>
    index == 1
        ? 'Buri Munsi • MTN MoMo • code 41258 • route locked'
        : 'Gikundiro • MTN MoMo • code 008000 • route locked',
  'admin_list_platform_payee_candidates' =>
    'Platform-sponsored public group with no payee route',
  'admin_list_collect_transactions' =>
    'Received message • parsed payer • linked group payee',
  'admin_list_collect_reconciliations' =>
    'Payment received • payee allocation required',
  'admin_list_collect_ledgers' =>
    'Debit payment clearing • credit group payable',
  'admin_list_users' || 'admin_list_members' || 'admin_list_non_member_users' =>
    'WhatsApp ${_evidenceWhatsAppMasked(_rowCountryCode(rpcName, index), index)}',
  'admin_list_collections' => switch (index) {
    1 => 'Platform-sponsored savings group',
    2 => 'Platform-sponsored Rayon Sports group',
    _ => 'Member-created private group',
  },
  'admin_list_payment_intents' => 'Pending Rwanda payer intent and expiry',
  'admin_list_payments' => 'Posted RWF MoMo contribution',
  'admin_list_payment_events' => 'Deterministically parsed receipt metadata',
  'admin_list_allocations' => 'Receipt-to-member and group allocation',
  'admin_list_unallocated' => 'Receipt requiring controlled review',
  'admin_list_ledger' => 'Balanced immutable RWF posting',
  'admin_list_receivers' => 'Consented group receiver with masked number',
  'admin_list_sms_metadata' => 'Raw body hidden behind audited reveal',
  'admin_list_bank_destinations' => 'Approved beneficiary and IBAN version',
  'admin_list_bank_destination_change_requests' =>
    'Independent maker-checker review required',
  'admin_list_bank_transfer_intents' => 'Exact EUR reference lifecycle',
  'admin_list_bank_transactions' => 'Canonical incoming bank receipt',
  'admin_list_bank_evidence' => 'Protected SMS or email evidence metadata',
  'admin_list_reconciliation_runs' => 'Daily statement matching and close',
  'admin_list_reconciliation_exceptions' =>
    'Controlled reconciliation resolution required',
  'admin_list_bank_allocation_requests' =>
    'Exact amount and currency maker-checker request',
  'admin_list_journal_entries' => 'Immutable balanced debit and credit entry',
  'admin_list_admin_users' => '',
  'admin_list_notifications' => 'Collect ID AB1234 • 1 delivery',
  'admin_list_audit_logs' => switch (index % 3) {
    1 => 'Maker A. • Buri Munsi',
    2 => 'Checker B. • COLLECT-AB1202-6802',
    _ => 'Admin • Reason recorded',
  },
  'admin_list_settings' => switch (index) {
    1 => 'MTN MoMo parser active',
    2 => 'EUR transfer intake active',
    3 => '1 business day',
    _ => '3 attempts',
  },
  'admin_list_feature_flags' => 'Production',
  _ => 'Admin evidence row with masked test data',
};

String _rowStatus(String rpcName, int index) => switch (rpcName) {
  'admin_list_collect_payees' => 'active',
  'admin_list_platform_payee_candidates' => 'eligible',
  'admin_list_collect_transactions' =>
    index % 3 == 0 ? 'needs_review' : 'allocated',
  'admin_list_collect_reconciliations' =>
    index.isEven ? 'ambiguous' : 'unallocated',
  'admin_list_collect_ledgers' => 'balanced',
  'admin_list_collections' => switch (index) {
    1 || 2 => 'public_approved',
    _ when index % 9 == 0 => 'archived',
    _ => 'private',
  },
  'admin_list_users' ||
  'admin_list_members' => index == 10 ? 'admin' : 'active',
  'admin_list_non_member_users' => index == 4 ? 'admin' : 'registered',
  'admin_list_payment_intents' => index.isEven ? 'matched' : 'pending',
  'admin_list_payments' => 'posted',
  'admin_list_payment_events' => index.isEven ? 'allocated' : 'needs_review',
  'admin_list_allocations' => 'allocated',
  'admin_list_unallocated' => 'needs_review',
  'admin_list_ledger' => 'posted',
  'admin_list_receivers' => 'active',
  'admin_list_sms_metadata' => index.isEven ? 'parsed' : 'needs_review',
  'admin_list_bank_destinations' => index == 1 ? 'active' : 'retired',
  'admin_list_bank_destination_change_requests' =>
    index.isEven ? 'approved' : 'pending',
  'admin_list_bank_transfer_intents' =>
    index.isEven ? 'reconciled' : 'received_unreconciled',
  'admin_list_bank_transactions' => index.isEven ? 'reconciled' : 'received',
  'admin_list_bank_evidence' => index.isEven ? 'allocated' : 'needs_review',
  'admin_list_reconciliation_runs' =>
    index.isEven ? 'completed' : 'completed_with_exceptions',
  'admin_list_reconciliation_exceptions' => 'open',
  'admin_list_bank_allocation_requests' =>
    index.isEven ? 'approved' : 'pending',
  'admin_list_journal_entries' => 'bank_receipt',
  'admin_list_admin_users' => 'active',
  'admin_list_notifications' => index.isEven ? 'sent' : 'failed',
  'admin_list_audit_logs' => 'logged',
  'admin_list_settings' => 'enabled',
  'admin_list_feature_flags' => 'enabled',
  _ => 'active',
};

String _rowAmount(String rpcName, int index) {
  if (rpcName == 'admin_list_collect_payees') {
    return 'RW • MoMo';
  }
  if (rpcName == 'admin_list_collect_transactions' ||
      rpcName == 'admin_list_collect_reconciliations') {
    final countryCode = _rowCountryCode(rpcName, index);
    return switch (countryCode) {
      'MT' => 'EUR ${(index * 24.50).toStringAsFixed(2)}',
      'GB' => 'GBP ${(index * 24.50).toStringAsFixed(2)}',
      _ => 'RWF ${index * 25000}',
    };
  }
  if (rpcName == 'admin_list_collect_ledgers') {
    final countryCode = _rowCountryCode(rpcName, index);
    return switch (countryCode) {
      'MT' => 'EUR ${(index * 24.50).toStringAsFixed(2)} =',
      'GB' => 'GBP ${(index * 24.50).toStringAsFixed(2)} =',
      _ => 'RWF ${index * 25000} =',
    };
  }
  if (rpcName == 'admin_list_notifications') return '1 delivery';
  if (rpcName == 'admin_list_admin_users') return 'Admin';
  if (rpcName == 'admin_list_collections') return '${10 + index} members';
  if (rpcName == 'admin_list_receivers' ||
      rpcName == 'admin_list_sms_metadata') {
    return '';
  }
  if (rpcName.startsWith('admin_list_payment') ||
      rpcName == 'admin_list_allocations' ||
      rpcName == 'admin_list_unallocated' ||
      rpcName == 'admin_list_ledger') {
    return 'RWF ${index * 25000}';
  }
  if (rpcName == 'admin_list_users' ||
      rpcName == 'admin_list_members' ||
      rpcName == 'admin_list_non_member_users' ||
      rpcName == 'admin_list_bank_destinations' ||
      rpcName == 'admin_list_bank_destination_change_requests' ||
      rpcName == 'admin_list_reconciliation_runs' ||
      rpcName == 'admin_list_reconciliation_exceptions' ||
      rpcName == 'admin_list_audit_logs' ||
      rpcName == 'admin_list_settings' ||
      rpcName == 'admin_list_feature_flags') {
    return '';
  }
  return 'EUR ${(index * 24.50).toStringAsFixed(2)}';
}

Map<String, dynamic> _rowExtra(String rpcName, int index) {
  if (rpcName == 'admin_list_collect_transactions') {
    final momo = index.isOdd;
    final countryCode = _rowCountryCode(rpcName, index);
    final groupName = switch (index % 3) {
      1 => 'Buri Munsi',
      2 => 'Gikundiro',
      _ => 'Community building fund',
    };
    return {
      'source_label': momo
          ? 'MTN MoMo receipt SMS'
          : 'Revolut ${countryCode == 'MT' ? 'EUR' : 'GBP'} account',
      'group_name': groupName,
      'payee_label': switch (groupName) {
        'Buri Munsi' => 'IKANISA LTD',
        'Gikundiro' => 'Rayon Sports FC',
        _ => 'Member MoMo receiver',
      },
    };
  }
  if (rpcName == 'admin_list_collections') {
    final publicGroup = index <= 2;
    return {
      'collection_type': index == 2 ? 'sport' : 'ikimina',
      'purpose_label': switch (index) {
        1 => 'Group savings',
        2 => 'Club support',
        _ => 'Member community support',
      },
      'visibility': publicGroup ? 'public' : 'private',
      'is_platform_sponsored': publicGroup,
      'creator_label': publicGroup
          ? 'Collect platform'
          : 'Collect ID ${38490 + index}',
      'active_members': 10 + index,
      'receiver_label': switch (index) {
        1 => 'IKANISA LTD',
        2 => 'Rayon Sports FC',
        _ => 'Member MoMo receiver',
      },
      'momo_code': switch (index) {
        1 => '41258',
        2 => '008000',
        _ => '0788${(120000 + index).toString().padLeft(6, '0')}',
      },
      'receiver_network': 'mtn_momo',
    };
  }
  if (rpcName == 'admin_list_users' ||
      rpcName == 'admin_list_members' ||
      rpcName == 'admin_list_non_member_users') {
    final countryCode = _rowCountryCode(rpcName, index);
    final rwanda = countryCode == 'RW';
    final hasMembership = rpcName != 'admin_list_non_member_users';
    return {
      'public_id': '${38490 + index}',
      'display_name': hasMembership ? 'Member $index' : 'User $index',
      'whatsapp_masked': _evidenceWhatsAppMasked(countryCode, index),
      'country_code': countryCode,
      'currency_code': switch (countryCode) {
        'RW' => 'RWF',
        'MT' => 'EUR',
        _ => 'GBP',
      },
      'momo_provider': rwanda ? 'mtn_momo' : null,
      'momo_masked': rwanda ? '078•••••${(10 + index) % 100}' : null,
      'has_revolut_profile': !rwanda,
      'account_last4': rwanda ? null : '${8200 + index}',
      'active_groups': hasMembership ? 1 + (index % 4) : 0,
      'updated_at': _rowCreatedAt(index).add(const Duration(hours: 3)),
      'is_platform_admin': hasMembership ? index == 10 : index == 4,
    };
  }
  if (rpcName == 'admin_list_audit_logs') {
    return {
      'actor': index.isEven ? 'Checker B.' : 'Maker A.',
      'target': index.isEven ? 'COLLECT-AB1202-6802' : 'Buri Munsi',
      'reason_recorded': true,
    };
  }
  if (rpcName == 'admin_list_settings') {
    return {
      'current_value': _rowSubtitle(rpcName, index),
      'scope': index == 1
          ? 'RW'
          : index == 2
          ? 'Diaspora'
          : 'Operations',
    };
  }
  if (rpcName == 'admin_list_feature_flags') {
    return {'scope': 'Production', 'enabled': true};
  }
  if (rpcName == 'admin_list_admin_users') {
    return {
      'phone_masked': '+250 78•••${6800 + index}',
      'roles': ['admin'],
    };
  }
  return const {};
}

Map<String, dynamic> _rowCountryExtra(String rpcName, int index) {
  final countryCode = _rowCountryCode(rpcName, index);
  return countryCode == null ? const {} : {'country_code': countryCode};
}

String? _rowCountryCode(String rpcName, int index) => switch (rpcName) {
  'admin_list_collections' || 'admin_list_collect_payees' => 'RW',
  'admin_list_collect_transactions' ||
  'admin_list_collect_reconciliations' ||
  'admin_list_collect_ledgers' ||
  'admin_list_notifications' =>
    index.isOdd
        ? 'RW'
        : index % 4 == 2
        ? 'MT'
        : 'GB',
  'admin_list_users' ||
  'admin_list_members' ||
  'admin_list_non_member_users' => switch (index % 3) {
    1 => 'RW',
    2 => 'MT',
    _ => 'GB',
  },
  _ => null,
};

String _evidenceWhatsAppMasked(String? countryCode, int index) =>
    switch (countryCode) {
      'MT' => '+356 79••${(4300 + index)}',
      'GB' => '+44 7•••${(4300 + index)}',
      _ => '+250 78•••${(4300 + index)}',
    };

String _maskedPayer(int index) {
  const payers = ['078•••4321', '078•••7662', '072•••9152', '073•••1775'];
  return payers[(index - 1) % payers.length];
}

String _rowAge(int index) {
  const ages = ['38m', '2h 14m', '4h 27m', '5h 05m'];
  return ages[(index - 1) % ages.length];
}

DateTime _rowCreatedAt(int index) {
  return DateTime.utc(2026, 8, 20, 22 - (index % 8), index.isEven ? 0 : 30);
}
