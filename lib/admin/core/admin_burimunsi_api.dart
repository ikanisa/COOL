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
  Future<BuriOperatorDirectory> loadBuriDirectory();
  Future<Map<String, dynamic>> submitBuriApproval(
    BuriApprovalIntent intent,
    Object fence,
  );
  Future<Map<String, dynamic>?> lookupBuriApproval(
    BuriApprovalIntent intent,
    Object fence,
  );
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
          entry.requestKey != intent.requestId ||
          intent.collectionId != collectionId) {
        throw const FormatException(
          'Check retained BuriMunsi requests before continuing.',
        );
      }
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
