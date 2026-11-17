import 'package:uuid/uuid.dart';

import 'admin_account_api.dart';
import 'admin_pending_attempt_store.dart';

const buriCapabilities = <String, String>{
  'records.read': 'View records',
  'members.enroll': 'Enroll members',
  'payments.allocate': 'Allocate payments',
  'staff.manage': 'Manage staff',
  'sms.read': 'View receiving SMS',
  'gateway.manage': 'Manage receiving phone',
};
final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _group = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$');
String _text(dynamic value, {int max = 254}) {
  if (value is! String ||
      value.length > max ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    throw const FormatException('BuriMunsi access could not be verified.');
  }
  return value;
}

String _id(dynamic value) {
  final id = _text(value, max: 36);
  if (!_uuid.hasMatch(id)) {
    throw const FormatException('Invalid Collect identity.');
  }
  return id;
}

String buriLoginPhone(String value) {
  if (value.length > 40 || !RegExp(r'^[+0-9 ()-]+$').hasMatch(value)) {
    throw const FormatException('Enter a Rwanda login phone number.');
  }
  var phone = value.trim().replaceAll(RegExp(r'[ ()-]'), '');
  if (phone.startsWith('00')) phone = '+${phone.substring(2)}';
  if (RegExp(r'^0\d{9}$').hasMatch(phone)) {
    phone = '+250${phone.substring(1)}';
  } else if (RegExp(r'^\d{9}$').hasMatch(phone)) {
    phone = '+250$phone';
  } else if (RegExp(r'^250\d{9}$').hasMatch(phone)) {
    phone = '+$phone';
  }
  if (!RegExp(r'^\+2507[2389]\d{7}$').hasMatch(phone)) {
    throw const FormatException('Enter a Rwanda login phone number.');
  }
  return phone;
}

List<String> _capabilities(dynamic value, String role) {
  if (value is! List ||
      value.isEmpty ||
      value.length > 6 ||
      value.any((c) => c is! String || !buriCapabilities.containsKey(c)) ||
      !value.contains('records.read') ||
      value.toSet().length != value.length ||
      role == 'staff' &&
          value.any(
            (c) => !const {
              'records.read',
              'members.enroll',
              'payments.allocate',
            }.contains(c),
          )) {
    throw const FormatException('Choose the exact BuriMunsi access.');
  }
  return List.unmodifiable(value.cast<String>().toList()..sort());
}

String _role(dynamic value) {
  if (!const {'admin', 'staff'}.contains(value)) {
    throw const FormatException('Choose a BuriMunsi role.');
  }
  return value as String;
}

class BuriSharedOperator {
  const BuriSharedOperator({
    required this.adminId,
    required this.principalId,
    required this.email,
    required this.name,
    required this.role,
  });
  final String adminId, principalId, email, name, role;
  factory BuriSharedOperator.parse(Map<String, dynamic> value) {
    final role = value['role'];
    if (!const {'owner', 'admin', 'staff'}.contains(role)) {
      throw const FormatException('Invalid Collect account role.');
    }
    return BuriSharedOperator(
      adminId: _id(value['adminId']),
      principalId: _id(value['principalId']),
      email: _text(value['email']),
      name: _text(value['displayName'], max: 120),
      role: role as String,
    );
  }
}

class BuriOperatorApproval {
  const BuriOperatorApproval({
    required this.operator,
    required this.phone,
    required this.role,
    required this.capabilities,
    required this.active,
    required this.version,
    required this.sharedStatus,
  });
  final BuriSharedOperator operator;
  final String phone, role, sharedStatus;
  final List<String> capabilities;
  final bool active;
  final int version;
  factory BuriOperatorApproval.parse(Map<String, dynamic> value) {
    final role = _role(value['role']), version = value['version'];
    if (value['active'] is! bool ||
        version is! int ||
        version < 1 ||
        version > 9007199254740991 ||
        !const {
          'active',
          'invited',
          'revoked',
        }.contains(value['sharedStatus'])) {
      throw const FormatException('Invalid BuriMunsi approval.');
    }
    final phone = _text(value['phone'], max: 16);
    if (buriLoginPhone(phone) != phone) {
      throw const FormatException('Invalid BuriMunsi login identity.');
    }
    return BuriOperatorApproval(
      operator: BuriSharedOperator.parse({
        ...value,
        'role': value['sharedRole'],
      }),
      phone: phone,
      role: role,
      capabilities: _capabilities(value['capabilities'], role),
      active: value['active'] as bool,
      version: version,
      sharedStatus: value['sharedStatus'] as String,
    );
  }
}

