import 'admin_models.dart';
import 'admin_transaction_details.dart';
import 'admin_member_identity_contract.dart';
import '../../core/data/exact_json_values.dart';

// These are wire contracts of the installed Admin read RPCs. DTO presentation
// defaults must never certify a malformed server response as an empty queue.
final _uuid = RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$');
final _symbol = RegExp(r'^[a-z][a-z0-9_.-]*$');
const _maximumInteger = maxExactJsonInteger;

Never _invalid() => throw const FormatException('Invalid Admin read response.');

Map<String, dynamic> _object(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) _invalid();
  return Map<String, dynamic>.from(value);
}

void _keys(Map<String, dynamic> row, Set<String> expected) {
  if (row.length != expected.length || !row.keys.every(expected.contains)) {
    _invalid();
  }
}

bool _text(Object? value, {bool empty = false, int max = 1000}) =>
    value is String &&
    value.length <= max &&
    (empty || value.trim().isNotEmpty);
bool _identifier(Object? value) =>
    _text(value, max: 128) && _symbol.hasMatch(value as String);
bool _integer(Object? value, {int min = 0, int max = _maximumInteger}) =>
    value is int && value >= min && value <= max;
bool _uuidValue(Object? value) => value is String && _uuid.hasMatch(value);
bool _stringList(Object? value) =>
    value is List &&
    value.length <= 256 &&
    value.every(_identifier) &&
    value.toSet().length == value.length;

AdminIdentity? parseAdminIdentity(Object? value, {required String actorId}) {
  if (value == null) return null;
  final row = _object(value);
  if (row.isEmpty) return null;
  _keys(row, {
    'user_id',
    'display_name',
    'phone_masked',
    'roles',
    'permissions',
  });
  if (!_uuidValue(row['user_id']) ||
      row['user_id'] != actorId ||
      !_text(row['display_name']) ||
      (row['phone_masked'] != null && !_text(row['phone_masked'], max: 128)) ||
      !_stringList(row['roles']) ||
      !_stringList(row['permissions'])) {
    _invalid();
  }
  return AdminIdentity(
    userId: row['user_id'] as String,
    displayName: row['display_name'] as String,
    phoneMasked: row['phone_masked'] as String?,
    roles: List<String>.unmodifiable(row['roles'] as List),
    permissions: List<String>.unmodifiable(row['permissions'] as List),
  );
}

List<AdminMetric> parseAdminOverview(Map<String, dynamic> row) {
  _keys(row, {'metrics'});
  final metrics = row['metrics'];
  if (metrics is! List || metrics.length > 256) _invalid();
  final labels = <String>{};
  return List<AdminMetric>.unmodifiable([
    for (final raw in metrics)
      (() {
        final item = _object(raw);
        _keys(item, {'label', 'value', 'status'});
        final amount = const {
          'Total collected',
          'Verified posted total',
        }.contains(item['label']);
        final validValue = amount
            ? item['value'] is String &&
                  RegExp(
                    r'^(0|[1-9][0-9]*)(\.[0-9]{1,2})?$',
                  ).hasMatch(item['value'] as String)
            : _integer(item['value']);
        if (!_text(item['label'], max: 256) ||
            !labels.add(item['label'] as String) ||
            !validValue ||
            !const {'active', 'needs_review'}.contains(item['status'])) {
          _invalid();
        }
        return AdminMetric.fromJson(item);
      })(),
  ]);
}

void _objects(Object? value, void Function(Map<String, dynamic>) validate) {
  if (value is! List || value.length > 1000) _invalid();
  for (final raw in value) {
    validate(_object(raw));
  }
}

