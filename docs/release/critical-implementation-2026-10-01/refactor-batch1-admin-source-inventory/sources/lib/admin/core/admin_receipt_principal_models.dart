import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'admin_receipt_operations_models.dart';

const _principalScope = 'rw_receipt_operations';

enum AdminReceiptPrincipalState {
  pending('Pending'),
  active('Active'),
  revoked('Revoked');

  const AdminReceiptPrincipalState(this.label);
  final String label;
  static AdminReceiptPrincipalState parse(Object? raw) => values.firstWhere(
    (state) => raw == state.name,
    orElse: operationsInvalid,
  );
}

enum AdminReceiptPrincipalAction {
  enroll,
  activate,
  revoke;

  String get rpcName => 'admin_${name}_receipt_operations_identity_v3';
  AdminReceiptPrincipalState get resultState => switch (this) {
    enroll => AdminReceiptPrincipalState.pending,
    activate => AdminReceiptPrincipalState.active,
    revoke => AdminReceiptPrincipalState.revoked,
  };
  static AdminReceiptPrincipalAction parse(Object? raw) => values.firstWhere(
    (action) => raw == action.name,
    orElse: operationsInvalid,
  );
}

String _fingerprint(Object? value) {
  if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    operationsInvalid();
  }
  return value;
}

bool _fresh(DateTime checked, DateTime valid, DateTime now) =>
    !checked.isAfter(now.toUtc().add(const Duration(seconds: 10))) &&
    now.toUtc().isBefore(valid);
({DateTime checked, DateTime valid}) _sample(Map<Object?, Object?> row) {
  if (row['contract_version'] is! int || row['contract_version'] != 3) {
    operationsInvalid();
  }
  final checked = operationsInstant(row['checked_at']),
      valid = operationsInstant(row['sample_valid_until']);
  if (valid.difference(checked) != const Duration(seconds: 60)) {
    operationsInvalid();
  }
  return (checked: checked, valid: valid);
}

/// Public CLI metadata only; this does not prove possession of its private key.
class AdminReceiptPrincipalPublicKey {
  const AdminReceiptPrincipalPublicKey._(this.spkiBase64, this.keySha256);
  final String spkiBase64, keySha256;

  /// A bounded flat CLI metadata document. Decode keys before duplicate checks
  /// so escaped aliases cannot be collapsed silently by jsonDecode.
  factory AdminReceiptPrincipalPublicKey.parseText(String text) {
    if (utf8.encode(text).length > 2048) {
      operationsInvalid();
    }
    final whitespace = RegExp(r'[ \t\r\n]*');
    final member = RegExp(
      r'("(?:[^"\\\x00-\x1f]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*")[ \t\r\n]*:[ \t\r\n]*("(?:[^"\\\x00-\x1f]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*"|2)',
    );
    var offset = 0;
    void skipWhitespace() {
      offset = whitespace.matchAsPrefix(text, offset)!.end;
    }

    skipWhitespace();
    if (offset >= text.length || text[offset++] != '{') {
      operationsInvalid();
    }
    final row = <String, dynamic>{};
    while (true) {
      skipWhitespace();
      final pair = member.matchAsPrefix(text, offset);
      if (pair == null || row.length >= 4) {
        operationsInvalid();
      }
      final key = jsonDecode(pair[1]!) as String;
      if (row.containsKey(key)) {
        operationsInvalid();
      }
      row[key] = pair[2] == '2' ? 2 : jsonDecode(pair[2]!);
      offset = pair.end;
      skipWhitespace();
      if (offset >= text.length) {
        operationsInvalid();
      }
      final delimiter = text[offset++];
      if (delimiter == '}') {
        break;
      }
      if (delimiter != ',') {
        operationsInvalid();
      }
    }
    skipWhitespace();
    if (offset != text.length) {
      operationsInvalid();
    }
    return AdminReceiptPrincipalPublicKey.parse(row);
  }
  factory AdminReceiptPrincipalPublicKey.parse(Object? raw) {
    final row = operationsObject(raw, {
      'contract_version',
      'scope',
      'public_key_spki_base64',
      'key_sha256',
    });
    final encoded = row['public_key_spki_base64'];
    if (row['contract_version'] is! int ||
        row['contract_version'] != 2 ||
        row['scope'] != _principalScope ||
        encoded is! String ||
        !RegExp(r'^[A-Za-z0-9+/]{122}==$').hasMatch(encoded)) {
      operationsInvalid();
    }
    final bytes = base64Decode(encoded), hash = _fingerprint(row['key_sha256']);
    const prefix = [
      0x30,
      0x59,
      0x30,
      0x13,
      0x06,
      0x07,
      0x2a,
      0x86,
      0x48,
      0xce,
      0x3d,
      0x02,
      0x01,
      0x06,
      0x08,
      0x2a,
      0x86,
      0x48,
      0xce,
      0x3d,
      0x03,
      0x01,
      0x07,
      0x03,
      0x42,
      0x00,
      0x04,
    ];
    if (bytes.length != 91 ||
        base64Encode(bytes) != encoded ||
        List.generate(
          prefix.length,
          (index) => prefix[index] == bytes[index],
        ).contains(false) ||
        sha256.convert(bytes).toString() != hash) {
      operationsInvalid();
    }
    BigInt coordinate(int start) => bytes
        .sublist(start, start + 32)
        .fold(
          BigInt.zero,
          (value, octet) => value * BigInt.from(256) + BigInt.from(octet),
        );
    final x = coordinate(27), y = coordinate(59);
    final prime = BigInt.parse(
      '115792089210356248762697446949407573530086143415290314195533631308867097853951',
    );
    final curveB = BigInt.parse(
      '41058363725152142129326129780047268409114441015993725554835256314039467401291',
    );
    if (x >= prime ||
        y >= prime ||
        (y * y - x * x * x + BigInt.from(3) * x - curveB) % prime !=
            BigInt.zero) {
      operationsInvalid();
    }
    return AdminReceiptPrincipalPublicKey._(encoded, hash);
  }
}

