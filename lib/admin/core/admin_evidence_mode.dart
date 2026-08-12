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
    'receivers.read',
    'sms.metadata.read',
    'sms.raw.reveal',
    'payment_events.read',
    'payment_events.reparse',
    'payments.read',
    'payments.allocate',
    'ledger.read',
    'audit.read',
    'feature_flags.read',
    'settings.read',
    'system_health.read',
    'admin_users.read',
  ],
);

class AdminEvidenceRepository extends AdminRepositoryBase {
  const AdminEvidenceRepository();

  @override
  Future<Map<String, dynamic>> action(
    String rpcName,
    Map<String, dynamic> params,
  ) async {
    if (rpcName == 'admin_reveal_raw_sms') {
      return {'message': 'Raw message hidden in route evidence.'};
    }
    return {'status': 'queued'};
  }

  @override
  Future<AdminIdentity?> currentIdentity() async => _evidenceAdmin;

  @override
  Future<Map<String, dynamic>> detail(String rpcName, String id) async {
    return {
      'id': id,
      'transaction_id': 'MOMO-EVIDENCE-001',
      'amount': 'RWF 24,500',
      'sender_masked': '+250***4321',
      'receiver_masked': '+250***1222',
      'payment_intent_id': 'intent-evidence',
      'status': 'needs_review',
      'created_at': '2026-06-15T12:00:00Z',
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
    final rowCount = switch (rpcName) {
      'admin_list_allocations' => 42,
      'admin_list_unallocated' => 6,
      _ => 30,
    };
    final allRows = [
      for (var index = 1; index <= rowCount; index += 1)
        AdminTableRowData(
          id: _rowId(rpcName, index),
          title: _rowTitle(rpcName, index),
          subtitle: _rowSubtitle(rpcName),
          status: _rowStatus(rpcName, index),
          amount: _rowAmount(rpcName, index),
          createdAt: _rowCreatedAt(rpcName, index),
          extra: {
            'sender_masked': _maskedSender(
              _displayedEventIndex(rpcName, index),
            ),
            'reference':
                'Ref MTN${12345 + _displayedEventIndex(rpcName, index)}',
            'age': _rowAge(index),
            'allocated_to': 'St Michael building fund',
            'operator': index <= 2 ? 'Alex K.' : 'Grace M.',
          },
        ),
    ];
    final normalizedSearch = search?.trim().toLowerCase() ?? '';
    final rows = normalizedSearch.isEmpty
        ? allRows
        : allRows
              .where(
                (row) =>
                    row.title.toLowerCase().contains(normalizedSearch) ||
                    row.subtitle.toLowerCase().contains(normalizedSearch) ||
                    row.id.toLowerCase().contains(normalizedSearch),
              )
              .toList(growable: false);
    final start = (offset ?? 0).clamp(0, rows.length);
    final pageLimit = limit ?? 25;
    final end = (start + pageLimit).clamp(start, rows.length);
    return AdminListResult(total: rows.length, rows: rows.sublist(start, end));
  }

  @override
  Future<List<AdminMetric>> overviewMetrics() async => const [
    AdminMetric(label: 'Review queue', value: '6', status: 'needs_review'),
    AdminMetric(label: 'Allocated today', value: '42', status: 'allocated'),
    AdminMetric(label: 'Parser health', value: '99%', status: 'active'),
    AdminMetric(label: 'Open support notes', value: '3', status: 'pending'),
  ];

  @override
  Future<AdminQueueSla?> queueSla(String queueKey) async => const AdminQueueSla(
    target: '< 15m',
    owner: 'Money operations',
    escalation: 'Review immediately when the target is exceeded',
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

String _rowId(String rpcName, int index) => switch (rpcName) {
  'admin_list_users' => 'user-$index',
  'admin_list_collections' => 'collection-$index',
  'admin_list_payment_events' => 'event-$index',
  'admin_list_allocations' => 'event-$index',
  'admin_list_unallocated' => 'event-$index',
  'admin_list_sms_metadata' => 'sms-$index',
  'admin_list_receivers' => 'receiver-$index',
  _ => 'admin-row-$index',
};

String _rowTitle(String rpcName, int index) => switch (rpcName) {
  'admin_list_users' => 'Member profile $index',
  'admin_list_collections' => 'Public group $index',
  'admin_list_payment_events' => 'Parsed MoMo event $index',
  'admin_list_allocations' => 'Parsed MoMo event ${index * 2}',
  'admin_list_unallocated' => 'Parsed MoMo event ${(index * 2) - 1}',
  'admin_list_sms_metadata' => 'SMS metadata $index',
  'admin_list_receivers' => 'Masked receiver $index',
  _ => 'Operational record $index',
};

String _rowSubtitle(String rpcName) => switch (rpcName) {
  'admin_list_users' => 'Collect ID and permission-safe account state',
  'admin_list_collections' => 'Verified group activity and owner controls',
  'admin_list_payment_events' => 'Masked sender and allocation review',
  'admin_list_allocations' => 'Successful masked payment allocation',
  'admin_list_unallocated' => 'Masked sender and allocation review',
  'admin_list_sms_metadata' => 'Metadata only; raw body is gated',
  'admin_list_receivers' => 'Masked MoMo receiver and review state',
  _ => 'Admin evidence row with masked test data',
};

String _rowStatus(String rpcName, int index) => switch (rpcName) {
  'admin_list_allocations' => 'allocated',
  'admin_list_unallocated' => 'needs_review',
  _ => index.isEven ? 'allocated' : 'needs_review',
};

String _maskedSender(int index) {
  const senders = [
    '0786 **** 341',
    '0789 **** 662',
    '0724 **** 152',
    '0720 **** 775',
    '0781 **** 908',
    '0783 **** 114',
    '0728 **** 440',
    '0731 **** 229',
  ];
  return senders[(index - 1) % senders.length];
}

String _rowAge(int index) {
  const ages = ['38m', '2h 14m', '4h 27m', '5h 05m', '6h 12m'];
  return ages[(index - 1) % ages.length];
}

String _rowAmount(String rpcName, int index) {
  return 'RWF ${_displayedEventIndex(rpcName, index) * 2500}';
}

int _displayedEventIndex(String rpcName, int index) => switch (rpcName) {
  'admin_list_allocations' => index * 2,
  'admin_list_unallocated' => (index * 2) - 1,
  _ => index,
};

DateTime _rowCreatedAt(String rpcName, int index) {
  if (rpcName == 'admin_list_allocations') {
    const times = [(21, 0), (18, 0), (16, 45), (15, 30)];
    final time = times[(index - 1) % times.length];
    return DateTime.utc(2026, 7, 24, time.$1, time.$2);
  }
  return DateTime.utc(2026, 7, 24, 22 - (index % 8), index.isEven ? 0 : 30);
}
