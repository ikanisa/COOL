import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:collect_app/admin/core/admin_receipt_notice_content_controller.dart';
import 'package:collect_app/admin/core/admin_receipt_notice_content_models.dart';
import 'package:collect_app/admin/core/admin_receipt_notice_dispatch_models.dart';
import 'package:collect_app/admin/core/admin_receipt_notice_dispatch_checkpoint.dart';
import 'admin_receipt_notice_content_test.dart' as content;
import 'support/receipt_notice_dispatch_journal_fixture.dart';

class _Harness {
  _Harness({this.handoff = true}) {
    sample = content.inspection('content-preview-duplicate_copy-rw');
    result = content.fixture('actual-prepared-duplicate_copy-rw');
    original = content.intent('content-preview-duplicate_copy-rw', result['request_id'] as String);
    api = content.Api(sample, result);
    for (var n = 0; n < 12; n++) {
      final value = content.fixture('actual-lookup-recorded-$n');
      if (value['request_id'] == original.requestId) {
        api.lookup = value;
        break;
      }
    }
    if (api.lookup == null) throw StateError('Actual original lookup fixture missing');
    controller = makeController();
  }
  final bool handoff;
  late final AdminReceiptNoticeInspection sample;
  late final Map<String, dynamic> result;
  late final AdminReceiptNoticeIntent original;
  late final content.Api api;
  final checkpoint = content.Store();
  final journal = NoticeDispatchJournalFixture();
  late AdminReceiptNoticeContentController controller;
  bool current = true;
  int recorded = 0, preserved = 0;
  Future<void> preserve(AdminReceiptNoticeIntent i, AdminReceiptNoticeRequest r) async {
    final ref = AdminReceiptNoticePreparedReference.fromRecorded(
      inspection: i.inspection, recorded: r, original: i,
      actorId: content.actor, sessionId: content.session,
    );
    await preserveReceiptNoticePreparedHandoff(reference: ref, store: journal.store, isCurrent: () => current);
    preserved++;
  }
  AdminReceiptNoticeContentController makeController() => AdminReceiptNoticeContentController(
    api: api, actorId: content.actor, sessionId: content.session,
    collectionId: sample.collectionId, outboxId: sample.outboxId,
    sourceSnapshotId: sample.sourceSnapshotId, policy: false,
    store: checkpoint, now: () => sample.checkedAt.add(const Duration(seconds: 1)),
    isCurrent: () => current, canManage: () => true,
    newRequestId: () => original.requestId, onRecorded: () => recorded++,
    preserveRecordedContent: handoff ? preserve : null,
  );
  Future<void> load() => controller.refresh(family: sample.family);
  Future<void> record() => controller.record(original.reason);
  Future<AdminReceiptNoticePreparedReference?> saved() => journal.store.readPrepared(content.actor, content.session, original.requestId);
  void restart() { controller.dispose(); controller = makeController(); }
  void dispose() => controller.dispose();
}