/// Restart-safe metadata. No signing material or freeform reason is retained.
/// Restoring this binding cannot create a new mutation intent.
class AdminReceiptPrincipalBinding {
  AdminReceiptPrincipalBinding._({
    required this.action,
    required String requestId,
    required String? principalId,
    required String keySha256,
    required DateTime identityExpiresAt,
    required DateTime createdAt,
    required DateTime requestExpiresAt,
    required String? reasonSha256,
  }) : requestId = operationsUuid(requestId),
       principalId = principalId == null ? null : operationsUuid(principalId),
       keySha256 = _fingerprint(keySha256),
       identityExpiresAt = identityExpiresAt.toUtc(),
       createdAt = createdAt.toUtc(),
       requestExpiresAt = requestExpiresAt.toUtc(),
       reasonSha256 = reasonSha256 == null ? null : _fingerprint(reasonSha256) {
    operationsInstant(operationsUtc(this.createdAt));
    operationsInstant(operationsUtc(this.requestExpiresAt));
    operationsInstant(operationsUtc(this.identityExpiresAt));
    if ((action == AdminReceiptPrincipalAction.enroll) !=
            (principalId == null) ||
        (action == AdminReceiptPrincipalAction.revoke) !=
            (reasonSha256 != null) ||
        !this.requestExpiresAt.isAfter(this.createdAt) ||
        this.requestExpiresAt.difference(this.createdAt) >
            const Duration(seconds: 120) ||
        action != AdminReceiptPrincipalAction.revoke &&
            !this.identityExpiresAt.isAfter(this.createdAt)) {
      operationsInvalid();
    }
  }
  final AdminReceiptPrincipalAction action;
  final String requestId, keySha256;
  final String? principalId, reasonSha256;
  final DateTime identityExpiresAt, createdAt, requestExpiresAt;
  factory AdminReceiptPrincipalBinding.fromIntent(
    AdminReceiptPrincipalIntent intent,
  ) => AdminReceiptPrincipalBinding._(
    action: intent.action,
    requestId: intent.requestId,
    principalId: intent.principalId,
    keySha256: intent.keySha256,
    identityExpiresAt: intent.identityExpiresAt,
    createdAt: intent.createdAt,
    requestExpiresAt: intent.requestExpiresAt,
    reasonSha256: intent.reasonSha256,
  );
  factory AdminReceiptPrincipalBinding.parse(Object? raw) {
    final row = operationsObject(raw, {
      'action',
      'request_id',
      'principal_id',
      'key_sha256',
      'identity_expires_at',
      'created_at',
      'request_expires_at',
      'reason_sha256',
    });
    return AdminReceiptPrincipalBinding._(
      action: AdminReceiptPrincipalAction.parse(row['action']),
      requestId: operationsUuid(row['request_id']),
      principalId: row['principal_id'] == null
          ? null
          : operationsUuid(row['principal_id']),
      keySha256: _fingerprint(row['key_sha256']),
      identityExpiresAt: operationsInstant(row['identity_expires_at']),
      createdAt: operationsInstant(row['created_at']),
      requestExpiresAt: operationsInstant(row['request_expires_at']),
      reasonSha256: row['reason_sha256'] == null
          ? null
          : _fingerprint(row['reason_sha256']),
    );
  }
  Map<String, dynamic> toJson() => Map.unmodifiable({
    'action': action.name,
    'request_id': requestId,
    'principal_id': principalId,
    'key_sha256': keySha256,
    'identity_expires_at': operationsUtc(identityExpiresAt),
    'created_at': operationsUtc(createdAt),
    'request_expires_at': operationsUtc(requestExpiresAt),
    'reason_sha256': reasonSha256,
  });
  Map<String, dynamic> get lookupParameters =>
      Map.unmodifiable({'p_request_id': requestId});
}

