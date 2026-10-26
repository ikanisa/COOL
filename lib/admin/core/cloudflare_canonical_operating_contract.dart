part of 'cloudflare_admin_repository.dart';

void _canonicalKeys(Map<dynamic, dynamic> value, Set<String> keys) {
  if (value.length != keys.length || !value.keys.every(keys.contains)) {
    _invalidCore();
  }
}

void _canonicalMarker(Map<String, dynamic> value) {
  if (value['contract_version'] != 2 ||
      value['model'] != 'canonical_evidence_ledger') {
    _invalidCore();
  }
}

void _canonicalRecord(CloudflareCoreArea area, Map<String, dynamic> row) {
  if (!_coreId(row['id']) ||
      row['title'] is! String ||
      (row['title'] as String).trim().isEmpty ||
      row['subtitle'] is! String ||
      row['amount'] is! String ||
      !area.canonicalStatuses.contains(row['status']) ||
      row['country_code'] != 'RW' ||
      row['currency_code'] != 'RWF' ||
      !_coreTimestamp(row['created_at'])) {
    _invalidCore();
  }
  _validateCanonicalCoreRow(area, row);
}

/// The canonical reconciliation UI consumes the same explicitly validated
/// evidence records as the workspace tables, without projecting journal data.
Map<String, dynamic> parseCanonicalEvidenceRecord(
  CloudflareCoreArea area,
  Map<String, dynamic> row,
) {
  _canonicalRecord(area, row);
  return Map.unmodifiable(row);
}

Map<String, dynamic> parseCanonicalRetainedEvidence(
  Map<String, dynamic> row,
  String expectedId,
) {
  _canonicalEvidence(row, expectedId);
  return Map.unmodifiable(row);
}

const _canonicalOperatingAreas = {
  'groups': CloudflareCoreArea.groups,
  'users': CloudflareCoreArea.users,
  'payees': CloudflareCoreArea.payees,
  'transactions': CloudflareCoreArea.transactions,
  'ledgers': CloudflareCoreArea.ledgers,
};

Set<CloudflareOperation> _canonicalPossibleOperations(
  String type,
  Map<String, dynamic> row,
) => switch (type) {
  'groups' => {
    if (row['status'] != 'archived') CloudflareOperation.updateGroup,
    if (row['status'] == 'active') ...{
      CloudflareOperation.createMembership,
      CloudflareOperation.updateMembership,
      CloudflareOperation.updatePayee,
      CloudflareOperation.createTransaction,
    },
  },
  'users' => {
    if (row['member_type'] != 'operator' && row['status'] != 'deleted') ...{
      CloudflareOperation.updateUser,
      if (row['status'] == 'active') CloudflareOperation.createMembership,
    },
  },
  'payees' => {if (row['status'] == 'active') CloudflareOperation.updatePayee},
  'transactions' => {
    if (const {'reconciled', 'confirmed'}.contains(row['status']) &&
        row['allocated_amount_rwf'] == row['amount_rwf'])
      CloudflareOperation.reverseTransaction,
  },
  _ => {},
};

void _canonicalMembership(
  Map<String, dynamic> row, {
  required String resourceType,
  required String resourceId,
}) {
  _canonicalKeys(row, const {
    'id',
    'group_id',
    'user_id',
    'role',
    'status',
    'version',
    'joined_at',
    'group_title',
    'public_id',
    'display_name',
    'member_type',
    'whatsapp_number',
    'momo_provider',
    'momo_number',
    'momo_pay_code',
    'account_status',
  });
  if (!['id', 'group_id', 'user_id'].every((key) => _coreId(row[key])) ||
      (resourceType == 'groups' ? row['group_id'] : row['user_id']) !=
          resourceId ||
      !{'owner', 'admin', 'member'}.contains(row['role']) ||
      !{'active', 'removed'}.contains(row['status']) ||
      !_coreInteger(row['version']) ||
      row['version'] == 0 ||
      !_coreTimestamp(row['joined_at']) ||
      !_publicId(row['public_id']) ||
      row['group_title'] is! String ||
      (row['display_name'] != null && row['display_name'] is! String) ||
      !{'app', 'direct'}.contains(row['member_type']) ||
      !{'active', 'suspended', 'deleted'}.contains(row['account_status']) ||
      !_optionalMatches(row['whatsapp_number'], r'^\+2507[2389][0-9]{7}$') ||
      (row['member_type'] == 'direct' && row['whatsapp_number'] != null) ||
      !{null, 'mtn_momo', 'airtel_money'}.contains(row['momo_provider']) ||
      !_optionalMatches(row['momo_number'], r'^07[2389][0-9]{7}$') ||
      !_optionalMatches(row['momo_pay_code'], r'^[0-9]{4,9}$')) {
    _invalidCore();
  }
}

void _canonicalEvidence(Map<String, dynamic> row, String expectedId) {
  _canonicalKeys(row, const {
    'id',
    'sha256',
    'size_bytes',
    'content_type',
    'authenticity',
    'reference',
    'observed_at',
    'created_at',
    'retained_until',
    'legal_hold',
  });
  if (row['id'] != expectedId ||
      row['sha256'] is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(row['sha256'] as String) ||
      !_coreInteger(row['size_bytes']) ||
      row['size_bytes'] == 0 ||
      row['content_type'] is! String ||
      !{
        'operator_recorded',
        'provider_authenticated',
      }.contains(row['authenticity']) ||
      (row['reference'] != null && row['reference'] is! String) ||
      !_coreTimestamp(row['observed_at']) ||
      !_coreTimestamp(row['created_at']) ||
      (row['retained_until'] != null &&
          !_coreTimestamp(row['retained_until'])) ||
      row['legal_hold'] is! bool) {
    _invalidCore();
  }
}

