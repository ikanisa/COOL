import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'admin_receipt_operations_models.dart';
import 'admin_receipt_operations_checkpoint_stub.dart'
    if (dart.library.js_interop) 'admin_receipt_operations_checkpoint_web.dart'
    as platform;

String adminReceiptOperationsOwnerDigest(String userId) {
  operationsUuid(userId);
  return sha256
      .convert(
        utf8.encode(
          'collect.receipt-operations.v2:lhbowpbcpwoiparwnwgt:$userId',
        ),
      )
      .toString();
}

/// An immutable original request bookmark. Reasons, credentials and contact or
/// receipt content are never stored. Recovery cannot reconstruct a mutation.
class AdminReceiptOperationsCheckpoint {
  const AdminReceiptOperationsCheckpoint._(
    this.ownerDigest,
    this.requestId,
    this.action,
    this.expectedRevision,
    this.mode,
    this.emergencyStop,
    this.createdAt,
    this.expiresAt,
  );
  final String ownerDigest, requestId, action;
  final int expectedRevision;
  final AdminReceiptOperationsMode mode;
  final bool emergencyStop;
  final DateTime createdAt, expiresAt;
  factory AdminReceiptOperationsCheckpoint.fromIntent(
    String ownerDigest,
    AdminReceiptOperationsIntent intent,
  ) => AdminReceiptOperationsCheckpoint.parse(
    jsonEncode({
      'version': 2,
      'owner_digest': ownerDigest,
      'request_id': intent.requestId,
      'action': intent.action,
      'expected_revision': intent.expectedRevision,
      'mode': intent.mode.label,
      'emergency_stop': intent.emergencyStop,
      'created_at': operationsUtc(intent.createdAt),
      'expires_at': operationsUtc(intent.expiresAt),
    }),
    ownerDigest,
  );
  String encode() => jsonEncode({
    'version': 2,
    'owner_digest': ownerDigest,
    'request_id': requestId,
    'action': action,
    'expected_revision': expectedRevision,
    'mode': mode.label,
    'emergency_stop': emergencyStop,
    'created_at': operationsUtc(createdAt),
    'expires_at': operationsUtc(expiresAt),
  });
  String get digest => sha256.convert(utf8.encode(encode())).toString();
  factory AdminReceiptOperationsCheckpoint.parse(
    String encoded,
    String ownerDigest,
  ) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(ownerDigest) ||
        encoded.length > 2048) {
      operationsInvalid();
    }
    final row = operationsObject(jsonDecode(encoded), {
      'version',
      'owner_digest',
      'request_id',
      'action',
      'expected_revision',
      'mode',
      'emergency_stop',
      'created_at',
      'expires_at',
    });
    if (row['version'] is! int ||
        row['version'] != 2 ||
        row['owner_digest'] != ownerDigest ||
        row['action'] is! String ||
        !{'configure', 'stop'}.contains(row['action']) ||
        row['expected_revision'] is! int ||
        (row['expected_revision'] as int) < 1 ||
        (row['expected_revision'] as int) >= 1000000000 ||
        row['emergency_stop'] is! bool) {
      operationsInvalid();
    }
    final mode = AdminReceiptOperationsMode.parse(row['mode']);
    final stop = row['emergency_stop'] as bool;
    final created = operationsInstant(row['created_at']),
        expiry = operationsInstant(row['expires_at']);
    if (!expiry.isAfter(created) ||
        expiry.difference(created) > const Duration(seconds: 120) ||
        (mode == AdminReceiptOperationsMode.paused && !stop) ||
        (row['action'] == 'stop' &&
            (mode != AdminReceiptOperationsMode.paused || !stop))) {
      operationsInvalid();
    }
    final checkpoint = AdminReceiptOperationsCheckpoint._(
      ownerDigest,
      operationsUuid(row['request_id']),
      row['action'] as String,
      row['expected_revision'] as int,
      mode,
      stop,
      created,
      expiry,
    );
    if (checkpoint.encode() != encoded) operationsInvalid();
    return checkpoint;
  }
  void validateReceipt(AdminReceiptOperationsReceipt receipt) {
    if (receipt.requestId != requestId ||
        receipt.revision != expectedRevision + 1 ||
        receipt.mode != mode ||
        receipt.emergencyStop != emergencyStop ||
        receipt.expiresAt != expiresAt ||
        receipt.recordedAt.isBefore(
          createdAt.subtract(const Duration(seconds: 5)),
        )) {
      operationsInvalid();
    }
  }
}

abstract class AdminReceiptOperationsCheckpointStore {
  /// Returns original checkpoints that have no validated resolution marker.
  List<String> read(String ownerDigest);

  /// Must refuse overwrite and read back the exact original before returning.
  void write(String ownerDigest, String requestId, String encoded);

  /// Archives a resolution marker; retains the immutable original checkpoint.
  void resolve(AdminReceiptOperationsCheckpoint checkpoint, String status);
}

AdminReceiptOperationsCheckpointStore?
browserAdminReceiptOperationsCheckpointStore() =>
    platform.createReceiptOperationsCheckpointStore();