AdminRuntimeConfig parseAdminRuntimeConfig(Map<String, dynamic> row) {
  _keys(row, {'navigation_items', 'queue_specs'});
  final keys = <String>{}, paths = <String>{}, queues = <String>{};
  _objects(row['navigation_items'], (item) {
    _keys(item, {
      'key',
      'label',
      'icon_key',
      'route_path',
      'required_permission',
      'display_order',
    });
    final path = item['route_path'];
    if (!_identifier(item['key']) ||
        !keys.add(item['key'] as String) ||
        !_text(item['label']) ||
        !_identifier(item['icon_key']) ||
        !_text(path, max: 256) ||
        !RegExp(r'^/admin(?:/[a-z0-9_-]+)*$').hasMatch(path as String) ||
        !paths.add(path) ||
        !_identifier(item['required_permission']) ||
        !_integer(item['display_order'], min: -2147483648, max: 2147483647)) {
      _invalid();
    }
  });
  _objects(row['queue_specs'], (item) {
    _keys(item, {
      'rpc_name',
      'title',
      'subtitle',
      'required_permission',
      'status_options',
      'sort_options',
      'priority_signals',
      'workflow_steps',
    });
    if (!_identifier(item['rpc_name']) ||
        !(item['rpc_name'] as String).startsWith('admin_list_') ||
        !queues.add(item['rpc_name'] as String) ||
        !_text(item['title']) ||
        !_text(item['subtitle'], empty: true) ||
        !_identifier(item['required_permission'])) {
      _invalid();
    }
    for (final field in ['status_options', 'sort_options']) {
      final values = <String>{};
      _objects(item[field], (option) {
        _keys(option, {'value', 'label'});
        if (!_text(option['value'], empty: true, max: 128) ||
            !values.add(option['value'] as String) ||
            !_text(option['label'])) {
          _invalid();
        }
      });
    }
    for (final field in ['priority_signals', 'workflow_steps']) {
      _objects(item[field], (signal) {
        _keys(signal, {'icon_key', 'label'});
        if (!_identifier(signal['icon_key']) || !_text(signal['label'])) {
          _invalid();
        }
      });
    }
  });
  return AdminRuntimeConfig.fromJson(row);
}

String validateAdminQueueSlaRequest(String queueKey) {
  final normalized = queueKey.trim();
  if (!_identifier(normalized) ||
      !RegExp(r'^admin_list_[a-z][a-z0-9_]*$').hasMatch(normalized)) {
    _invalid();
  }
  return normalized;
}

AdminQueueSla? parseAdminQueueSla(Object? value, {required String queueKey}) {
  final normalized = validateAdminQueueSlaRequest(queueKey);
  final row = _object(value);
  if (row.isEmpty) return null; // The source RPC's explicit policy-not-found.
  _keys(row, {'queue_key', 'target', 'owner', 'escalation', 'updated_at'});
  if (row['queue_key'] != normalized ||
      !_text(row['target']) ||
      !_text(row['owner']) ||
      !_text(row['escalation']) ||
      !_timestamp(row['updated_at'])) {
    _invalid();
  }
  return AdminQueueSla.fromJson(row);
}

bool adminApprovalReadMatches(String userId, Map<String, dynamic> row) {
  try {
    _keys(row, {
      'user_id',
      'phone_masked',
      'approved_at',
      'expires_at',
      'status',
      'approved',
      'role_granted',
      'admin_access',
      'access_status',
    });
    if (!_uuidValue(userId) ||
        row['user_id'] != userId ||
        (row['phone_masked'] != null &&
            !_text(row['phone_masked'], max: 128)) ||
        (row['approved_at'] != null && !_timestamp(row['approved_at'])) ||
        (row['expires_at'] != null && !_timestamp(row['expires_at'])) ||
        row['approved'] is! bool ||
        row['role_granted'] is! bool ||
        row['admin_access'] is! bool ||
        !const {
          'not_approved',
          'revoked',
          'expired',
          'identity_changed',
          'approved',
        }.contains(row['status'])) {
      return false;
    }
    final approved = row['approved'] as bool,
        granted = row['role_granted'] as bool;
    return (row['status'] == 'approved') == approved &&
        row['admin_access'] == (approved && granted) &&
        row['access_status'] ==
            (approved && granted
                ? 'active'
                : granted
                ? 'approval_required'
                : approved
                ? 'approved'
                : 'revoked');
  } on FormatException {
    return false;
  }
}

enum _Field {
  text,
  optionalText,
  uuid,
  optionalUuid,
  count,
  boolean,
  strings,
  date,
  optionalDate,
}

bool _timestamp(Object? value) {
  if (value is! String) return false;
  try {
    exactJsonTimestamp(value, field: 'Admin read timestamp');
    return true;
  } on FormatException {
    return false;
  }
}

bool _field(Object? value, _Field type) => switch (type) {
  _Field.text => _text(value, empty: true, max: 16000),
  _Field.optionalText => value == null || _text(value, empty: true, max: 16000),
  _Field.uuid => _uuidValue(value),
  _Field.optionalUuid => value == null || _uuidValue(value),
  _Field.count => _integer(value),
  _Field.boolean => value is bool,
  _Field.strings => _stringList(value),
  _Field.date => _timestamp(value),
  _Field.optionalDate => value == null || _timestamp(value),
};

