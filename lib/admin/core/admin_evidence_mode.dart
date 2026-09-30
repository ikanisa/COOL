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
  Future<Map<String, dynamic>> prepareRosterImport(
    Map<String, dynamic> body,
  ) async => {
    'ok': true,
    'processing_method': 'deterministic',
    'model': null,
    'row_count': 2,
    'ready_count': 2,
    'error_count': 0,
    'can_submit': true,
    'rows': const [
      {
        'source_row': 2,
        'member_name': 'Alice Evidence',
        'momo_name': 'ALICE EVIDENCE',
        'momo_number': '+250788000101',
        'confidence': 1.0,
        'issues': <String>[],
        'ready': true,
      },
      {
        'source_row': 3,
        'member_name': 'Bob Evidence',
        'momo_name': 'BOB EVIDENCE',
        'momo_number': '+250788000102',
        'confidence': 1.0,
        'issues': <String>[],
        'ready': true,
      },
    ],
    'normalized_rows': const [
      {
        'member_name': 'Alice Evidence',
        'momo_name': 'ALICE EVIDENCE',
        'momo_number': '+250788000101',
      },
      {
        'member_name': 'Bob Evidence',
        'momo_name': 'BOB EVIDENCE',
        'momo_number': '+250788000102',
      },
    ],
  };

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
        'payment_route': 'Rwanda MoMo',
        'raw_sms_id': '00000000-0000-0000-0000-000000006816',
        'sms_sender': 'MTN MoMo',
        'sender_masked': '078•••4321',
        'parse_status': 'parsed',
        'sender_name': 'Evidence payer',
        'network': 'MTN MoMo',
        'reference': 'COL-RW-6816',
        'amount': 'RWF 25,000',
        'payee': 'St Michael group MoMo receiver ••6816',
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
      'admin_get_member_record' => {
        'id': id,
        'collect_id': '960200',
        'member_name': 'Evidence feature-phone member',
        'momo_registered_name': 'EVIDENCE FEATURE PHONE MEMBER',
        'momo_masked': '+250•••200',
        'whatsapp_masked': null,
        'account_state': 'feature_phone',
        'origin': 'admin_assisted',
        'lifecycle': 'active',
        'active_groups': 1,
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
        'type': 'momo_contribution_reconciled',
        'title': 'MoMo contribution reconciled',
        'collect_id': 'AB1234',
        'status': 'failed',
        'delivery_statuses': 'failed: 1',
        'retryable_count': 1,
        'last_error_code': 'provider_unavailable',
        'created_at': createdAt,
      },
      'admin_get_hybrid_sms_receipt' => {
        'id': id,
        'state': 'queued',
        'channel': 'Assisted SMS via Mac Messages',
        'member_collect_id': '960200',
        'collection_id': 'collection-1',
        'collection_title': 'Buri Munsi',
        'destination_masked': '+250•••200',
        'amount_rwf': 1500,
        'member_balance_rwf': 3500,
        'group_balance_rwf': 12500,
        'reference': 'SYNTHETIC-001',
        'template_key': 'buri_munsi.payment_received',
        'template_version': 1,
        'message_body': 'Hidden until a current fenced operator claim',
        'attempt_count': 0,
        'latest_attempt_state': null,
        'suppression_reason': null,
        'created_at': createdAt,
        'observed_sent_at': null,
        'delivery_claim':
            'Observed sent is a Messages UI state, not handset delivery',
      },
      'admin_system_health' => {
        'id': id,
        'database': 'reachable',
        'auth': 'authenticated',
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
            'rail': 'rw_momo',
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
          final matchesCountry =
              normalizedCountry.isEmpty ||
              (normalizedCountry == 'RW' && rowCountry == 'RW');
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
  final normalized = PhoneNormalizer.normalizeRwanda(phone);
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
  'admin_list_collections' => 30,
  'admin_list_payment_intents' => 12,
  'admin_list_payments' => 10,
  'admin_list_payment_events' => 8,
  'admin_list_allocations' => 8,
  'admin_list_unallocated' => 3,
  'admin_list_ledger' => 10,
  'admin_list_receivers' => 6,
  'admin_list_sms_metadata' => 8,
  'admin_list_notifications' => 4,
  'admin_list_hybrid_sms_receipts' => 4,
  'admin_list_audit_logs' => 8,
  'admin_list_settings' => 3,
  'admin_list_feature_flags' => 3,
  'admin_list_admin_users' => 2,
  _ => 0,
};

String _rowId(String rpcName, int index) => switch (rpcName) {
  'admin_list_collect_payees' => 'momo:payee-$index',
  'admin_list_platform_payee_candidates' => 'collection-$index',
  'admin_list_collect_transactions' => 'momo:transaction-$index',
  'admin_list_collect_reconciliations' => 'momo:exception-$index',
  'admin_list_collect_ledgers' => 'ledger-$index',
  'admin_list_users' ||
  'admin_list_members' ||
  'admin_list_non_member_users' => 'user-$index',
  'admin_list_collections' => 'collection-$index',
  'admin_list_admin_users' => 'admin-user-$index',
  'admin_list_notifications' => 'notification-$index',
  'admin_list_hybrid_sms_receipts' => 'sms-receipt-$index',
  _ => 'momo-$rpcName-$index',
};

