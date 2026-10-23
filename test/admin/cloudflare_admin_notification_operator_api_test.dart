import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_notification_operator_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/app/env/app_env.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/legacy_backend_fixture.dart';

const _supabaseOperatorEnvironment = AppEnv(
  apiUrl: '',
  publicUrl: '',
  adminAppUrl: '',
  enableSmsReader: false,
  enableAndroidSmsAccess: true,
  enableAdminPanel: false,
  enableAdminDevTools: false,
  authCaptchaEnabled: false,
  authCaptchaProvider: '',
  authCaptchaSiteKey: '',
  backend: 'supabase',
  supabaseUrl: 'https://operator-fixture.supabase.co',
  supabaseApiUrl: 'https://admin.example.test',
  supabaseAdminApiUrl: 'https://admin.example.test',
  supabasePublishableKey: 'sb_publishable_synthetic_operator_test_only',
);

const actor = '10000000-0000-4000-8000-000000000001',
    principal = '10000000-0000-4000-8000-000000000002',
    publicSession = '10000000-0000-4000-8000-000000000003',
    canonicalSession = '10000000-0000-4000-8000-000000000004',
    jobId = '10000000-0000-4000-8000-000000000005',
    paymentId = '10000000-0000-4000-8000-000000000006',
    claimToken = '10000000-0000-4000-8000-000000000007',
    confirmationId = '10000000-0000-4000-8000-000000000008',
    attemptId = '10000000-0000-4000-8000-000000000009',
    requestId = '10000000-0000-4000-8000-000000000010',
    otherId = '10000000-0000-4000-8000-000000000011',
    phone = '+250788123456',
    message = 'Collect record: RWF 2000. Provider confirmation not asserted.';

