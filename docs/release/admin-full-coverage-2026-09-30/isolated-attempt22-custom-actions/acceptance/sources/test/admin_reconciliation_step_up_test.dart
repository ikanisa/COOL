import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_reconciliation_step_up.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Session _session({
  String user = 'operator-a',
  String sessionId = 'session-a',
  String aal = 'aal1',
  int? expiry,
}) {
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'sub': user,
            'session_id': sessionId,
            'aal': aal,
            'exp':
                expiry ?? DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
          }),
        ),
      )
      .replaceAll('=', '');
  return Session(
    accessToken: 'e30.$payload.synthetic',
    refreshToken: 'synthetic-refresh',
    tokenType: 'bearer',
    user: User(
      id: user,
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-09-30T00:00:00Z',
    ),
  );
}

Matcher _code(String code) => isA<AdminReconciliationStepUpException>().having(
  (e) => e.code,
  'code',
  code,
);

class _Transport implements AdminReconciliationMfaTransport {
  List<String> factors = ['factor-a'];
  Session verified = _session(aal: 'aal2');
  final calls = <String>[];
  Future<void> Function(String)? barrier;
  Object? failure;

  Future<void> _stage(String stage) async {
    calls.add(stage);
    await barrier?.call(stage);
    if (failure != null) throw failure!;
  }

  @override
  Future<List<String>> verifiedTotpFactors(Session session) async {
    await _stage('list');
    return factors;
  }

  @override
  Future<String> challenge(Session session, String factorId) async {
    expect(factorId, 'factor-a');
    await _stage('challenge');
    return 'challenge-a';
  }

  @override
  Future<Session> verify(
    Session session,
    String factorId,
    String challengeId,
    String code,
  ) async {
    expect(factorId, 'factor-a');
    expect(challengeId, 'challenge-a');
    expect(code, '123456');
    await _stage('verify');
    return verified;
  }
}