const _detailContracts = <String, Map<String, _Field>>{
  'admin_get_user': {
    'email': _Field.optionalText,
    'display_name': _Field.optionalText,
    'user_type': _Field.text,
    'id': _Field.uuid,
    'public_id': _Field.optionalText,
    'whatsapp_phone': _Field.optionalText,
    'momo_number': _Field.optionalText,
    'momo_pay_code': _Field.optionalText,
    'momo_provider': _Field.optionalText,
    'active_groups': _Field.count,
    'groups_total': _Field.count,
    'status': _Field.text,
    'created_at': _Field.optionalDate,
    'updated_at': _Field.date,
  },
  'admin_get_member_record': {
    'id': _Field.uuid,
    'collect_id': _Field.text,
    'member_name': _Field.optionalText,
    'momo_registered_name': _Field.optionalText,
    'momo_number': _Field.optionalText,
    'whatsapp_phone': _Field.optionalText,
    'momo_pay_code': _Field.optionalText,
    'member_type': _Field.text,
    'contributed_amount_rwf': _Field.optionalText,
    'contribution_status': _Field.text,
    'account_state': _Field.text,
    'origin': _Field.text,
    'lifecycle': _Field.text,
    'active_groups': _Field.count,
    'created_at': _Field.date,
  },
  'admin_get_collection': {
    'admin_operator_draft': _Field.boolean,
    'id': _Field.uuid,
    'slug': _Field.optionalText,
    'title': _Field.text,
    'description': _Field.optionalText,
    'creator_user_id': _Field.optionalUuid,
    'creator_label': _Field.optionalText,
    'collection_type': _Field.text,
    'category_subtype': _Field.optionalText,
    'purpose_label': _Field.optionalText,
    'receiver_display_label': _Field.optionalText,
    'receiver_momo_code': _Field.optionalText,
    'receiver_network': _Field.optionalText,
    'is_platform_sponsored': _Field.boolean,
    'visibility': _Field.text,
    'public_status': _Field.text,
    'status': _Field.text,
    'creation_origin': _Field.text,
    'archived_at': _Field.optionalDate,
    'currency': _Field.text,
    'active_receivers': _Field.count,
    'active_members': _Field.count,
    'pending_payment_intents': _Field.count,
    'created_at': _Field.date,
    'updated_at': _Field.date,
  },
  'admin_get_notification': {
    'id': _Field.uuid,
    'type': _Field.text,
    'title': _Field.text,
    'status': _Field.text,
    'collect_id': _Field.text,
    'collection_id': _Field.optionalUuid,
    'deep_link': _Field.optionalText,
    'delivery_statuses': _Field.text,
    'retryable_count': _Field.count,
    'cumulative_attempt_count': _Field.count,
    'last_error_code': _Field.optionalText,
    'created_at': _Field.date,
    'sent_at': _Field.optionalDate,
    'read_at': _Field.optionalDate,
  },
  'admin_get_hybrid_sms_receipt': {
    'id': _Field.uuid,
    'state': _Field.text,
    'channel': _Field.text,
    'member_collect_id': _Field.text,
    'collection_id': _Field.uuid,
    'collection_title': _Field.text,
    'destination_masked': _Field.text,
    'amount_rwf': _Field.count,
    'member_balance_rwf': _Field.count,
    'group_balance_rwf': _Field.count,
    'reference': _Field.text,
    'template_key': _Field.text,
    'template_version': _Field.count,
    'consent_revision': _Field.count,
    'authorization_current': _Field.boolean,
    'body_sha256': _Field.optionalText,
    'message_body': _Field.text,
    'attempt_count': _Field.count,
    'claim_expires_at': _Field.optionalDate,
    'suppression_reason': _Field.optionalText,
    'created_at': _Field.date,
    'observed_sent_at': _Field.optionalDate,
    'latest_attempt_state': _Field.optionalText,
    'delivery_claim': _Field.text,
  },
  'admin_get_staff_user_v1': {
    'id': _Field.uuid,
    'display_name': _Field.optionalText,
    'email': _Field.optionalText,
    'public_id': _Field.optionalText,
    'staff_access': _Field.boolean,
    'operator_approved': _Field.boolean,
    'created_at': _Field.date,
  },
  'admin_get_admin_user': {
    'id': _Field.uuid,
    'user_id': _Field.uuid,
    'public_id': _Field.text,
    'phone_masked': _Field.optionalText,
    'approved_at': _Field.optionalDate,
    'expires_at': _Field.optionalDate,
    'status': _Field.text,
    'approved': _Field.boolean,
    'role_granted': _Field.boolean,
    'admin_access': _Field.boolean,
    'access_status': _Field.text,
    'whatsapp_approval': _Field.text,
    'active_roles': _Field.strings,
    'created_at': _Field.date,
  },
};

