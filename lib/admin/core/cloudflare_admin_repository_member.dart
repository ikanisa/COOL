part of 'cloudflare_admin_repository.dart';

class CloudflareMemberReceipt {
  const CloudflareMemberReceipt(this.values);
  final Map<String, dynamic> values;
  String get id => values['id'] as String;
  int get version => values['version'] as int;
  String get status => values['status'] as String;
  factory CloudflareMemberReceipt.parse(Map<String, dynamic> data) {
    const fields = {
      'id',
      'user_id',
      'body_sha256',
      'status',
      'version',
      'received_at',
      'created_at',
      'public_id',
      'display_name',
      'transaction_id',
      'reviewed_at',
    };
    if (data.length != fields.length ||
        !data.keys.every(fields.contains) ||
        !_coreId(data['id']) ||
        !_coreId(data['user_id']) ||
        data['body_sha256'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(data['body_sha256'] as String) ||
        !{'needs_review', 'reviewed', 'rejected'}.contains(data['status']) ||
        !_coreInteger(data['version']) ||
        data['version'] == 0 ||
        !_coreTimestamp(data['received_at']) ||
        !_coreTimestamp(data['created_at']) ||
        data['public_id'] != null &&
            (data['public_id'] is! String ||
                !RegExp(r'^[0-9]{6}$').hasMatch(data['public_id'] as String)) ||
        data['display_name'] != null && data['display_name'] is! String ||
        data['transaction_id'] != null && !_coreId(data['transaction_id']) ||
        data['reviewed_at'] != null && !_coreTimestamp(data['reviewed_at']) ||
        data['status'] == 'needs_review' && data['reviewed_at'] != null ||
        data['status'] != 'needs_review' && data['reviewed_at'] == null) {
      _invalidCore();
    }
    return CloudflareMemberReceipt(Map.unmodifiable(data));
  }
}

class CloudflareMemberReceiptDetail {
  const CloudflareMemberReceiptDetail({
    required this.receipt,
    required this.canManage,
    required this.reviews,
  });
  final CloudflareMemberReceipt receipt;
  final bool canManage;
  final List<Map<String, dynamic>> reviews;
}

extension CloudflareMemberReceiptRepository on CloudflareAdminRepository {
  Future<({List<CloudflareMemberReceipt> rows, int total})> memberReceiptList({
    String status = '',
    int offset = 0,
  }) async {
    if (!{'', 'needs_review', 'reviewed', 'rejected'}.contains(status) ||
        offset < 0 ||
        offset > 2147483647) {
      throw const FormatException('Invalid receipt filter.');
    }
    final query = Uri(
      queryParameters: {
        'limit': '25',
        'offset': '$offset',
        if (status.isNotEmpty) 'status': status,
      },
    ).query;
    final result = await _read('gateway/receipts?$query', 'payments.read');
    if (result.length != 2 ||
        result['rows'] is! List ||
        !_coreInteger(result['total'])) {
      _invalidCore();
    }
    final rows = [
      for (final row in result['rows'] as List)
        if (row is Map)
          CloudflareMemberReceipt.parse(Map<String, dynamic>.from(row))
        else
          _invalidCore(),
    ];
    final total = result['total'] as int;
    if (rows.length > 25 ||
        rows.length != (total - offset).clamp(0, 25) ||
        rows.map((row) => row.id).toSet().length != rows.length ||
        status.isNotEmpty && rows.any((row) => row.status != status)) {
      _invalidCore();
    }
    return (rows: rows, total: total);
  }

  Future<CloudflareMemberReceiptDetail> memberReceiptDetail(String id) async {
    if (!_coreId(id)) throw const FormatException('Select a valid receipt.');
    final result = await _read('gateway/receipts/$id', 'payments.read');
    if (result.length != 6 ||
        result['resource_type'] != 'member_receipts' ||
        result['resource'] is! Map ||
        result['current_actor_id'] != session.user?.id ||
        result['can_manage'] is! bool ||
        result['related_truncated'] != false ||
        result['related'] is! Map) {
      _invalidCore();
    }
    final receipt = CloudflareMemberReceipt.parse(
      Map<String, dynamic>.from(result['resource'] as Map),
    );
    if (receipt.id != id ||
        session.user?.role == AdminAccountRole.staff &&
            result['can_manage'] != false) {
      _invalidCore();
    }
    final related = result['related'] as Map;
    if (related.length != 1 ||
        related['reviews'] is! List ||
        (related['reviews'] as List).length > 100) {
      _invalidCore();
    }
    const fields = {
      'id',
      'outcome',
      'transaction_id',
      'evidence_id',
      'actor_admin_id',
      'reason',
      'reviewed_at',
    };
    final reviews = <Map<String, dynamic>>[];
    for (final row in related['reviews'] as List) {
      if (row is! Map ||
          row.length != fields.length ||
          !row.keys.every(fields.contains) ||
          !_coreId(row['id']) ||
          !_coreId(row['actor_admin_id']) ||
          !{'reviewed', 'rejected'}.contains(row['outcome']) ||
          row['reason'] is! String ||
          !_coreTimestamp(row['reviewed_at']) ||
          row['transaction_id'] != null && !_coreId(row['transaction_id']) ||
          row['evidence_id'] != null && !_coreId(row['evidence_id'])) {
        _invalidCore();
      }
      reviews.add(Map<String, dynamic>.from(row));
    }
    return CloudflareMemberReceiptDetail(
      receipt: receipt,
      canManage: result['can_manage'] as bool,
      reviews: reviews,
    );
  }