class BuriOperatorDirectory {
  const BuriOperatorDirectory({
    required this.collectionId,
    required this.configured,
    required this.team,
    required this.approvals,
  });
  final String collectionId;
  final bool configured;
  final List<BuriSharedOperator> team;
  final List<BuriOperatorApproval> approvals;
  factory BuriOperatorDirectory.parse(Map<String, dynamic> value) {
    final group = value['collectionId'],
        team = value['team'],
        approvals = value['approvals'];
    if (value['contractVersion'] is! int ||
        value['contractVersion'] != 1 ||
        group is! String ||
        !_group.hasMatch(group) ||
        value['configured'] is! bool ||
        team is! List ||
        team.length > 500 ||
        approvals is! List ||
        approvals.length > 500) {
      throw const FormatException('BuriMunsi access could not be verified.');
    }
    final members = team
        .map(
          (v) => BuriSharedOperator.parse(Map<String, dynamic>.from(v as Map)),
        )
        .toList();
    final bindings = approvals
        .map(
          (v) =>
              BuriOperatorApproval.parse(Map<String, dynamic>.from(v as Map)),
        )
        .toList();
    if (members.map((v) => v.principalId).toSet().length != members.length ||
        members.map((v) => v.adminId).toSet().length != members.length ||
        bindings.map((v) => v.operator.principalId).toSet().length !=
            bindings.length ||
        bindings.map((v) => v.phone).toSet().length != bindings.length) {
      throw const FormatException('BuriMunsi account selection is ambiguous.');
    }
    return BuriOperatorDirectory(
      collectionId: group,
      configured: value['configured'] as bool,
      team: List.unmodifiable(members),
      approvals: List.unmodifiable(bindings),
    );
  }
}

class BuriApprovalIntent {
  BuriApprovalIntent({
    required this.collectionId,
    required this.operator,
    required String phone,
    required String role,
    required List<String> capabilities,
    required this.active,
    required this.expectedVersion,
    String? requestId,
  }) : phone = buriLoginPhone(phone),
       role = _role(role),
       capabilities = _capabilities(capabilities, role),
       requestId = requestId ?? const Uuid().v4() {
    if (!_group.hasMatch(collectionId) ||
        !_uuid.hasMatch(this.requestId) ||
        !_uuid.hasMatch(operator.adminId) ||
        !_uuid.hasMatch(operator.principalId) ||
        !const {'owner', 'admin', 'staff'}.contains(operator.role) ||
        expectedVersion < 0 ||
        expectedVersion >= 9007199254740991 ||
        expectedVersion == 0 && !active ||
        role == 'admin' && !const {'owner', 'admin'}.contains(operator.role)) {
      throw const FormatException(
        'Check the selected Collect account and access.',
      );
    }
  }
  final String collectionId, requestId, phone, role;
  final BuriSharedOperator operator;
  final List<String> capabilities;
  final bool active;
  final int expectedVersion;
  String get resourceId => '$collectionId:${operator.principalId}';
  Map<String, dynamic> get body => {
    'requestId': requestId,
    'collectionId': collectionId,
    'adminId': operator.adminId,
    'principalId': operator.principalId,
    'phone': phone,
    'role': role,
    'capabilities': capabilities,
    'active': active,
    'expectedVersion': expectedVersion,
  };
  Map<String, dynamic> get checkpoint => {
    ...body,
    'principalId': operator.principalId,
    'sharedRole': operator.role,
  };
  factory BuriApprovalIntent.restore(Map<String, dynamic> value) =>
      BuriApprovalIntent(
        collectionId: _text(value['collectionId'], max: 128),
        operator: BuriSharedOperator(
          adminId: _id(value['adminId']),
          principalId: _id(value['principalId']),
          email: '',
          name: '',
          role: _text(value['sharedRole'], max: 10),
        ),
        phone: _text(value['phone']),
        role: _role(value['role']),
        capabilities: _capabilities(
          value['capabilities'],
          _role(value['role']),
        ),
        active: value['active'] as bool,
        expectedVersion: value['expectedVersion'] as int,
        requestId: _id(value['requestId']),
      );
  void verify(Map<String, dynamic> receipt) {
    if (receipt['contractVersion'] is! int ||
        receipt['contractVersion'] != 1 ||
        receipt['version'] is! int ||
        receipt['requestId'] != requestId ||
        receipt['principalId'] != operator.principalId ||
        receipt['version'] != expectedVersion + 1 ||
        receipt['active'] != active ||
        receipt['applied'] != true) {
      throw const FormatException(
        'The original BuriMunsi approval could not be verified.',
      );
    }
  }
}

