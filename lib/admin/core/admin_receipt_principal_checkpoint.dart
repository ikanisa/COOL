import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'admin_receipt_operations_models.dart';
import 'admin_receipt_principal_models.dart';
import 'admin_receipt_principal_checkpoint_stub.dart'
    if (dart.library.js_interop) 'admin_receipt_principal_checkpoint_web.dart'
    as platform;

String adminReceiptPrincipalOwnerDigest(String userId) => sha256
    .convert(
      utf8.encode(
        'collect.receipt-principal-owner.v4:${operationsUuid(userId)}',
      ),
    )
    .toString();

const adminReceiptPrincipalMaximumOriginals = 500;
const adminReceiptPrincipalMaximumPending = 50;

/// A metadata-only original. Restoring it cannot construct or replay an intent.
class AdminReceiptPrincipalCheckpoint {
  const AdminReceiptPrincipalCheckpoint._(this.ownerDigest, this.binding);
  final String ownerDigest;
  final AdminReceiptPrincipalBinding binding;
  String get requestId => binding.requestId;

  factory AdminReceiptPrincipalCheckpoint.fromIntent(
    String ownerDigest,
    AdminReceiptPrincipalIntent intent,
  ) => AdminReceiptPrincipalCheckpoint.parse(
    jsonEncode({
      'version': 3,
      'owner_digest': ownerDigest,
      'binding': AdminReceiptPrincipalBinding.fromIntent(intent).toJson(),
    }),
    ownerDigest,
  );

  String encode() => jsonEncode({
    'version': 3,
    'owner_digest': ownerDigest,
    'binding': binding.toJson(),
  });
  String get digest => sha256.convert(utf8.encode(encode())).toString();

  factory AdminReceiptPrincipalCheckpoint.parse(
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
      'binding',
    });
    if (row['version'] is! int ||
        row['version'] != 3 ||
        row['owner_digest'] != ownerDigest) {
      operationsInvalid();
    }
    final checkpoint = AdminReceiptPrincipalCheckpoint._(
      ownerDigest,
      AdminReceiptPrincipalBinding.parse(row['binding']),
    );
    if (checkpoint.encode() != encoded) operationsInvalid();
    return checkpoint;
  }
}

/// Exclusive owner-scoped publication must enforce pending bounds under the
/// same lock as readback. Originals and resolution markers are never deleted.
abstract class AdminReceiptPrincipalCheckpointStore {
  Future<List<String>> read(String ownerDigest);
  Future<void> write(
    String ownerDigest,
    String requestId,
    String encoded, {
    required bool Function() isCurrent,
  });
  Future<void> resolve(
    AdminReceiptPrincipalCheckpoint checkpoint,
    String status, {
    required bool Function() isCurrent,
  });
}

AdminReceiptPrincipalCheckpointStore?
browserAdminReceiptPrincipalCheckpointStore() =>
    platform.createReceiptPrincipalCheckpointStore();

/// Used both by the controller and by locked storage before publication, so a
/// different tab cannot create a second pending revoke for the same identity.
bool adminReceiptPrincipalMayPublish(
  List<AdminReceiptPrincipalCheckpoint> pending,
  AdminReceiptPrincipalBinding binding,
) {
  if (pending.length >= adminReceiptPrincipalMaximumPending ||
      pending.any((p) => p.requestId == binding.requestId)) {
    return false;
  }
  if (binding.action != AdminReceiptPrincipalAction.revoke) {
    return pending.isEmpty;
  }
  return !pending.any(
    (p) =>
        p.binding.action == AdminReceiptPrincipalAction.revoke &&
        p.binding.principalId == binding.principalId,
  );
}
