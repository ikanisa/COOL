part of 'cloudflare_admin_repository.dart';

const cloudflareEmailStates = [
  'queued',
  'leased',
  'send_started',
  'accepted',
  'delivered',
  'failed_no_send',
  'uncertain',
  'suppressed',
];

extension CloudflareEmailRepository on CloudflareAdminRepository {
  Future<({List<Map<String, dynamic>> rows, int total})> emailEvents({
    String status = '',
    int offset = 0,
  }) async {
    if (status.isNotEmpty && !cloudflareEmailStates.contains(status) ||
        offset < 0 ||
        offset > 2147483647) {
      throw const FormatException('Invalid email filters.');
    }
    final query = Uri(
      queryParameters: {
        'limit': '25',
        'offset': '$offset',
        if (status.isNotEmpty) 'status': status,
      },
    ).query;
    final result = await _read('email/events?$query', 'email.read');
    if (result.length != 4 ||
        result['rows'] is! List ||
        !_coreInteger(result['total']) ||
        result['limit'] != 25 ||
        result['offset'] != offset) {
      _invalidCore();
    }
    const fields = {
      'id',
      'recipient_masked',
      'notification_type',
      'status',
      'attempt_count',
      'created_at',
      'updated_at',
      'accepted_at',
      'delivered_at',
    };
    final rows = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final value in result['rows'] as List) {
      if (value is! Map ||
          value.length != fields.length ||
          !value.keys.every(fields.contains) ||
          !_coreId(value['id']) ||
          !seen.add(value['id'] as String) ||
          value['recipient_masked'] is! String ||
          !(value['recipient_masked'] == 'Unavailable' ||
              RegExp(
                r'^.•••@[^\s@]+$',
              ).hasMatch(value['recipient_masked'] as String)) ||
          value['notification_type'] is! String ||
          (value['notification_type'] as String).isEmpty ||
          !cloudflareEmailStates.contains(value['status']) ||
          status.isNotEmpty && value['status'] != status ||
          !_coreInteger(value['attempt_count']) ||
          !_coreInteger(value['created_at']) ||
          value['created_at'] == 0 ||
          (value['created_at'] as int) > 253402300799 ||
          !_coreInteger(value['updated_at']) ||
          (value['updated_at'] as int) > 253402300799 ||
          (value['updated_at'] as int) < (value['created_at'] as int)) {
        _invalidCore();
      }
      for (final key in ['accepted_at', 'delivered_at']) {
        if (value[key] != null &&
            (!_coreInteger(value[key]) ||
                (value[key] as int) > 253402300799 ||
                (value[key] as int) < (value['created_at'] as int))) {
          _invalidCore();
        }
      }
      if (value['status'] == 'accepted' && value['accepted_at'] == null ||
          value['status'] == 'delivered' && value['delivered_at'] == null) {
        _invalidCore();
      }
      rows.add(Map<String, dynamic>.from(value));
    }
    final total = result['total'] as int;
    if (rows.length > 25 || rows.length != (total - offset).clamp(0, 25)) {
      _invalidCore();
    }
    return (rows: rows, total: total);
  }

  Future<CloudflareOperationReceipt> dispatchEmails({
    required String key,
    required String reason,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9_.-]{8,200}$').hasMatch(key) ||
        reason.trim().length < 8 ||
        reason.trim().length > 1000) {
      throw const FormatException('Provide a valid dispatch reason.');
    }
    final before = _requirePermission('email.manage');
    if (before.role == AdminAccountRole.staff) {
      throw const AdminAccountException(
        'Only administrators can run an email batch.',
      );
    }
    final result = await session.request(
      'email/dispatch',
      body: {'reason': reason.trim()},
      method: 'POST',
      authenticated: true,
      idempotencyKey: key,
    );
    final after = _requirePermission('email.manage');
    if (before.id != after.id || before.sessionId != after.sessionId) {
      throw const AdminAccountException(
        'Your session changed. Check the dispatch receipt.',
      );
    }
    final receipt = CloudflareOperationReceipt.parse(result);
    if (receipt.resourceType != 'email_dispatch') _invalidCore();
    return receipt;
  }
}
