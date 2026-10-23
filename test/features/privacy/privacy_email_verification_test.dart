// Synthetic HTTP only. These tests exercise actual transport, mapped SDK,
// synchronous authority and email coordinator; they do not qualify Auth/SQL.
import 'dart:async';
import 'dart:convert';

import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:collect_app/core/supabase/collect_supabase_configuration.dart';
import 'package:collect_app/features/privacy/privacy_contract.dart';
import 'package:collect_app/features/privacy/privacy_email_verification.dart';
import 'package:collect_app/features/privacy/privacy_request_controller.dart';
import 'package:collect_app/features/privacy/privacy_session.dart';
import 'package:collect_app/features/privacy/privacy_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../core/supabase_backend_test.dart' as fixtures;
import 'privacy_test_support.dart';

const challengeId = '10000000-0000-4000-8000-000000000101';
const operation1 = '10000000-0000-4000-8000-000000000102';
const operation2 = '10000000-0000-4000-8000-000000000103';
const oldSid = '10000000-0000-4000-8000-000000000104';
const newSid = '10000000-0000-4000-8000-000000000105';
const otherManaged = '10000000-0000-4000-8000-000000000106';
const otherCanonical = '10000000-0000-4000-8000-000000000107';
const apiOrigin = 'https://native-fixture.invalid';
final context = base64UrlEncode(List<int>.filled(32, 7)).replaceAll('=', '');
String jwt(Map<String, dynamic> claims) {
  String part(Object value) =>
      base64UrlEncode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'ES256'})}.${part(claims)}.synthetic';
}

Map<String, dynamic> sessionJson(
  int now, {
  String sid = oldSid,
  String principal = fixtures.principal,
  String managed = fixtures.authUser,
  Object? amrTime,
}) => {
  'access_token': jwt({
    'iss': '${fixtures.project}/auth/v1',
    'sub': managed,
    'aud': 'authenticated',
    'role': 'authenticated',
    'session_id': sid,
    'iat': now,
    'exp': now + 3600,
    'amr': [
      {'method': 'otp', 'timestamp': amrTime ?? now},
    ],
  }),
  'refresh_token': 'synthetic-captured-refresh',
  'token_type': 'bearer',
  'expires_at': now + 3600,
  'expires_in': 3600,
  'user': {
    'id': principal,
    'auth_user_id': managed,
    'email': 'member@example.test',
    'email_confirmed_at': '2026-10-01T00:00:00Z',
    'is_anonymous': false,
  },
};
Map<String, dynamic> envelope(Map<String, dynamic> input) => {
  for (final key in [
    'contract_version',
    'purpose',
    'mode',
    'challenge_id',
    'challenge_context',
  ])
    key: input[key],
  'identity_type': 'email',
  'channel': 'email',
};
Map<String, dynamic> descriptor(
  Map<String, dynamic> input,
  int created, {
  String state = 'not_started',
  String cleanup = 'not_required',
  bool cancelled = false,
  String delivery = 'accepted',
}) => {
  ...envelope(input),
  'destination_hint': 'm***@example.test',
  'retry_after': 60,
  'created_at': created,
  'expires_at': created + 300,
  'delivery_status': delivery,
  'verification_state': state,
  'operation_id': input['operation_id'],
  'cancelled': cancelled,
  'candidate_cleanup': cleanup,
};
Map<String, dynamic> candidate(Map<String, dynamic> input, int now) => {
  ...sessionJson(now, sid: newSid),
  ...envelope(input),
  'operation_id': input['operation_id'],
  'auth_event': {'method': 'otp', 'timestamp': now},
  'purpose_proof': {
    'purpose': privacyEmailPurpose,
    'challenge_id': input['challenge_id'],
    'user_id': fixtures.principal,
    'auth_user_id': fixtures.authUser,
    'initiating_session_id': oldSid,
    'session_id': newSid,
    'method': 'otp',
    'authenticated_at': now,
    'expires_at': now + 300,
  },
};
http.Response response(Object? value, [int status = 200]) =>
    http.Response(jsonEncode(value), status);

