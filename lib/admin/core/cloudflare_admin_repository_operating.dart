part of 'cloudflare_admin_repository.dart';

/// Native operating contracts are deliberately separate from legacy RPC actions.
enum CloudflareOperation {
  createGroup('groups', 'collections.manage'),
  updateGroup('groups', 'collections.manage', update: true),
  createUser('users', 'users.manage'),
  updateUser('users', 'users.manage', update: true),
  createMembership('memberships', 'users.manage'),
  updateMembership('memberships', 'users.manage', update: true),
  createPayee('payees', 'receivers.manage'),
  updatePayee('payees', 'receivers.manage', update: true),
  createAccount('accounts', 'ledger.manage'),
  updateAccount('accounts', 'ledger.manage', update: true),
  createTransaction('transactions', 'payments.manage'),
  addEvidence('transactions', 'payments.manage', suffix: 'evidence'),
  verifyTransaction('transactions', 'payments.manage', suffix: 'verification'),
  allocateTransaction('transactions', 'payments.manage', suffix: 'allocations'),
  createJournal('journals', 'ledger.manage'),
  updateJournal('journals', 'ledger.manage', update: true),
  postJournal('journals', 'ledger.manage', suffix: 'post');

  const CloudflareOperation(
    this.resource,
    this.permission, {
    this.update = false,
    this.suffix,
  });
  final String resource, permission;
  final bool update;
  final String? suffix;
  bool get needsVersion => update || suffix != null;
  String get method => update ? 'PATCH' : 'POST';

  String path(String? id) {
    if (needsVersion) {
      final ids = id?.split('/') ?? [];
      if (ids.length != (resource == 'memberships' ? 2 : 1) ||
          !ids.every(_coreId)) {
        throw const FormatException('Select a valid record.');
      }
    } else if (id != null) {
      throw const FormatException(
        'Create requests cannot target an existing record.',
      );
    }
    return 'operations/$resource${needsVersion ? '/$id' : ''}${suffix == null ? '' : '/$suffix'}';
  }
}

extension CloudflareCoreOperating on CloudflareCoreArea {
  String get nativeResource => switch (this) {
    CloudflareCoreArea.members => 'users',
    CloudflareCoreArea.ledgers => 'journals',
    _ => name,
  };
  CloudflareOperation get createOperation => switch (this) {
    CloudflareCoreArea.groups => CloudflareOperation.createGroup,
    CloudflareCoreArea.users => CloudflareOperation.createUser,
    CloudflareCoreArea.members => CloudflareOperation.createMembership,
    CloudflareCoreArea.payees => CloudflareOperation.createPayee,
    CloudflareCoreArea.transactions => CloudflareOperation.createTransaction,
    CloudflareCoreArea.ledgers => CloudflareOperation.createJournal,
  };
}

class CloudflareOperatingDetail {
  const CloudflareOperatingDetail({
    required this.type,
    required this.resource,
    required this.actorId,
    required this.canManage,
    required this.related,
    required this.truncated,
    this.relatedPages = const {},
  });
  final String type, actorId;
  final Map<String, dynamic> resource;
  final bool canManage, truncated;
  final Map<String, List<Map<String, dynamic>>> related;
  final Map<String, CloudflareRelatedPage> relatedPages;
  String get id => resource['id'] as String;
  int get version => resource['version'] as int;
}

class CloudflareRelatedPage {
  const CloudflareRelatedPage({
    required this.total,
    required this.limit,
    required this.offset,
    required this.nextOffset,
  });
  final int total, limit, offset;
  final int? nextOffset;
}

