import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';

import 'admin_action_session_test.dart' as auth;

const _email = 'operator@collect.example';

class _ObservedRequest {
  const _ObservedRequest(this.path, this.method, this.body, this.bearer);
  final String path, method;
  final Map<String, dynamic> body;
  final String? bearer;
}

class _Reply {
  const _Reply(this.body, {this.status = 200});
  final Object? body;
  final int status;
}

class _NativeHttp extends HttpOverrides {}

/// Real localhost sockets and the Collect HTTP client. Every address,
/// token and identity below is synthetic; no configured service is contacted.
class _Loopback {
  late HttpServer server;
  late CollectCloudflareClient client;
  late StreamSubscription<HttpRequest> subscription;
  late AdminRepository repository;
  late IOClient http;
  final requests = <_ObservedRequest>[];
  final handlerErrors = <Object>[];
  final truncatePaths = <String>{};
  String sessionId = 'email-a';
  int nonce = 0;
  Future<_Reply> Function(_ObservedRequest)? override;

  static Future<_Loopback> open() async {
    final loop = _Loopback();
    loop.server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    loop.subscription = loop.server.listen(loop._handle);
    // Explicit native sockets bypass the widget binding's HTTP400 stub without
    // changing global overrides or contacting an external endpoint.
    loop.http = IOClient(_NativeHttp().createHttpClient(null));
    loop.client = CollectCloudflareClient(
      'http://127.0.0.1:${loop.server.port}',
      surface: 'admin',
      httpClient: loop.http,
    );
    loop.repository = AdminRepository(loop.client);
    return loop;
  }

  Map<String, dynamic> get identity => {
    'user_id': auth.actor,
    'display_name': 'Synthetic operator',
    'phone_masked': null,
    'roles': ['platform_owner'],
    'permissions': ['overview.read'],
  };

