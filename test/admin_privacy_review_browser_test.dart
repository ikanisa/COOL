@TestOn('browser')
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:collect_app/admin/core/admin_privacy_review_models.dart';
import 'package:collect_app/admin/core/admin_privacy_review_checkpoint.dart';
import 'package:collect_app/admin/core/admin_privacy_review_controller.dart';
import 'support/privacy_review_fixtures.dart';

const _key = 'collect.privacy-review.v1.$privacyActor.$privacySession';
void main() {
  setUp(() => web.window.localStorage.removeItem(_key));
  tearDown(() => web.window.localStorage.removeItem(_key));
  test(
    'actual Chrome localStorage and WebLock preserve only pending command after store recreation',
    () async {
      final first = browserPrivacyReviewStore()!, i = privacyIntent();
      await first.reserve(i, 0);
      final recreated = browserPrivacyReviewStore()!,
          stored = await recreated.read(privacyActor, privacySession);
      expect(stored.pending!.fingerprint, i.fingerprint);
      expect(stored.generation, 1);
      final raw = web.window.localStorage.getItem(_key)!;
      expect(raw, isNot(contains('Authorization')));
      expect(raw, isNot(contains('expires_at')));
      expect(raw, isNot(contains('claim_id')));
      expect(
        (await recreated.read(privacyActor, privacyClaim)).pending,
        isNull,
      );
    },
  );
  test(
    'two real WebLock writers admit one original and stale generation cannot restore cleared metadata',
    () async {
      final a = browserPrivacyReviewStore()!,
          b = browserPrivacyReviewStore()!,
          first = privacyIntent(),
          second = AdminPrivacyReviewIntent.claim(
            operationId: privacyOutcomeOperation,
            actorId: privacyActor,
            sessionId: privacySession,
            detail: privacyDetail(),
          );
      final outcomes = await Future.wait([
        a.reserve(first, 0).then((_) => true, onError: (_) => false),
        b.reserve(second, 0).then((_) => true, onError: (_) => false),
      ]);
      expect(outcomes.where((e) => e), hasLength(1));
      final checkpoint = await a.read(privacyActor, privacySession),
          original = checkpoint.pending!;
      await b.complete(
        original,
        checkpoint.generation,
        AdminPrivacyReviewClaim.parse(
          privacyClaimReceipt(operation: original.operationId),
        ),
      );
      await expectLater(
        a.reserve(original, checkpoint.generation),
        throwsFormatException,
      );
      final cleared = jsonDecode(web.window.localStorage.getItem(_key)!) as Map;
      expect(cleared['pending'], isNull);
      expect(cleared['generation'], 2);
      expect(
        web.window.localStorage.getItem(_key),
        isNot(contains(original.operationId)),
      );
    },
  );
  test(
    'real browser recreation after lost reply performs original lookup and same-ID retry',
    () async {
      final api = PrivacyApiFake()..loseResponse = true;
      AdminPrivacyReviewController make() => AdminPrivacyReviewController(
        api: api,
        actorId: privacyActor,
        sessionId: privacySession,
        store: browserPrivacyReviewStore(),
        now: () => privacyNow,
        isCurrent: () => true,
        newOperationId: () => privacyOperation,
      );
      final first = make();
      await first.refresh();
      await first.open(privacyRequest);
      await first.startReview();
      first.dispose();
      final restarted = make();
      addTearDown(restarted.dispose);
      await restarted.refresh();
      await restarted.resolve();
      expect(restarted.pending!.operationId, privacyOperation);
      expect(api.writes, hasLength(1));
      api.loseResponse = false;
      await restarted.retryOriginal();
      expect(api.writes.map((i) => i.operationId).toSet(), {privacyOperation});
      expect(api.writes, hasLength(2));
      expect(
        (await browserPrivacyReviewStore()!.read(
          privacyActor,
          privacySession,
        )).pending,
        isNull,
      );
    },
  );
  test(
    'corrupt real browser journal refuses reads and preserves original bytes',
    () async {
      const bytes = '{"version":1,"generation":0,"actor_id":"PRIVATE"}';
      web.window.localStorage.setItem(_key, bytes);
      await expectLater(
        browserPrivacyReviewStore()!.read(privacyActor, privacySession),
        throwsFormatException,
      );
      await expectLater(
        browserPrivacyReviewStore()!.reserve(privacyIntent(), 0),
        throwsFormatException,
      );
      expect(web.window.localStorage.getItem(_key), bytes);
    },
  );
}