void main() {
  test('exact actual content is durable before checkpoint clearance and invalidation', () async {
    final h = _Harness(); addTearDown(h.dispose);
    await h.load(); await h.record();
    expect(h.api.mutations, 1); expect(h.preserved, 1); expect(h.recorded, 1);
    expect(h.checkpoint.value, isNull); expect(h.controller.pending, isNull);
    final saved = (await h.saved())!;
    expect(saved.preparedReviewId, h.result['review_id']);
    expect(saved.original.fingerprint, h.original.fingerprint);
    expect(saved.outboxId, h.sample.outboxId);
    expect(saved.sourceSnapshotId, h.sample.sourceSnapshotId);
    expect(saved.bodySha256, h.result['body_sha256']);
    final recreated = NoticeDispatchJournalFixture(shared: h.journal.bytes);
    expect((await recreated.store.readPrepared(content.actor, content.session, h.original.requestId))!.fingerprint, saved.fingerprint);
    expect(await recreated.store.readPrepared(content.actor, '99780000-0000-4000-8000-000000010002', h.original.requestId), isNull);
  });
  test('storage refusal leaves the original request; lookup recovers the same handoff', () async {
    final h = _Harness(); addTearDown(h.dispose);
    h.journal.refuseWrite = true; await h.load(); await h.record();
    expect(h.api.mutations, 1); expect(h.recorded, 0); expect(h.checkpoint.value?.fingerprint, h.original.fingerprint);
    expect(h.controller.canRecord, isFalse);
    h.journal.refuseWrite = false; h.restart(); await h.load(); await h.controller.recover();
    expect(h.api.mutations, 1); expect(h.api.recoveries, 1); expect(h.recorded, 1);
    expect((await h.saved())!.original.fingerprint, h.original.fingerprint);
    expect(h.checkpoint.value, isNull);
  });
  test('failed durable readback retains original even after a platform write', () async {
    final h = _Harness(); addTearDown(h.dispose);
    h.journal.refuseReadback = true; await h.load(); await h.record();
    expect(h.journal.writes, 1); expect(h.recorded, 0);
    expect(h.checkpoint.value?.fingerprint, h.original.fingerprint);
    h.journal.refuseReadback = false; h.restart(); await h.load(); await h.controller.recover();
    expect(h.journal.writes, 1); expect(h.api.mutations, 1); expect(h.recorded, 1);
    expect((await h.saved())!.originalRequestId, h.original.requestId);
  });
  test('session loss during awaited preservation cannot clear or invalidate', () async {
    final h = _Harness(); addTearDown(h.dispose);
    final release = Completer<void>(); h.journal.release = release.future;
    await h.load(); final request = h.record();
    for (var n = 0; n < 100 && h.journal.writes == 0; n++) { await Future<void>.delayed(const Duration(milliseconds: 1)); }
    expect(h.journal.writes, 1);
    h.current = false; release.complete(); await request;
    expect(h.api.mutations, 1); expect(h.recorded, 0); expect(h.preserved, 0);
    expect(h.checkpoint.value?.fingerprint, h.original.fingerprint);
    expect((await h.saved())!.originalRequestId, h.original.requestId);
  });
  test('absent handoff blocks new content preparation before a side effect', () async {
    final h = _Harness(handoff: false); addTearDown(h.dispose);
    await h.load(); expect(h.controller.canRecord, isFalse); await h.record();
    expect(h.api.mutations, 0); expect(h.checkpoint.events, isEmpty);
  });
  test('recorded original recovery cannot clear without the durable handoff', () async {
    final h = _Harness(handoff: false); addTearDown(h.dispose);
    h.checkpoint.value = h.original; await h.load(); await h.controller.recover();
    expect(h.api.recoveries, 1); expect(h.api.mutations, 0); expect(h.recorded, 0);
    expect(h.checkpoint.value?.fingerprint, h.original.fingerprint);
  });
  test('checkpoint-clear failure reuses the already preserved original on recovery', () async {
    final h = _Harness(); addTearDown(h.dispose);
    h.checkpoint.failClear = true; await h.load(); await h.record();
    final fingerprint = (await h.saved())!.fingerprint;
    expect(h.recorded, 0); expect(h.checkpoint.value, isNotNull);
    h.checkpoint.failClear = false; h.restart(); await h.load(); await h.controller.recover();
    expect(h.api.mutations, 1); expect(h.journal.writes, 1); expect(h.recorded, 1);
    expect((await h.saved())!.fingerprint, fingerprint);
  });
  test('foreign-session handoff is refused and preserves the original', () async {
    final h = _Harness(); addTearDown(h.dispose); h.controller.dispose();
    h.controller = AdminReceiptNoticeContentController(
      api: h.api, actorId: content.actor, sessionId: content.session,
      collectionId: h.sample.collectionId, outboxId: h.sample.outboxId,
      sourceSnapshotId: h.sample.sourceSnapshotId, policy: false, store: h.checkpoint,
      now: () => h.sample.checkedAt, isCurrent: () => true, canManage: () => true,
      newRequestId: () => h.original.requestId,
      preserveRecordedContent: (i, r) async {
        AdminReceiptNoticePreparedReference.fromRecorded(inspection: i.inspection, recorded: r, original: i, actorId: content.actor, sessionId: '99780000-0000-4000-8000-000000010002');
      },
    );
    await h.load(); await h.record();
    expect(h.api.mutations, 1); expect(h.recorded, 0); expect(h.checkpoint.value?.fingerprint, h.original.fingerprint);
    expect(await h.saved(), isNull);
  });
}