  Future<Map<String, String>> memberReceiptContent(
    CloudflareMemberReceipt receipt, {
    required String reason,
  }) async {
    if (reason.trim().length < 8 || reason.trim().length > 1000) {
      throw const FormatException(
        'Provide a reason for viewing the submitted content.',
      );
    }
    final before = _requirePermission('payments.manage');
    if (before.role == AdminAccountRole.staff) {
      throw const AdminAccountException(
        'Only administrators can review submitted content.',
      );
    }
    final result = await session.request(
      'gateway/receipts/${receipt.id}/content',
      authenticated: true,
      reviewReason: reason.trim(),
    );
    final after = _requirePermission('payments.manage');
    if (before.id != after.id || before.sessionId != after.sessionId) {
      throw const AdminAccountException(
        'Your session changed. Reopen the receipt.',
      );
    }
    if (result.length != 5 ||
        result['submission_id'] != receipt.id ||
        result['evidence_level'] != 'member_submitted' ||
        result['raw_sender'] is! String ||
        result['raw_body'] is! String ||
        (result['raw_body'] as String).isEmpty ||
        (result['raw_body'] as String).length > 16000 ||
        result['body_sha256'] != receipt.values['body_sha256'] ||
        sha256.convert(utf8.encode(result['raw_body'] as String)).toString() !=
            result['body_sha256']) {
      _invalidCore();
    }
    return Map<String, String>.from(result);
  }

  Future<List<Map<String, dynamic>>> memberReceiptTransactions(
    String id, {
    String search = '',
  }) async {
    if (!_coreId(id) || search.length > 200) {
      throw const FormatException('Invalid receipt transaction lookup.');
    }
    final query = Uri(
      queryParameters: {'limit': '100', 'search': search.trim()},
    ).query;
    final result = await _read(
      'gateway/receipts/$id/transactions?$query',
      'payments.manage',
    );
    if (result.length != 1 ||
        result['rows'] is! List ||
        (result['rows'] as List).length > 100) {
      _invalidCore();
    }
    const fields = {
      'id',
      'label',
      'version',
      'amount_rwf',
      'group_id',
      'group_name',
      'provider_reference',
    };
    final rows = <Map<String, dynamic>>[];
    for (final row in result['rows'] as List) {
      if (row is! Map ||
          row.length != fields.length ||
          !row.keys.every(fields.contains) ||
          !_coreId(row['id']) ||
          !_coreId(row['group_id']) ||
          !_coreInteger(row['version']) ||
          row['version'] == 0 ||
          !_coreInteger(row['amount_rwf']) ||
          row['amount_rwf'] == 0 ||
          ![
            'label',
            'group_name',
            'provider_reference',
          ].every((key) => row[key] is String)) {
        _invalidCore();
      }
      rows.add(Map<String, dynamic>.from(row));
    }
    if (rows.map((row) => row['id']).toSet().length != rows.length) {
      _invalidCore();
    }
    return rows;
  }

  Future<CloudflareOperationReceipt> reviewMemberReceipt(
    CloudflareMemberReceipt receipt, {
    required String key,
    required String outcome,
    String? transactionId,
    required String reason,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9_.-]{8,200}$').hasMatch(key) ||
        !{'reviewed', 'rejected'}.contains(outcome) ||
        transactionId != null && !_coreId(transactionId) ||
        outcome == 'rejected' && transactionId != null ||
        reason.trim().length < 8 ||
        reason.trim().length > 1000) {
      throw const FormatException(
        'Review the classification, transaction and reason.',
      );
    }
    final before = _requirePermission('payments.manage');
    if (before.role == AdminAccountRole.staff) {
      throw const AdminAccountException(
        'Only administrators can classify submitted receipts.',
      );
    }
    final result = await session.request(
      'gateway/receipts/${receipt.id}/review',
      body: {
        'expected_version': receipt.version,
        'outcome': outcome,
        'transaction_id': transactionId,
        'reason': reason.trim(),
      },
      method: 'POST',
      idempotencyKey: key,
      authenticated: true,
    );
    final after = _requirePermission('payments.manage');
    if (before.id != after.id || before.sessionId != after.sessionId) {
      throw const AdminAccountException(
        'Your session changed. Check the review receipt.',
      );
    }
    final saved = CloudflareOperationReceipt.parse(result);
    if (saved.resourceType != 'member_receipts' ||
        saved.resourceId != receipt.id ||
        saved.version != receipt.version + 1) {
      _invalidCore();
    }
    return saved;
  }
}