class CloudflareOperationReceipt {
  const CloudflareOperationReceipt({
    required this.requestId,
    required this.resourceType,
    required this.resourceId,
    required this.version,
    this.accepted,
    this.uncertain,
    this.suppressed,
  });
  final String requestId, resourceType, resourceId;
  final int version;
  final int? accepted, uncertain, suppressed;
  factory CloudflareOperationReceipt.parse(Map<String, dynamic> data) {
    final email = data['resource_type'] == 'email_dispatch';
    if (data.length != (email ? 8 : 5) ||
        data['status'] != 'succeeded' ||
        !_coreId(data['request_id']) ||
        data['resource_type'] is! String ||
        data['resource_id'] is! String ||
        !_coreInteger(data['version']) ||
        data['version'] == 0) {
      _invalidCore();
    }
    const types = {
      'groups',
      'users',
      'memberships',
      'payees',
      'accounts',
      'transactions',
      'journals',
      'allocations',
      'evidence',
      'gateway_devices',
      'email_dispatch',
      'member_receipts',
      'receiver_capture_grants',
    };
    if (!types.contains(data['resource_type'])) _invalidCore();
    final ids = (data['resource_id'] as String).split('/');
    if (ids.length != (data['resource_type'] == 'memberships' ? 2 : 1) ||
        !ids.every(_coreId)) {
      _invalidCore();
    }
    if (email &&
        (data['resource_id'] != data['request_id'] ||
            data['version'] != 1 ||
            !['accepted', 'uncertain', 'suppressed'].every(
              (key) => _coreInteger(data[key]) && (data[key] as int) <= 20,
            ) ||
            (data['accepted'] as int) +
                    (data['uncertain'] as int) +
                    (data['suppressed'] as int) >
                20)) {
      _invalidCore();
    }
    return CloudflareOperationReceipt(
      requestId: data['request_id'] as String,
      resourceType: data['resource_type'] as String,
      resourceId: data['resource_id'] as String,
      version: data['version'] as int,
      accepted: data['accepted'] as int?,
      uncertain: data['uncertain'] as int?,
      suppressed: data['suppressed'] as int?,
    );
  }
}

/// Request history includes operating changes, SMS facts and reconciliations.
/// Operating writes still require [CloudflareOperationReceipt] explicitly.
sealed class CloudflareRequestReceipt {
  const CloudflareRequestReceipt();

  String get requestId;
  String get resourceType;
  String get resourceId;

  factory CloudflareRequestReceipt.parse(Map<String, dynamic> data) =>
      switch (data['resource_type']) {
        'sms_facts' => CloudflareSmsFactsRequestReceipt(
          SmsExtractionReceipt.parse(data),
        ),
        'reconciliation_proposals' => CloudflareReconciliationRequestReceipt(
          ReconciliationReceipt.parse(data),
        ),
        _ => CloudflareVersionedRequestReceipt(
          CloudflareOperationReceipt.parse(data),
        ),
      };
}

final class CloudflareVersionedRequestReceipt extends CloudflareRequestReceipt {
  const CloudflareVersionedRequestReceipt(this.operation);
  final CloudflareOperationReceipt operation;
  @override
  String get requestId => operation.requestId;
  @override
  String get resourceType => operation.resourceType;
  @override
  String get resourceId => operation.resourceId;
}

final class CloudflareSmsFactsRequestReceipt extends CloudflareRequestReceipt {
  const CloudflareSmsFactsRequestReceipt(this.extraction);
  final SmsExtractionReceipt extraction;
  @override
  String get requestId => extraction.values['request_id'] as String;
  @override
  String get resourceType => extraction.values['resource_type'] as String;
  @override
  String get resourceId => extraction.values['resource_id'] as String;
  String get sourceKind => extraction.values['source_kind'] as String;
  String get sourceId => extraction.values['source_id'] as String;
  String get parserVersion => extraction.values['parser_version'] as String;
}

final class CloudflareReconciliationRequestReceipt
    extends CloudflareRequestReceipt {
  const CloudflareReconciliationRequestReceipt(this.reconciliation);
  final ReconciliationReceipt reconciliation;
  @override
  String get requestId => reconciliation.values['request_id'] as String;
  @override
  String get resourceType => 'reconciliation_proposals';
  @override
  String get resourceId => reconciliation.proposalId;
  String get transactionId => reconciliation.values['transaction_id'] as String;
}

bool _requestReceiptMatchesScope(
  CloudflareRequestReceipt receipt,
  String scope,
) => switch (receipt) {
  CloudflareSmsFactsRequestReceipt() => scope == 'sms.extract',
  CloudflareReconciliationRequestReceipt(:final reconciliation) =>
    scope ==
        (reconciliation.status == 'pending'
            ? 'reconciliations.propose'
            : 'reconciliations.review'),
  CloudflareVersionedRequestReceipt() =>
    _versionedRequestScopes[receipt.resourceType]?.contains(scope) ?? false,
};

