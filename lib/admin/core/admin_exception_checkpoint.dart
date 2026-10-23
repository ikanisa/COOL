import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'admin_exception_models.dart';
import 'admin_exception_checkpoint_stub.dart'
    if (dart.library.js_interop) 'admin_exception_checkpoint_web.dart'
    as platform;

/// Only opaque reviewed references survive a same-tab reload after fresh sign-in. No source payload,
/// actor identifier, session token, contact or free-text reason is stored.
class AdminExceptionCheckpoint {
  const AdminExceptionCheckpoint(this.ownerDigest, this.intent);
  final String ownerDigest;
  final AdminExceptionIntent intent;
  String encode() {
    _digest(ownerDigest);
    return jsonEncode({
      'version': 1,
      'owner_digest': ownerDigest,
      'request': intent.parameters,
    });
  }

  factory AdminExceptionCheckpoint.parse(String encoded, String ownerDigest) {
    if (encoded.length > 2048) exceptionInvalid();
    _digest(ownerDigest);
    final data = exceptionObject(jsonDecode(encoded), {
      'version',
      'owner_digest',
      'request',
    });
    if (data['version'] is! int ||
        data['version'] != 1 ||
        data['owner_digest'] != ownerDigest) {
      exceptionInvalid();
    }
    if (data['request'] is! Map) exceptionInvalid();
    final intent = AdminExceptionIntent.fromParameters(
      Map<String, dynamic>.from(data['request'] as Map),
    );
    return AdminExceptionCheckpoint(ownerDigest, intent);
  }
}

void _digest(String value) {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) exceptionInvalid();
}

String adminExceptionOwnerDigest(String userId) => sha256
    .convert(utf8.encode('collect-exception-review-v2:$userId'))
    .toString();

abstract class AdminExceptionCheckpointStore {
  String? read(String ownerDigest);
  void write(String ownerDigest, String encoded);
  void clear(String ownerDigest);
}

AdminExceptionCheckpointStore? browserAdminExceptionCheckpointStore() =>
    platform.createExceptionCheckpointStore();
