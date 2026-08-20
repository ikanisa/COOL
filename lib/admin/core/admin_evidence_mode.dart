import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_auth_guard.dart';
import 'admin_repository_base.dart';

const adminPwaEvidenceMode = bool.fromEnvironment('ADMIN_PWA_EVIDENCE_MODE');

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
  roles: ['platform_owner'],
  permissions: [
    'overview.read',
    'public_requests.read',
    'collections.read',
    'users.read',
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
    if (rpcName == 'admin_reveal_raw_bank_evidence') {
      return {'message': 'Raw bank evidence hidden in route evidence.'};
    }
    return {'status': 'queued'};
  }

  @override
  Future<AdminIdentity?> currentIdentity() async => _evidenceAdmin;

  @override
  Future<Map<String, dynamic>> detail(String rpcName, String id) async {
    const createdAt = '2026-08-20T06:30:00Z';
    return switch (rpcName) {
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
        'name': 'St Michael building fund',
        'public_id': 'AB1234',
        'visibility': 'private',
        'member_count': 24,
        'total_raised': 'EUR 1,842.50',
        'created_at': createdAt,
      },
      'admin_get_user' => {
        'id': id,
        'collect_id': 'CM6816',
        'display_name': 'Evidence member',
        'phone_masked': '+250***4321',
        'status': 'active',
        'created_at': createdAt,
      },
      'admin_get_admin_user' => {
        'id': id,
        'public_id': 'CA6816',
        'phone_masked': '+250***6816',
        'status': 'active',
        'active_roles': ['platform_owner', 'compliance_admin'],
        'available_roles': [
          'platform_owner',
          'compliance_admin',
          'operations_admin',
          'payments_admin',
          'group_ops_admin',
          'support_admin',
          'read_only_admin',
        ],
        'legacy_platform_owner': false,
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
  }) async {
    final allRows = [
      for (var index = 1; index <= _rowCount(rpcName); index += 1)
        AdminTableRowData(
          id: _rowId(rpcName, index),
          title: _rowTitle(rpcName, index),
          subtitle: _rowSubtitle(rpcName),
          status: _rowStatus(rpcName, index),
          amount: _rowAmount(rpcName, index),
          createdAt: _rowCreatedAt(index),
          extra: {
            'sender_masked': _maskedPayer(index),
            'reference': 'COLLECT-AB${1200 + index}-${6800 + index}',
            'age': _rowAge(index),
            'allocated_to': 'St Michael building fund',
            'operator': index.isEven ? 'Checker B.' : 'Maker A.',
          },
        ),
    ];
    final normalizedSearch = search?.trim().toLowerCase() ?? '';
    final normalizedStatus = status?.trim().toLowerCase() ?? '';
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
          return matchesSearch && matchesStatus;
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
    AdminMetric(label: 'Open exceptions', value: '3', status: 'needs_review'),
    AdminMetric(label: 'Awaiting approvals', value: '4', status: 'pending'),
    AdminMetric(label: 'Unreconciled transfers', value: '2', status: 'pending'),
    AdminMetric(label: 'Evidence health', value: '100%', status: 'active'),
  ];

  @override
  Future<AdminQueueSla?> queueSla(String queueKey) async => const AdminQueueSla(
    target: '< 1 business day',
    owner: 'Bank reconciliation operations',
    escalation: 'Escalate unresolved variances to the platform owner',
  );

  @override
  Future<void> sendOtp({required String phone}) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<AdminIdentity?> verifyOtp({
    required String phone,
    required String otp,
  }) async => _evidenceAdmin;
}

int _rowCount(String rpcName) => switch (rpcName) {
  'admin_list_bank_destinations' => 2,
  'admin_list_bank_destination_change_requests' => 4,
  'admin_list_bank_transfer_intents' => 12,
  'admin_list_bank_transactions' => 8,
  'admin_list_bank_evidence' => 8,
  'admin_list_reconciliation_runs' => 7,
  'admin_list_reconciliation_exceptions' => 3,
  'admin_list_bank_allocation_requests' => 4,
  'admin_list_journal_entries' => 10,
  _ => 30,
};

String _rowId(String rpcName, int index) => switch (rpcName) {
  'admin_list_users' => 'user-$index',
  'admin_list_collections' => 'collection-$index',
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
  'admin_list_users' => 'Member profile $index',
  'admin_list_collections' => 'Verified group $index',
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
  'admin_list_admin_users' => 'Collect ID CA${6800 + index}',
  'admin_list_notifications' => 'Bank contribution reconciled',
  'admin_list_audit_logs' => 'Controlled operation $index',
  'admin_list_settings' => 'Bank transfer setting $index',
  'admin_list_feature_flags' => 'bank_transfer_v1',
  _ => 'Operational record $index',
};

String _rowSubtitle(String rpcName) => switch (rpcName) {
  'admin_list_users' => 'Collect ID and permission-safe account state',
  'admin_list_collections' => 'Member, role, and group management controls',
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
  'admin_list_admin_users' => 'platform_owner • compliance_admin',
  'admin_list_notifications' => 'Collect ID AB1234 • 1 delivery',
  'admin_list_audit_logs' => 'Reason, actor, timestamp, and target',
  'admin_list_settings' => 'Governed bank control-plane configuration',
  'admin_list_feature_flags' => 'Production bank-transfer availability',
  _ => 'Admin evidence row with masked test data',
};

String _rowStatus(String rpcName, int index) => switch (rpcName) {
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
  'admin_list_feature_flags' => 'enabled',
  _ => 'active',
};

String _rowAmount(String rpcName, int index) {
  if (rpcName == 'admin_list_notifications') return '1 delivery';
  if (rpcName == 'admin_list_admin_users') return '2 roles';
  if (rpcName == 'admin_list_collections') return '${10 + index} members';
  if (rpcName == 'admin_list_users' ||
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

String _maskedPayer(int index) {
  const payers = [
    'Payer ••4321',
    'Payer ••7662',
    'Payer ••9152',
    'Payer ••1775',
  ];
  return payers[(index - 1) % payers.length];
}

String _rowAge(int index) {
  const ages = ['38m', '2h 14m', '4h 27m', '5h 05m'];
  return ages[(index - 1) % ages.length];
}

DateTime _rowCreatedAt(int index) {
  return DateTime.utc(2026, 8, 20, 22 - (index % 8), index.isEven ? 0 : 30);
}
