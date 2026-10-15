import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> sessionBody() => {
  'user': {
    'id': '00000000-0000-4000-8000-000000000001',
    'email': 'owner@example.test',
    'role': 'owner',
    'sessionId': 'public-session-one',
    'permissions': ['overview.read', 'account.manage', 'admin_users.read'],
  },
  'expiresAt': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
};

void main() {
  test(
    'session authority ignores expiry and permission order, not access changes',
    () {
      final first = CloudflareAdminUser.parse(sessionBody());
      final reordered = sessionBody();
      (reordered['user'] as Map)['permissions'] = first.permissions.reversed
          .toList();
      reordered['expiresAt'] = DateTime.now()
          .add(const Duration(hours: 2))
          .toIso8601String();
      expect(
        CloudflareAdminUser.parse(reordered).authorityKey,
        first.authorityKey,
      );
      (reordered['user'] as Map)['permissions'] = ['overview.read'];
      expect(
        CloudflareAdminUser.parse(reordered).authorityKey,
        isNot(first.authorityKey),
      );
    },
  );

  test(
    'same-cookie capability change fences pending authenticated responses',
    () async {
      final pending = Completer<http.Response>();
      var permissions = sessionBody()['user'] as Map;
      final service = CloudflareAdminSession(
        MockClient((request) async {
          if (request.url.path.endsWith('/auth/session')) {
            return http.Response(
              jsonEncode({...sessionBody(), 'user': permissions}),
              200,
            );
          }
          return pending.future;
        }),
        origin: Uri.parse('https://admin.example.test/'),
      );
      addTearDown(service.dispose);
      await service.refresh();
      final request = service.request('team', authenticated: true);
      final rejected = expectLater(
        request,
        throwsA(isA<CloudflareAdminRequestException>()),
      );
      permissions = {
        ...permissions,
        'permissions': ['overview.read'],
      };
      await service.refresh();
      pending.complete(http.Response('{"members":[]}', 200));
      await rejected;
      expect(service.user?.permissions, ['overview.read']);
    },
  );

  test(
    'failed authority check fences earlier responses after recovery',
    () async {
      final pending = Completer<http.Response>();
      var sessionReads = 0;
      final service = CloudflareAdminSession(
        MockClient((request) async {
          if (request.url.path.endsWith('/auth/session')) {
            if (++sessionReads == 2) {
              throw http.ClientException('Authority unavailable');
            }
            return http.Response(jsonEncode(sessionBody()), 200);
          }
          return pending.future;
        }),
        origin: Uri.parse('https://admin.example.test/'),
      );
      addTearDown(service.dispose);
      await service.refresh();
      final request = service.request('team', authenticated: true);
      final rejected = expectLater(
        request,
        throwsA(isA<CloudflareAdminRequestException>()),
      );
      await service.refresh();
      expect(service.user, isNull);
      expect(service.state.hasError, isTrue);
      await service.refresh();
      expect(service.user, isNotNull);
      pending.complete(http.Response('{"members":[]}', 200));
      await rejected;
    },
  );

  test('identical-authority refresh keeps pending request current', () async {
    final pending = Completer<http.Response>();
    final service = CloudflareAdminSession(
      MockClient(
        (request) async => request.url.path.endsWith('/auth/session')
            ? http.Response(jsonEncode(sessionBody()), 200)
            : pending.future,
      ),
      origin: Uri.parse('https://admin.example.test/'),
    );
    addTearDown(service.dispose);
    await service.refresh();
    final request = service.request('team', authenticated: true);
    await service.refresh();
    pending.complete(http.Response('{"members":[]}', 200));
    expect(await request, {'members': []});
  });

  test(
    'receipt review reason is bounded and confined to its audit header',
    () async {
      var sends = 0;
      final service = CloudflareAdminSession(
        MockClient((request) async {
          sends++;
          expect(request.method, 'GET');
          expect(
            request.headers['X-Collect-Review-Reason'],
            'Review member receipt',
          );
          expect(request.url.query, isEmpty);
          return http.Response('{"ok":true}', 200);
        }),
        origin: Uri.parse('https://admin.example.test/'),
      );
      addTearDown(service.dispose);
      for (final reason in [
        'short',
        'Review\r\nInjected: header',
        'x' * 1001,
      ]) {
        await expectLater(
          service.request(
            'gateway/member-receipts/one/content',
            reviewReason: reason,
          ),
          throwsArgumentError,
        );
      }
      expect(sends, 0);
      await service.request(
        'gateway/member-receipts/one/content',
        reviewReason: ' Review member receipt ',
      );
      expect(sends, 1);
    },
  );

  test(
    'operating PATCH preserves reason, version and idempotency key',
    () async {
      final service = CloudflareAdminSession(
        MockClient((request) async {
          expect(request.method, 'PATCH');
          expect(request.url.path, '/api/admin/operations/groups/group-one');
          expect(request.headers['Idempotency-Key'], 'request-12345');
          expect(jsonDecode(request.body), {
            'expected_version': 3,
            'reason': 'Reviewed group details',
            'title': 'New title',
          });
          return http.Response('{"status":"succeeded","version":4}', 200);
        }),
        origin: Uri.parse('https://admin.example.test/'),
      );
      addTearDown(service.dispose);
      expect(
        (await service.request(
          'operations/groups/group-one',
          method: 'PATCH',
          idempotencyKey: 'request-12345',
          body: {
            'expected_version': 3,
            'reason': 'Reviewed group details',
            'title': 'New title',
          },
        ))['version'],
        4,
      );
    },
  );

  test(
    'rejected operating request is known; server failure is uncertain and never retried',
    () async {
      var status = 409;
      var sends = 0;
      final service = CloudflareAdminSession(
        MockClient((_) async {
          sends++;
          return http.Response(
            '{"error":"version_conflict","message":"Changed"}',
            status,
          );
        }),
        origin: Uri.parse('https://admin.example.test/'),
      );
      addTearDown(service.dispose);
      await expectLater(
        service.request(
          'operations/groups',
          body: {},
          idempotencyKey: 'request-12345',
        ),
        throwsA(
          isA<CloudflareAdminRequestException>()
              .having((error) => error.code, 'code', 'version_conflict')
              .having((error) => error.outcomeUnknown, 'outcomeUnknown', false),
        ),
      );
      status = 503;
      await expectLater(
        service.request(
          'operations/groups',
          body: {},
          idempotencyKey: 'request-12345',
        ),
        throwsA(
          isA<CloudflareAdminRequestException>().having(
            (error) => error.outcomeUnknown,
            'outcomeUnknown',
            true,
          ),
        ),
      );
      expect(sends, 2);
    },
  );

  test(
    'broken connection and invalid accepted response preserve unknown mutation outcome',
    () async {
      var sends = 0;
      final service = CloudflareAdminSession(
        MockClient((_) async {
          if (++sends == 1) throw http.ClientException('Connection lost');
          return http.Response('<html>proxy</html>', 200);
        }),
        origin: Uri.parse('https://admin.example.test/'),
      );
      addTearDown(service.dispose);
      for (var attempt = 0; attempt < 2; attempt++) {
        await expectLater(
          service.request(
            'operations/groups',
            body: {},
            idempotencyKey: 'request-12345',
          ),
          throwsA(
            isA<CloudflareAdminRequestException>().having(
              (error) => error.outcomeUnknown,
              'outcomeUnknown',
              true,
            ),
          ),
        );
      }
      expect(sends, 2);
    },
  );

  const conflictMessages = {
    'account_changed': 'This account changed. Refresh and try again.',
    'state_conflict':
        'This record or its related state does not meet the requirements for this request. Refresh the details before continuing.',
    'idempotency_conflict':
        'This request reference was already used for different content. Check the original request before making another change.',
    'request_pending':
        'The original request is still pending. Check its receipt before continuing.',
    'version_conflict':
        'The request conflicts with the current state. Refresh the details and check the original request before continuing.',
    'future_conflict_code':
        'The request conflicts with the current state. Refresh the details and check the original request before continuing.',
  };
  for (final entry in conflictMessages.entries) {
    for (final nested in const [false, true]) {
      test(
        '409 ${entry.key} ${nested ? 'nested' : 'string'} code gives safe contextual guidance without ending the session',
        () async {
          var sends = 0;
          const serverMessage =
              'RAW CONSTRAINT private@example.test password-token-secret';
          final service = CloudflareAdminSession(
            MockClient((request) async {
              if (request.url.path.endsWith('/auth/session')) {
                return http.Response(jsonEncode(sessionBody()), 200);
              }
              sends++;
              expect(request.method, 'PATCH');
              expect(
                request.headers['Idempotency-Key'],
                'original-request-key',
              );
              return http.Response(
                jsonEncode({
                  'error': nested
                      ? {'code': entry.key, 'message': serverMessage}
                      : entry.key,
                  'message': serverMessage,
                }),
                409,
              );
            }),
            origin: Uri.parse('https://admin.example.test/'),
          );
          addTearDown(service.dispose);
          await service.refresh();
          final authority = service.user!.authorityKey;
          await expectLater(
            service.request(
              'operations/payees/payee-one',
              method: 'PATCH',
              body: {'status': 'inactive'},
              idempotencyKey: 'original-request-key',
              authenticated: true,
            ),
            throwsA(
              isA<CloudflareAdminRequestException>()
                  .having(
                    (error) => error.message,
                    'contextual message',
                    entry.value,
                  )
                  .having(
                    (error) => error.toString(),
                    'safe display',
                    entry.value,
                  )
                  .having((error) => error.statusCode, 'status', 409)
                  .having((error) => error.code, 'structured code', entry.key)
                  .having(
                    (error) => error.outcomeUnknown,
                    'known rejection',
                    false,
                  ),
            ),
          );
          expect(service.user!.authorityKey, authority);
          expect(
            sends,
            1,
            reason: 'A conflict must not retry the original mutation.',
          );
        },
      );
    }
  }
  test(
    '409 missing or malformed error code uses neutral conflict guidance and hides raw server details',
    () async {
      for (final error in [
        null,
        123,
        {'code': 123, 'message': 'SQL private token'},
        {'details': 'private-account-data'},
      ]) {
        final service = CloudflareAdminSession(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'error': error,
                'message': 'This account changed for private@example.test',
              }),
              409,
            ),
          ),
          origin: Uri.parse('https://admin.example.test/'),
        );
        addTearDown(service.dispose);
        await expectLater(
          service.request(
            'operations/payees/payee-one',
            method: 'PATCH',
            body: {'status': 'inactive'},
          ),
          throwsA(
            isA<CloudflareAdminRequestException>()
                .having(
                  (value) => value.message,
                  'neutral conflict',
                  conflictMessages['future_conflict_code'],
                )
                .having((value) => value.code, 'unverified code', isNull)
                .having((value) => value.statusCode, 'status', 409)
                .having(
                  (value) => value.outcomeUnknown,
                  'known rejection',
                  false,
                ),
          ),
        );
      }
    },
  );
  for (final record in const [
    ('GET', 403, 'You do not have permission to view these records.', false),
    ('PATCH', 403, 'You do not have permission to make this change.', false),
    (
      'GET',
      503,
      'The records could not be loaded. Refresh and try again.',
      false,
    ),
    (
      'POST',
      503,
      'The request was not confirmed. Refresh before trying again.',
      true,
    ),
    (
      'GET',
      404,
      'The records could not be loaded. Refresh and try again.',
      false,
    ),
    (
      'PATCH',
      404,
      'The request was not confirmed. Refresh before trying again.',
      false,
    ),
  ]) {
    test(
      '${record.$1} ${record.$2} distinguishes view/change guidance and preserves outcome classification',
      () async {
        var sends = 0;
        final service = CloudflareAdminSession(
          MockClient((request) async {
            if (request.url.path.endsWith('/auth/session')) {
              return http.Response(jsonEncode(sessionBody()), 200);
            }
            sends++;
            return http.Response(
              jsonEncode({
                'error': {
                  'code': 'state_conflict',
                  'message': 'Private provider data must not be displayed',
                },
                'message': 'Raw SQL key',
              }),
              record.$2,
            );
          }),
          origin: Uri.parse('https://admin.example.test/'),
        );
        addTearDown(service.dispose);
        await service.refresh();
        final authority = service.user!.authorityKey;
        await expectLater(
          service.request(
            'operations/payees/payee-one',
            method: record.$1,
            body: record.$1 == 'GET' ? null : {'status': 'inactive'},
            authenticated: true,
          ),
          throwsA(
            isA<CloudflareAdminRequestException>()
                .having(
                  (error) => error.message,
                  'request-context guidance',
                  record.$3,
                )
                .having((error) => error.statusCode, 'status', record.$2)
                .having(
                  (error) => error.code,
                  'structured code',
                  'state_conflict',
                )
                .having((error) => error.outcomeUnknown, 'outcome', record.$4),
          ),
        );
        expect(sends, 1);
        expect(service.user!.authorityKey, authority);
      },
    );
  }

  test(
    'unsafe request escapes and malformed idempotency key never send',
    () async {
      var sends = 0;
      final service = CloudflareAdminSession(
        MockClient((_) async {
          sends++;
          return http.Response('{}', 200);
        }),
        origin: Uri.parse('https://admin.example.test/'),
      );
      addTearDown(service.dispose);
      for (final path in ['../../elsewhere', '../auth/login']) {
        await expectLater(
          service.request(path, body: {}, idempotencyKey: 'bad key'),
          throwsArgumentError,
        );
      }
      expect(sends, 0);
    },
  );

  test('out-of-order refresh cannot resurrect an ended session', () async {
    final first = Completer<http.Response>();
    final second = Completer<http.Response>();
    var count = 0;
    final service = CloudflareAdminSession(
      MockClient((_) => ++count == 1 ? first.future : second.future),
      origin: Uri.parse('https://admin.example.test/'),
    );
    addTearDown(service.dispose);
    final older = service.refresh();
    final newer = service.refresh();
    second.complete(http.Response('{"user":null,"expiresAt":null}', 200));
    await newer;
    first.complete(http.Response(jsonEncode(sessionBody()), 200));
    await older;
    expect(service.user, isNull);
  });

  test(
    'failed logout blocks access and refresh until logout is confirmed',
    () async {
      var logoutWorks = false;
      var sessionReads = 0;
      final service = CloudflareAdminSession(
        MockClient((request) async {
          if (request.url.path.endsWith('/logout')) {
            return logoutWorks
                ? http.Response('{"ok":true}', 200)
                : http.Response('{"error":"unavailable"}', 503);
          }
          sessionReads++;
          return http.Response(jsonEncode(sessionBody()), 200);
        }),
        origin: Uri.parse('https://admin.example.test/'),
      );
      addTearDown(service.dispose);
      await service.refresh();
      await expectLater(
        service.signOut(),
        throwsA(isA<AdminAccountException>()),
      );
      expect(service.user, isNull);
      expect(service.logoutUnconfirmed, isTrue);
      await service.refresh();
      expect(sessionReads, 1);
      logoutWorks = true;
      await service.signOut();
      expect(service.logoutUnconfirmed, isFalse);
      expect(service.user, isNull);
    },
  );

  test(
    'password sign-in uses only same-origin Cloudflare account endpoints',
    () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        expect(request.url.origin, 'https://admin.example.test');
        paths.add(request.url.path);
        if (request.url.path.endsWith('/login')) {
          expect(jsonDecode(request.body), {
            'email': 'owner@example.test',
            'password': 'test-password-123',
          });
          return http.Response('{"ok":true}', 200);
        }
        return http.Response(jsonEncode(sessionBody()), 200);
      });
      final service = CloudflareAdminSession(
        client,
        origin: Uri.parse('https://admin.example.test/'),
      );
      addTearDown(service.dispose);
      await service.signIn('owner@example.test', 'test-password-123');
      expect(service.user?.role, AdminAccountRole.owner);
      expect(paths, ['/api/admin/auth/login', '/api/admin/auth/session']);
    },
  );

  test('in-flight account response cannot survive logout', () async {
    final pending = Completer<http.Response>();
    final service = CloudflareAdminSession(
      MockClient((_) => pending.future),
      origin: Uri.parse('https://admin.example.test/'),
    );
    addTearDown(service.dispose);
    final request = service.request('team');
    final check = expectLater(request, throwsA(isA<AdminAccountException>()));
    service.clear();
    pending.complete(http.Response('{"members":[]}', 200));
    await check;
    expect(service.user, isNull);
  });

  test('malformed or expired session cannot open admin access', () async {
    final expired = sessionBody()..['expiresAt'] = '2020-01-01T00:00:00Z';
    final service = CloudflareAdminSession(
      MockClient((_) async => http.Response(jsonEncode(expired), 200)),
      origin: Uri.parse('https://admin.example.test/'),
    );
    addTearDown(service.dispose);
    await service.refresh();
    expect(service.user, isNull);
  });

  test('password setup requires an explicit server acknowledgement', () async {
    final service = CloudflareAdminSession(
      MockClient((_) async => http.Response('{}', 200)),
      origin: Uri.parse('https://admin.example.test/'),
    );
    addTearDown(service.dispose);
    await expectLater(
      CloudflareAdminAccountApi(service).completePasswordSetup(
        'one-time-secret',
        'test-password-123',
        invite: true,
      ),
      throwsA(isA<AdminAccountException>()),
    );
  });

  test('unauthorized responses invalidate prior access', () async {
    var authorized = true;
    final service = CloudflareAdminSession(
      MockClient(
        (_) async => authorized
            ? http.Response(jsonEncode(sessionBody()), 200)
            : http.Response('{"error":"unauthenticated"}', 401),
      ),
      origin: Uri.parse('https://admin.example.test/'),
    );
    addTearDown(service.dispose);
    await service.refresh();
    expect(service.user, isNotNull);
    authorized = false;
    await expectLater(
      service.request('team', authenticated: true),
      throwsA(isA<AdminAccountException>()),
    );
    expect(service.user, isNull);
  });
}