void main() {
  late Session? active;
  late _Transport transport;
  late AdminReconciliationStepUp controller;
  late int adoptions;

  setUp(() {
    active = _session();
    transport = _Transport();
    adoptions = 0;
    controller = AdminReconciliationStepUp(
      currentSession: () => active,
      transport: transport,
      adoptSession: (session) async {
        adoptions++;
        active = session;
      },
    );
  });

  for (final code in ['', '12345', '1234567', '123 56', '１２３４５６', '123456\n']) {
    test(
      'rejects non-exact six digit code ${jsonEncode(code)} without network',
      () async {
        await expectLater(
          controller.call(code),
          throwsA(_code('invalid_code')),
        );
        expect(transport.calls, isEmpty);
        expect(adoptions, 0);
      },
    );
  }

  test('verified TOTP upgrades only the current user and session', () async {
    await controller.call('123456');
    expect(transport.calls, ['list', 'challenge', 'verify']);
    expect(active, same(transport.verified));
    expect(adoptions, 1);
  });

  for (final stage in ['list', 'challenge', 'verify']) {
    for (final switchSessionOnly in [false, true]) {
      test(
        'fences ${switchSessionOnly ? 'same user new session' : 'new user'} after $stage',
        () async {
          final replacement = _session(
            user: switchSessionOnly ? 'operator-a' : 'operator-b',
            sessionId: 'session-b',
          );
          transport.barrier = (current) async {
            if (current == stage) active = replacement;
          };
          await expectLater(
            controller.call('123456'),
            throwsA(_code('session_changed')),
          );
          expect(adoptions, 0);
          expect(active, same(replacement));
          expect(transport.calls.last, stage);
        },
      );
    }
  }

  test(
    'sign-out while challenge is pending cannot verify or restore account',
    () async {
      transport.barrier = (stage) async {
        if (stage == 'challenge') active = null;
      };
      await expectLater(
        controller.call('123456'),
        throwsA(_code('session_changed')),
      );
      expect(transport.calls, ['list', 'challenge']);
      expect(active, isNull);
      expect(adoptions, 0);
    },
  );

  test('provider disposal fences a pending response', () async {
    transport.barrier = (_) async => controller.dispose();
    await expectLater(
      controller.call('123456'),
      throwsA(_code('session_changed')),
    );
    expect(adoptions, 0);
  });

  test(
    'requires an existing verified authenticator without enrollment',
    () async {
      transport.factors = [];
      await expectLater(
        controller.call('123456'),
        throwsA(_code('verified_authenticator_required')),
      );
      expect(transport.calls, ['list']);
    },
  );

  test('never guesses between multiple authenticators', () async {
    transport.factors = ['factor-a', 'factor-b'];
    await expectLater(
      controller.call('123456'),
      throwsA(_code('authenticator_selection_required')),
    );
    expect(transport.calls, ['list']);
  });

  test('concurrent submissions do not create competing challenges', () async {
    final pending = Completer<void>();
    transport.barrier = (stage) async {
      if (stage == 'list') await pending.future;
    };
    final first = controller.call('123456');
    await expectLater(
      controller.call('123456'),
      throwsA(_code('verification_in_progress')),
    );
    pending.complete();
    await first;
    expect(adoptions, 1);
  });

  test(
    'untrusted failures are redacted and a later retry is allowed',
    () async {
      transport.failure = StateError('SECRET 123456 synthetic-refresh');
      try {
        await controller.call('123456');
        fail('must reject');
      } on AdminReconciliationStepUpException catch (error) {
        expect(error.code, 'step_up_unavailable');
        expect(error.toString(), isNot(contains('SECRET')));
        expect(error.toString(), isNot(contains('123456')));
      }
      transport.failure = null;
      await controller.call('123456');
      expect(adoptions, 1);
    },
  );

  for (final invalid in ['aal1', 'user', 'session', 'expiry']) {
    test('rejects verified response with wrong $invalid', () async {
      transport.verified = _session(
        aal: invalid == 'aal1' ? 'aal1' : 'aal2',
        user: invalid == 'user' ? 'operator-b' : 'operator-a',
        sessionId: invalid == 'session' ? 'session-b' : 'session-a',
        expiry: invalid == 'expiry' ? 0 : null,
      );
      await expectLater(
        controller.call('123456'),
        throwsA(_code('step_up_unavailable')),
      );
      expect(adoptions, 0);
    });
  }

  test('missing or expiring local session never calls Auth', () async {
    active = null;
    await expectLater(
      controller.call('123456'),
      throwsA(_code('session_changed')),
    );
    active = _session(
      expiry: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 10,
    );
    await expectLater(
      controller.call('123456'),
      throwsA(_code('session_changed')),
    );
    expect(transport.calls, isEmpty);
  });

  test(
    'Supabase transport uses Auth contracts, filters factors and never refreshes',
    () async {
      final requests = <http.Request>[];
      final authTransport = SupabaseReconciliationMfaTransport(
        supabaseUrl: 'https://synthetic.invalid/',
        publishableKey: 'synthetic-publishable',
        httpClient: MockClient((request) async {
          requests.add(request);
          expect(
            request.headers['authorization'],
            'Bearer ${active!.accessToken}',
          );
          expect(request.headers['apikey'], 'synthetic-publishable');
          if (request.url.path.endsWith('/user')) {
            return http.Response(
              jsonEncode({
                ...active!.user.toJson(),
                'factors': [
                  for (final (id, type, status) in [
                    ('factor-a', 'totp', 'verified'),
                    ('unverified', 'totp', 'unverified'),
                    ('phone', 'phone', 'verified'),
                  ])
                    {
                      'id': id,
                      'factor_type': type,
                      'status': status,
                      'created_at': '2026-09-30T00:00:00Z',
                      'updated_at': '2026-09-30T00:00:00Z',
                    },
                ],
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/challenge')) {
            expect(jsonDecode(request.body), <String, dynamic>{});
            return http.Response('{"id":"challenge-a"}', 200);
          }
          expect(jsonDecode(request.body), {
            'challenge_id': 'challenge-a',
            'code': '123456',
          });
          return http.Response(jsonEncode(_session(aal: 'aal2').toJson()), 200);
        }),
      );
      expect(await authTransport.verifiedTotpFactors(active!), ['factor-a']);
      expect(await authTransport.challenge(active!, 'factor-a'), 'challenge-a');
      final verified = await authTransport.verify(
        active!,
        'factor-a',
        'challenge-a',
        '123456',
      );
      expect(verified.user.id, active!.user.id);
      expect(requests.map((r) => '${r.method} ${r.url.path}'), [
        'GET /auth/v1/user',
        'POST /auth/v1/factors/factor-a/challenge',
        'POST /auth/v1/factors/factor-a/verify',
      ]);
    },
  );

  for (final (status, body, expected) in [
    (429, 'sensitive provider error', 'verification_rate_limited'),
    (
      422,
      '{"code":"mfa_verification_failed","message":"SECRET"}',
      'verification_failed',
    ),
    (422, '{"code":"mfa_challenge_expired"}', 'verification_failed'),
    (403, '{"message":"SECRET"}', 'step_up_unavailable'),
  ]) {
    test('Auth failure $status maps to safe $expected', () async {
      final authTransport = SupabaseReconciliationMfaTransport(
        supabaseUrl: 'https://synthetic.invalid',
        publishableKey: 'synthetic-publishable',
        httpClient: MockClient((_) async => http.Response(body, status)),
      );
      await expectLater(
        authTransport.verify(active!, 'factor-a', 'challenge-a', '123456'),
        throwsA(_code(expected)),
      );
    });
  }

  test(
    'provider adopts and emits MFA event through the pinned main SDK',
    () async {
      final client = SupabaseClient(
        'https://synthetic.invalid',
        'synthetic-publishable',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      await client.auth.recoverSession(jsonEncode(active!.toJson()));
      final events = <AuthChangeEvent>[];
      final subscription = client.auth.onAuthStateChange.listen(
        (event) => events.add(event.event),
      );
      addTearDown(subscription.cancel);
      final container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          adminReconciliationMfaTransportProvider.overrideWithValue(transport),
        ],
      );
      addTearDown(container.dispose);
      await container.read(adminReconciliationStepUpProvider)('123456');
      await Future<void>.delayed(Duration.zero);
      expect(
        client.auth.currentSession!.accessToken,
        transport.verified.accessToken,
      );
      expect(events, contains(AuthChangeEvent.mfaChallengeVerified));
    },
  );
}