abstract interface class AdminBuriMunsiApi {
  bool get buriAvailable;
  bool get buriAuthorized;
  Object get buriAuthorityFence;
  Future<BuriOperatorDirectory> loadBuriDirectory({String? collectionId});
  Future<Map<String, dynamic>> submitBuriApproval(
    BuriApprovalIntent intent,
    Object fence,
  );
  Future<Map<String, dynamic>?> lookupBuriApproval(
    BuriApprovalIntent intent,
    Object fence,
  );
}

class BuriScopeChoice {
  const BuriScopeChoice(this.id, this.title);
  final String id, title;
}

abstract interface class AdminBuriMunsiScopeApi
    implements AdminBuriMunsiProvisioningApi {
  Future<List<BuriScopeChoice>> loadBuriScopes();
}

/// Reuses Collect's bounded, same-account/session tab checkpoint. Only explicit
/// submit/check actions perform transport; restored intents never auto-dispatch.
class BuriApprovalCoordinator {
  BuriApprovalCoordinator({
    required this.api,
    required this.store,
    required this.collectionId,
  }) : fence = api.buriAuthorityFence {
    _owned();
    for (final entry in store.restoreFamily(
      family: family,
      permission: permission,
      schema: schema,
    )) {
      final intent = BuriApprovalIntent.restore(entry.intent);
      if (entry.resourceId != intent.resourceId ||
          entry.requestKey != intent.requestId) {
        throw const FormatException(
          'Check retained BuriMunsi requests before continuing.',
        );
      }
      if (intent.collectionId != collectionId) continue;
      _pending[intent.resourceId] = intent;
    }
  }
  static const family = 'burimunsi.operator';
  static const permission = 'admin_users.manage';
  static const schema = AdminPendingAttemptSchema(
    fields: {
      'requestId',
      'adminId',
      'phone',
      'role',
      'capabilities',
      'active',
      'expectedVersion',
      'collectionId',
      'principalId',
      'sharedRole',
    },
  );
  final AdminBuriMunsiApi api;
  final AdminPendingAttemptStore store;
  final String collectionId;
  final Object fence;
  final _pending = <String, BuriApprovalIntent>{};
  bool get current => api.buriAuthorized && api.buriAuthorityFence == fence;
  List<BuriApprovalIntent> get pending =>
      current ? List.unmodifiable(_pending.values) : const [];
  void _owned() {
    if (!api.buriAvailable || !current) {
      throw const AdminAccountException(
        'Verify your current owner sign-in to manage BuriMunsi access.',
      );
    }
  }

