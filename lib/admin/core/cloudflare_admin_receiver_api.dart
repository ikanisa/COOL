import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_account_api.dart';
import 'cloudflare_admin_repository.dart';
import 'cloudflare_admin_session.dart';

final _id = RegExp(
  r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
);
final _digest = RegExp(r'^[a-f0-9]{64}$');
Never _invalid() => throw const FormatException(
  'The receiver capture response could not be verified.',
);
Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : _invalid();
void _keys(Map<String, dynamic> v, Set<String> keys) {
  if (v.length != keys.length || !v.keys.every(keys.contains)) _invalid();
}

bool _integer(Object? v, [int minimum = 0]) =>
    v is int && v >= minimum && v <= 9007199254740991;
bool _identifier(Object? v) => v is String && _id.hasMatch(v);
bool _time(Object? v) =>
    v is String &&
    RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$').hasMatch(v) &&
    DateTime.tryParse(v)?.toUtc().toIso8601String() == v;
bool _sourceTime(Object? v) =>
    v is String &&
    RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$').hasMatch(v) &&
    DateTime.tryParse(v)?.toUtc().toIso8601String().substring(0, 19) ==
        v.substring(0, 19);
bool _text(Object? v, [int maximum = 120]) =>
    v is String &&
    v.trim().isNotEmpty &&
    v.length <= maximum &&
    !RegExp(r'[\x00-\x1f\x7f]').hasMatch(v);

class ReceiverCaptureGrant {
  ReceiverCaptureGrant._(this.values);
  final Map<String, dynamic> values;
  String get id => values['id'] as String;
  int get version => values['version'] as int;
  bool get active => values['status'] == 'active';
  factory ReceiverCaptureGrant.parse(Map<String, dynamic> v) {
    _keys(v, {
      'id',
      'device_id',
      'device_label',
      'installation_id',
      'key_sha256',
      'payee_id',
      'payee_label',
      'payee_network',
      'payee_momo_number_or_code',
      'status',
      'version',
      'created_by_admin_id',
      'created_at',
      'revoked_by_admin_id',
      'revoked_at',
      'capture_authority',
      'send_authority',
      'financial_authority',
    });
    if (![
          'id',
          'device_id',
          'installation_id',
          'payee_id',
          'created_by_admin_id',
        ].every((k) => _identifier(v[k])) ||
        !_text(v['device_label']) ||
        !_text(v['payee_label']) ||
        v['key_sha256'] is! String ||
        !_digest.hasMatch(v['key_sha256'] as String) ||
        !{'mtn_momo', 'airtel_money'}.contains(v['payee_network']) ||
        v['payee_momo_number_or_code'] is! String ||
        !RegExp(
          r'^[0-9]{4,12}$',
        ).hasMatch(v['payee_momo_number_or_code'] as String) ||
        !{'active', 'revoked'}.contains(v['status']) ||
        !_integer(v['version'], 1) ||
        !_time(v['created_at']) ||
        v['capture_authority'] != (v['status'] == 'active') ||
        v['send_authority'] != false ||
        v['financial_authority'] != false ||
        (v['status'] == 'active'
            ? v['revoked_by_admin_id'] != null ||
                  v['revoked_at'] != null ||
                  v['version'] != 1
            : !_identifier(v['revoked_by_admin_id']) ||
                  !_time(v['revoked_at']) ||
                  v['version'] != 2)) {
      _invalid();
    }
    return ReceiverCaptureGrant._(Map.unmodifiable(v));
  }
}

class ReceiverCaptureDetail {
  const ReceiverCaptureDetail(
    this.grant,
    this.canManage,
    this.captures,
    this.total,
    this.limit,
    this.offset,
  );
  final ReceiverCaptureGrant grant;
  final bool canManage;
  final List<Map<String, dynamic>> captures;
  final int total, limit, offset;
}

final cloudflareAdminReceiverApiProvider = Provider<CloudflareAdminReceiverApi>(
  (ref) {
    ref.watch(
      cloudflareAdminSessionProvider.select(
        (v) => v.asData?.value?.authorityKey,
      ),
    );
    return CloudflareAdminReceiverApi(
      ref.read(cloudflareAdminSessionProvider.notifier),
    );
  },
);

class CloudflareAdminReceiverApi {
  CloudflareAdminReceiverApi(this.session)
    : _authority = session.user?.authorityKey;
  final CloudflareAdminSession session;
  final Object? _authority;
  bool get canManage =>
      _current &&
      session.user!.role != AdminAccountRole.staff &&
      session.user!.permissions.contains('gateway.manage');
  bool get _current =>
      _authority != null && session.user?.authorityKey == _authority;
  void _allow([bool manage = false]) {
    if (!_current ||
        session.user!.permissions.contains('gateway.read') != true ||
        manage && !canManage) {
      throw const AdminAccountException(
        'This receiver capture action is unavailable to your current account.',
      );
    }
  }

  void _paging(int offset, int limit) {
    if (!_integer(offset) || offset > 2147483647 || limit < 1 || limit > 100) {
      throw const FormatException('Select a valid receiver capture page.');
    }
  }

  Future<Map<String, dynamic>> _read(String path) async {
    _allow();
    final result = await session.request('gateway/$path', authenticated: true);
    _allow();
    return result;
  }

