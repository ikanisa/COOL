import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_reconciliation_step_up.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actorA = '99920000-0000-4000-8000-000000000001';
const actorB = '99920000-0000-4000-8000-000000000002';
const paymentId = '99920000-0000-4000-8000-000000000003';
const reviewId = '99920000-0000-4000-8000-000000000004';

Map<String, dynamic> review({
  int index = 4,
  String status = 'proposed',
  String proposer = actorA,
  String? approver,
}) => {
  'id': '99920000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
  'payment_id': paymentId,
  'status': status,
  'source_reference': 'STATEMENT-$index',
  'evidence_sha256': 'a' * 64,
  'occurred_at': '2026-09-30T08:00:00Z',
  'proposed_at': '2026-09-30T08:00:00Z',
  'proposed_by': proposer,
  'approved_by': approver,
  'approved_at': approver == null ? null : '2026-09-30T08:10:00Z',
  'amount_rwf': 2500,
  'currency': 'RWF',
};

Map<String, dynamic> finalization({
  String status = 'posted',
  bool replayed = false,
}) => {
  'review_id': reviewId,
  'payment_id': paymentId,
  'payment_status': status,
  'replayed': replayed,
  'evidence_level': 'independently_reconciled',
};

Map<String, dynamic> lineage() => {
  ...review(),
  'audit': <Map<String, dynamic>>[],
  'journals': <Map<String, dynamic>>[],
  'receiver_routes': <Map<String, dynamic>>[],
};

Future<void> installSession(
  SupabaseClient client, {
  String actor = actorA,
  String session = 'session-a',
}) => client.auth.recoverSession(
  jsonEncode({
    'access_token':
        'e30.${base64Url.encode(utf8.encode(jsonEncode({'sub': actor, 'session_id': session, 'aal': 'aal2', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.synthetic',
    'refresh_token': 'synthetic-refresh',
    'token_type': 'bearer',
    'user': {
      'id': actor,
      'aud': 'authenticated',
      'app_metadata': {},
      'user_metadata': {},
      'created_at': '2026-09-30T00:00:00Z',
    },
  }),
);

