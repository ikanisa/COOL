import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'admin_receipt_successor_models.dart';
import 'admin_receipt_successor_checkpoint_stub.dart'
    if (dart.library.js_interop) 'admin_receipt_successor_checkpoint_web.dart'
    as platform;

String successorOwnerDigest(String userId) => sha256
    .convert(
      utf8.encode('collect-receipt-successor-v1:lhbowpbcpwoiparwnwgt:$userId'),
    )
    .toString();

class AdminReceiptSuccessorCheckpoint {
  AdminReceiptSuccessorCheckpoint(this.ownerDigest, this.binding) {
    successorHash(ownerDigest);
  }
  final String ownerDigest;
  final AdminReceiptSuccessorBinding binding;
  String encode() => jsonEncode({
    'version': 1,
    'owner_digest': ownerDigest,
    'binding': binding.encode(),
  });
  factory AdminReceiptSuccessorCheckpoint.parse(
    String encoded,
    String ownerDigest,
  ) {
    successorHash(ownerDigest);
    if (utf8.encode(encoded).length > 4096) successorInvalid();
    final r = successorObject(jsonDecode(encoded), {
      'version',
      'owner_digest',
      'binding',
    });
    if (r['version'] is! int ||
        r['version'] != 1 ||
        r['owner_digest'] != ownerDigest) {
      successorInvalid();
    }
    return AdminReceiptSuccessorCheckpoint(
      ownerDigest,
      AdminReceiptSuccessorBinding.parse(r['binding']),
    );
  }
}

abstract interface class AdminReceiptSuccessorCheckpointStore {
  String? read(String ownerDigest);
  void write(String ownerDigest, String encoded);
  void clear(String ownerDigest);
}

AdminReceiptSuccessorCheckpointStore?
browserReceiptSuccessorCheckpointStore() =>
    platform.createReceiptSuccessorCheckpointStore();