class Harness {
  Harness(
    this.backend,
    this.authority,
    this.transport,
    this.flow,
    this.calls,
    this.clock,
    this.zone,
  );
  final CollectCloudflareClient backend;
  final CollectPrivacySessionAuthority authority;
  final CollectPrivacyRequestTransport transport;
  final PrivacyEmailVerification flow;
  final List<http.Request> calls;
  final List<int> clock;
  final Zone zone;
  bool _closed = false;
  Future<void> close() {
    if (_closed) return Future<void>.value();
    _closed = true;
    // Native storage and streams were created in this zone. Widget fake
    // pumps cannot complete the original real-zone stream close.
    return zone.run(() async {
      await authority.dispose();
      await backend.dispose();
    });
  }

  static Future<Harness> create(
    Future<http.Response> Function(http.Request, int) send,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000,
        clock = [DateTime.now().millisecondsSinceEpoch ~/ 1000];
    final config = CollectSupabaseConfiguration.fromEnvironment(
      fixtures.environment(api: apiOrigin),
    );
    final backend = CollectCloudflareClient(
      apiOrigin,
      supabaseConfiguration: config,
      httpClient: MockClient(
        (_) async => throw StateError('No SDK HTTP is permitted'),
      ),
    );
    await backend.auth.recoverSession(
      jsonEncode(sessionJson(now, amrTime: now - 600)),
    );
    final authority = CollectPrivacySessionAuthority(backend.auth),
        calls = <http.Request>[];
    final transport = CollectPrivacyRequestTransport(
      apiUrl: apiOrigin,
      supabaseConfiguration: config,
      httpClient: MockClient((r) async {
        calls.add(r);
        return send(r, now);
      }),
      isSessionCurrent: (owner) {
        try {
          return authority.capture().sameFence(owner);
        } catch (_) {
          return false;
        }
      },
    );
    final ids = [challengeId, operation1, operation2].iterator;
    final flow = PrivacyEmailVerification(
      authority: authority,
      transport: transport,
      now: () => clock.single,
      newId: () {
        if (!ids.moveNext()) throw StateError('Unexpected new operation');
        return ids.current;
      },
      newContext: () => context,
    );
    final harness = Harness(
      backend,
      authority,
      transport,
      flow,
      calls,
      clock,
      Zone.current,
    );
    addTearDown(harness.close);
    return harness;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'actual native email keeps initiating bearer/pair, then adopts once without generic OTP or later cancel',
    () async {
      final h = await Harness.create((r, now) async {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        expect(
          r.url.path.startsWith('/functions/v1/collect-api/v1/privacy/email/'),
          isTrue,
        );
        expect(r.followRedirects, isFalse);
        expect(r.headers['apikey'], fixtures.publishable);
        if (r.url.path.endsWith('/challenge')) {
          expect(body['allow_registration'], isFalse);
          expect(body['should_create_user'], isFalse);
          expect(body.containsKey('email'), isFalse);
          expect(body.containsKey('user_id'), isFalse);
          expect(body['challenge_id'], challengeId);
          expect(body['challenge_context'], context);
          return response(descriptor(body, now), 202);
        }
        expect(r.url.path.endsWith('/verify'), isTrue);
        expect(body['operation_id'], operation1);
        expect(body['code'], '1234567890');
        return response(candidate(body, now));
      });
      final original = h.authority.capture(),
          token = h.backend.auth.currentSession!.accessToken;
      await h.flow.challenge(original);
      final adopted = await h.flow.verify('1234567890');
      expect(adopted.subjectId, fixtures.principal);
      expect(adopted.sessionId, newSid);
      expect(h.backend.auth.currentSession!.user.authUserId, fixtures.authUser);
      expect(
        h.calls.every((r) => r.headers['Authorization'] == 'Bearer $token'),
        isTrue,
      );
      await h.flow.cancel();
      expect(h.calls, hasLength(2));
      expect(h.flow.toString(), isNot(contains(context)));
    },
  );