/// A newly reviewed original instruction; never reconstructed from a bookmark.
class AdminReceiptPrincipalIntent extends AdminReceiptPrincipalBinding {
  AdminReceiptPrincipalIntent.enroll({
    required super.requestId,
    required super.createdAt,
    required super.requestExpiresAt,
    required super.identityExpiresAt,
    required AdminReceiptPrincipalPublicKey publicKey,
  }) : publicKey = publicKey,
       reason = null,
       super._(
         action: AdminReceiptPrincipalAction.enroll,
         principalId: null,
         keySha256: publicKey.keySha256,
         reasonSha256: null,
       ) {
    if (identityExpiresAt.difference(createdAt) < const Duration(minutes: 10) ||
        identityExpiresAt.difference(createdAt) > const Duration(days: 30)) {
      operationsInvalid();
    }
  }
  AdminReceiptPrincipalIntent.activate({
    required super.requestId,
    required super.createdAt,
    required super.requestExpiresAt,
    required super.identityExpiresAt,
    required String principalId,
    required super.keySha256,
  }) : publicKey = null,
       reason = null,
       super._(
         action: AdminReceiptPrincipalAction.activate,
         principalId: principalId,
         reasonSha256: null,
       );
  AdminReceiptPrincipalIntent.revoke({
    required super.requestId,
    required super.createdAt,
    required super.requestExpiresAt,
    required super.identityExpiresAt,
    required String principalId,
    required super.keySha256,
    required String reason,
  }) : publicKey = null,
       reason = _reason(reason),
       super._(
         action: AdminReceiptPrincipalAction.revoke,
         principalId: principalId,
         reasonSha256: sha256.convert(utf8.encode(_reason(reason))).toString(),
       );
  final AdminReceiptPrincipalPublicKey? publicKey;
  final String? reason;
  String get rpcName => action.rpcName;
  bool canSubmitAt(DateTime now) =>
      !createdAt.isAfter(now.toUtc().add(const Duration(seconds: 10))) &&
      now.toUtc().isBefore(requestExpiresAt) &&
      requestExpiresAt.difference(now.toUtc()) <=
          const Duration(seconds: 120) &&
      (action == AdminReceiptPrincipalAction.revoke ||
          now.toUtc().isBefore(identityExpiresAt));
  Map<String, dynamic> get parameters => Map.unmodifiable({
    'p_request_id': requestId,
    'p_request_expires_at': operationsUtc(requestExpiresAt),
    if (action == AdminReceiptPrincipalAction.enroll) ...{
      'p_public_key_spki_base64': publicKey!.spkiBase64,
      'p_key_sha256': keySha256,
      'p_identity_expires_at': operationsUtc(identityExpiresAt),
    } else ...{
      'p_principal_id': principalId,
      'p_expected_key_sha256': keySha256,
    },
    if (action == AdminReceiptPrincipalAction.revoke) 'p_reason': reason!,
  });
}