CloudflareOperatingDetail _parseCanonicalOperatingDetail(
  Map<String, dynamic> result,
  String type,
  String id,
  CloudflareAdminUser user,
) {
  _canonicalKeys(result, const {
    'contract_version',
    'model',
    'resource_type',
    'resource',
    'current_actor_id',
    'can_manage',
    'allowed_operations',
    'related',
    'related_pages',
    'related_truncated',
  });
  _canonicalMarker(result);
  final area = _canonicalOperatingAreas[type];
  if (area == null ||
      result['resource_type'] != type ||
      result['resource'] is! Map ||
      result['current_actor_id'] != user.id ||
      result['can_manage'] is! bool ||
      result['related_truncated'] != false ||
      result['allowed_operations'] is! List ||
      result['related'] is! Map ||
      result['related_pages'] is! Map) {
    _invalidCore();
  }
  final resource = Map<String, dynamic>.from(result['resource'] as Map);
  if (resource['id'] != id) _invalidCore();
  final base = Map<String, dynamic>.from(resource);
  if (type == 'groups') {
    if (base['description'] is! String || !_coreId(base['owner_user_id'])) {
      _invalidCore();
    }
    base.remove('description');
    base.remove('owner_user_id');
  } else if (type == 'payees') {
    if (base['label'] != base['title'] ||
        base['group_title'] != base['group_name']) {
      _invalidCore();
    }
    base.remove('label');
    base.remove('group_title');
  }
  _canonicalRecord(area, base);
  final possible = _canonicalPossibleOperations(type, resource);
  final operations = <CloudflareOperation>{};
  for (final name in result['allowed_operations'] as List) {
    final matching = possible.where((operation) => operation.name == name);
    if (matching.length != 1 || user.role == AdminAccountRole.staff) {
      _invalidCore();
    }
    final operation = matching.single;
    if (!user.permissions.contains(operation.permission) ||
        !operations.add(operation)) {
      _invalidCore();
    }
  }
  if (result['can_manage'] != operations.isNotEmpty) _invalidCore();
  final permittedRelations = switch (type) {
    'groups' => {
      if (user.permissions.contains('users.read')) 'memberships',
      if (user.permissions.contains('receivers.read')) 'payees',
    },
    'users' => {
      if (user.permissions.contains('collections.read')) 'memberships',
    },
    'transactions' => {
      'evidence',
      if (user.permissions.contains('ledger.read')) 'ledger_entries',
    },
    _ => <String>{},
  };
  final related = <String, List<Map<String, dynamic>>>{};
  final pages = <String, CloudflareRelatedPage>{};
  final rawRelated = result['related'] as Map,
      rawPages = result['related_pages'] as Map;
  if (rawPages.length != rawRelated.length) _invalidCore();
  for (final entry in rawRelated.entries) {
    final name = entry.key;
    if (name is! String ||
        !permittedRelations.contains(name) ||
        entry.value is! List) {
      _invalidCore();
    }
    final page = rawPages[name];
    if (page is! Map) _invalidCore();
    _canonicalKeys(page, const {'total', 'limit', 'offset', 'next_offset'});
    if (!['total', 'limit', 'offset'].every((key) => _coreInteger(page[key])) ||
        (page['limit'] as int) < 1 ||
        (page['limit'] as int) > 100 ||
        (entry.value as List).length !=
            ((page['total'] as int) - (page['offset'] as int)).clamp(
              0,
              page['limit'] as int,
            )) {
      _invalidCore();
    }
    final rows = <Map<String, dynamic>>[], seen = <String>{};
    for (final value in entry.value as List) {
      if (value is! Map) _invalidCore();
      final row = Map<String, dynamic>.from(value);
      if (!_coreId(row['id']) || !seen.add(row['id'] as String)) _invalidCore();
      switch (name) {
        case 'memberships':
          _canonicalMembership(row, resourceType: type, resourceId: id);
        case 'payees':
          _canonicalRecord(CloudflareCoreArea.payees, row);
          if (row['group_id'] != id) _invalidCore();
        case 'evidence':
          _canonicalEvidence(row, resource['evidence_id'] as String);
        case 'ledger_entries':
          _canonicalRecord(CloudflareCoreArea.ledgers, row);
          if (row['payment_id'] != id ||
              row['evidence_id'] != resource['evidence_id']) {
            _invalidCore();
          }
        default:
          _invalidCore();
      }
      rows.add(Map.unmodifiable(row));
    }
    final next = (page['offset'] as int) + rows.length;
    if (page['next_offset'] != (next < (page['total'] as int) ? next : null)) {
      _invalidCore();
    }
    related[name] = List.unmodifiable(rows);
    pages[name] = CloudflareRelatedPage(
      total: page['total'] as int,
      limit: page['limit'] as int,
      offset: page['offset'] as int,
      nextOffset: page['next_offset'] as int?,
    );
  }
  return CloudflareOperatingDetail(
    type: type,
    resource: Map.unmodifiable(resource),
    actorId: user.id,
    canManage: result['can_manage'] as bool,
    allowedOperations: Set.unmodifiable(operations),
    sourceModel: 'canonical_evidence_ledger',
    related: Map.unmodifiable(related),
    relatedPages: Map.unmodifiable(pages),
    truncated: false,
  );
}