  Future<void> submit(BuriApprovalIntent intent) async {
    _owned();
    if (intent.collectionId != collectionId ||
        _pending.isNotEmpty &&
            (_pending.length != 1 || _pending[intent.resourceId] != intent)) {
      throw const AdminAccountException(
        'Resolve the original BuriMunsi request first.',
      );
    }
    if (!_pending.containsKey(intent.resourceId)) {
      if (!store.storageAvailable) {
        throw AdminAccountException(store.storageMessage);
      }
      store.retain(
        family: family,
        resourceId: intent.resourceId,
        requestKey: intent.requestId,
        permission: permission,
        intent: intent.checkpoint,
        schema: schema,
      );
      if (!store.storageAvailable) {
        store.clear(family: family, resourceId: intent.resourceId);
        throw AdminAccountException(store.storageMessage);
      }
      _pending[intent.resourceId] = intent;
    } else if (_pending[intent.resourceId] != intent) {
      throw const AdminAccountException('Use the unchanged original request.');
    }
    _owned();
    final receipt = await api.submitBuriApproval(intent, fence);
    _owned();
    intent.verify(receipt);
    _complete(intent);
  }

  Future<bool> check(BuriApprovalIntent intent) async {
    _owned();
    if (_pending[intent.resourceId] != intent) {
      throw const AdminAccountException('Reopen the original request.');
    }
    final receipt = await api.lookupBuriApproval(intent, fence);
    _owned();
    if (receipt == null) return false;
    intent.verify(receipt);
    _complete(intent);
    return true;
  }

  void _complete(BuriApprovalIntent intent) {
    store.clear(family: family, resourceId: intent.resourceId);
    _pending.remove(intent.resourceId);
  }
}

int _nativeVersion(dynamic value, {bool zero = false}) {
  if (value is! int || value < (zero ? 0 : 1) || value > 9007199254740991) {
    throw const FormatException(
      'The current native access version is invalid.',
    );
  }
  return value;
}

void _nativeFields(Map<String, dynamic> value, Set<String> fields) {
  if (value.length != fields.length || !fields.every(value.containsKey)) {
    throw const FormatException('The native provisioning contract changed.');
  }
}

class BuriNativeAccount {
  BuriNativeAccount.parse(Map<String, dynamic> value)
    : principalId = _id(value['principalId']),
      accountId = value['accountId'] == null ? null : _id(value['accountId']),
      phone = buriLoginPhone(_text(value['phone'])),
      name = _text(value['name'], max: 100),
      role = _role(value['role']),
      capabilities = _capabilities(value['capabilities'], _role(value['role'])),
      approvalVersion = _nativeVersion(value['approvalVersion']),
      version = _nativeVersion(value['version'], zero: true),
      credentialVersion = _nativeVersion(
        value['credentialVersion'],
        zero: true,
      ) {
    _nativeFields(value, {
      'principalId',
      'accountId',
      'phone',
      'name',
      'role',
      'capabilities',
      'approvalVersion',
      'version',
      'credentialVersion',
      'approved',
      'active',
      'removed',
    });
    if (value['approved'] is! bool ||
        value['active'] is! bool ||
        value['removed'] is! bool ||
        (accountId == null) != (version == 0) ||
        (accountId == null) != (credentialVersion == 0)) {
      throw const FormatException('The approved native account is invalid.');
    }
    approved = value['approved'] as bool;
    active = value['active'] as bool;
    removed = value['removed'] as bool;
  }
  final String principalId, phone, name, role;
  final String? accountId;
  final List<String> capabilities;
  final int approvalVersion, version, credentialVersion;
  late final bool approved, active, removed;
}

class BuriNativeGrant {
  BuriNativeGrant.parse(Map<String, dynamic> value)
    : id = _id(value['id']),
      accountId = value['accountId'] == null ? null : _id(value['accountId']),
      installationId = _id(value['installationId']),
      profile = _text(value['profile']),
      version = _nativeVersion(value['version']) {
    _nativeFields(value, {
      'id',
      'accountId',
      'installationId',
      'profile',
      'version',
      'active',
    });
    if (!const {'staff', 'internal_receiver'}.contains(profile) ||
        value['active'] is! bool) {
      throw const FormatException('The native installation grant is invalid.');
    }
    active = value['active'] as bool;
  }
  final String id, installationId, profile;
  final String? accountId;
  final int version;
  late final bool active;
}