Map<String, dynamic> marker() => {
  'contract_version': 1,
  'scope': 'assisted_sms_internal_record',
  'delivery_confirmed': false,
  'provider_confirmation': false,
  'settlement_status': 'not_asserted',
};
String digest(String text) => sha256.convert(utf8.encode(text)).toString();
http.Response response(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

class Fixture {
  Fixture({this.useSupabase = false}) {
    session = CloudflareAdminSession(
      MockClient((request) async {
        if (request.url.path == '${prefix}auth/session') {
          return response({
            'user': {
              'id': actor,
              'email': 'operator@example.test',
              'role': 'owner',
              'sessionId': currentPublicSession,
              'principalId': principal,
              'permissions': permissions,
              'assuranceLevel': assurance,
              if (assurance == 2) 'mfaAt': mfaAt.toIso8601String(),
              if (useSupabase && assurance == 1) 'mfaAt': null,
              'financialModel': 'canonical_evidence_ledger',
            },
            'expiresAt': now.add(const Duration(hours: 1)).toIso8601String(),
            if (useSupabase) 'csrfToken': 'a' * 64,
          });
        }
        if (useSupabase &&
            request.url.path == '${prefix}auth/email-verification') {
          sidecarReads++;
          expect(request.method, 'GET');
          return response({
            'contractVersion': 1,
            'sessionId': sidecarSessionId ?? currentPublicSession,
            'emailVerifiedAt': emailVerifiedAt?.toUtc().toIso8601String(),
          });
        }
        requests.add(request);
        expect(request.url.path, '${prefix}notification-operator');
        expect(request.method, 'POST');
        expect(request.headers['X-Collect-Admin'], '1');
        if (useSupabase) {
          expect(request.headers['X-Collect-CSRF'], 'a' * 64);
          expect(request.headers.containsKey('Authorization'), isFalse);
        }
        final body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        if (handler != null) return handler!(body);
        return response({'ok': true, 'result': result(body)});
      }),
      origin: Uri.parse('https://admin.example.test/'),
      environment: useSupabase
          ? _supabaseOperatorEnvironment
          : legacyBackendFixtureEnvironment,
    );
  }
  factory Fixture.supabase({Duration? proofAge = Duration.zero}) {
    final fixture = Fixture(useSupabase: true)..assurance = 1;
    fixture.emailVerifiedAt = proofAge == null
        ? null
        : fixture.now.subtract(proofAge);
    return fixture;
  }
  final bool useSupabase;
  String get prefix =>
      useSupabase ? '/functions/v1/admin-api/api/admin/' : '/api/admin/';
  DateTime? emailVerifiedAt;
  String? sidecarSessionId;
  int sidecarReads = 0;
  final DateTime now = DateTime.fromMillisecondsSinceEpoch(
    (DateTime.now().millisecondsSinceEpoch ~/ 1000) * 1000,
    isUtc: true,
  );
  late DateTime clock = now;
  late DateTime mfaAt = now;
  int assurance = 2;
  String currentPublicSession = publicSession;
  List<String> permissions = ['assisted_sms.read', 'assisted_sms.manage'];
  final requests = <http.Request>[];
  Future<http.Response> Function(Map<String, dynamic>)? handler;
  late final CloudflareAdminSession session;
  late CloudflareAdminNotificationOperatorApi api;
  String get expires =>
      now.add(const Duration(seconds: 90)).toUtc().toIso8601String();
  Future<void> open() async {
    await session.refresh();
    api = CloudflareAdminNotificationOperatorApi(session, now: () => clock);
  }

  Map<String, dynamic> pendingItem({
    String id = jobId,
    String state = 'queued',
    int fence = 0,
  }) => {
    'id': id,
    'payment_id': paymentId,
    'state': state,
    'created_at': '2026-10-15T10:00:00.000Z',
    'fence': fence,
    'attempt_id': state == 'send_started' || state == 'uncertain'
        ? attemptId
        : null,
  };
  Map<String, dynamic> claimReceipt() => {
    ...marker(),
    'job_id': jobId,
    'claim_token': claimToken,
    'fence_version': 1,
    'worker_id': 'operator.tab',
    'claim_expires_at': expires,
    'originating_session_id': canonicalSession,
    'public_session_id': publicSession,
  };
  Map<String, dynamic> content() => {
    ...marker(),
    'job_id': jobId,
    'claim_token': claimToken,
    'fence_version': 1,
    'destination_e164': phone,
    'destination_sha256': digest(phone),
    'destination_revision': 1,
    'message_body': message,
    'body_sha256': digest(message),
    'payment_id': paymentId,
    'template_key': 'collect.recorded_contribution.v1',
    'claim_expires_at': expires,
  };
  Map<String, dynamic> confirmation(Map<String, dynamic> body) => {
    ...marker(),
    'job_id': jobId,
    'confirmation_id': body['confirmation_id'],
    'claim_token': claimToken,
    'fence_version': 1,
    'body_sha256': digest(message),
    'destination_sha256': digest(phone),
    'destination_revision': 1,
    'expires_at': expires,
    'originating_session_id': canonicalSession,
    'public_session_id': publicSession,
  };
  Map<String, dynamic> startReceipt({
    bool acknowledgement = true,
    bool replay = false,
  }) => {
    ...marker(),
    'attempt_id': attemptId,
    'job_id': jobId,
    'confirmation_id': confirmationId,
    'claim_token': claimToken,
    'fence_version': 1,
    'state': 'send_started',
    'originating_session_id': canonicalSession,
    'public_session_id': publicSession,
    if (acknowledgement) ...{
      'replay': replay,
      'may_send': !replay,
      'acknowledgement': replay
          ? 'recorded_start_permit_not_reissued'
          : 'first_committed_response_only',
    },
  };
  Map<String, dynamic> result(Map<String, dynamic> body) =>
      switch (body['action']) {
        'list_pending' => {
          ...marker(),
          'items': [pendingItem()],
          'next_cursor': null,
        },
        'claim' => claimReceipt(),
        'get_claimed' => content(),
        'confirm' => confirmation(body),
        'record_send_start' => startReceipt(),
        'release_claim' => {
          ...marker(),
          'job_id': jobId,
          'state': 'queued',
          'fence_version': 2,
        },
        'record_outcome' => {
          ...marker(),
          'attempt_id': body['attempt_id'],
          'observation': body['observation'],
          'evidence_reference_sha256': body['evidence_reference_sha256'],
          'may_send': false,
        },
        'get_operation' => {
          ...marker(),
          'request_id': body['request_id'],
          'observed': true,
          'receipt': startReceipt(acknowledgement: false),
          'may_send': false,
        },
        _ => throw StateError('Unexpected action'),
      };
  Future<NotificationOperatorClaim> claimed() async {
    final jobs = await api.listPending();
    return api.claim(
      api.prepareClaim(jobs.items.single, workerId: 'operator.tab'),
    );
  }

  Future<NotificationOperatorConfirmation> confirmed() async {
    final content = await api.getClaimed(await claimed());
    return api.confirm(
      api.prepareConfirm(
        content,
        userConfirmation: true,
        confirmationId: confirmationId,
      ),
    );
  }

  void dispose() => session.dispose();
}

void main() {
  late Fixture fixture;
  setUp(() async {
    fixture = Fixture();
    await fixture.open();
  });
  tearDown(() => fixture.dispose());

  test(
    'Supabase email proof admits real AAL1 without changing command bodies',
    () async {
      final fresh = Fixture.supabase(proofAge: const Duration(seconds: 20));
      try {
        await fresh.open();
        expect(fresh.sidecarReads, greaterThan(0));
        expect(fresh.session.user!.assuranceLevel, 1);
        expect(fresh.session.user!.mfaAt, isNull);
        expect(fresh.session.user!.sessionId, publicSession);
        expect(fresh.api.canRead, isTrue);
        expect(fresh.api.canManage, isTrue);
        final confirmation = await fresh.confirmed();
        final original = fresh.api.prepareSendStart(
          confirmation,
          requestId: requestId,
        );
        final start = await fresh.api.recordSendStart(original);
        expect(original.requestId, requestId);
        expect(start.publicSessionId, publicSession);
        expect(start.originatingSessionId, canonicalSession);
        expect(start.permit!.consume(), isTrue);
        expect(start.permit!.consume(), isFalse);
        for (final request in fresh.requests) {
          final body = jsonDecode(request.body) as Map;
          expect(body.containsKey('emailVerifiedAt'), isFalse);
          expect(body.containsKey('usesEmailVerification'), isFalse);
        }
      } finally {
        fresh.dispose();
      }
    },
  );

  test(
    'Supabase absent, stale, future or wrong-session proof cannot dispatch',
    () async {
      for (final age in <Duration?>[
        null,
        const Duration(minutes: 6),
        const Duration(minutes: -1),
      ]) {
        final fresh = Fixture.supabase(proofAge: age);
        try {
          await fresh.open();
          expect(fresh.api.canRead, isFalse);
          expect(fresh.api.canManage, isFalse);
          await expectLater(
            fresh.api.listPending(),
            throwsA(isA<AdminAccountException>()),
          );
          expect(fresh.requests, isEmpty);
        } finally {
          fresh.dispose();
        }
      }
      final wrongSession = Fixture.supabase()..sidecarSessionId = otherId;
      try {
        await wrongSession.open();
        expect(wrongSession.api.canRead, isFalse);
        expect(wrongSession.requests, isEmpty);
      } finally {
        wrongSession.dispose();
      }
    },
  );

  test(
    'Supabase proof preserves exact read grants and expires before transport',
    () async {
      final fresh = Fixture.supabase()..permissions = ['assisted_sms.read'];
      try {
        await fresh.open();
        expect(fresh.api.canRead, isTrue);
        expect(fresh.api.canManage, isFalse);
        final jobs = await fresh.api.listPending();
        expect(
          () => fresh.api.prepareClaim(
            jobs.items.single,
            workerId: 'operator.tab',
          ),
          throwsA(isA<AdminAccountException>()),
        );
        final count = fresh.requests.length;
        fresh.clock = fresh.now.add(const Duration(minutes: 6));
        await expectLater(
          fresh.api.listPending(),
          throwsA(isA<AdminAccountException>()),
        );
        expect(fresh.requests, hasLength(count));
      } finally {
        fresh.dispose();
      }
      final generic = Fixture.supabase()
        ..permissions = ['notifications.read', 'notifications.manage'];
      try {
        await generic.open();
        expect(generic.api.canRead, isFalse);
        expect(generic.api.canManage, isFalse);
        expect(generic.requests, isEmpty);
      } finally {
        generic.dispose();
      }
    },
  );

  test(
    'same-session proof renewal retains originals but cannot extend confirmation',
    () async {
      final fresh = Fixture.supabase(proofAge: const Duration(minutes: 4));
      try {
        await fresh.open();
        final confirmation = await fresh.confirmed();
        final authority = fresh.session.authorityFence;
        fresh.emailVerifiedAt = fresh.now;
        await fresh.session.refresh();
        expect(fresh.session.authorityFence, authority);
        expect(fresh.session.user!.sessionId, publicSession);
        expect(fresh.session.user!.assuranceLevel, 1);
        expect(fresh.session.user!.mfaAt, isNull);
        expect(fresh.api.authorityCurrent, isTrue);
        final original = fresh.api.prepareSendStart(
          confirmation,
          requestId: requestId,
        );
        expect(original.requestId, requestId);
        fresh.clock = fresh.now.add(const Duration(seconds: 91));
        expect(fresh.api.canManage, isTrue);
        await expectLater(
          fresh.api.recordSendStart(original),
          throwsA(isA<AdminAccountException>()),
        );
        expect(original.dispatched, isFalse);
        expect(
          fresh.requests.where(
            (r) => (jsonDecode(r.body) as Map)['action'] == 'record_send_start',
          ),
          isEmpty,
        );
      } finally {
        fresh.dispose();
      }
    },
  );

  test(
    'Supabase proof loss during dispatch retains unknown original without replay',
    () async {
      final fresh = Fixture.supabase();
      try {
        await fresh.open();
        final job = (await fresh.api.listPending()).items.single;
        final original = fresh.api.prepareClaim(
          job,
          workerId: 'operator.tab',
          requestId: requestId,
        );
        final reply = Completer<http.Response>();
        final entered = Completer<void>();
        fresh.handler = (_) {
          entered.complete();
          return reply.future;
        };
        final result = fresh.api.claim(original);
        final failure = expectLater(
          result,
          throwsA(
            isA<NotificationOperatorRequestException>()
                .having(
                  (e) => e.operation.requestId,
                  'original UUID',
                  requestId,
                )
                .having((e) => e.outcomeUnknown, 'unknown result', isTrue),
          ),
        );
        await entered.future;
        fresh.emailVerifiedAt = fresh.now.subtract(const Duration(minutes: 6));
        await fresh.session.refresh();
        reply.complete(response({'ok': true, 'result': fresh.claimReceipt()}));
        await failure;
        expect(original.dispatched, isTrue);
        await expectLater(
          fresh.api.claim(original),
          throwsA(isA<AdminAccountException>()),
        );
        expect(
          fresh.requests.where(
            (r) => (jsonDecode(r.body) as Map)['action'] == 'claim',
          ),
          hasLength(1),
        );
      } finally {
        fresh.dispose();
      }
    },
  );

  test(
    'Supabase fresh proof in a new public session cannot adopt an old claim',
    () async {
      final fresh = Fixture.supabase();
      try {
        await fresh.open();
        final claim = await fresh.claimed();
        fresh.currentPublicSession = otherId;
        await fresh.session.refresh();
        expect(fresh.session.user!.sessionId, otherId);
        expect(fresh.api.authorityCurrent, isFalse);
        final replacement = CloudflareAdminNotificationOperatorApi(
          fresh.session,
        );
        expect(replacement.canManage, isTrue);
        await expectLater(
          replacement.getClaimed(claim),
          throwsA(isA<AdminAccountException>()),
        );
        expect(
          fresh.requests.where(
            (r) => (jsonDecode(r.body) as Map)['action'] == 'get_claimed',
          ),
          isEmpty,
        );
      } finally {
        fresh.dispose();
      }
    },
  );

  test(
    'generic notification grants cannot read or operate assisted SMS',
    () async {
      fixture.permissions = ['notifications.read', 'notifications.manage'];
      await fixture.session.refresh();
      final api = CloudflareAdminNotificationOperatorApi(fixture.session);
      expect(api.canRead, isFalse);
      expect(api.canManage, isFalse);
      final before = fixture.requests.length;
      await expectLater(
        api.listPending(),
        throwsA(isA<AdminAccountException>()),
      );
      await expectLater(
        api.getOperation(requestId),
        throwsA(isA<AdminAccountException>()),
      );
      expect(
        () => api.prepareOutcome(
          attemptId: attemptId,
          observation: NotificationOperatorObservation.uncertain,
          evidenceReferenceSha256: 'b' * 64,
        ),
        throwsA(isA<AdminAccountException>()),
      );
      expect(fixture.requests, hasLength(before));
    },
  );

  test(
    'eight exact action bodies preserve original ids and exact content',
    () async {
      final claim = await fixture.claimed();
      final content = await fixture.api.getClaimed(claim);
      final confirmation = await fixture.api.confirm(
        fixture.api.prepareConfirm(
          content,
          userConfirmation: true,
          confirmationId: confirmationId,
        ),
      );
      final op = fixture.api.prepareSendStart(
        confirmation,
        requestId: requestId,
      );
      final started = await fixture.api.recordSendStart(op);
      expect(started.permit!.consume(), isTrue);
      expect(started.permit!.consume(), isFalse);
      expect(op.dispatched, isTrue);
      final outcome = await fixture.api.recordOutcome(
        fixture.api.prepareOutcome(
          attemptId: started.attemptId,
          observation: NotificationOperatorObservation.uncertain,
          evidenceReferenceSha256: 'b' * 64,
        ),
      );
      expect(outcome.observation, NotificationOperatorObservation.uncertain);
      final resolution = await fixture.api.getOperation(
        requestId,
        originalOperation: op,
      );
      expect(
        (resolution.receipt as NotificationOperatorSendStart).permit,
        isNull,
      );
      await fixture.api.releaseClaim(fixture.api.prepareRelease(claim));
      final bodies = fixture.requests
          .map((r) => jsonDecode(r.body) as Map)
          .toList();
      expect(bodies.map((body) => body['action']).toList(), [
        'list_pending',
        'claim',
        'get_claimed',
        'confirm',
        'record_send_start',
        'record_outcome',
        'get_operation',
        'release_claim',
      ]);
      expect(bodies[4], {
        'action': 'record_send_start',
        'job_id': jobId,
        'claim_token': claimToken,
        'fence_version': 1,
        'confirmation_id': confirmationId,
        'request_id': requestId,
      });
      expect(bodies[3]['body_sha256'], digest(message));
      expect(bodies[3]['destination_sha256'], digest(phone));
      expect(bodies[3]['user_confirmation'], isTrue);
    },
  );

  test(
    'no automatic retry and unknown result keeps the exact original operation',
    () async {
      final confirmation = await fixture.confirmed();
      final op = fixture.api.prepareSendStart(
        confirmation,
        requestId: requestId,
      );
      fixture.handler = (body) async =>
          throw http.ClientException('lost response');
      await expectLater(
        fixture.api.recordSendStart(op),
        throwsA(
          isA<NotificationOperatorRequestException>()
              .having(
                (e) => identical(e.operation, op),
                'original operation',
                isTrue,
              )
              .having((e) => e.operation.requestId, 'original key', requestId)
              .having((e) => e.outcomeUnknown, 'unknown', isTrue),
        ),
      );
      expect(
        fixture.requests.where(
          (r) => (jsonDecode(r.body) as Map)['action'] == 'record_send_start',
        ),
        hasLength(1),
      );
      await expectLater(fixture.api.recordSendStart(op), throwsStateError);
      expect(
        () => fixture.api.prepareSendStart(confirmation, requestId: requestId),
        throwsStateError,
      );
      final another = fixture.api.prepareSendStart(confirmation);
      await expectLater(fixture.api.recordSendStart(another), throwsStateError);
      fixture.handler = null;
      final resolved = await fixture.api.getOperation(
        requestId,
        originalOperation: op,
      );
      expect(resolved.observed, isTrue);
      expect(
        (resolved.receipt as NotificationOperatorSendStart).permit,
        isNull,
      );
    },
  );

  test('replayed start never produces a permit', () async {
    final confirmation = await fixture.confirmed();
    fixture.handler = (body) async =>
        response({'ok': true, 'result': fixture.startReceipt(replay: true)});
    final start = await fixture.api.recordSendStart(
      fixture.api.prepareSendStart(confirmation),
    );
    expect(start.replay, isTrue);
    expect(start.permit, isNull);
  });

  test(
    'permit cannot survive original authority departure and same-user return',
    () async {
      final start = await fixture.api.recordSendStart(
        fixture.api.prepareSendStart(await fixture.confirmed()),
      );
      expect(start.permit!.isUsable, isTrue);
      fixture.session.clear();
      await fixture.session.refresh();
      expect(fixture.api.authorityCurrent, isFalse);
      expect(start.permit!.consume(), isFalse);
      expect(start.permit!.consume(), isFalse);
    },
  );

  test(
    'permit expires and a fresh same-user sign-in cannot adopt old claims',
    () async {
      final claim = await fixture.claimed();
      final content = await fixture.api.getClaimed(claim);
      final confirmation = await fixture.api.confirm(
        fixture.api.prepareConfirm(
          content,
          userConfirmation: true,
          confirmationId: confirmationId,
        ),
      );
      final start = await fixture.api.recordSendStart(
        fixture.api.prepareSendStart(confirmation),
      );
      fixture.clock = fixture.now.add(const Duration(seconds: 91));
      expect(start.permit!.consume(), isFalse);
      fixture.currentPublicSession = otherId;
      await fixture.session.refresh();
      final fresh = CloudflareAdminNotificationOperatorApi(fixture.session);
      await expectLater(
        fresh.getClaimed(claim),
        throwsA(isA<AdminAccountException>()),
      );
    },
  );

  test('inflight session change cannot expose a permit', () async {
    final confirmation = await fixture.confirmed();
    final reply = Completer<http.Response>();
    fixture.handler = (_) => reply.future;
    final future = fixture.api.recordSendStart(
      fixture.api.prepareSendStart(confirmation),
    );
    await Future<void>.delayed(Duration.zero);
    fixture.session.clear();
    reply.complete(response({'ok': true, 'result': fixture.startReceipt()}));
    await expectLater(
      future,
      throwsA(
        isA<NotificationOperatorRequestException>().having(
          (e) => e.outcomeUnknown,
          'unknown',
          isTrue,
        ),
      ),
    );
  });

  test(
    'all actions require fresh AAL2; read permission grants only listing',
    () async {
      fixture.assurance = 1;
      await fixture.session.refresh();
      var api = CloudflareAdminNotificationOperatorApi(fixture.session);
      expect(api.canRead, isFalse);
      await expectLater(
        api.listPending(),
        throwsA(isA<AdminAccountException>()),
      );
      fixture.assurance = 2;
      fixture.permissions = ['assisted_sms.read'];
      await fixture.session.refresh();
      api = CloudflareAdminNotificationOperatorApi(fixture.session);
      expect(api.canRead, isTrue);
      expect(api.canManage, isFalse);
      final jobs = await api.listPending();
      expect(
        () => api.prepareClaim(jobs.items.single, workerId: 'operator.tab'),
        throwsA(isA<AdminAccountException>()),
      );
      await expectLater(
        api.getOperation(requestId),
        throwsA(isA<AdminAccountException>()),
      );
      fixture.clock = fixture.now.add(const Duration(minutes: 6));
      api = CloudflareAdminNotificationOperatorApi(
        fixture.session,
        now: () => fixture.clock,
      );
      expect(api.canRead, isFalse);
    },
  );

  test(
    'plaintext must match both exact content digests and current claim',
    () async {
      final claim = await fixture.claimed();
      for (final patch in <Map<String, dynamic>>[
        {'message_body': '$message changed'},
        {'destination_e164': '+250788111111'},
        {'claim_token': otherId},
        {'fence_version': 2},
        {'template_key': 'unapproved'},
        {'delivery_confirmed': true},
        {'unexpected': true},
      ]) {
        fixture.handler = (_) async => response({
          'ok': true,
          'result': {...fixture.content(), ...patch},
        });
        await expectLater(fixture.api.getClaimed(claim), throwsFormatException);
      }
    },
  );

  test(
    'confirmation rejects changed session/digest and requires explicit assent',
    () async {
      final content = await fixture.api.getClaimed(await fixture.claimed());
      expect(
        () => fixture.api.prepareConfirm(content, userConfirmation: false),
        throwsArgumentError,
      );
      for (final patch in <Map<String, dynamic>>[
        {'body_sha256': 'c' * 64},
        {'destination_revision': 2},
        {'public_session_id': otherId},
        {'originating_session_id': otherId},
      ]) {
        fixture.handler = (body) async => response({
          'ok': true,
          'result': {...fixture.confirmation(body), ...patch},
        });
        await expectLater(
          fixture.api.confirm(
            fixture.api.prepareConfirm(content, userConfirmation: true),
          ),
          throwsA(
            isA<NotificationOperatorRequestException>().having(
              (e) => e.outcomeUnknown,
              'unknown',
              isTrue,
            ),
          ),
        );
      }
    },
  );

  test('only exact first acknowledgment can construct a permit', () async {
    for (final patch in <Map<String, dynamic>>[
      {'replay': true},
      {'acknowledgement': 'recorded_start_permit_not_reissued'},
      {'confirmation_id': otherId},
      {'public_session_id': otherId},
      {'delivery_confirmed': true},
      {'provider_confirmation': true},
    ]) {
      final fresh = Fixture();
      await fresh.open();
      try {
        final confirmation = await fresh.confirmed();
        fresh.handler = (_) async => response({
          'ok': true,
          'result': {...fresh.startReceipt(), ...patch},
        });
        await expectLater(
          fresh.api.recordSendStart(fresh.api.prepareSendStart(confirmation)),
          throwsA(isA<NotificationOperatorRequestException>()),
        );
      } finally {
        fresh.dispose();
      }
    }
  });

  test(
    'nil, invalid version and invalid variant attempt IDs cannot mint a permit',
    () async {
      for (final invalidId in [
        '00000000-0000-0000-0000-000000000000',
        '10000000-0000-0000-8000-000000000009',
        '10000000-0000-9000-8000-000000000009',
        '10000000-0000-4000-7000-000000000009',
      ]) {
        final fresh = Fixture();
        await fresh.open();
        try {
          final confirmation = await fresh.confirmed();
          final operation = fresh.api.prepareSendStart(
            confirmation,
            requestId: requestId,
          );
          fresh.handler = (_) async => response({
            'ok': true,
            'result': {...fresh.startReceipt(), 'attempt_id': invalidId},
          });
          await expectLater(
            fresh.api.recordSendStart(operation),
            throwsA(
              isA<NotificationOperatorRequestException>()
                  .having(
                    (error) => identical(error.operation, operation),
                    'original operation',
                    isTrue,
                  )
                  .having(
                    (error) => error.outcomeUnknown,
                    'no valid acknowledgment',
                    isTrue,
                  ),
            ),
          );
          await expectLater(
            fresh.api.recordSendStart(operation),
            throwsStateError,
          );
          expect(
            () => fresh.api.prepareOutcome(
              attemptId: invalidId,
              observation: NotificationOperatorObservation.uncertain,
              evidenceReferenceSha256: 'b' * 64,
            ),
            throwsFormatException,
          );
          expect(
            fresh.requests.where(
              (request) =>
                  (jsonDecode(request.body) as Map)['action'] ==
                  'record_send_start',
            ),
            hasLength(1),
          );
        } finally {
          fresh.dispose();
        }
      }
    },
  );

  test('valid mixed-case UUIDs normalize with the backend semantics', () async {
    const mixedRequest = 'A1000000-DEAD-4ABC-8DEF-000000000010';
    const mixedAttempt = 'A1000000-BEEF-4ABC-9DEF-000000000009';
    final operation = fixture.api.prepareOutcome(
      attemptId: mixedAttempt,
      requestId: mixedRequest,
      observation: NotificationOperatorObservation.uncertain,
      evidenceReferenceSha256: 'b' * 64,
    );
    expect(operation.requestId, mixedRequest.toLowerCase());
    expect(operation.resourceId, mixedAttempt.toLowerCase());
    final outcome = await fixture.api.recordOutcome(operation);
    expect(outcome.attemptId, mixedAttempt.toLowerCase());
    final recovered = await fixture.api.getOperation(mixedRequest);
    expect(recovered.requestId, mixedRequest.toLowerCase());
    final body = jsonDecode(fixture.requests.last.body) as Map;
    expect(body['request_id'], mixedRequest.toLowerCase());
  });

  test(
    'postdispatch refusals retain recovery even when shared session reports known HTTP error',
    () async {
      for (final error in [
        (403, 'sms_authority_changed'),
        (403, 'permission_required'),
        (409, 'sms_claim_unavailable'),
        (503, 'sms_operation_unknown'),
      ]) {
        final fresh = Fixture();
        await fresh.open();
        try {
          final confirmation = await fresh.confirmed();
          final operation = fresh.api.prepareSendStart(
            confirmation,
            requestId: requestId,
          );
          fresh.handler = (body) async => body['action'] == 'record_send_start'
              ? response({'error': error.$2}, error.$1)
              : response({'ok': true, 'result': fresh.result(body)});
          await expectLater(
            fresh.api.recordSendStart(operation),
            throwsA(
              isA<NotificationOperatorRequestException>()
                  .having(
                    (failure) => identical(failure.operation, operation),
                    'original operation',
                    isTrue,
                  )
                  .having(
                    (failure) => failure.operation.requestId,
                    'original key',
                    requestId,
                  )
                  .having(
                    (failure) => failure.outcomeUnknown,
                    'commit cannot be excluded',
                    isTrue,
                  )
                  .having(
                    (failure) => failure.code,
                    'server code retained',
                    error.$2,
                  ),
            ),
          );
          final recovered = await fresh.api.getOperation(
            requestId,
            originalOperation: operation,
          );
          expect(recovered.observed, isTrue);
          expect(
            (recovered.receipt as NotificationOperatorSendStart).permit,
            isNull,
          );
          await expectLater(
            fresh.api.recordSendStart(operation),
            throwsStateError,
          );
          expect(
            fresh.requests.where(
              (request) =>
                  (jsonDecode(request.body) as Map)['action'] ==
                  'record_send_start',
            ),
            hasLength(1),
          );
        } finally {
          fresh.dispose();
        }
      }
    },
  );

  test(
    'recovered receipt cannot contain a permit, be adopted or mismatch original',
    () async {
      final claim = await fixture.claimed();
      final content = await fixture.api.getClaimed(claim);
      final op = fixture.api.prepareConfirm(
        content,
        userConfirmation: true,
        confirmationId: confirmationId,
      );
      fixture.handler = (body) async => response({
        'ok': true,
        'result': {
          ...marker(),
          'request_id': requestId,
          'observed': true,
          'receipt': fixture.claimReceipt(),
          'may_send': false,
        },
      });
      var resolution = await fixture.api.getOperation(requestId);
      await expectLater(
        fixture.api.getClaimed(resolution.receipt as NotificationOperatorClaim),
        throwsA(isA<AdminAccountException>()),
      );
      await expectLater(
        fixture.api.getOperation(op.requestId, originalOperation: op),
        throwsFormatException,
      );
      fixture.handler = (body) async => response({
        'ok': true,
        'result': {
          ...marker(),
          'request_id': requestId,
          'observed': true,
          'receipt': fixture.startReceipt(),
          'may_send': false,
        },
      });
      await expectLater(
        fixture.api.getOperation(requestId),
        throwsFormatException,
      );
      fixture.handler = (body) async => response({
        'ok': true,
        'result': {
          ...marker(),
          'request_id': requestId,
          'observed': false,
          'receipt': null,
          'may_send': false,
        },
      });
      resolution = await fixture.api.getOperation(requestId);
      expect(resolution.observed, isFalse);
      expect(resolution.receipt, isNull);
    },
  );

  test(
    'pending pagination rejects duplicates, ordering and mismatched cursor',
    () async {
      for (final items in <List<Map<String, dynamic>>>[
        [fixture.pendingItem(), fixture.pendingItem()],
        [fixture.pendingItem(id: otherId), fixture.pendingItem()],
        [fixture.pendingItem(state: 'send_started')..['attempt_id'] = null],
      ]) {
        fixture.handler = (_) async => response({
          'ok': true,
          'result': {...marker(), 'items': items, 'next_cursor': null},
        });
        await expectLater(fixture.api.listPending(), throwsFormatException);
      }
      fixture.handler = (_) async => response({
        'ok': true,
        'result': {
          ...marker(),
          'items': [fixture.pendingItem()],
          'next_cursor': {
            'after_created_at': '2026-10-15T10:00:00.000Z',
            'after_job_id': otherId,
          },
        },
      });
      await expectLater(
        fixture.api.listPending(limit: 1),
        throwsFormatException,
      );
    },
  );

  test(
    'invalid operation IDs, action mismatch and HTTP failures cannot resend',
    () async {
      final job = (await fixture.api.listPending()).items.single;
      expect(
        () => fixture.api.prepareClaim(
          job,
          workerId: 'operator.tab',
          requestId: 'not-a-uuid',
        ),
        throwsFormatException,
      );
      expect(
        () => fixture.api.prepareClaim(job, workerId: 'bad worker'),
        throwsArgumentError,
      );
      final op = fixture.api.prepareClaim(job, workerId: 'operator.tab');
      await expectLater(fixture.api.recordOutcome(op), throwsArgumentError);
      fixture.handler = (_) async =>
          response({'error': 'sms_claim_unavailable'}, 409);
      await expectLater(
        fixture.api.claim(op),
        throwsA(
          isA<NotificationOperatorRequestException>()
              .having(
                (e) => e.outcomeUnknown,
                'dispatch requires reconciliation',
                isTrue,
              )
              .having((e) => e.code, 'server code', 'sms_claim_unavailable'),
        ),
      );
      await expectLater(fixture.api.claim(op), throwsStateError);
    },
  );
}