String _reason(String value) {
  if (value != value.trim() ||
      value.runes.length < 8 ||
      value.runes.length > 500 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    operationsInvalid();
  }
  return value;
}

class AdminReceiptPrincipalIdentity {
  const AdminReceiptPrincipalIdentity._({
    required this.principalId,
    required this.keySha256,
    required this.state,
    required this.createdAt,
    required this.expiresAt,
    required this.activatedAt,
    required this.revokedAt,
  });
  final String principalId, keySha256;
  final AdminReceiptPrincipalState state;
  final DateTime createdAt, expiresAt;
  final DateTime? activatedAt, revokedAt;
  String get scope => _principalScope;
  bool isExpired(DateTime now) => !expiresAt.isAfter(now.toUtc());
  factory AdminReceiptPrincipalIdentity.parse(Object? raw) {
    final row = operationsObject(raw, {
      'principal_id',
      'key_sha256',
      'state',
      'scope',
      'created_at',
      'expires_at',
      'activated_at',
      'revoked_at',
    });
    final state = AdminReceiptPrincipalState.parse(row['state']);
    final created = operationsInstant(row['created_at']),
        expires = operationsInstant(row['expires_at']);
    final activated = row['activated_at'] == null
        ? null
        : operationsInstant(row['activated_at']);
    final revoked = row['revoked_at'] == null
        ? null
        : operationsInstant(row['revoked_at']);
    if (row['scope'] != _principalScope ||
        !expires.isAfter(created) ||
        activated?.isBefore(created) == true ||
        revoked?.isBefore(created) == true ||
        state == AdminReceiptPrincipalState.pending &&
            (activated != null || revoked != null) ||
        state == AdminReceiptPrincipalState.active &&
            (activated == null || revoked != null) ||
        state == AdminReceiptPrincipalState.revoked &&
            (revoked == null ||
                activated != null && revoked.isBefore(activated))) {
      operationsInvalid();
    }
    return AdminReceiptPrincipalIdentity._(
      principalId: operationsUuid(row['principal_id']),
      keySha256: _fingerprint(row['key_sha256']),
      state: state,
      createdAt: created,
      expiresAt: expires,
      activatedAt: activated,
      revokedAt: revoked,
    );
  }
  void _validateObservedAt(DateTime checked) {
    if ([
      createdAt,
      activatedAt,
      revokedAt,
    ].any((value) => value?.isAfter(checked) == true)) {
      operationsInvalid();
    }
  }
}

class AdminReceiptPrincipalCursor {
  AdminReceiptPrincipalCursor({
    required DateTime createdAt,
    required String principalId,
  }) : createdAt = createdAt.toUtc(),
       principalId = operationsUuid(principalId) {
    operationsInstant(operationsUtc(this.createdAt));
  }
  final DateTime createdAt;
  final String principalId;
  factory AdminReceiptPrincipalCursor.parse(Object? raw) {
    final row = operationsObject(raw, {'created_at', 'principal_id'});
    return AdminReceiptPrincipalCursor(
      createdAt: operationsInstant(row['created_at']),
      principalId: operationsUuid(row['principal_id']),
    );
  }
  Map<String, dynamic> toJson() => Map.unmodifiable({
    'created_at': operationsUtc(createdAt),
    'principal_id': principalId,
  });
  @override
  bool operator ==(Object other) =>
      other is AdminReceiptPrincipalCursor &&
      createdAt == other.createdAt &&
      principalId == other.principalId;
  @override
  int get hashCode => Object.hash(createdAt, principalId);
}

class AdminReceiptPrincipalDirectoryQuery {
  const AdminReceiptPrincipalDirectoryQuery({this.limit = 25, this.before});
  final int limit;
  final AdminReceiptPrincipalCursor? before;
  void _validate() {
    if (limit < 1 || limit > 25) {
      operationsInvalid();
    }
  }

  Map<String, dynamic> get parameters {
    _validate();
    return Map.unmodifiable({
      'p_limit': limit,
      'p_before_created_at': before == null
          ? null
          : operationsUtc(before!.createdAt),
      'p_before_principal_id': before?.principalId,
    });
  }

  @override
  bool operator ==(Object other) =>
      other is AdminReceiptPrincipalDirectoryQuery &&
      limit == other.limit &&
      before == other.before;
  @override
  int get hashCode => Object.hash(limit, before);
}