class BuriProvisioningDirectory {
  BuriProvisioningDirectory.parse(Map<String, dynamic> value)
    : collectionId = _text(value['collectionId'], max: 128),
      scopeVersion = value['scopeVersion'] == null
          ? null
          : _nativeVersion(value['scopeVersion']) {
    _nativeFields(value, {
      'contractVersion',
      'collectionId',
      'configured',
      'scopeVersion',
      'scopeEnabled',
      'accounts',
      'grants',
    });
    if (value['contractVersion'] != 1 ||
        !_group.hasMatch(collectionId) ||
        value['configured'] is! bool ||
        value['scopeEnabled'] is! bool ||
        value['accounts'] is! List ||
        value['grants'] is! List ||
        (value['accounts'] as List).length > 500 ||
        (value['grants'] as List).length > 500) {
      throw const FormatException('Native provisioning could not be verified.');
    }
    configured = value['configured'] as bool;
    scopeEnabled = value['scopeEnabled'] as bool;
    accounts = List.unmodifiable(
      (value['accounts'] as List).map(
        (v) => BuriNativeAccount.parse(Map<String, dynamic>.from(v as Map)),
      ),
    );
    grants = List.unmodifiable(
      (value['grants'] as List).map(
        (v) => BuriNativeGrant.parse(Map<String, dynamic>.from(v as Map)),
      ),
    );
    if (configured && scopeVersion == null ||
        accounts.map((a) => a.principalId).toSet().length != accounts.length ||
        grants.map((g) => g.installationId).toSet().length != grants.length ||
        grants.map((g) => g.id).toSet().length != grants.length) {
      throw const FormatException(
        'Native installation selection is ambiguous.',
      );
    }
  }
  final String collectionId;
  final int? scopeVersion;
  late final bool configured, scopeEnabled;
  late final List<BuriNativeAccount> accounts;
  late final List<BuriNativeGrant> grants;
}