void validateAdminDetailRequest(String rpcName, String id) {
  if (id.isEmpty || id.length > 160) _invalid();
  if (_detailContracts.containsKey(rpcName) && !_uuidValue(id)) _invalid();
  if (rpcName == 'admin_get_collect_transaction') {
    final match = RegExp(r'^momo:([0-9a-f-]{36})$').firstMatch(id);
    if (match == null || !_uuidValue(match[1])) _invalid();
  }
}

Map<String, dynamic> validateAdminDetail(
  String rpcName,
  String id,
  Map<String, dynamic> row,
) {
  validateAdminDetailRequest(rpcName, id);
  if (row.isEmpty) {
    return row; // The existing SQL contract's real not-found state.
  }
  if (row['id'] != id) _invalid();
  var contract = _detailContracts[rpcName];
  if (rpcName == 'admin_get_collect_transaction') {
    final match = RegExp(r'^momo:([0-9a-f-]{36})$').firstMatch(id);
    if (match == null || !_uuidValue(match[1])) _invalid();
    contract = {
      'id': _Field.text,
      'transaction_id': _Field.text,
      'payment_route': _Field.text,
      'rail': _Field.text,
      'sms_sender': _Field.optionalText,
      'parse_status': _Field.text,
      'reference': _Field.optionalText,
      'amount': _Field.optionalText,
      'payee': _Field.text,
      'group_name': _Field.optionalText,
      'allocation_status': _Field.text,
      'received_at': _Field.date,
      'created_at': _Field.date,
      'raw_sms_id': _Field.uuid,
      'sender_name': _Field.optionalText,
      'network': _Field.text,
    };
    final supplement = AdminTransactionDetails.parse(row);
    if (supplement.member != null) {
      validateAdminDetail(
        'admin_get_member_record',
        supplement.member!['id'] as String,
        supplement.member!,
      );
    }
    if (row['rail'] != 'rw_momo' || row['raw_sms_id'] != match[1]) {
      _invalid();
    }
  }
  if (contract != null) {
    final baseRow = rpcName == 'admin_get_collect_transaction'
        ? (Map<String, dynamic>.from(row)..removeWhere(
            (key, _) => const {
              'collect_transaction_id',
              'identity_status',
              'sms_details',
              'payer_insights',
            }.contains(key),
          ))
        : row;
    _keys(baseRow, contract.keys.toSet());
    for (final field in contract.entries) {
      if (!_field(row[field.key], field.value)) _invalid();
    }
  }
  if (rpcName == 'admin_get_admin_user' && row['user_id'] != id) _invalid();
  if (rpcName == 'admin_get_staff_user_v1' &&
      (row['public_id'] != null &&
              !RegExp(r'^[0-9]{6}$').hasMatch(row['public_id'] as String) ||
          row['staff_access'] == true && row['operator_approved'] != true)) {
    _invalid();
  }
  if (rpcName == 'admin_get_user' &&
      ((row['public_id'] != null &&
              !RegExp(r'^[0-9]{6}$').hasMatch(row['public_id'] as String)) ||
          !{'admin', 'active', 'registered'}.contains(row['status']) ||
          !{'Admin', 'Staff', 'App'}.contains(row['user_type']) ||
          (row['groups_total'] as int) < (row['active_groups'] as int))) {
    _invalid();
  }
  if (rpcName == 'admin_get_member_record') validateAdminMemberIdentity(row);
  if (rpcName == 'admin_get_hybrid_sms_receipt') {
    final digest = row['body_sha256'];
    if (row['channel'] != 'Assisted SMS operator' ||
        row['message_body'] != 'Hidden until a current fenced operator claim' ||
        row['delivery_claim'] !=
            'Observed sent is operator-recorded UI evidence, not handset delivery' ||
        !RegExp(
          r'^\+250•••[0-9]{3}$',
        ).hasMatch(row['destination_masked'] as String) ||
        (digest != null &&
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest as String))) {
      _invalid();
    }
  }
  return Map<String, dynamic>.unmodifiable(row);
}