void main() {
  late SupabaseClient client;
  late AdminRepository repository;
  late Future<http.Response> Function(http.Request) respond;
  late List<http.Request> requests;
  http.Response json(Object? body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
  setUp(() async {
    requests = [];
    respond = (_) async => json(finalization());
    client = SupabaseClient(
      'https://synthetic.invalid',
      'synthetic-publishable',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) {
        requests.add(request);
        return respond(request).then(
          (response) => http.Response.bytes(
            response.bodyBytes,
            response.statusCode,
            headers: response.headers,
            request: request,
          ),
        );
      }),
    );
    await installSession(client);
    repository = AdminRepository(client);
  });
  tearDown(() => client.dispose());

  for (final (status, replay) in [
    ('posted', false),
    ('posted', true),
    ('reversed', true),
  ]) {
    test('validates $status acknowledgment replay=$replay', () async {
      respond = (_) async =>
          json(finalization(status: status, replayed: replay));
      final result = await repository.finalizePaymentReconciliation(
        reviewId,
        paymentId: paymentId,
      );
      expect(result.paymentStatus, status);
      expect(result.replayed, replay);
      expect(requests.single.url.path, '/functions/v1/reconciliation-finalize');
      expect(jsonDecode(requests.single.body), {'review_id': reviewId});
      if (status == 'reversed') {
        expect(result.message, contains('later reversed'));
      }
    });
  }
  for (final (key, value) in <(String, Object?)>[
    ('review_id', actorB),
    ('review_id', null),
    ('payment_id', actorB),
    ('payment_id', 'invalid'),
    ('replayed', 'false'),
    ('replayed', null),
    ('payment_status', 'review'),
    ('evidence_level', 'sms'),
    ('evidence_level', null),
  ]) {
    test('rejects malformed finality $key=$value', () async {
      respond = (_) async => json({...finalization(), key: value});
      await expectLater(
        repository.finalizePaymentReconciliation(
          reviewId,
          paymentId: paymentId,
        ),
        throwsFormatException,
      );
    });
  }
  test('reversed acknowledgment must be an exact replay', () async {
    respond = (_) async => json(finalization(status: 'reversed'));
    await expectLater(
      repository.finalizePaymentReconciliation(reviewId, paymentId: paymentId),
      throwsFormatException,
    );
  });
  test('finalization rejects fields outside the exact Edge receipt', () async {
    respond = (_) async => json({
      ...finalization(),
      'unexpected_sensitive_context': 'synthetic-only',
    });
    await expectLater(
      repository.finalizePaymentReconciliation(reviewId, paymentId: paymentId),
      throwsFormatException,
    );
    expect(requests, hasLength(1));
  });
  test('denial never invokes a fallback endpoint', () async {
    respond = (_) async =>
        json({'error': 'reconciliation_approver_required'}, 403);
    await expectLater(
      repository.finalizePaymentReconciliation(reviewId, paymentId: paymentId),
      throwsA(isA<FunctionException>()),
    );
    expect(requests, hasLength(1));
  });
  test('invalid input IDs fail before network calls', () async {
    await expectLater(
      repository.finalizePaymentReconciliation('bad', paymentId: paymentId),
      throwsFormatException,
    );
    await expectLater(
      repository.paymentReconciliationReviews('bad'),
      throwsFormatException,
    );
    await expectLater(
      repository.paymentReconciliationDetail(reviewId, paymentId: 'bad'),
      throwsFormatException,
    );
    expect(requests, isEmpty);
  });
  test('review pages preserve exact filter and offset', () async {
    respond = (_) async => json({
      'rows': [review()],
      'total': 26,
    });
    final page = await repository.paymentReconciliationReviews(
      paymentId,
      offset: 25,
    );
    expect(page.rows.single.id, reviewId);
    expect(jsonDecode(requests.single.body), {
      'p_payment_id': paymentId,
      'p_limit': 25,
      'p_offset': 25,
    });
  });
  test('all-review history sends null payment filter', () async {
    respond = (_) async => json({'rows': [], 'total': 0});
    await repository.paymentReconciliationReviews(null);
    expect(jsonDecode(requests.single.body)['p_payment_id'], isNull);
  });
  for (final defect in [
    'wrong payment',
    'unknown status',
    'truncated',
    'duplicate',
    'missing total',
  ]) {
    test('rejects $defect review page', () async {
      final row = review();
      if (defect == 'wrong payment') row['payment_id'] = actorB;
      if (defect == 'unknown status') row['status'] = 'trusted';
      respond = (_) async => json({
        'rows': [row, if (defect == 'duplicate') row],
        if (defect != 'missing total')
          'total': ['truncated', 'duplicate'].contains(defect) ? 2 : 1,
      });
      await expectLater(
        repository.paymentReconciliationReviews(paymentId),
        throwsFormatException,
      );
    });
  }
  for (final defect in ['payment_id', 'id', 'proposed_session_id', 'audit']) {
    test('rejects invalid or leaked lineage $defect', () async {
      respond = (_) async =>
          json({...lineage(), defect: defect == 'audit' ? 'invalid' : actorB});
      await expectLater(
        repository.paymentReconciliationDetail(reviewId, paymentId: paymentId),
        throwsFormatException,
      );
    });
  }
  for (final operation in [
    'reviews',
    'detail',
    'proposal',
    'approval',
    'finalization',
  ]) {
    for (final sameUser in [false, true]) {
      test(
        '$operation cannot publish after ${sameUser ? 'same-user session' : 'account'} change',
        () async {
          final gate = Completer<http.Response>();
          final started = Completer<void>();
          respond = (_) {
            started.complete();
            return gate.future;
          };
          final Future<dynamic> pending = switch (operation) {
            'reviews' => repository.paymentReconciliationReviews(paymentId),
            'detail' => repository.paymentReconciliationDetail(
              reviewId,
              paymentId: paymentId,
            ),
            'proposal' => repository.proposePaymentReconciliation({
              'p_payment_id': paymentId,
            }),
            'approval' => repository.approvePaymentReconciliation(
              reviewId,
              'Independent source checked.',
            ),
            _ => repository.finalizePaymentReconciliation(
              reviewId,
              paymentId: paymentId,
            ),
          };
          final failure = expectLater(
            pending,
            throwsA(
              isA<AdminReconciliationStepUpException>().having(
                (e) => e.code,
                'code',
                'session_changed',
              ),
            ),
          );
          await started.future;
          await installSession(
            client,
            actor: sameUser ? actorA : actorB,
            session: 'session-b',
          );
          gate.complete(
            json(switch (operation) {
              'reviews' => {
                'rows': [review()],
                'total': 1,
              },
              'detail' => lineage(),
              'proposal' => reviewId,
              'approval' => true,
              _ => finalization(),
            }),
          );
          await failure;
          expect(client.auth.currentUser!.id, sameUser ? actorA : actorB);
        },
      );
    }
  }
}