const _versionedRequestScopes = <String, Set<String>>{
  'groups': {'groups.post', 'groups.patch'},
  'users': {'users.post', 'users.patch'},
  'memberships': {'memberships.post', 'memberships.patch'},
  'payees': {'payees.post', 'payees.patch'},
  'accounts': {'accounts.post', 'accounts.patch'},
  'transactions': {
    'transactions.post',
    'transactions.post.evidence',
    'transactions.post.verification',
    // Preserve receipt reads from the retired allocation route. This does not
    // admit that route through operate(), nor reinstate any allocation action.
    'transactions.post.allocations',
  },
  'journals': {'journals.post', 'journals.patch', 'journals.post.post'},
  'gateway_devices': {'gateway.enroll', 'gateway.activate', 'gateway.revoke'},
  'member_receipts': {'receipt.review'},
  'receiver_capture_grants': {
    'gateway.receiver.grant',
    'gateway.receiver.revoke',
  },
  'email_dispatch': {'email_dispatch'},
  // These strict receipt resource types remain read-only historical variants.
  'allocations': {'transactions.post.allocations'},
  'evidence': {'transactions.post.evidence'},
};

extension CloudflareOperatingRepository on CloudflareAdminRepository {
  Future<CloudflareOperatingDetail> operatingDetail(
    String type,
    String id, {
    String? relation,
    int limit = 50,
    int offset = 0,
  }) async {
    const permissions = {
      'groups': 'collections.read',
      'users': 'users.read',
      'payees': 'receivers.read',
      'transactions': 'payments.read',
      'journals': 'ledger.read',
      'accounts': 'ledger.read',
    };
    if (!permissions.containsKey(type) || !_coreId(id)) {
      throw const FormatException('Select a valid record.');
    }
    if (relation != null &&
        (!RegExp(r'^[a-z_]{1,40}$').hasMatch(relation) ||
            limit < 1 ||
            limit > 100 ||
            offset < 0 ||
            offset > 2147483647)) {
      throw const FormatException('Select a valid related page.');
    }
    final query = relation == null
        ? ''
        : '?${Uri(queryParameters: {'relation': relation, 'limit': '$limit', 'offset': '$offset'}).query}';
    final result = await _read(
      'operations/$type/$id$query',
      permissions[type]!,
    );
    if ((result.length != 6 && result.length != 7) ||
        (result.length == 7 && result['related_pages'] is! Map) ||
        result['resource_type'] != type ||
        result['resource'] is! Map ||
        result['current_actor_id'] != session.user?.id ||
        result['can_manage'] is! bool ||
        result['related'] is! Map ||
        result['related_truncated'] is! bool) {
      _invalidCore();
    }
    final resource = Map<String, dynamic>.from(result['resource'] as Map);
    if ((resource['id'] != id &&
            !(type == 'users' && resource['operator_admin_id'] == id)) ||
        !_coreInteger(resource['version']) ||
        resource['version'] == 0) {
      _invalidCore();
    }
    _validateOperatingNumbers(resource);
    if (type == 'transactions') {
      validateCloudflareTransactionFacts(resource, operating: true);
    }
    final staff = session.user?.role == AdminAccountRole.staff;
    if (staff && result['can_manage'] != false) _invalidCore();
    const relatedFields = {
      'groups': {'memberships', 'payees', 'accounts'},
      'users': {'memberships'},
      'payees': <String>{},
      'accounts': <String>{},
      'transactions': {
        'evidence',
        'reviews',
        'allocations',
        'journals',
        'payer_insights',
      },
      'journals': {'entries'},
    };
    final related = <String, List<Map<String, dynamic>>>{};
    for (final entry in (result['related'] as Map).entries) {
      if (entry.key is! String ||
          !relatedFields[type]!.contains(entry.key) ||
          entry.value is! List ||
          (entry.value as List).length > 200) {
        _invalidCore();
      }
      related[entry.key as String] = [
        for (final row in entry.value as List)
          if (row is Map) Map<String, dynamic>.from(row) else _invalidCore(),
      ];
      for (final row in related[entry.key]!) {
        _validateOperatingNumbers(row);
      }
    }
    final pages = <String, CloudflareRelatedPage>{};
    final rawPages = result['related_pages'];
    if (rawPages != null) {
      if (rawPages is! Map || rawPages.length != related.length) _invalidCore();
      for (final entry in related.entries) {
        final page = rawPages[entry.key];
        if (page is! Map ||
            page.length != 4 ||
            !_coreInteger(page['total']) ||
            !_coreInteger(page['limit']) ||
            (page['limit'] as int) < 1 ||
            (page['limit'] as int) > 100 ||
            !_coreInteger(page['offset']) ||
            (page['next_offset'] != null &&
                !_coreInteger(page['next_offset']))) {
          _invalidCore();
        }
        final total = page['total'] as int,
            size = page['limit'] as int,
            start = page['offset'] as int;
        final count = (total - start).clamp(0, size);
        if (entry.value.length != count ||
            page['next_offset'] !=
                (start + count < total ? start + count : null)) {
          _invalidCore();
        }
        pages[entry.key] = CloudflareRelatedPage(
          total: total,
          limit: size,
          offset: start,
          nextOffset: page['next_offset'] as int?,
        );
      }
    } else if (result['related_truncated'] == true) {
      _invalidCore();
    }
    return CloudflareOperatingDetail(
      type: type,
      resource: resource,
      actorId: result['current_actor_id'] as String,
      canManage: result['can_manage'] as bool,
      related: related,
      relatedPages: pages,
      truncated: result['related_truncated'] as bool,
    );
  }