  Map<String, dynamic> get receipt {
    final value = auth.authReceipt(sessionId, '$nonce');
    (value['user'] as Map<String, dynamic>)['email'] = _email;
    return value;
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final raw = await utf8.decoder.bind(request).join();
      final decoded = raw.isEmpty ? null : jsonDecode(raw);
      final observed = _ObservedRequest(
        request.uri.path,
        request.method,
        decoded == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(decoded as Map<String, dynamic>),
        request.headers.value(HttpHeaders.authorizationHeader),
      );
      requests.add(observed);
      if (truncatePaths.contains(observed.path)) {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..contentLength = 4096;
        // Explicit headers distinguish an uncertain lost response from a
        // before-header reused-socket failure that HTTP may retransmit.
        final socket = await request.response.detachSocket(writeHeaders: true);
        socket.add(utf8.encode('{"synthetic_partial_response":'));
        await socket.flush();
        await socket.close();
        return;
      }
      final reply = await (override?.call(observed) ?? _default(observed));
      request.response
        ..statusCode = reply.status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(reply.body));
      await request.response.close();
    } catch (error) {
      handlerErrors.add(error);
      request.response.statusCode = 500;
      await request.response.close();
    }
  }

  Future<_Reply> _default(_ObservedRequest request) async {
    if (request.path.endsWith('/otp')) {
      return const _Reply({'challenge_id': 'synthetic-email-challenge'});
    }
    if (request.path.endsWith('/verify')) {
      return _Reply(receipt);
    }
    if (request.path.endsWith('/admin_current_user')) {
      return _Reply(identity);
    }
    return const _Reply({});
  }

  Future<void> replace(String id, {int newNonce = 0}) async {
    sessionId = id;
    nonce = newNonce;
    await client.auth.recoverSession(jsonEncode(receipt));
    // Drain actual Auth stream delivery before resolving a departed request.
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> requestChallenge() async {
    await repository.sendEmailOtp(email: _email);
    requests.clear();
  }

  Future<void> close() async {
    await client.dispose();
    http.close();
    await subscription.cancel();
    await server.close(force: true);
    expect(handlerErrors, isEmpty);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Collect email loopback', () {
    late _Loopback loop;
    setUp(() async => loop = await _Loopback.open());
    tearDown(() => loop.close());

    test('request is one normalized POST without account creation', () async {
      await loop.repository.sendEmailOtp(email: ' OPERATOR@Collect.Example ');
      final request = loop.requests.single;
      expect(request.path, '/v1/auth/otp');
      expect(request.method, 'POST');
      expect(request.body['email'], _email);
      expect(request.body['surface'], 'admin');
      expect(request.body.containsKey('create_user'), isFalse);
      expect(request.body.containsKey('phone'), isFalse);
      expect(request.body.containsKey('redirect_to'), isFalse);
    });

    test(
      'verification pins new session Bearer for exact current identity',
      () async {
        await loop.requestChallenge();
        final identity = await loop.repository.verifyEmailOtp(
          email: ' OPERATOR@Collect.Example ',
          otp: ' 123456 ',
        );
        expect(identity?.userId, auth.actor);
        expect(loop.requests, hasLength(2));
        final verify = loop.requests.first;
        expect(verify.path, '/v1/auth/verify');
        expect(verify.body['email'], _email);
        expect(verify.body['code'], '123456');
        expect(verify.body['challenge_id'], 'synthetic-email-challenge');
        expect(verify.body['surface'], 'admin');
        final current = loop.requests.last;
        expect(current.path, '/v1/rpc/admin_current_user');
        expect(current.method, 'POST');
        expect(
          current.bearer,
          'Bearer ${loop.client.auth.currentSession!.accessToken}',
        );
      },
    );

    for (final status in [400, 429, 503]) {
      test('request HTTP$status fails once without implicit reissue', () async {
        loop.override = (_) async => _Reply({
          'msg': 'Synthetic unavailable',
          'code': 'synthetic_denial',
        }, status: status);
        await expectLater(
          loop.repository.sendEmailOtp(email: _email),
          throwsA(isA<CollectAuthException>()),
        );
        expect(loop.requests, hasLength(1));
        expect(loop.client.auth.currentSession, isNull);
      });
      test(
        'verification HTTP$status cannot read an identity or reissue',
        () async {
          await loop.requestChallenge();
          loop.override = (_) async => _Reply({
            'msg': 'Synthetic unavailable',
            'code': 'synthetic_denial',
          }, status: status);
          await expectLater(
            loop.repository.verifyEmailOtp(email: _email, otp: '123456'),
            throwsA(isA<CollectAuthException>()),
          );
          expect(loop.requests, hasLength(1));
          expect(loop.requests.single.path, '/v1/auth/verify');
          expect(loop.client.auth.currentSession, isNull);
        },
      );
    }

    test('verification without a session never reads Admin identity', () async {
      await loop.requestChallenge();
      loop.override = (_) async => const _Reply({});
      await expectLater(
        loop.repository.verifyEmailOtp(email: _email, otp: '123456'),
        throwsA(isA<CollectAuthException>()),
      );
      expect(loop.requests, hasLength(1));
      expect(loop.client.auth.currentSession, isNull);
    });

    for (final operation in ['request', 'verification']) {
      test(
        '$operation partial response loss stays uncertain until an explicit caller',
        () async {
          if (operation == 'verification') await loop.requestChallenge();
          final path = operation == 'request'
              ? '/v1/auth/otp'
              : '/v1/auth/verify';
          loop.truncatePaths.add(path);
          Future<Object?> dispatch() => operation == 'request'
              ? loop.repository.sendEmailOtp(email: _email)
              : loop.repository.verifyEmailOtp(email: _email, otp: '123456');
          await expectLater(dispatch(), throwsA(isA<CollectAuthException>()));
          expect(loop.requests, hasLength(1));
          expect(loop.requests.single.path, path);
          expect(loop.client.auth.currentSession, isNull);
          loop.truncatePaths.clear();
          await dispatch();
          expect(loop.requests.where((r) => r.path == path), hasLength(2));
          expect(
            loop.requests.where((r) => r.path.endsWith('/admin_current_user')),
            hasLength(operation == 'request' ? 0 : 1),
          );
        },
      );
    }

    test(
      'confirmed email without enrolled identity returns no approval',
      () async {
        await loop.requestChallenge();
        loop.override = (request) async => request.path.endsWith('/verify')
            ? _Reply(loop.receipt)
            : const _Reply(null);
        expect(
          await loop.repository.verifyEmailOtp(email: _email, otp: '123456'),
          isNull,
        );
        expect(loop.requests, hasLength(2));
      },
    );

    for (final scenario in [
      'replacement',
      'A-B-A',
      'logout',
      'same-session-refresh',
    ]) {
      test(
        '$scenario while identity is pending respects exact session scope',
        () async {
          await loop.requestChallenge();
          final entered = Completer<void>();
          final pending = Completer<_Reply>();
          loop.override = (request) async {
            if (request.path.endsWith('/admin_current_user')) {
              entered.complete();
              return pending.future;
            }
            return loop._default(request);
          };
          final verification = loop.repository.verifyEmailOtp(
            email: _email,
            otp: '123456',
          );
          final assertion = scenario == 'same-session-refresh'
              ? verification.then(
                  (identity) => expect(identity?.userId, auth.actor),
                )
              : expectLater(verification, throwsA(isA<AdminSessionChanged>()));
          await entered.future;
          final bearer = loop.requests.last.bearer;
          if (scenario == 'logout') {
            await loop.client.auth.signOut();
          } else if (scenario == 'same-session-refresh') {
            await loop.replace('email-a', newNonce: 1);
          } else {
            await loop.replace('email-b');
            if (scenario == 'A-B-A') {
              await loop.replace('email-a');
            }
          }
          pending.complete(_Reply(loop.identity));
          await assertion;
          expect(
            loop.requests.where((r) => r.path.endsWith('/admin_current_user')),
            hasLength(1),
          );
          if (scenario == 'same-session-refresh') {
            expect(
              bearer,
              isNot('Bearer ${loop.client.auth.currentSession!.accessToken}'),
            );
          }
        },
      );
    }
  });
}