/// Immutable NONSECRET intent. A PIN is a transient submit argument only.
/// Restored requests can be checked or cancelled, never automatically replayed.
class BuriProvisioningIntent {
  BuriProvisioningIntent({
    required this.collectionId,
    required this.principalId,
    required this.scopeVersion,
    required this.approvalVersion,
    required this.expectedAccountVersion,
    required this.operation,
    required this.reason,
    this.accountId,
    this.grantId,
    this.installationId,
    this.profile,
    this.expectedGrantVersion,
    String? requestId,
  }) : requestId = requestId ?? const Uuid().v4() {
    if (!_group.hasMatch(collectionId) ||
        !_uuid.hasMatch(principalId) ||
        !_uuid.hasMatch(this.requestId) ||
        !const {
          'set_pin',
          'grant_installation',
          'revoke_installation',
        }.contains(operation) ||
        reason.trim() != reason ||
        reason.length < 8 ||
        reason.length > 300 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(reason) ||
        RegExp(r'[a-f0-9]{64}', caseSensitive: false).hasMatch(reason)) {
      throw const FormatException('Check the native provisioning request.');
    }
    _nativeVersion(scopeVersion);
    _nativeVersion(approvalVersion);
    _nativeVersion(expectedAccountVersion, zero: true);
    if (operation == 'set_pin') {
      if (grantId != null ||
          installationId != null ||
          profile != null ||
          expectedGrantVersion != null ||
          (accountId == null) != (expectedAccountVersion == 0)) {
        throw const FormatException('Check the current native account.');
      }
      if (accountId != null) _id(accountId);
    } else {
      _id(accountId);
      _id(installationId);
      if (expectedAccountVersion < 1 ||
          !const {'staff', 'internal_receiver'}.contains(profile) ||
          expectedGrantVersion == null ||
          expectedGrantVersion! < 0 ||
          (grantId == null) != (expectedGrantVersion == 0) ||
          operation == 'revoke_installation' && expectedGrantVersion == 0) {
        throw const FormatException(
          'Check the exact native installation grant.',
        );
      }
      _nativeVersion(expectedGrantVersion, zero: true);
      if (grantId != null) _id(grantId);
    }
  }
  final String collectionId, principalId, operation, reason, requestId;
  final int scopeVersion, approvalVersion, expectedAccountVersion;
  final String? accountId, grantId, installationId, profile;
  final int? expectedGrantVersion;
  String get resourceId => '$collectionId:$principalId';
  Map<String, dynamic> get checkpoint => {
    'collectionId': collectionId,
    'principalId': principalId,
    'scopeVersion': scopeVersion,
    'approvalVersion': approvalVersion,
    'expectedAccountVersion': expectedAccountVersion,
    'operation': operation,
    'reason': reason,
    'requestId': requestId,
    'accountId': accountId,
    'grantId': grantId,
    'installationId': installationId,
    'profile': profile,
    'expectedGrantVersion': expectedGrantVersion,
  };
  Map<String, dynamic> body({String? pin}) {
    if (operation == 'set_pin' &&
        (pin == null ||
            !RegExp(r'^\d{4}$').hasMatch(pin) ||
            reason.contains(pin))) {
      throw const FormatException(
        'Enter a four-digit PIN; keep it out of the reason.',
      );
    }
    return {
      'collectionId': collectionId,
      'principalId': principalId,
      'scopeVersion': scopeVersion,
      'approvalVersion': approvalVersion,
      'expectedAccountVersion': expectedAccountVersion,
      'operation': operation,
      'reason': reason,
      'requestId': requestId,
      if (operation == 'set_pin')
        'pin': pin
      else ...{
        'accountId': accountId,
        'grantId': grantId,
        'installationId': installationId,
        'profile': profile,
        'expectedGrantVersion': expectedGrantVersion,
      },
    };
  }

  factory BuriProvisioningIntent.restore(Map<String, dynamic> value) {
    _nativeFields(value, BuriProvisioningCoordinator.schema.fields);
    return BuriProvisioningIntent(
      collectionId: _text(value['collectionId']),
      principalId: _id(value['principalId']),
      scopeVersion: _nativeVersion(value['scopeVersion']),
      approvalVersion: _nativeVersion(value['approvalVersion']),
      expectedAccountVersion: _nativeVersion(
        value['expectedAccountVersion'],
        zero: true,
      ),
      operation: _text(value['operation']),
      reason: _text(value['reason'], max: 300),
      requestId: _id(value['requestId']),
      accountId: value['accountId'] == null ? null : _id(value['accountId']),
      grantId: value['grantId'] == null ? null : _id(value['grantId']),
      installationId: value['installationId'] == null
          ? null
          : _id(value['installationId']),
      profile: value['profile'] == null ? null : _text(value['profile']),
      expectedGrantVersion: value['expectedGrantVersion'] == null
          ? null
          : _nativeVersion(value['expectedGrantVersion'], zero: true),
    );
  }
  void verify(Map<String, dynamic> value) {
    if (value['contractVersion'] != 1 ||
        value['collectionId'] != collectionId ||
        value['requestId'] != requestId) {
      throw const FormatException(
        'The original native request could not be verified.',
      );
    }
    if (value['operation'] == 'cancelled') {
      _nativeFields(value, {
        'contractVersion',
        'collectionId',
        'requestId',
        'operation',
        'applied',
      });
      if (value['applied'] != false) {
        throw const FormatException('Invalid native cancellation.');
      }
      return;
    }
    _nativeFields(value, {
      'contractVersion',
      'collectionId',
      'requestId',
      'operation',
      'principalId',
      'accountId',
      'accountVersion',
      'credentialVersion',
      'approvalVersion',
      'scopeVersion',
      'applied',
      if (operation != 'set_pin') ...{
        'grantId',
        'installationId',
        'profile',
        'grantVersion',
        'active',
        'deliveryExpiresAt',
      },
    });
    _id(value['accountId']);
    _nativeVersion(value['credentialVersion']);
    if (value['operation'] != operation ||
        value['principalId'] != principalId ||
        value['applied'] != true ||
        value['approvalVersion'] != approvalVersion ||
        value['scopeVersion'] != scopeVersion ||
        value['accountVersion'] !=
            expectedAccountVersion + (operation == 'set_pin' ? 1 : 0) ||
        accountId != null && value['accountId'] != accountId) {
      throw const FormatException(
        'The native request does not match the original intent.',
      );
    }
    if (operation != 'set_pin') {
      _id(value['grantId']);
      if (grantId != null && value['grantId'] != grantId ||
          value['installationId'] != installationId ||
          value['profile'] != profile ||
          value['grantVersion'] != expectedGrantVersion! + 1 ||
          value['active'] != (operation == 'grant_installation') ||
          !(operation == 'grant_installation'
              ? value['deliveryExpiresAt'] is int &&
                    (value['deliveryExpiresAt'] as int) > 0
              : value['deliveryExpiresAt'] == null)) {
        throw const FormatException(
          'The original installation grant could not be verified.',
        );
      }
    }
  }
}

