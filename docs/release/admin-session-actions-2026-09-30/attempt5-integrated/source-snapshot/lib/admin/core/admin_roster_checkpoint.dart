import 'dart:convert';

import 'admin_roster_models.dart';
import 'admin_roster_checkpoint_stub.dart'
    if (dart.library.js_interop) 'admin_roster_checkpoint_web.dart'
    as platform;

/// A browser bookmark contains only opaque references and digests. Private
/// editor values live in memory and in the session-owned server draft.
class RosterBookmark {
  RosterBookmark({
    required this.ownerDigest,
    required this.uploadRequestId,
    required this.sourceSha256,
    this.collectionId,
    this.importId,
    this.checkpointId,
    this.pendingRequestId,
    this.pendingSha256,
  });
  final String ownerDigest, uploadRequestId, sourceSha256;
  final String? collectionId,
      importId,
      checkpointId,
      pendingRequestId,
      pendingSha256;
  Map<String, dynamic> toJson() => {
    'version': 1,
    'owner_digest': ownerDigest,
    'upload_request_id': uploadRequestId,
    'source_sha256': sourceSha256,
    'collection_id': collectionId,
    'import_id': importId,
    'checkpoint_id': checkpointId,
    'pending_request_id': pendingRequestId,
    'pending_sha256': pendingSha256,
  };
  factory RosterBookmark.parse(String encoded, String ownerDigest) {
    if (encoded.length > 2048)
      throw const FormatException('Invalid recovery reference.');
    final m = rosterObject(jsonDecode(encoded));
    const fields = {
      'version',
      'owner_digest',
      'upload_request_id',
      'source_sha256',
      'collection_id',
      'import_id',
      'checkpoint_id',
      'pending_request_id',
      'pending_sha256',
    };
    if (m.length != fields.length ||
        !m.keys.toSet().containsAll(fields) ||
        m['version'] != 1 ||
        m['owner_digest'] != ownerDigest ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(ownerDigest) ||
        !rosterUuid.hasMatch('${m['upload_request_id']}') ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch('${m['source_sha256']}'))
      throw const FormatException('Invalid recovery reference.');
    for (final field in [
      'collection_id',
      'import_id',
      'checkpoint_id',
      'pending_request_id',
    ]) {
      if (m[field] != null && !rosterUuid.hasMatch('${m[field]}'))
        throw const FormatException('Invalid recovery reference.');
    }
    if ((m['pending_request_id'] == null) != (m['pending_sha256'] == null) ||
        m['pending_sha256'] != null &&
            !RegExp(r'^[a-f0-9]{64}$').hasMatch('${m['pending_sha256']}'))
      throw const FormatException('Invalid recovery reference.');
    return RosterBookmark(
      ownerDigest: ownerDigest,
      uploadRequestId: m['upload_request_id'] as String,
      sourceSha256: m['source_sha256'] as String,
      collectionId: m['collection_id'] as String?,
      importId: m['import_id'] as String?,
      checkpointId: m['checkpoint_id'] as String?,
      pendingRequestId: m['pending_request_id'] as String?,
      pendingSha256: m['pending_sha256'] as String?,
    );
  }
  RosterBookmark withReferences({
    String? importId,
    String? checkpointId,
    String? pendingRequestId,
    String? pendingSha256,
    bool clearPending = false,
  }) => RosterBookmark(
    ownerDigest: ownerDigest,
    uploadRequestId: uploadRequestId,
    sourceSha256: sourceSha256,
    collectionId: collectionId,
    importId: importId ?? this.importId,
    checkpointId: checkpointId ?? this.checkpointId,
    pendingRequestId: clearPending
        ? null
        : pendingRequestId ?? this.pendingRequestId,
    pendingSha256: clearPending ? null : pendingSha256 ?? this.pendingSha256,
  );
}

abstract class RosterBookmarkStore {
  String? read();
  void write(String value);
  void clear();
}

RosterBookmarkStore? browserRosterBookmarkStore() =>
    platform.createRosterBookmarkStore();