  Future<List<Map<String, dynamic>>> operatingLookups(
    String kind, {
    String? groupId,
    String search = '',
  }) async {
    const permissions = {
      'groups': 'collections.read',
      'users': 'users.read',
      'members': 'users.read',
      'payees': 'receivers.read',
      'accounts': 'ledger.read',
    };
    if (!permissions.containsKey(kind) ||
        search.length > 200 ||
        ({'payees', 'accounts', 'members'}.contains(kind)
            ? !_coreId(groupId)
            : groupId != null)) {
      throw const FormatException(
        'Select the group before choosing its records.',
      );
    }
    final query = Uri(
      queryParameters: {
        'kind': kind,
        'search': search.trim(),
        'limit': '100',
        'group_id': ?groupId,
      },
    ).query;
    final result = await _read('operations/lookups?$query', permissions[kind]!);
    if (result['rows'] is! List || (result['rows'] as List).length > 100) {
      _invalidCore();
    }
    final rows = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final value in result['rows'] as List) {
      if (value is! Map ||
          !_coreId(value['id']) ||
          value['label'] is! String ||
          (value['label'] as String).trim().isEmpty ||
          !_coreInteger(value['version']) ||
          value['version'] == 0 ||
          !seen.add(value['id'] as String)) {
        _invalidCore();
      }
      rows.add(Map<String, dynamic>.from(value));
    }
    return rows;
  }

  Future<CloudflareOperationReceipt> operate(
    CloudflareOperation operation, {
    String? id,
    required String key,
    required Map<String, dynamic> body,
  }) async {
    if (operation == CloudflareOperation.allocateTransaction) {
      throw const AdminAccountException(
        'Use Reconciliations to select the member, confirm their MoMo identity and obtain independent review.',
      );
    }
    final path = operation.path(id);
    if (!RegExp(r'^[A-Za-z0-9_.-]{8,200}$').hasMatch(key) ||
        body['reason'] is! String ||
        (body['reason'] as String).trim().runes.length < 8 ||
        (body['reason'] as String).trim().runes.length > 1000 ||
        (operation.needsVersion &&
            (!_coreInteger(body['expected_version']) ||
                body['expected_version'] == 0))) {
      throw const FormatException(
        'Provide a valid reason and current record version.',
      );
    }
    _validateOperatingNumbers(body);
    final requiredPermission = operation == CloudflareOperation.createGroup
        ? 'collections.create'
        : operation.permission;
    final before = _requirePermission(requiredPermission);
    if (before.role == AdminAccountRole.staff &&
        operation != CloudflareOperation.createGroup) {
      throw const AdminAccountException(
        'Your account can view records but cannot change them.',
      );
    }
    final result = await session.request(
      path,
      body: body,
      authenticated: true,
      method: operation.method,
      idempotencyKey: key,
    );
    final after = _requirePermission(requiredPermission);
    if (before.id != after.id || before.sessionId != after.sessionId) {
      throw const AdminAccountException(
        'Your session changed. Check the request before continuing.',
      );
    }
    final receipt = CloudflareOperationReceipt.parse(result);
    if (receipt.resourceType != operation.resource ||
        (operation.needsVersion && receipt.resourceId != id) ||
        receipt.version !=
            (operation.needsVersion
                ? (body['expected_version'] as int) + 1
                : 1)) {
      _invalidCore();
    }
    return receipt;
  }

  Future<({List<Map<String, dynamic>> rows, int total})> operatingRequests({
    int offset = 0,
  }) async {
    if (offset < 0 || offset > 2147483647) {
      throw const FormatException('Invalid page.');
    }
    final result = await _read(
      'operations/requests?limit=25&offset=$offset',
      'overview.read',
    );
    if (result.length != 2 ||
        result['rows'] is! List ||
        !_coreInteger(result['total'])) {
      _invalidCore();
    }
    final rows = <Map<String, dynamic>>[];
    for (final value in result['rows'] as List) {
      if (value is! Map ||
          !_coreId(value['id']) ||
          value['idempotency_key'] is! String ||
          !RegExp(
            r'^[A-Za-z0-9_.-]{8,200}$',
          ).hasMatch(value['idempotency_key'] as String) ||
          value['scope'] is! String ||
          !{'pending', 'succeeded', 'failed'}.contains(value['status']) ||
          !_coreInteger(value['created_at'])) {
        _invalidCore();
      }
      if (value['status'] == 'succeeded') {
        if (value['receipt'] is! Map) _invalidCore();
        final receipt = CloudflareRequestReceipt.parse(
          Map<String, dynamic>.from(value['receipt'] as Map),
        );
        if (receipt.requestId != value['id'] ||
            !_requestReceiptMatchesScope(receipt, value['scope'] as String)) {
          _invalidCore();
        }
      }
      rows.add(Map<String, dynamic>.from(value));
    }
    final total = result['total'] as int;
    if (rows.length > 25 || rows.length != (total - offset).clamp(0, 25)) {
      _invalidCore();
    }
    return (rows: rows, total: total);
  }

  Future<Map<String, dynamic>> operatingRequest(String key) async {
    if (!RegExp(r'^[A-Za-z0-9_.-]{8,200}$').hasMatch(key)) {
      throw const FormatException('Enter a valid request reference.');
    }
    final result = await _read('operations/requests/$key', 'overview.read');
    if (!{
      'pending',
      'succeeded',
      'failed',
      'not_found',
    }.contains(result['status'])) {
      _invalidCore();
    }
    if (result['status'] == 'succeeded') {
      if (result['receipt'] is! Map) _invalidCore();
      final receipt = CloudflareRequestReceipt.parse(
        Map<String, dynamic>.from(result['receipt'] as Map),
      );
      if (result['request_id'] != receipt.requestId) _invalidCore();
    }
    return result;
  }
}

void _validateOperatingNumbers(Map<String, dynamic> map) {
  for (final entry in map.entries) {
    if (entry.key == 'currency' && entry.value != 'RWF' ||
        entry.key == 'country_code' && entry.value != 'RW') {
      _invalidCore();
    }
    if ((entry.key == 'version' || entry.key.endsWith('_at')) &&
        entry.value != null &&
        (!_coreInteger(entry.value) || entry.value == 0)) {
      _invalidCore();
    }
    if (entry.key.endsWith('_rwf') &&
        entry.value != null &&
        !_coreInteger(entry.value)) {
      _invalidCore();
    }
    if (entry.value is Map) {
      _validateOperatingNumbers(Map<String, dynamic>.from(entry.value as Map));
    }
    if (entry.value is List) {
      for (final row in entry.value as List) {
        if (row is Map) {
          _validateOperatingNumbers(Map<String, dynamic>.from(row));
        }
      }
    }
  }
}
