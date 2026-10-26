@TestOn('browser')
library;

import 'dart:convert';
import 'package:collect_app/admin/core/admin_receipt_notice_content_models.dart';
import 'package:collect_app/admin/core/admin_receipt_notice_dispatch_models.dart';
import 'package:collect_app/admin/core/admin_receipt_notice_dispatch_checkpoint.dart';
import 'package:collect_app/admin/core/admin_receipt_notice_dispatch_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'admin_receipt_notice_dispatch_test.dart'
    show prepared, approveIntent, DispatchApi;
import 'support/receipt_notice_dispatch_fixtures.dart';

const _key = 'collect.notice-dispatch.v1.$dispatchActor.$dispatchSession';
void main() {
  setUp(() => web.window.localStorage.removeItem(_key));
  tearDown(() => web.window.localStorage.removeItem(_key));
  test(
    'real Chrome WebLocks/localStorage durably preserves exact prepared handoff across recreated stores',
    () async {
      final store = browserReceiptNoticeDispatchStore()!, ref = prepared();
      await preserveReceiptNoticePreparedHandoff(
        reference: ref,
        store: store,
        isCurrent: () => true,
      );
      final recreated = browserReceiptNoticeDispatchStore()!;
      expect(
        (await recreated.readPrepared(
          dispatchActor,
          dispatchSession,
          ref.originalRequestId,
        ))!.fingerprint,
        ref.fingerprint,
      );
      expect(
        (await recreated.latestPrepared(
          dispatchActor,
          dispatchSession,
          ref.outboxId,
          ref.sourceSnapshotId,
          ref.collectionId,
          ref.family,
        ))!.preparedReviewId,
        ref.preparedReviewId,
      );
    },
  );
  test(
    'two actual WebLock writers admit one pending original and refuse concurrent replacement',
    () async {
      final a = browserReceiptNoticeDispatchStore()!,
          b = browserReceiptNoticeDispatchStore()!,
          ref = prepared();
      await a.preservePrepared(ref);
      final first = approveIntent(ref),
          second = approveIntent(
            ref,
            requestId: '99780000-0000-4000-8000-000000000099',
          );
      final outcomes = await Future.wait([
        a.savePending(first).then((_) => true, onError: (_) => false),
        b.savePending(second).then((_) => true, onError: (_) => false),
      ]);
      expect(outcomes.where((e) => e).length, 1);
      final retained = await b.pending(dispatchActor, dispatchSession);
      expect([
        first.requestId,
        second.requestId,
      ], contains(retained!.requestId));
      await expectLater(
        a.savePending(retained.requestId == first.requestId ? second : first),
        throwsFormatException,
      );
    },
  );
  test(
    'atomic actual browser completion retains exact approval and original tombstone',
    () async {
      final store = browserReceiptNoticeDispatchStore()!,
          ref = prepared(),
          intent = approveIntent(prepared());
      await store.preservePrepared(ref);
      await store.savePending(intent);
      await store.complete(
        intent,
        AdminReceiptNoticeDispatchRequest.recorded(
          dispatchFixture('approved-copy'),
          intent,
        ),
      );
      final next = browserReceiptNoticeDispatchStore()!;
      expect(await next.pending(dispatchActor, dispatchSession), isNull);
      expect(
        (await next.approval(ref))!['approval_id'],
        dispatchFixture('approved-copy')['approval_id'],
      );
      await expectLater(next.savePending(intent), throwsFormatException);
    },
  );
  test(
    'real browser checkpoint survives lost reply and recreated controller; not_recorded never unlocks replacement',
    () async {
      final store = browserReceiptNoticeDispatchStore()!,
          ref = prepared(),
          api = DispatchApi(prepared())..loseReply = true;
      await store.preservePrepared(ref);
      AdminReceiptNoticeDispatchController create() =>
          AdminReceiptNoticeDispatchController(
            api: api,
            actorId: dispatchActor,
            sessionId: dispatchSession,
            isCurrent: () => true,
            canManage: () => true,
            now: () => DateTime.parse(
              dispatchFixture('dispatch-copy')['checked_at'] as String,
            ).add(const Duration(seconds: 1)),
            newRequestId: () =>
                dispatchFixture('approved-copy')['request_id'] as String,
            store: browserReceiptNoticeDispatchStore(),
            reference: ref,
          );
      final first = create();
      await first.refresh();
      await first.record(
        AdminReceiptNoticeDispatchAction.approve,
        'Synthetic current owner dispatch approval',
      );
      first.dispose();
      final next = create();
      addTearDown(next.dispose);
      api.missing = true;
      await next.refresh();
      await next.recover();
      expect(next.pending, isNotNull);
      expect(next.canApprove, isFalse);
      expect(api.writes, 1);
      expect(api.lookups, 1);
      expect(
        (await store.pending(dispatchActor, dispatchSession))!.requestId,
        api.written!.requestId,
      );
      api.missing = false;
      await next.recover();
      expect(next.pending, isNull);
      expect(api.writes, 1);
      expect((await store.approval(ref))!['send_authority'], isFalse);
    },
  );
  test(
    'session loss during actual asynchronous handoff refuses clearance and another session cannot adopt it',
    () async {
      final store = browserReceiptNoticeDispatchStore()!, ref = prepared();
      var current = true;
      final work = preserveReceiptNoticePreparedHandoff(
        reference: ref,
        store: store,
        isCurrent: () => current,
      );
      current = false;
      await expectLater(work, throwsFormatException);
      expect(
        await store.readPrepared(
          dispatchActor,
          '99780000-0000-4000-8000-000000010002',
          ref.originalRequestId,
        ),
        isNull,
      );
    },
  );
  test(
    'browser journal explicit64/65 capacity refuses without truncation or forgetting an unresolved original',
    () async {
      final ref = prepared(), derived = <Object?>[];
      // Declared synthetic cardinality fixture: distinct original/review UUIDs are
      // derived for the storage ceiling only; this is not SQL financial evidence.
      for (var i = 0; i < 64; i++) {
        final row = jsonDecode(jsonEncode(ref.row)) as Map<String, dynamic>,
            id =
                '99789999-0000-4000-8000-${(i + 1).toString().padLeft(12, '0')}',
            review =
                '99789998-0000-4000-8000-${(i + 1).toString().padLeft(12, '0')}';
        final original = row['original'] as Map<String, dynamic>;
        original['request_id'] = id;
        original.remove('fingerprint');
        original['fingerprint'] = noticeFingerprint(original);
        (row['recorded'] as Map)['request_id'] = id;
        (row['recorded'] as Map)['review_id'] = review;
        AdminReceiptNoticePreparedReference.parse(row);
        derived.add(row);
      }
      web.window.localStorage.setItem(
        _key,
        jsonEncode({
          'version': 1,
          'actor_id': dispatchActor,
          'session_id': dispatchSession,
          'prepared': derived,
          'pending': null,
          'completed': <Object?>[],
        }),
      );
      final before = web.window.localStorage.getItem(_key),
          store = browserReceiptNoticeDispatchStore()!;
      expect(
        (await store.readPrepared(
          dispatchActor,
          dispatchSession,
          '99789999-0000-4000-8000-000000000064',
        ))!.preparedReviewId,
        '99789998-0000-4000-8000-000000000064',
      );
      await expectLater(store.preservePrepared(ref), throwsFormatException);
      expect(web.window.localStorage.getItem(_key), before);
    },
  );
}