class BuriNativeDelivery {
  BuriNativeDelivery.parse(
    Map<String, dynamic> value,
    BuriProvisioningIntent intent,
  ) {
    _nativeFields(value, {
      'contractVersion',
      'collectionId',
      'requestId',
      'installationId',
      'profile',
      'grantVersion',
      'expiresAt',
      'installationToken',
    });
    if (value['contractVersion'] != 1 ||
        value['collectionId'] != intent.collectionId ||
        value['requestId'] != intent.requestId ||
        value['installationId'] != intent.installationId ||
        value['profile'] != intent.profile ||
        value['grantVersion'] != intent.expectedGrantVersion! + 1 ||
        value['expiresAt'] is! int ||
        (value['expiresAt'] as int) <= DateTime.now().millisecondsSinceEpoch ||
        value['installationToken'] is! String ||
        !RegExp(
          r'^[a-f0-9]{64}$',
        ).hasMatch(value['installationToken'] as String)) {
      throw const FormatException('The native delivery could not be verified.');
    }
    installationToken = value['installationToken'] as String;
    expiresAt = DateTime.fromMillisecondsSinceEpoch(
      value['expiresAt'] as int,
      isUtc: true,
    );
  }
  late final String installationToken;
  late final DateTime expiresAt;
  @override
  String toString() => 'BuriNativeDelivery(protected)';
}

abstract interface class AdminBuriMunsiProvisioningApi
    implements AdminBuriMunsiApi {
  Future<BuriProvisioningDirectory> loadBuriProvisioning({
    String? collectionId,
  });
  Future<Map<String, dynamic>> submitBuriProvisioning(
    BuriProvisioningIntent intent,
    Object fence, {
    String? pin,
  });
  Future<Map<String, dynamic>?> lookupBuriProvisioning(
    BuriProvisioningIntent intent,
    Object fence,
  );
  Future<Map<String, dynamic>> cancelBuriProvisioning(
    BuriProvisioningIntent intent,
    Object fence,
  );
  Future<BuriNativeDelivery> loadBuriDelivery(
    BuriProvisioningIntent intent,
    Object fence,
  );
}