  for (final action in ['flow cancellation', 'controller disposal']) {
    test(
      'synchronous candidate installation survives $action without retiring the installed session',
      () async {
        final h = await Harness.create((r, now) async {
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          if (r.url.path.endsWith('/challenge')) {
            return response(descriptor(body, now), 202);
          }
          if (r.url.path.endsWith('/cancel')) {
            return response(
              descriptor(
                body,
                now,
                state: 'verified',
                cleanup: 'confirmed',
                cancelled: true,
              ),
            );
          }
          return response(candidate(body, now));
        });
        final controller = PrivacyRequestController(
          authority: h.authority,
          transport: h.transport,
          subjectId: fixtures.principal,
        );
        addTearDown(controller.dispose);
        if (action == 'controller disposal') {
          await controller.sendCode();
        } else {
          await h.flow.challenge(h.authority.capture());
        }
        var observedInstall = false;
        final subscription = h.backend.auth.onAuthStateChangeSync.listen((
          state,
        ) {
          if (state.event != CollectAuthEvent.signedIn ||
              state.session?.claims['session_id'] != newSid) {
            return;
          }
          observedInstall = true;
          // This callback runs inside actual SDK _install, not a fake authority.
          expect(h.backend.auth.currentSession, same(state.session));
          if (action == 'controller disposal') {
            controller.dispose();
          } else {
            unawaited(h.flow.cancel());
          }
        });
        addTearDown(subscription.cancel);
        if (action == 'controller disposal') {
          await expectLater(
            controller.verifyCode('123456'),
            throwsA(isA<PrivacyRequestException>()),
          );
        } else {
          await h.flow.verify('123456');
        }
        // Drain the captured HTTP cleanup if the regression dispatches one.
        await Future<void>.delayed(Duration.zero);
        expect(observedInstall, isTrue);
        expect(h.backend.auth.currentSession!.claims['session_id'], newSid);
        expect(
          h.calls.where((r) => r.url.path.endsWith('/verify')),
          hasLength(1),
        );
        expect(h.calls.where((r) => r.url.path.endsWith('/cancel')), isEmpty);
      },
    );
  }

  final mutations = <String, void Function(Map<String, dynamic>, int)>{
    'same email wrong managed subject': (v, n) =>
        (v['user'] as Map)['auth_user_id'] = otherManaged,
    'different canonical subject': (v, n) =>
        (v['user'] as Map)['id'] = otherCanonical,
    'missing explicit mapping': (v, n) =>
        (v['user'] as Map).remove('auth_user_id'),
    'original session reused': (v, n) {
      v['access_token'] = (sessionJson(n, sid: oldSid))['access_token'];
      (v['purpose_proof'] as Map)['session_id'] = oldSid;
    },
    'string OTP event': (v, n) =>
        (v['auth_event'] as Map)['timestamp'] = n.toString(),
    'future OTP event': (v, n) {
      (v['auth_event'] as Map)['timestamp'] = n + 1;
      (v['purpose_proof'] as Map)['authenticated_at'] = n + 1;
    },
    'fresh iat stale OTP': (v, n) {
      v['access_token'] = sessionJson(
        n,
        sid: newSid,
        amrTime: n - 600,
      )['access_token'];
    },
    'different operation': (v, n) => v['operation_id'] = operation2,
    'different context': (v, n) => v['challenge_context'] = 'x' * 43,
    'different purpose': (v, n) => v['purpose'] = 'login',
    'string AMR': (v, n) {
      v['access_token'] = sessionJson(
        n,
        sid: newSid,
        amrTime: n.toString(),
      )['access_token'];
    },
  };
  for (final item in mutations.entries) {
    test(
      'native email refuses ${item.key} without adopting or guessing cleanup',
      () async {
        final h = await Harness.create((r, now) async {
          final b = jsonDecode(r.body) as Map<String, dynamic>;
          if (r.url.path.endsWith('/challenge')) {
            return response(descriptor(b, now), 202);
          }
          final value = candidate(b, now);
          item.value(value, now);
          return response(value);
        });
        final original = h.backend.auth.currentSession;
        await h.flow.challenge(h.authority.capture());
        await expectLater(
          h.flow.verify('123456'),
          throwsA(isA<PrivacyRequestException>()),
        );
        expect(h.backend.auth.currentSession, same(original));
        expect(h.flow.unknown, isTrue);
        expect(h.calls.where((r) => r.url.path.endsWith('/cancel')), isEmpty);
      },
    );
  }