class AdminReceiptPrincipalDirectory {
  const AdminReceiptPrincipalDirectory._(
    this.checkedAt,
    this.validUntil,
    this.rows,
    this.nextCursor,
  );
  final DateTime checkedAt, validUntil;
  final List<AdminReceiptPrincipalIdentity> rows;
  final AdminReceiptPrincipalCursor? nextCursor;
  bool isFresh(DateTime now) => _fresh(checkedAt, validUntil, now);
  factory AdminReceiptPrincipalDirectory.parse(
    Object? raw, {
    required AdminReceiptPrincipalDirectoryQuery query,
  }) {
    query._validate();
    final row = operationsObject(raw, {
      'contract_version',
      'checked_at',
      'sample_valid_until',
      'rows',
      'next_cursor',
    });
    final sample = _sample(row), values = row['rows'];
    if (values is! List || values.length > query.limit) {
      operationsInvalid();
    }
    final rows = values.map(AdminReceiptPrincipalIdentity.parse).toList(),
        seen = <String>{};
    var prior = query.before;
    for (final identity in rows) {
      identity._validateObservedAt(sample.checked);
      if (!seen.add(identity.principalId) ||
          prior != null &&
              (identity.createdAt.isAfter(prior.createdAt) ||
                  identity.createdAt == prior.createdAt &&
                      identity.principalId.compareTo(prior.principalId) >= 0)) {
        operationsInvalid();
      }
      prior = AdminReceiptPrincipalCursor(
        createdAt: identity.createdAt,
        principalId: identity.principalId,
      );
    }
    final next = row['next_cursor'] == null
        ? null
        : AdminReceiptPrincipalCursor.parse(row['next_cursor']);
    if (next != null && (rows.length != query.limit || next != prior)) {
      operationsInvalid();
    }
    return AdminReceiptPrincipalDirectory._(
      sample.checked,
      sample.valid,
      List.unmodifiable(rows),
      next,
    );
  }
}

class AdminReceiptPrincipalObservation {
  const AdminReceiptPrincipalObservation._(
    this.checkedAt,
    this.validUntil,
    this.found,
    this.identity,
  );
  final DateTime checkedAt, validUntil;
  final bool found;
  final AdminReceiptPrincipalIdentity? identity;
  bool isFresh(DateTime now) => _fresh(checkedAt, validUntil, now);
  factory AdminReceiptPrincipalObservation.parse(
    Object? raw, {
    required String principalId,
  }) {
    operationsUuid(principalId);
    final row = operationsObject(raw, {
      'contract_version',
      'checked_at',
      'sample_valid_until',
      'found',
      'identity',
    });
    final sample = _sample(row), found = row['found'];
    final identity = row['identity'] == null
        ? null
        : AdminReceiptPrincipalIdentity.parse(row['identity']);
    if (found is! bool ||
        found != (identity != null) ||
        identity != null && identity.principalId != principalId) {
      operationsInvalid();
    }
    identity?._validateObservedAt(sample.checked);
    return AdminReceiptPrincipalObservation._(
      sample.checked,
      sample.valid,
      found,
      identity,
    );
  }
}