String _rowTitle(String rpcName, int index) => switch (rpcName) {
  'admin_list_collect_payees' => index == 1 ? 'IKANISA LTD' : 'Rayon Sports FC',
  'admin_list_collect_transactions' => 'MoMo transaction ${681600 + index}',
  'admin_list_collect_reconciliations' =>
    'Unallocated MoMo receipt ${681600 + index}',
  'admin_list_collect_ledgers' => 'Ledger entry ${681600 + index}',
  'admin_list_users' ||
  'admin_list_members' ||
  'admin_list_non_member_users' => 'Collect ID ${38490 + index}',
  'admin_list_collections' => switch (index) {
    1 => 'Buri Munsi',
    2 => 'Gikundiro',
    _ => 'Verified group $index',
  },
  'admin_list_notifications' => 'MoMo contribution reconciled',
  'admin_list_hybrid_sms_receipts' => 'Buri Munsi receipt',
  'admin_list_settings' => switch (index) {
    1 => 'Rwanda MoMo receipts',
    2 => 'Reconciliation window',
    _ => 'Notification retries',
  },
  'admin_list_feature_flags' => switch (index) {
    1 => 'Android private groups',
    2 => 'MoMo receipt intake',
    _ => 'Member notifications',
  },
  'admin_list_admin_users' => '+250 78•••${6800 + index}',
  _ => 'Rwanda MoMo record $index',
};

String _rowSubtitle(String rpcName, int index) => switch (rpcName) {
  'admin_list_collect_transactions' => 'MTN MoMo receipt SMS · Rwanda',
  'admin_list_collect_reconciliations' => 'MoMo receipt awaiting allocation',
  'admin_list_collect_ledgers' => 'RWF balanced posting',
  'admin_list_collect_payees' =>
    index == 1 ? 'Buri Munsi · code 41258' : 'Gikundiro · code 008000',
  'admin_list_members' => 'Rwanda · MoMo',
  'admin_list_non_member_users' => 'Rwanda · no active group',
  'admin_list_collections' => 'Rwanda MoMo group',
  'admin_list_hybrid_sms_receipts' => 'MoMo receipt · 078•••4321',
  _ => 'Rwanda operations',
};

String _rowStatus(String rpcName, int index) => switch (rpcName) {
  'admin_list_collect_transactions' =>
    index.isEven ? 'unallocated' : 'allocated',
  'admin_list_collect_reconciliations' => 'unallocated',
  'admin_list_collect_ledgers' => 'balanced',
  'admin_list_collections' => index <= 2 ? 'public_approved' : 'private',
  'admin_list_notifications' => index.isEven ? 'sent' : 'failed',
  'admin_list_hybrid_sms_receipts' => index.isEven ? 'queued' : 'sent',
  'admin_list_admin_users' => 'active',
  _ => 'active',
};

String _rowAmount(String rpcName, int index) => switch (rpcName) {
  'admin_list_collect_payees' => 'RW • MoMo',
  'admin_list_collect_transactions' ||
  'admin_list_collect_reconciliations' ||
  'admin_list_collect_ledgers' ||
  'admin_list_payment_intents' ||
  'admin_list_payments' ||
  'admin_list_payment_events' ||
  'admin_list_allocations' ||
  'admin_list_unallocated' ||
  'admin_list_ledger' => 'RWF ${index * 25000}',
  'admin_list_hybrid_sms_receipts' => 'RWF ${index * 1500}',
  'admin_list_collections' => '${10 + index} members',
  _ => '',
};

Map<String, dynamic> _rowExtra(String rpcName, int index) {
  if (rpcName == 'admin_list_collect_transactions') {
    return {
      'source_label': 'MTN MoMo receipt SMS',
      'group_name': 'Buri Munsi',
      'payee_label': 'IKANISA LTD',
    };
  }
  if (rpcName == 'admin_list_collections') {
    return {
      'collection_type': index == 2 ? 'sport' : 'ikimina',
      'purpose_label': index == 2 ? 'Club support' : 'Group savings',
      'visibility': index <= 2 ? 'public' : 'private',
      'is_platform_sponsored': index <= 2,
      'creator_label': index <= 2
          ? 'Collect platform'
          : 'Collect ID ${38490 + index}',
      'active_members': 10 + index,
      'receiver_label': index == 2 ? 'Rayon Sports FC' : 'IKANISA LTD',
      'momo_code': index == 2 ? '008000' : '41258',
      'receiver_network': 'mtn_momo',
    };
  }
  if (rpcName == 'admin_list_members' ||
      rpcName == 'admin_list_non_member_users') {
    final member = rpcName == 'admin_list_members';
    return {
      'public_id': '${38490 + index}',
      'display_name': member ? 'Member $index' : 'User $index',
      'whatsapp_masked': member && index.isOdd
          ? null
          : '+250 78•••${4300 + index}',
      'account_state': member && index.isOdd ? 'feature_phone' : 'app',
      'country_code': 'RW',
      'currency_code': 'RWF',
      'momo_provider': 'mtn_momo',
      'momo_masked': '078•••••${(10 + index) % 100}',
      'active_groups': member ? 1 + (index % 4) : 0,
      'is_platform_admin': index == 10,
    };
  }
  if (rpcName == 'admin_list_admin_users') {
    return {
      'phone_masked': '+250 78•••${6800 + index}',
      'roles': ['admin'],
    };
  }
  return const {};
}

Map<String, dynamic> _rowCountryExtra(String rpcName, int index) => {
  'country_code': 'RW',
};

String _maskedPayer(int index) {
  const payers = ['078•••4321', '078•••7662', '072•••9152', '073•••1775'];
  return payers[(index - 1) % payers.length];
}

String _rowAge(int index) {
  const ages = ['38m', '2h 14m', '4h 27m', '5h 05m'];
  return ages[(index - 1) % ages.length];
}

DateTime _rowCreatedAt(int index) =>
    DateTime.utc(2026, 8, 20, 22 - (index % 8), index.isEven ? 0 : 30);