  for (final mode in [
    'lost',
    'native exception',
    'malformed JSON',
    '503',
    'metadata-only replay',
  ]) {
    test(
      '$mode verify remains unknown; verified status metadata cannot recover tokens or replay verify',
      () async {
        final h = await Harness.create((r, now) async {
          final b = jsonDecode(r.body) as Map<String, dynamic>;
          if (r.url.path.endsWith('/challenge')) {
            return response(descriptor(b, now), 202);
          }
          if (r.url.path.endsWith('/status')) {
            return response(
              descriptor(b, now, state: 'verified', cleanup: 'unconfirmed'),
            );
          }
          if (mode == 'lost') {
            throw http.ClientException('Synthetic response lost');
          }
          if (mode == 'native exception') {
            throw StateError('Never expose native details');
          }
          if (mode == 'malformed JSON') return http.Response('{not-json', 200);
          if (mode == '503') {
            return response({'code': 'privacy_email_operation_unknown'}, 503);
          }
          return response(
            descriptor(b, now, state: 'verified', cleanup: 'unconfirmed'),
          );
        });
        final original = h.backend.auth.currentSession;
        await h.flow.challenge(h.authority.capture());
        await expectLater(
          h.flow.verify('123456'),
          throwsA(isA<PrivacyRequestException>()),
        );
        await h.flow.status();
        expect(h.flow.unknown, isTrue);
        expect(h.flow.codeReady, isFalse);
        await expectLater(
          h.flow.verify('123456'),
          throwsA(isA<PrivacyRequestException>()),
        );
        expect(
          h.calls.where((r) => r.url.path.endsWith('/verify')),
          hasLength(1),
        );
        expect(
          h.calls.where((r) => r.url.path.endsWith('/status')),
          hasLength(1),
        );
        expect(h.backend.auth.currentSession, same(original));
      },
    );
  }

  test(
    'definite code rejection permits only an explicit new verification operation',
    () async {
      var verifies = 0;
      final h = await Harness.create((r, now) async {
        final b = jsonDecode(r.body) as Map<String, dynamic>;
        if (r.url.path.endsWith('/challenge')) {
          return response(descriptor(b, now), 202);
        }
        verifies++;
        if (verifies == 1) {
          return response({
            ...descriptor(b, now, state: 'rejected', cleanup: 'unconfirmed'),
            'code': 'privacy_email_code_rejected',
            'message': 'UNTRUSTED_PROVIDER_DETAIL',
          }, 401);
        }
        return response(candidate(b, now));
      });
      await h.flow.challenge(h.authority.capture());
      await expectLater(
        h.flow.verify('111111'),
        throwsA(isA<PrivacyRequestException>()),
      );
      expect(verifies, 1);
      expect(h.flow.codeReady, isTrue);
      await h.flow.verify('222222');
      final posts = h.calls
          .where((r) => r.url.path.endsWith('/verify'))
          .map((r) => jsonDecode(r.body) as Map)
          .toList();
      expect(posts.map((b) => b['operation_id']), [operation1, operation2]);
      expect(posts.map((b) => b['challenge_context']).toSet(), {context});
      expect(h.backend.auth.currentSession!.claims['session_id'], newSid);
    },
  );

