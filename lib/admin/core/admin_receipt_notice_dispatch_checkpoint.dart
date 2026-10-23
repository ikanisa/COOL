import 'dart:convert';
import 'admin_receipt_notice_content_models.dart';
import 'admin_receipt_notice_dispatch_models.dart';
import 'admin_receipt_notice_dispatch_checkpoint_stub.dart'
    if (dart.library.js_interop) 'admin_receipt_notice_dispatch_checkpoint_web.dart'
    as platform;

abstract interface class AdminReceiptNoticeDispatchStore {
  Future<void> preservePrepared(AdminReceiptNoticePreparedReference reference);
  Future<AdminReceiptNoticePreparedReference?> readPrepared(
    String actor,
    String session,
    String originalRequestId,
  );
  Future<AdminReceiptNoticePreparedReference?> latestPrepared(
    String actor,
    String session,
    String outbox,
    String source,
    String collection,
    AdminReceiptNoticeFamily family,
  );
  Future<AdminReceiptNoticeDispatchIntent?> pending(
    String actor,
    String session,
  );
  Future<void> savePending(AdminReceiptNoticeDispatchIntent intent);
  Future<void> complete(
    AdminReceiptNoticeDispatchIntent intent,
    AdminReceiptNoticeDispatchRequest recorded,
  );
  Future<Map<String, dynamic>?> approval(
    AdminReceiptNoticePreparedReference reference,
  );
}

AdminReceiptNoticeDispatchStore? browserReceiptNoticeDispatchStore() =>
    platform.createStore();

/// Must be awaited before clearing the actual1600 original checkpoint.
/// Failure leaves that original available for idempotent original-request lookup.
Future<void> preserveReceiptNoticePreparedHandoff({
  required AdminReceiptNoticePreparedReference reference,
  required AdminReceiptNoticeDispatchStore store,
  required bool Function() isCurrent,
}) async {
  if (!isCurrent()) noticeInvalid();
  await store.preservePrepared(reference);
  if (!isCurrent()) noticeInvalid();
  final saved = await store.readPrepared(
    reference.actorId,
    reference.sessionId,
    reference.originalRequestId,
  );
  if (!isCurrent() || saved?.fingerprint != reference.fingerprint) {
    noticeInvalid();
  }
}

