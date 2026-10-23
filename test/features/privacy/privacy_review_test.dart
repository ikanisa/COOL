import 'dart:async';
import 'dart:convert';

import 'package:collect_app/features/privacy/privacy_contract.dart';
import 'package:collect_app/features/privacy/privacy_review_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'privacy_controller_transport_test.dart' show Harness, fails;
import 'privacy_test_support.dart';

const _rpc = 'get_account_deletion_review_status_v1';
http.Response _json(Object? value, [int status = 200]) =>
    http.Response(jsonEncode(value), status);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final state in const {
    'not_started': PrivacyReviewState.notStarted,
    'awaiting_review': PrivacyReviewState.awaitingReview,
    'claim_active': PrivacyReviewState.claimActive,
    'claim_expired': PrivacyReviewState.claimExpired,
    'blocked': PrivacyReviewState.blocked,
  }.entries) {
    test('strict own review observation accepts ${state.key}', () {
      final parsed = PrivacyReviewStatus.fromJson(
        privacyReviewJson(state: state.key),
      );
      expect(parsed.state, state.value);
      expect(parsed.requestId, privacyCanonical);
      expect(parsed.outcomeRecordedAt != null, state.key == 'blocked');
      expect(parsed.toString(), isNot(contains(privacyCanonical)));
    });
  }
  final contradictions = <String, void Function(Map<String, dynamic>)>{
    'missing field': (j) => j.remove('copy_dispositions_verified'),
    'extra sensitive field': (j) => j['actor_session_id'] = privacyOldSid,
    'wrong scope': (j) => j['scope'] = 'account_privacy_review_only',
    'coerced version': (j) => j['contract_version'] = 1.0,
    'coerced revision': (j) => j['revision'] = '1',
    'negative revision': (j) => j['revision'] = -1,
    'unknown state': (j) => j['review_state'] = 'deleted',
    'invalid UUID': (j) => j['request_id'] = 'not-a-request',
    'non-UTC observation': (j) =>
        j['checked_at'] = '2026-10-03T12:00:00.000000+01:00',
    'overflow date': (j) => j['checked_at'] = '2026-02-30T12:00:00.000000Z',
    'missing blocker outcome': (j) => j['outcome_code'] = null,
    'future outcome': (j) =>
        j['outcome_recorded_at'] = '2026-10-04T12:00:00.000000Z',
    'approved completion': (j) => j['completion'] = 'completed',
    'approved policy': (j) => j['policy_acceptance_granted'] = true,
    'finished subject scope': (j) => j['subject_scope_review_pending'] = false,
    'no hold review': (j) => j['legal_hold_review_pending'] = false,
    'copy verified': (j) => j['copy_dispositions_verified'] = true,
    'destructive capability': (j) =>
        j['destructive_execution_available'] = true,
    'erased': (j) => j['erasure_completed'] = true,
    'access removed': (j) => j['account_access_restricted'] = true,
    'auth removed': (j) => j['auth_removed'] = true,
    'processor started': (j) => j['processor_operation_started'] = true,
  };
  for (final mutation in contradictions.entries) {
    test('refuses contradictory review: ${mutation.key}', () {
      final raw = privacyReviewJson(state: 'blocked');
      mutation.value(raw);
      expect(
        () => PrivacyReviewStatus.fromJson(raw),
        fails(PrivacyFailure.protocolUnavailable),
      );
    });
  }
  test(
    'a non-blocked state cannot carry an outcome or zero active revision',
    () {
      for (final raw in [
        privacyReviewJson(state: 'claim_active', revision: 0),
        privacyReviewJson(state: 'awaiting_review', revision: 1),
        privacyReviewJson(state: 'blocked', revision: 1),
        privacyReviewJson()..['revision'] = 1,
        privacyReviewJson()
          ..['outcome_recorded_at'] = '2026-10-03T11:00:00.000000Z',
        privacyReviewJson()..['outcome_code'] = 'policy_authority_unavailable',
      ]) {
        expect(
          () => PrivacyReviewStatus.fromJson(raw),
          fails(PrivacyFailure.protocolUnavailable),
        );
      }
    },
  );

  test(
    'real HTTP adapter reads canonical review with actual session bearer and keeps intake immutable',
    () async {
      http.Request? observed;
      final h = await Harness.create((r) async {
        if (r.url.path.endsWith('/$_rpc')) {
          observed = r;
          return _json(privacyReviewJson(state: 'blocked'));
        }
        return _json(privacyReceiptJson(requestId: privacyCanonical));
      });
      final receipt = await h.controller.refreshStatus();
      final review = await h.controller.refreshReviewStatus();
      expect(observed!.url.path, '/v1/rpc/$_rpc');
      expect(jsonDecode(observed!.body), {'p_request_id': privacyCanonical});
      expect(
        observed!.headers['Authorization'],
        'Bearer ${h.auth.currentSession!.accessToken}',
      );
      expect(review.state, PrivacyReviewState.blocked);
      expect(h.controller.receipt, same(receipt));
      expect(receipt!.state, 'pending_review');
    },
  );

  for (final failure in ['foreign receipt', 'denial', 'malformed', 'timeout']) {
    test(
      'failed $failure review read preserves confirmed intake without guessed status',
      () async {
        var calls = 0;
        final h = await Harness.create((r) async {
          if (!r.url.path.endsWith('/$_rpc')) {
            return _json(privacyReceiptJson(requestId: privacyCanonical));
          }
          calls++;
          if (calls == 1) {
            return _json(privacyReviewJson(state: 'claim_active'));
          }
          return switch (failure) {
            'foreign receipt' => _json(
              privacyReviewJson(requestId: privacySubmission),
            ),
            'denial' => _json({'message': 'SYNTHETIC_PRIVATE_REASON'}, 403),
            'malformed' => _json(privacyReviewJson()..['auth_removed'] = true),
            _ => Completer<http.Response>().future,
          };
        }, timeout: const Duration(milliseconds: 80));
        final intake = await h.controller.refreshStatus();
        await h.controller.refreshReviewStatus();
        await expectLater(
          h.controller.refreshReviewStatus(),
          throwsA(isA<PrivacyRequestException>()),
        );
        expect(h.controller.reviewStatus, isNull);
        expect(h.controller.receipt, same(intake));
        expect(calls, 2);
        expect(h.controller.outcomeUnknown, isFalse);
      },
    );
  }

  for (final race in ['same-user replacement', 'ABA', 'cancel', 'dispose']) {
    test(
      'late review after $race cannot publish a current observation',
      () async {
        final response = Completer<http.Response>();
        final started = Completer<void>();
        final h = await Harness.create((r) async {
          if (r.url.path.endsWith('/$_rpc')) {
            started.complete();
            return response.future;
          }
          return _json(privacyReceiptJson(requestId: privacyCanonical));
        });
        await h.controller.refreshStatus();
        final reading = h.controller.refreshReviewStatus();
        await started.future;
        if (race == 'same-user replacement') {
          await h.replace(privacySession(sid: privacyNewSid));
        } else if (race == 'ABA') {
          await h.replace(privacySession(subject: privacyOtherSubject));
          await h.replace(privacySession());
        } else if (race == 'cancel') {
          h.controller.cancel();
        } else {
          h.controller.dispose();
        }
        final expectation = expectLater(
          reading,
          fails(
            race == 'cancel' || race == 'dispose'
                ? PrivacyFailure.cancelled
                : PrivacyFailure.sessionChanged,
          ),
        );
        response.complete(_json(privacyReviewJson(state: 'blocked')));
        await expectation;
        expect(h.controller.reviewStatus, isNull);
        if (race != 'dispose') expect(h.controller.receipt, isNotNull);
      },
    );
  }

  test(
    'an earlier review observation is hidden immediately when the same user changes session',
    () async {
      final h = await Harness.create(
        (r) async => r.url.path.endsWith('/$_rpc')
            ? _json(privacyReviewJson(state: 'blocked'))
            : _json(privacyReceiptJson(requestId: privacyCanonical)),
      );
      await h.controller.refreshStatus();
      await h.controller.refreshReviewStatus();
      expect(h.controller.reviewStatus, isNotNull);
      await h.replace(privacySession(sid: privacyNewSid));
      expect(h.controller.reviewStatus, isNull);
      expect(h.controller.receipt, isNotNull);
    },
  );
}