  for (final race in ['account switch', 'ABA', 'local cancel', 'flow expiry']) {
    test(
      'late candidate after $race uses only exact captured candidate cleanup',
      () async {
        final entered = Completer<void>(), answer = Completer<http.Response>();
        late Map<String, dynamic> verifyBody;
        late int issued;
        final h = await Harness.create((r, now) async {
          final b = jsonDecode(r.body) as Map<String, dynamic>;
          if (r.url.path.endsWith('/challenge')) {
            return response(descriptor(b, now), 202);
          }
          if (r.url.path.endsWith('/verify')) {
            verifyBody = b;
            issued = now;
            entered.complete();
            return answer.future;
          }
          expect(r.url.path.endsWith('/cancel'), isTrue);
          if (b.containsKey('candidate_access_token')) {
            expect(b.keys.toSet(), {
              'contract_version',
              'purpose',
              'mode',
              'challenge_id',
              'challenge_context',
              'operation_id',
              'candidate_access_token',
            });
            expect(
              b['candidate_access_token'],
              candidate(verifyBody, issued)['access_token'],
            );
            expect(b['operation_id'], operation1);
            expect(b['challenge_context'], context);
          }
          return response(
            descriptor(
              b,
              now,
              state: 'verified',
              cleanup: b.containsKey('candidate_access_token')
                  ? 'confirmed'
                  : 'unconfirmed',
              cancelled: true,
            ),
          );
        });
        final original = h.backend.auth.currentSession!;
        await h.flow.challenge(h.authority.capture());
        final verifying = h.flow.verify('123456');
        final rejected = expectLater(
          verifying,
          throwsA(isA<PrivacyRequestException>()),
        );
        await entered.future;
        if (race == 'local cancel') {
          await h.flow.cancel();
        } else if (race == 'flow expiry') {
          h.clock[0] += 601;
        } else {
          await h.backend.auth.clearLocalSession();
          await h.backend.auth.recoverSession(
            jsonEncode(
              sessionJson(
                issued,
                principal: otherCanonical,
                managed: otherManaged,
              ),
            ),
          );
          if (race == 'ABA') {
            await h.backend.auth.recoverSession(jsonEncode(original.toJson()));
          }
        }
        final current = h.backend.auth.currentSession;
        answer.complete(response(candidate(verifyBody, issued)));
        await rejected;
        expect(h.backend.auth.currentSession, same(current));
        final cleanup = h.calls
            .where(
              (r) =>
                  r.url.path.endsWith('/cancel') &&
                  (jsonDecode(r.body) as Map).containsKey(
                    'candidate_access_token',
                  ),
            )
            .single;
        expect(
          cleanup.headers['Authorization'],
          'Bearer ${original.accessToken}',
        );
        expect(
          (jsonDecode(cleanup.body) as Map)['candidate_access_token'],
          isNot(current?.accessToken),
        );
        expect(
          h.backend.auth.currentSession?.claims['session_id'],
          isNot(newSid),
        );
      },
    );
  }

  test(
    'integrated request controller keeps review-only intake and phone capability',
    () async {
      final h = await Harness.create((r, now) async {
        final b = jsonDecode(r.body) as Map<String, dynamic>;
        if (r.url.path.endsWith('/challenge')) {
          return response(descriptor(b, now), 202);
        }
        if (r.url.path.endsWith('/verify')) return response(candidate(b, now));
        if (r.url.path.endsWith('/request_account_deletion_v1')) {
          return response(
            privacyReceiptJson(
              submission: true,
              requestId: b['p_request_id'] as String,
              submissionId: b['p_request_id'] as String,
              reasonSupplied: false,
            ),
          );
        }
        throw StateError('No other endpoint is expected');
      });
      final controller = PrivacyRequestController(
        authority: h.authority,
        transport: h.transport,
      );
      addTearDown(controller.dispose);
      expect(controller.emailVerificationAvailable, isTrue);
      expect(controller.usingEmailVerification, isTrue);
      // The controller owns production random IDs. Bind synthetic server echoes
      // from request bodies; direct flow tests above additionally pin exact IDs.
      await controller.sendCode();
      await controller.verifyCode('123456');
      final receipt = await controller.submit();
      expect(receipt.state, 'pending_review');
      expect(receipt.erasureCompleted, isFalse);
      expect(receipt.authRemoved, isFalse);
      expect(receipt.retentionApprovalGranted, isFalse);
      final intake = h.calls.last;
      expect(
        intake.headers['Authorization'],
        'Bearer ${h.backend.auth.currentSession!.accessToken}',
      );
    },
  );
}