/// One atomically replaced journal under the platform's owner/session WebLock.
/// Explicit capacity refusal retains unresolved and completed original records.
class AdminReceiptNoticeDispatchJournalStore
    implements AdminReceiptNoticeDispatchStore {
  const AdminReceiptNoticeDispatchJournalStore({
    required this.readRaw,
    required this.writeRaw,
    required this.exclusive,
  });
  final String? Function(String) readRaw;
  final void Function(String, String) writeRaw;
  final Future<void> Function(String, void Function()) exclusive;
  static const capacity = 64, maximumBytes = 2097152;
  String _key(String actor, String session) =>
      'collect.notice-dispatch.v1.${noticeUuid(actor)}.${noticeUuid(session)}';
  Map<String, dynamic> _read(String actor, String session) {
    final raw = readRaw(_key(actor, session));
    if (raw == null) {
      return {
        'version': 1,
        'actor_id': actor,
        'session_id': session,
        'prepared': <Object?>[],
        'pending': null,
        'completed': <Object?>[],
      };
    }
    if (utf8.encode(raw).length > maximumBytes) noticeInvalid();
    final row = noticeObject(jsonDecode(raw), {
      'version',
      'actor_id',
      'session_id',
      'prepared',
      'pending',
      'completed',
    });
    if (row['version'] is! int ||
        row['version'] != 1 ||
        row['actor_id'] != actor ||
        row['session_id'] != session ||
        row['prepared'] is! List ||
        row['completed'] is! List ||
        (row['prepared'] as List).length > capacity ||
        (row['completed'] as List).length > capacity) {
      noticeInvalid();
    }
    final originals = <String>{}, reviews = <String>{}, requests = <String>{};
    for (final raw in row['prepared'] as List) {
      final ref = AdminReceiptNoticePreparedReference.parse(raw);
      if (ref.actorId != actor ||
          ref.sessionId != session ||
          !originals.add(ref.originalRequestId) ||
          !reviews.add(ref.preparedReviewId)) {
        noticeInvalid();
      }
    }
    void bound(AdminReceiptNoticeDispatchIntent i) {
      if (i.actorId != actor ||
          i.sessionId != session ||
          originals.contains(i.requestId) ||
          !requests.add(i.requestId)) {
        noticeInvalid();
      }
      if (i.reference != null &&
          !(row['prepared'] as List).any(
            (r) => noticeFingerprint(r) == i.reference!.fingerprint,
          )) {
        noticeInvalid();
      }
    }

    for (final raw in row['completed'] as List) {
      final done = noticeObject(raw, {'intent', 'result'}),
          i = AdminReceiptNoticeDispatchIntent.parse(done['intent']);
      bound(i);
      AdminReceiptNoticeDispatchRequest.recorded(done['result'], i);
    }
    if (row['pending'] != null) {
      bound(AdminReceiptNoticeDispatchIntent.parse(row['pending']));
    }
    return row;
  }

  void _write(String actor, String session, Map<String, dynamic> row) {
    final raw = jsonEncode(row);
    if (utf8.encode(raw).length > maximumBytes) noticeInvalid();
    writeRaw(_key(actor, session), raw);
    if (readRaw(_key(actor, session)) != raw) noticeInvalid();
    _read(actor, session); // A successful write never hides an invalid journal.
  }

  @override
  Future<void> preservePrepared(
    AdminReceiptNoticePreparedReference reference,
  ) => exclusive(_key(reference.actorId, reference.sessionId), () {
    final row = _read(reference.actorId, reference.sessionId),
        refs = List<Object?>.from(row['prepared'] as List);
    for (final raw in refs) {
      final old = AdminReceiptNoticePreparedReference.parse(raw);
      if (old.originalRequestId == reference.originalRequestId ||
          old.preparedReviewId == reference.preparedReviewId) {
        if (old.fingerprint != reference.fingerprint) noticeInvalid();
        return;
      }
    }
    final pending = row['pending'] == null
        ? null
        : AdminReceiptNoticeDispatchIntent.parse(row['pending']);
    if (pending?.requestId == reference.originalRequestId ||
        (row['completed'] as List).any(
          (e) =>
              ((e as Map)['intent'] as Map)['request_id'] ==
              reference.originalRequestId,
        ) ||
        refs.length >= capacity) {
      noticeInvalid();
    }
    refs.add(reference.row);
    row['prepared'] = refs;
    _write(reference.actorId, reference.sessionId, row);
  });
  @override
  Future<AdminReceiptNoticePreparedReference?> readPrepared(
    String actor,
    String session,
    String originalRequestId,
  ) async {
    noticeUuid(originalRequestId);
    for (final raw in _read(actor, session)['prepared'] as List) {
      final ref = AdminReceiptNoticePreparedReference.parse(raw);
      if (ref.originalRequestId == originalRequestId) return ref;
    }
    return null;
  }

  @override
  Future<AdminReceiptNoticePreparedReference?> latestPrepared(
    String actor,
    String session,
    String outbox,
    String source,
    String collection,
    AdminReceiptNoticeFamily family,
  ) async {
    for (final id in [outbox, source, collection]) {
      noticeUuid(id);
    }
    AdminReceiptNoticePreparedReference? found;
    for (final raw in _read(actor, session)['prepared'] as List) {
      final ref = AdminReceiptNoticePreparedReference.parse(raw);
      if (ref.outboxId == outbox &&
          ref.sourceSnapshotId == source &&
          ref.collectionId == collection &&
          ref.family == family &&
          (found == null ||
              (ref.recorded.result!['content_review_revision'] as int) >
                  (found.recorded.result!['content_review_revision'] as int))) {
        found = ref;
      }
    }
    return found;
  }

  @override
  Future<AdminReceiptNoticeDispatchIntent?> pending(
    String actor,
    String session,
  ) async {
    final raw = _read(actor, session)['pending'];
    return raw == null ? null : AdminReceiptNoticeDispatchIntent.parse(raw);
  }

  @override
  Future<void> savePending(
    AdminReceiptNoticeDispatchIntent intent,
  ) => exclusive(_key(intent.actorId, intent.sessionId), () {
    final row = _read(intent.actorId, intent.sessionId);
    if ((row['completed'] as List).length >= capacity &&
        row['pending'] == null) {
      noticeInvalid();
    }
    if ((row['prepared'] as List).any(
          (e) =>
              AdminReceiptNoticePreparedReference.parse(e).originalRequestId ==
              intent.requestId,
        ) ||
        (row['completed'] as List).any(
          (e) =>
              ((e as Map)['intent'] as Map)['request_id'] == intent.requestId,
        )) {
      noticeInvalid();
    }
    if (intent.reference != null &&
        !(row['prepared'] as List).any(
          (e) => noticeFingerprint(e) == intent.reference!.fingerprint,
        )) {
      noticeInvalid();
    }
    if (row['pending'] != null &&
        AdminReceiptNoticeDispatchIntent.parse(row['pending']).fingerprint !=
            intent.fingerprint) {
      noticeInvalid();
    }
    row['pending'] = intent.row;
    _write(intent.actorId, intent.sessionId, row);
  });
  @override
  Future<void> complete(
    AdminReceiptNoticeDispatchIntent intent,
    AdminReceiptNoticeDispatchRequest recorded,
  ) => exclusive(_key(intent.actorId, intent.sessionId), () {
    if (!recorded.recorded) noticeInvalid();
    final result = AdminReceiptNoticeDispatchRequest.recorded(
          recorded.result,
          intent,
        ),
        row = _read(intent.actorId, intent.sessionId),
        done = List<Object?>.from(row['completed'] as List);
    final completed = {'intent': intent.row, 'result': result.result};
    for (final e in done) {
      if (((e as Map)['intent'] as Map)['request_id'] == intent.requestId) {
        if (noticeFingerprint(e) != noticeFingerprint(completed)) {
          noticeInvalid();
        }
        return;
      }
    }
    if (row['pending'] == null ||
        AdminReceiptNoticeDispatchIntent.parse(row['pending']).fingerprint !=
            intent.fingerprint ||
        done.length >= capacity) {
      noticeInvalid();
    }
    done.add(completed);
    row['completed'] = done;
    row['pending'] = null;
    _write(intent.actorId, intent.sessionId, row);
  });
  @override
  Future<Map<String, dynamic>?> approval(
    AdminReceiptNoticePreparedReference reference,
  ) async {
    Map<String, dynamic>? approval;
    for (final raw
        in _read(reference.actorId, reference.sessionId)['completed'] as List) {
      final e = raw as Map,
          intent = AdminReceiptNoticeDispatchIntent.parse(e['intent']);
      if (intent.reference?.fingerprint != reference.fingerprint) continue;
      if (intent.action == AdminReceiptNoticeDispatchAction.approve) {
        approval = dispatchApproval(e['result'], reference);
      }
      if (intent.action == AdminReceiptNoticeDispatchAction.revoke &&
          (e['result'] as Map)['approval_id'] == approval?['approval_id']) {
        approval = null;
      }
    }
    return approval;
  }
}
