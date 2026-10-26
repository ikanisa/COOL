import 'dart:convert';
import 'admin_privacy_review_models.dart';
import 'admin_privacy_review_checkpoint_stub.dart'
    if (dart.library.js_interop) 'admin_privacy_review_checkpoint_web.dart'
    as platform;

class AdminPrivacyReviewCheckpoint {
  const AdminPrivacyReviewCheckpoint(this.generation, this.pending);
  final int generation;
  final AdminPrivacyReviewIntent? pending;
}

abstract interface class AdminPrivacyReviewStore {
  Future<AdminPrivacyReviewCheckpoint> read(String actor, String session);
  Future<void> reserve(AdminPrivacyReviewIntent intent, int expectedGeneration);
  Future<void> complete(
    AdminPrivacyReviewIntent intent,
    int expectedGeneration,
    Object receipt,
  );
}

AdminPrivacyReviewStore? browserPrivacyReviewStore() => platform.createStore();

/// One bounded atomic journal under the actor/SID WebLock. The monotonically
/// advanced generation refuses a stale tab after resolution without retaining
/// completed command metadata or receipts in browser storage.
class AdminPrivacyReviewJournalStore implements AdminPrivacyReviewStore {
  const AdminPrivacyReviewJournalStore({
    required this.readRaw,
    required this.writeRaw,
    required this.exclusive,
  });
  final String? Function(String) readRaw;
  final void Function(String, String) writeRaw;
  final Future<void> Function(String, void Function()) exclusive;
  String _key(String actor, String session) =>
      'collect.privacy-review.v1.${privacyReviewUuid(actor)}.${privacyReviewUuid(session)}';
  Map<String, dynamic> _read(String actor, String session) {
    final raw = readRaw(_key(actor, session));
    if (raw == null) {
      return {
        'version': 1,
        'generation': 0,
        'actor_id': actor,
        'session_id': session,
        'pending': null,
      };
    }
    if (utf8.encode(raw).length > 4096) privacyReviewInvalid();
    final value = jsonDecode(raw);
    if (value is! Map ||
        value.length != 5 ||
        !{
          'version',
          'generation',
          'actor_id',
          'session_id',
          'pending',
        }.every(value.containsKey) ||
        value['version'] != 1 ||
        value['version'] is! int ||
        value['actor_id'] != actor ||
        value['session_id'] != session ||
        value['generation'] is! int ||
        (value['generation'] as int) < 0 ||
        (value['generation'] as int) > 1000000000) {
      privacyReviewInvalid();
    }
    final row = Map<String, dynamic>.from(value);
    if (row['pending'] != null) {
      final i = AdminPrivacyReviewIntent.parse(row['pending']);
      if (i.actorId != actor ||
          i.sessionId != session ||
          row['generation'] == 0) {
        privacyReviewInvalid();
      }
    }
    return row;
  }

  void _write(AdminPrivacyReviewIntent i, Map<String, dynamic> row) {
    final raw = jsonEncode(row);
    if (utf8.encode(raw).length > 4096) privacyReviewInvalid();
    writeRaw(_key(i.actorId, i.sessionId), raw);
    if (readRaw(_key(i.actorId, i.sessionId)) != raw) privacyReviewInvalid();
    _read(i.actorId, i.sessionId);
  }

  @override
  Future<AdminPrivacyReviewCheckpoint> read(
    String actor,
    String session,
  ) async {
    final r = _read(actor, session);
    return AdminPrivacyReviewCheckpoint(
      r['generation'] as int,
      r['pending'] == null
          ? null
          : AdminPrivacyReviewIntent.parse(r['pending']),
    );
  }

  @override
  Future<void> reserve(
    AdminPrivacyReviewIntent intent,
    int expectedGeneration,
  ) => exclusive(_key(intent.actorId, intent.sessionId), () {
    final i = AdminPrivacyReviewIntent.parse(intent.row),
        row = _read(i.actorId, i.sessionId);
    if (row['generation'] != expectedGeneration ||
        expectedGeneration >= 999999999 ||
        row['pending'] != null) {
      privacyReviewInvalid();
    }
    row['generation'] = expectedGeneration + 1;
    row['pending'] = i.row;
    _write(i, row);
  });
  @override
  Future<void> complete(
    AdminPrivacyReviewIntent intent,
    int expectedGeneration,
    Object receipt,
  ) => exclusive(_key(intent.actorId, intent.sessionId), () {
    intent.checkReceipt(receipt);
    final row = _read(intent.actorId, intent.sessionId);
    if (row['generation'] != expectedGeneration ||
        expectedGeneration >= 1000000000 ||
        row['pending'] == null ||
        AdminPrivacyReviewIntent.parse(row['pending']).fingerprint !=
            intent.fingerprint) {
      privacyReviewInvalid();
    }
    row['generation'] = expectedGeneration + 1;
    row['pending'] = null;
    _write(intent, row);
  });
}
