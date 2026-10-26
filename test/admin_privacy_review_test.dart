import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_privacy_review_models.dart';
import 'package:collect_app/admin/core/admin_privacy_review_sdk.dart';
import 'package:collect_app/admin/core/admin_privacy_review_controller.dart';
import 'support/privacy_review_fixtures.dart';

AdminPrivacyReviewController controller(
  PrivacyApiFake api,
  PrivacyJournalFixture journal, {
  bool Function()? current,
  DateTime Function()? now,
  String Function()? newId,
}) => AdminPrivacyReviewController(
  api: api,
  actorId: privacyActor,
  sessionId: privacySession,
  store: journal.store,
  now: now ?? () => privacyNow,
  isCurrent: current ?? () => true,
  newOperationId: newId ?? () => privacyOperation,
);

void main() {
  test(
    'typed evidence rejects changed flags, unknown states, extra PII and malformed UTC',
    () {
      for (final flags in [
        'policy_acceptance_granted',
        'erasure_completed',
        'auth_removed',
        'processor_operation_started',
      ]) {
        expect(
          () => AdminPrivacyReviewDetail.parse(
            privacyDetailRaw()..[flags] = true,
            privacyRequest,
          ),
          throwsFormatException,
        );
      }
      expect(
        () => AdminPrivacyReviewDetail.parse(
          privacyDetailRaw()..['subject_phone'] = 'PRIVATE',
          privacyRequest,
        ),
        throwsFormatException,
      );
      final malformed = privacyDetailRaw();
      (malformed['item'] as Map)['review_state'] = 'completed';
      expect(
        () => AdminPrivacyReviewDetail.parse(malformed, privacyRequest),
        throwsFormatException,
      );
      expect(
        () => AdminPrivacyReviewDetail.parse(
          privacyDetailRaw()..['checked_at'] = '2026-02-30T12:00:00Z',
          privacyRequest,
        ),
        throwsFormatException,
      );
      expect(
        () => AdminPrivacyReviewDetail.parse(
          privacyDetailRaw()..['checked_at'] = '2026-10-03T12:00:00+00:00',
          privacyRequest,
        ),
        throwsFormatException,
      );
      expect(
        () => AdminPrivacyReviewDetail.parse(
          privacyDetailRaw()..['contract_version'] = 1.0,
          privacyRequest,
        ),
        throwsFormatException,
      );
    },
  );
  test('queue pagination preserves canonical ordering and cursor scope', () {
    final newer = privacyItem(),
        older = privacyItem(
          id: privacyClaim,
          accepted: privacyNow.subtract(const Duration(days: 2)),
        );
    final p = AdminPrivacyReviewPage.parse(
      privacyPageRaw(
        items: [newer],
        limit: 1,
        next: {
          'accepted_at': newer['accepted_at'],
          'request_id': privacyRequest,
        },
      ),
      limit: 1,
    );
    expect(
      AdminPrivacyReviewPage.parse(
        privacyPageRaw(items: [older], limit: 1),
        limit: 1,
        before: p.next,
      ).items.single.requestId,
      privacyClaim,
    );
    expect(
      () => AdminPrivacyReviewPage.parse(
        privacyPageRaw(items: [newer, older]),
        limit: 25,
        before: p.next,
      ),
      throwsFormatException,
    );
    expect(
      () => AdminPrivacyReviewPage.parse(
        privacyPageRaw(items: [older, newer]),
        limit: 25,
      ),
      throwsFormatException,
    );
    expect(
      () => AdminPrivacyReviewPage.parse(
        privacyPageRaw(
          items: [newer],
          next: {
            'accepted_at': newer['accepted_at'],
            'request_id': privacyClaim,
          },
        ),
        limit: 25,
      ),
      throwsFormatException,
    );
  });
  test('historical and expired receipts cannot authorize an outcome', () {
    final active = privacyDetail(state: 'claim_active', owned: true);
    expect(active.canRecord(privacyNow), isTrue);
    expect(
      active.canRecord(privacyNow.add(const Duration(seconds: 60))),
      isFalse,
    );
    expect(active.fresh(privacyNow.add(const Duration(minutes: 10))), isFalse);
    final foreign = privacyDetail(state: 'claim_active');
    expect(foreign.canRecord(privacyNow), isFalse);
    final malformed = privacyDetailRaw(state: 'claim_active', owned: true);
    (malformed['own_claim_receipt'] as Map)['revision'] = 2;
    expect(
      () => AdminPrivacyReviewDetail.parse(malformed, privacyRequest),
      throwsFormatException,
    );
    expect(
      () => AdminPrivacyReviewDetail.parse(
        privacyDetailRaw(
          state: 'claim_expired',
          owned: true,
          checked: privacyNow.add(const Duration(seconds: 60)),
        )..['own_claim_authority_current'] = true,
        privacyRequest,
      ),
      throwsFormatException,
    );
  });
  test(
    'SDK uses bounded concrete RPCs and original immutable parameters',
    () async {
      final calls = <(String, Map<String, dynamic>)>[];
      final sdk = AdminPrivacyReviewSdk(
        actorId: privacyActor,
        sessionId: privacySession,
        isCurrent: () => true,
        now: () => privacyNow,
        rpc: (name, p) async {
          calls.add((name, p));
          if (name.contains('list_')) return privacyPageRaw();
          if (name == 'admin_get_account_deletion_review_v1') {
            return privacyDetailRaw();
          }
          if (name.contains('operation_v1')) {
            return privacyOperationRaw(privacyIntent());
          }
          return privacyClaimReceipt();
        },
      );
      await sdk.list();
      final d = await sdk.detail(privacyRequest);
      await sdk.write(privacyIntent(), d);
      await sdk.resolve(privacyIntent());
      expect(calls.map((e) => e.$1), [
        'admin_list_account_deletion_reviews_v1',
        'admin_get_account_deletion_review_v1',
        'admin_claim_account_deletion_review_v1',
        'admin_get_account_deletion_review_operation_v1',
      ]);
      expect(calls[2].$2, privacyIntent().parameters);
      expect(
        () => calls[2].$2['p_claim_request_id'] = privacyClaim,
        throwsUnsupportedError,
      );
      expect(calls.last.$2, {
        'p_operation_kind': 'claim',
        'p_operation_id': privacyOperation,
      });
    },
  );
  test(
    'SDK denies expired sample, foreign SID and revoked access before or after awaited calls',
    () async {
      var live = true, count = 0;
      final reply = Completer<Object?>();
      final sdk = AdminPrivacyReviewSdk(
        actorId: privacyActor,
        sessionId: privacySession,
        isCurrent: () => live,
        now: () => privacyNow,
        rpc: (_, _) {
          count++;
          return reply.future;
        },
      );
      final read = sdk.detail(privacyRequest);
      live = false;
      reply.complete(privacyDetailRaw());
      await expectLater(read, throwsA(isA<AdminSessionChanged>()));
      live = true;
      final foreign = AdminPrivacyReviewIntent.claim(
        operationId: privacyOperation,
        actorId: privacyActor,
        sessionId: privacyClaim,
        detail: privacyDetail(),
      );
      await expectLater(sdk.resolve(foreign), throwsFormatException);
      expect(count, 1);
      final stale = AdminPrivacyReviewSdk(
        actorId: privacyActor,
        sessionId: privacySession,
        isCurrent: () => true,
        now: () => privacyNow.add(const Duration(minutes: 10)),
        rpc: (_, _) async => privacyDetailRaw(),
      );
      await expectLater(stale.detail(privacyRequest), throwsFormatException);
    },
  );
  test(
    'durable reservation refuses competing tab and stale generation after typed resolution',
    () async {
      final j = PrivacyJournalFixture(), original = privacyIntent();
      await j.store.reserve(original, 0);
      final before = await j.store.read(privacyActor, privacySession);
      expect(before.pending!.fingerprint, original.fingerprint);
      await expectLater(j.store.reserve(original, 0), throwsFormatException);
      final wrong = AdminPrivacyReviewClaim.parse(
        privacyClaimReceipt(operation: privacyClaim),
      );
      await expectLater(
        j.store.complete(original, before.generation, wrong),
        throwsFormatException,
      );
      await j.store.complete(
        original,
        before.generation,
        AdminPrivacyReviewClaim.parse(privacyClaimReceipt()),
      );
      expect(
        (await j.store.read(privacyActor, privacySession)).pending,
        isNull,
      );
      await expectLater(
        j.store.reserve(original, before.generation),
        throwsFormatException,
      );
      final raw = jsonDecode(j.bytes.values.single) as Map;
      expect(raw['pending'], isNull);
      expect(raw.keys, isNot(contains('receipt')));
      expect(j.bytes.values.single, isNot(contains(privacyOperation)));
    },
  );
  test(
    'storage refusal blocks mutation before RPC and permits current reads',
    () async {
      final a = PrivacyApiFake(),
          j = PrivacyJournalFixture(),
          c = controller(a, j);
      addTearDown(c.dispose);
      await c.refresh();
      await c.open(privacyRequest);
      j.failWrite = true;
      await c.startReview();
      expect(a.writes, isEmpty);
      expect(c.pending, isNull);
      expect(c.error, contains('No server action'));
      j.failRead = true;
      await c.refresh();
      expect(c.page, isNotNull);
      expect(c.checkpointReady, isFalse);
      expect(c.canStart, isFalse);
    },
  );
  test(
    'lost reply and controller recreation retain original and unseen never releases it',
    () async {
      final a = PrivacyApiFake()..loseResponse = true,
          j = PrivacyJournalFixture();
      final c = controller(a, j);
      await c.refresh();
      await c.open(privacyRequest);
      await c.startReview();
      final fingerprint = c.pending!.fingerprint;
      c.dispose();
      var allocated = 0;
      final next = controller(
        a,
        j,
        newId: () {
          allocated++;
          return privacyOutcomeOperation;
        },
      );
      addTearDown(next.dispose);
      await next.refresh();
      expect(next.pending!.fingerprint, fingerprint);
      await next.resolve();
      expect(next.pending!.fingerprint, fingerprint);
      expect(next.notice, contains('may still arrive'));
      expect(next.canStart, isFalse);
      a.loseResponse = false;
      await next.retryOriginal();
      expect(a.writes, hasLength(2));
      expect(a.writes.map((i) => i.fingerprint).toSet(), {fingerprint});
      expect(allocated, 0);
      expect(next.pending, isNull);
      expect(next.detail!.claimAuthorityCurrent, isTrue);
    },
  );
  test('disposed or A to B to A owner cannot adopt a late response', () async {
    final a = PrivacyApiFake()..deferredWrite = Completer<Object>(),
        j = PrivacyJournalFixture();
    var live = true;
    final c = controller(a, j, current: () => live);
    await c.refresh();
    await c.open(privacyRequest);
    final write = c.startReview();
    await Future<void>.delayed(Duration.zero);
    live = false;
    c.dispose();
    live = true;
    a.deferredWrite!.complete(a.receipt(a.writes.single));
    await write;
    expect(
      (await j.store.read(privacyActor, privacySession)).pending!.operationId,
      privacyOperation,
    );
  });
  test(
    'current own claim resumes, expired claim blocks outcome and original unknown retry',
    () async {
      final a = PrivacyApiFake()
            ..sample = privacyDetail(state: 'claim_active', owned: true),
          j = PrivacyJournalFixture();
      var now = privacyNow;
      final c = controller(
        a,
        j,
        now: () => now,
        newId: () => privacyOutcomeOperation,
      );
      addTearDown(c.dispose);
      await c.refresh();
      await c.open(privacyRequest);
      expect(c.canRecord, isTrue);
      a.loseResponse = true;
      await c.recordPolicyBlocker();
      expect(c.pending!.kind, AdminPrivacyReviewOperationKind.outcome);
      now = privacyNow.add(const Duration(seconds: 60));
      expect(c.canRetry, isFalse);
      await c.retryOriginal();
      expect(a.writes, hasLength(1));
      expect(
        (await j.store.read(privacyActor, privacySession)).pending!.operationId,
        privacyOutcomeOperation,
      );
    },
  );
  test(
    'verified outcome records only the blocker and clears minimal pending metadata',
    () async {
      final a = PrivacyApiFake()
            ..sample = privacyDetail(state: 'claim_active', owned: true),
          j = PrivacyJournalFixture(),
          c = controller(a, j, newId: () => privacyOutcomeOperation);
      addTearDown(c.dispose);
      await c.refresh();
      await c.open(privacyRequest);
      await c.recordPolicyBlocker();
      expect(c.detail!.item!.state, AdminPrivacyReviewState.blocked);
      expect(c.notice, contains('no data was erased'));
      expect(a.writes.single.parameters, {
        'p_outcome_request_id': privacyOutcomeOperation,
        'p_claim_id': privacyClaim,
        'p_fence': 1,
        'p_outcome_code': 'policy_authority_unavailable',
      });
      expect(
        (await j.store.read(privacyActor, privacySession)).pending,
        isNull,
      );
    },
  );
}