class BuriProvisioningCoordinator {
  BuriProvisioningCoordinator({
    required this.api,
    required this.store,
    required this.collectionId,
  }) : fence = api.buriAuthorityFence {
    _owned();
    for (final entry in store.restoreFamily(
      family: family,
      permission: permission,
      schema: schema,
    )) {
      final intent = BuriProvisioningIntent.restore(entry.intent);
      if (entry.resourceId != intent.resourceId ||
          entry.requestKey != intent.requestId) {
        throw const FormatException(
          'Check retained native setup requests before continuing.',
        );
      }
      if (intent.collectionId != collectionId) continue;
      _pending[intent.resourceId] = intent;
    }
  }
  static const family = 'burimunsi.provisioning',
      permission = 'admin_users.manage';
  static const schema = AdminPendingAttemptSchema(
    fields: {
      'collectionId',
      'principalId',
      'scopeVersion',
      'approvalVersion',
      'expectedAccountVersion',
      'operation',
      'reason',
      'requestId',
      'accountId',
      'grantId',
      'installationId',
      'profile',
      'expectedGrantVersion',
    },
  );
  final AdminBuriMunsiProvisioningApi api;
  final AdminPendingAttemptStore store;
  final String collectionId;
  final Object fence;
  final _pending = <String, BuriProvisioningIntent>{};
  final _receipts = <String, Map<String, dynamic>>{};
  bool get current => api.buriAuthorized && api.buriAuthorityFence == fence;
  List<BuriProvisioningIntent> get pending =>
      current ? List.unmodifiable(_pending.values) : const [];
  Map<String, dynamic>? receipt(BuriProvisioningIntent intent) =>
      current ? _receipts[intent.requestId] : null;
  void _owned() {
    if (!api.buriAvailable || !current) {
      throw const AdminAccountException(
        'Verify your current owner email before provisioning native access.',
      );
    }
  }

  Future<void> submit(BuriProvisioningIntent intent, {String? pin}) async {
    _owned();
    intent.body(
      pin: pin,
    ); // Validate before persisting the NONSECRET checkpoint.
    if (_pending.isNotEmpty ||
        intent.collectionId != collectionId ||
        !store.storageAvailable) {
      throw const AdminAccountException(
        'Resolve the original native setup request first.',
      );
    }
    store.retain(
      family: family,
      resourceId: intent.resourceId,
      requestKey: intent.requestId,
      permission: permission,
      intent: intent.checkpoint,
      schema: schema,
    );
    if (!store.storageAvailable) {
      throw AdminAccountException(store.storageMessage);
    }
    _pending[intent.resourceId] = intent;
    _owned();
    final value = await api.submitBuriProvisioning(intent, fence, pin: pin);
    _owned();
    _resolve(intent, value);
  }

  Future<bool> check(BuriProvisioningIntent intent) async {
    _original(intent);
    final value = await api.lookupBuriProvisioning(intent, fence);
    _owned();
    if (value == null) return false;
    _resolve(intent, value);
    return true;
  }

  Future<void> cancel(BuriProvisioningIntent intent) async {
    _original(intent);
    final value = await api.cancelBuriProvisioning(intent, fence);
    _owned();
    _resolve(intent, value);
  }

  Future<BuriNativeDelivery> delivery(BuriProvisioningIntent intent) async {
    _original(intent);
    if (receipt(intent)?['operation'] != 'grant_installation') {
      throw const AdminAccountException(
        'Confirm the original grant before opening delivery.',
      );
    }
    final value = await api.loadBuriDelivery(intent, fence);
    _owned();
    return value;
  }

  void closeDelivery(BuriProvisioningIntent intent) {
    _original(intent);
    if (receipt(intent)?['operation'] != 'grant_installation') {
      throw const AdminAccountException('Confirm the original grant first.');
    }
    _complete(intent);
  }

  void _original(BuriProvisioningIntent intent) {
    _owned();
    if (_pending[intent.resourceId] != intent) {
      throw const AdminAccountException(
        'Reopen the unchanged original native request.',
      );
    }
  }

  void _resolve(BuriProvisioningIntent intent, Map<String, dynamic> value) {
    intent.verify(value);
    if (value['operation'] == 'grant_installation') {
      _receipts[intent.requestId] = Map.unmodifiable(value);
    } else {
      _complete(intent);
    }
  }

  void _complete(BuriProvisioningIntent intent) {
    store.clear(family: family, resourceId: intent.resourceId);
    _pending.remove(intent.resourceId);
    _receipts.remove(intent.requestId);
  }
}