/// Historical action evidence; never substituted for a current identity read.
class AdminReceiptPrincipalReceipt {
  const AdminReceiptPrincipalReceipt._({
    required this.action,
    required this.requestId,
    required this.principalId,
    required this.keySha256,
    required this.stateAtAction,
    required this.identityExpiresAt,
    required this.recordedAt,
    required this.requestExpiresAt,
    required this.reasonSha256,
  });
  final AdminReceiptPrincipalAction action;
  final String requestId, principalId, keySha256;
  final AdminReceiptPrincipalState stateAtAction;
  final DateTime identityExpiresAt, recordedAt, requestExpiresAt;
  final String? reasonSha256;
  String get scope => _principalScope;
  factory AdminReceiptPrincipalReceipt.parse(
    Object? raw, {
    required AdminReceiptPrincipalBinding binding,
  }) {
    final row = operationsObject(raw, {
      'contract_version',
      'action',
      'request_id',
      'principal_id',
      'state_at_action',
      'scope',
      'key_sha256',
      'identity_expires_at',
      'recorded_at',
      'request_expires_at',
      if (binding.action == AdminReceiptPrincipalAction.revoke) 'reason_sha256',
    });
    final action = AdminReceiptPrincipalAction.parse(row['action']),
        state = AdminReceiptPrincipalState.parse(row['state_at_action']);
    final request = operationsUuid(row['request_id']),
        principal = operationsUuid(row['principal_id']),
        key = _fingerprint(row['key_sha256']);
    final identityExpiry = operationsInstant(row['identity_expires_at']),
        recorded = operationsInstant(row['recorded_at']),
        expiry = operationsInstant(row['request_expires_at']);
    final reason = action == AdminReceiptPrincipalAction.revoke
        ? _fingerprint(row['reason_sha256'])
        : null;
    if (row['contract_version'] is! int ||
        row['contract_version'] != 3 ||
        row['scope'] != _principalScope ||
        action != binding.action ||
        state != action.resultState ||
        request != binding.requestId ||
        key != binding.keySha256 ||
        binding.principalId != null && principal != binding.principalId ||
        identityExpiry != binding.identityExpiresAt ||
        expiry != binding.requestExpiresAt ||
        reason != binding.reasonSha256 ||
        !recorded.isBefore(expiry) ||
        expiry.difference(recorded) > const Duration(seconds: 120) ||
        recorded.isBefore(
          binding.createdAt.subtract(const Duration(seconds: 10)),
        ) ||
        action != AdminReceiptPrincipalAction.revoke &&
            !recorded.isBefore(identityExpiry)) {
      operationsInvalid();
    }
    return AdminReceiptPrincipalReceipt._(
      action: action,
      requestId: request,
      principalId: principal,
      keySha256: key,
      stateAtAction: state,
      identityExpiresAt: identityExpiry,
      recordedAt: recorded,
      requestExpiresAt: expiry,
      reasonSha256: reason,
    );
  }
}

class AdminReceiptPrincipalLookup {
  const AdminReceiptPrincipalLookup._(
    this.binding,
    this.checkedAt,
    this.validUntil,
    this.action,
    this.status,
    this.requestExpiresAt,
    this.receipt,
  );
  final AdminReceiptPrincipalBinding binding;
  final DateTime checkedAt, validUntil;
  final AdminReceiptPrincipalAction? action;
  final String status;
  final DateTime? requestExpiresAt;
  final AdminReceiptPrincipalReceipt? receipt;
  String get requestId => binding.requestId;
  bool isFresh(DateTime now) => _fresh(checkedAt, validUntil, now);

  /// A fresh server absence after its enforced original deadline permits
  /// closing that bookmark. It does not authorize replaying the mutation.
  bool provesExpiredAbsence(DateTime now) =>
      status == 'not_recorded' &&
      isFresh(now) &&
      !checkedAt.isBefore(binding.requestExpiresAt) &&
      !now.toUtc().isBefore(binding.requestExpiresAt);
  factory AdminReceiptPrincipalLookup.parse(
    Object? raw, {
    required AdminReceiptPrincipalBinding binding,
  }) {
    final row = operationsObject(raw, {
      'contract_version',
      'request_id',
      'action',
      'status',
      'checked_at',
      'sample_valid_until',
      'request_expires_at',
      'receipt',
    });
    final sample = _sample(row), status = row['status'];
    final action = row['action'] == null
        ? null
        : AdminReceiptPrincipalAction.parse(row['action']);
    final expiry = row['request_expires_at'] == null
        ? null
        : operationsInstant(row['request_expires_at']);
    final receipt = row['receipt'] == null
        ? null
        : AdminReceiptPrincipalReceipt.parse(row['receipt'], binding: binding);
    if (operationsUuid(row['request_id']) != binding.requestId ||
        status is! String ||
        !{'recorded', 'not_recorded', 'in_progress'}.contains(status) ||
        status == 'recorded' &&
            (action != binding.action ||
                expiry != binding.requestExpiresAt ||
                receipt == null ||
                receipt.recordedAt.isAfter(sample.checked)) ||
        status != 'recorded' &&
            (action != null || expiry != null || receipt != null)) {
      operationsInvalid();
    }
    return AdminReceiptPrincipalLookup._(
      binding,
      sample.checked,
      sample.valid,
      action,
      status,
      expiry,
      receipt,
    );
  }
}