  Future<({List<ReceiverCaptureGrant> rows, int total})> grants({
    String status = '',
    int offset = 0,
    int limit = 25,
  }) async {
    _paging(offset, limit);
    if (!{'', 'active', 'revoked'}.contains(status)) {
      throw const FormatException('Select a valid capture status.');
    }
    final q = Uri(
      queryParameters: {
        'limit': '$limit',
        'offset': '$offset',
        if (status.isNotEmpty) 'status': status,
      },
    ).query;
    final result = await _read('receiver-grants?$q');
    _keys(result, {'rows', 'total', 'limit', 'offset'});
    if (!_integer(result['total']) ||
        result['offset'] != offset ||
        result['limit'] != limit ||
        result['rows'] is! List) {
      _invalid();
    }
    final rows = (result['rows'] as List)
        .map((v) => ReceiverCaptureGrant.parse(_map(v)))
        .toList();
    if (rows.length != ((result['total'] as int) - offset).clamp(0, limit) ||
        rows.map((v) => v.id).toSet().length != rows.length ||
        status.isNotEmpty && rows.any((v) => v.values['status'] != status)) {
      _invalid();
    }
    return (
      rows: List<ReceiverCaptureGrant>.unmodifiable(rows),
      total: result['total'] as int,
    );
  }

  Future<ReceiverCaptureDetail> detail(
    String id, {
    int offset = 0,
    int limit = 25,
  }) async {
    _paging(offset, limit);
    if (!_identifier(id)) {
      throw const FormatException('Select a valid capture grant.');
    }
    final result = await _read(
      'receiver-grants/$id?limit=$limit&offset=$offset',
    );
    _keys(result, {
      'resource_type',
      'resource',
      'current_actor_id',
      'can_manage',
      'related',
      'related_total',
      'related_limit',
      'related_offset',
    });
    final related = _map(result['related']);
    _keys(related, {'captures'});
    if (result['resource_type'] != 'receiver_capture_grants' ||
        result['current_actor_id'] != session.user?.id ||
        result['can_manage'] is! bool ||
        result['can_manage'] == true && !canManage ||
        !_integer(result['related_total']) ||
        result['related_limit'] != limit ||
        result['related_offset'] != offset ||
        related['captures'] is! List) {
      _invalid();
    }
    final grant = ReceiverCaptureGrant.parse(_map(result['resource']));
    if (grant.id != id) _invalid();
    final captures = (related['captures'] as List).map((v) {
      final row = _map(v);
      _keys(row, {
        'id',
        'request_id',
        'client_sms_id',
        'ingress_id',
        'payload_sha256',
        'issued_at',
        'source_received_at',
        'accepted_at',
        'metadata_accepted',
        'provider_confirmation',
        'send_authority',
        'financial_authority',
      });
      if (![
            'id',
            'request_id',
            'client_sms_id',
            'ingress_id',
          ].every((k) => _identifier(row[k])) ||
          row['payload_sha256'] is! String ||
          !_digest.hasMatch(row['payload_sha256'] as String) ||
          !_sourceTime(row['issued_at']) ||
          !['source_received_at', 'accepted_at'].every((k) => _time(row[k])) ||
          row['metadata_accepted'] != true ||
          row['provider_confirmation'] != false ||
          row['send_authority'] != false ||
          row['financial_authority'] != false) {
        _invalid();
      }
      return Map<String, dynamic>.unmodifiable(row);
    }).toList();
    if (captures.length !=
            ((result['related_total'] as int) - offset).clamp(0, limit) ||
        captures.map((v) => v['id']).toSet().length != captures.length) {
      _invalid();
    }
    return ReceiverCaptureDetail(
      grant,
      result['can_manage'] as bool,
      List.unmodifiable(captures),
      result['related_total'] as int,
      limit,
      offset,
    );
  }

  Future<CloudflareOperationReceipt> submit({
    required String key,
    required Map<String, dynamic> body,
    String? revokeId,
  }) async {
    _allow(true);
    final keys = revokeId == null
        ? {
            'device_id',
            'expected_device_version',
            'payee_id',
            'expected_payee_version',
            'reason',
          }
        : {'expected_version', 'reason'};
    _keys(body, keys);
    if (!_identifier(key) ||
        !_text(body['reason'], 1000) ||
        (body['reason'] as String).trim().runes.length < 8 ||
        (revokeId == null
            ? !_identifier(body['device_id']) ||
                  !_identifier(body['payee_id']) ||
                  !_integer(body['expected_device_version'], 1) ||
                  !_integer(body['expected_payee_version'], 1)
            : !_identifier(revokeId) ||
                  !_integer(body['expected_version'], 1))) {
      throw const FormatException(
        'Confirm the current device, payee and review reason.',
      );
    }
    final result = await session.request(
      'gateway/receiver-grants${revokeId == null ? '' : '/$revokeId/revoke'}',
      body: body,
      method: 'POST',
      authenticated: true,
      idempotencyKey: key,
    );
    _allow(true);
    try {
      final receipt = CloudflareOperationReceipt.parse(result);
      _receipt(receipt, revokeId: revokeId);
      return receipt;
    } on FormatException {
      throw const CloudflareAdminRequestException(
        'The capture acknowledgement could not confirm completion. Check the original request receipt.',
        outcomeUnknown: true,
      );
    }
  }

  void _receipt(CloudflareOperationReceipt receipt, {String? revokeId}) {
    if (receipt.resourceType != 'receiver_capture_grants' ||
        revokeId != null && receipt.resourceId != revokeId ||
        receipt.version != (revokeId == null ? 1 : 2)) {
      _invalid();
    }
  }

  Future<CloudflareOperationReceipt?> lookup(
    String key, {
    String? revokeId,
  }) async {
    if (!_identifier(key) || revokeId != null && !_identifier(revokeId)) {
      throw const FormatException(
        'Use the original capture request reference.',
      );
    }
    final result = await _read('receiver-requests/$key');
    if (result['found'] == false) {
      _keys(result, {'found'});
      return null;
    }
    _keys(result, {'found', 'receipt'});
    if (result['found'] != true) _invalid();
    final receipt = CloudflareOperationReceipt.parse(_map(result['receipt']));
    _receipt(receipt, revokeId: revokeId);
    return receipt;
  }
}
