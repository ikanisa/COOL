import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'admin_receipt_cancel_models.dart';
import 'admin_receipt_cancel_checkpoint_stub.dart'
    if (dart.library.js_interop) 'admin_receipt_cancel_checkpoint_web.dart'
    as platform;

class AdminReceiptCancelCheckpoint {
  AdminReceiptCancelCheckpoint(this.ownerDigest, this.intent) {
    _digest(ownerDigest);
  }
  final String ownerDigest;
  final AdminReceiptCancelIntent intent;
  String encode() => jsonEncode({
    'version': 1,
    'owner_digest': ownerDigest,
    'request': intent.parameters,
  });
  factory AdminReceiptCancelCheckpoint.parse(
    String encoded,
    String ownerDigest,
  ) {
    if (encoded.length > 2048) cancelInvalid();
    _digest(ownerDigest);
    final row = cancelObject(jsonDecode(encoded), {
      'version',
      'owner_digest',
      'request',
    });
    if (row['version'] is! int ||
        row['version'] != 1 ||
        row['owner_digest'] != ownerDigest) {
      cancelInvalid();
    }
    return AdminReceiptCancelCheckpoint(
      ownerDigest,
      AdminReceiptCancelIntent.fromParameters(row['request']),
    );
  }
}

void _digest(String value) {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) cancelInvalid();
}

String adminReceiptCancelOwnerDigest(String userId) =>
    sha256.convert(utf8.encode('collect-receipt-cancel-v2:$userId')).toString();

abstract class AdminReceiptCancelCheckpointStore {
  String? read(String ownerDigest);
  void write(String ownerDigest, String encoded);
  void clear(String ownerDigest);
}

AdminReceiptCancelCheckpointStore? browserAdminReceiptCancelCheckpointStore() =>
    platform.createReceiptCancelCheckpointStore();
