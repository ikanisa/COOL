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
    final rows = [
      for (var index = 1; index <= 30; index += 1)
        AdminTableRowData(
          id: _rowId(rpcName, index),
          title: _rowTitle(rpcName, index),
          subtitle: _rowSubtitle(rpcName),
          status: index.isEven ? 'allocated' : 'needs_review',
          amount: 'RWF ${index * 2500}',
          createdAt: DateTime.utc(2026, 6, (index % 15) + 1, 12),
        ),
    ];
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
  'admin_list_sms_metadata' => 'sms-$index',
  'admin_list_receivers' => 'receiver-$index',
  _ => 'admin-row-$index',
};

String _rowTitle(String rpcName, int index) => switch (rpcName) {
  'admin_list_users' => 'Member profile $index',
  'admin_list_collections' => 'Public group $index',
  'admin_list_payment_events' => 'Parsed MoMo event $index',
  'admin_list_sms_metadata' => 'SMS metadata $index',
  'admin_list_receivers' => 'Masked receiver $index',
  _ => 'Operational record $index',
};

String _rowSubtitle(String rpcName) => switch (rpcName) {
  'admin_list_users' => 'Collect ID and permission-safe account state',
  'admin_list_collections' => 'Verified group activity and owner controls',
  'admin_list_payment_events' => 'Masked sender and allocation review',
  'admin_list_sms_metadata' => 'Metadata only; raw body is gated',
  'admin_list_receivers' => 'Masked MoMo receiver and review state',
  _ => 'Admin evidence row with masked test data',
};
