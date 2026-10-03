import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_operator_approval.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_action_session_test.dart' as sdk;

Map<String, dynamic> _approval({bool approved = false, bool role = false}) => {
  'contract_version': 1,
  'user_id': sdk.target,
  'provider': 'email',
  'mode': 'email',
  'identity_masked': 'o***@***',
  'approved_at': approved ? '2026-09-30T08:00:00Z' : null,
  'expires_at': null,
  'status': approved ? 'approved' : 'not_approved',
  'approved': approved,
  'role_granted': role,
  'admin_access': approved && role,
  'access_status': approved && role
      ? 'active'
      : role
      ? 'approval_required'
      : approved
      ? 'approved'
      : 'revoked',
};

void main() {
  for (final approved in [false, true]) {
    for (final role in [false, true]) {
      test(
        'operator approval separates approval=$approved from role=$role',
        () {
          final value = AdminOperatorApproval.parse(
            _approval(approved: approved, role: role),
            targetUserId: sdk.target,
          );
          expect(value.approved, approved);
          expect(value.roleGranted, role);
          expect(value.adminAccess, approved && role);
          expect(value.legacyControls, isFalse);
        },
      );
    }
  }
  for (final key in _approval().keys) {
    test('operator approval requires exact nullable field $key', () {
      expect(
        () => AdminOperatorApproval.parse(
          _approval()..remove(key),
          targetUserId: sdk.target,
        ),
        throwsFormatException,
      );
    });
  }
  for (final (key, value) in <(String, Object?)>[
    ('contract_version', 2),
    ('user_id', sdk.actor),
    ('provider', 'sms'),
    ('mode', 'unknown'),
    ('identity_masked', 'operator@collect.example'),
    ('status', 'unknown'),
    ('approved', true),
    ('role_granted', 1),
    ('admin_access', true),
    ('access_status', 'active'),
    ('approved_at', '0000-01-01T00:00:00Z'),
    ('approved_at', '2026-02-30T08:00:00Z'),
    ('approved_at', '2026-09-30T08:00:00'),
    ('private_context', 'PRIVATE_CANARY'),
  ]) {
    test('operator approval rejects malformed or substituted $key=$value', () {
      expect(
        () => AdminOperatorApproval.parse({
          ..._approval(),
          key: value,
        }, targetUserId: sdk.target),
        throwsFormatException,
      );
    });
  }
  test(
    'operator approval accepts valid UTC calendar and rejects non-forward expiry',
    () {
      final source = {
        ..._approval(approved: true),
        'expires_at': '2026-09-30T08:15:00+00:00',
      };
      final value = AdminOperatorApproval.parse(
        source,
        targetUserId: sdk.target,
      );
      expect(value.expiresAt, DateTime.utc(2026, 9, 30, 8, 15));
      expect(
        () => AdminOperatorApproval.parse({
          ...source,
          'expires_at': source['approved_at'],
        }, targetUserId: sdk.target),
        throwsFormatException,
      );
    },
  );
  test(
    'operator approval disables legacy controls after email-mode transition',
    () {
      final legacy = {
        ..._approval(),
        'provider': 'whatsapp',
        'mode': 'transition',
        'identity_masked': '+250***4002',
      };
      expect(
        AdminOperatorApproval.parse(
          legacy,
          targetUserId: sdk.target,
        ).legacyControls,
        isTrue,
      );
      final disabled = {
        ...legacy,
        'mode': 'email',
        'status': 'legacy_disabled',
      };
      expect(
        AdminOperatorApproval.parse(
          disabled,
          targetUserId: sdk.target,
        ).legacyControls,
        isFalse,
      );
      expect(
        () => AdminOperatorApproval.parse({
          ...disabled,
          'approved': true,
          'status': 'approved',
        }, targetUserId: sdk.target),
        throwsFormatException,
      );
    },
  );

  group('operator approval actual SDK', () {
    late SupabaseClient client;
    late AdminRepository repository;
    late Future<http.Response> Function(http.Request) respond;
    final requests = <http.Request>[];
    Future<void> session(String id) => client.auth.verifyOTP(
      email: 'operator@collect.example',
      token: id,
      type: OtpType.email,
    );
    setUp(() async {
      requests.clear();
      respond = (_) async => sdk.response({});
      client = SupabaseClient(
        'https://synthetic.invalid',
        'synthetic-publishable',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/verify')) {
            return sdk.response(
              sdk.authReceipt(jsonDecode(request.body)['token'] as String, '0'),
            );
          }
          if (request.url.path.endsWith('/logout')) {
            return sdk.response({});
          }
          requests.add(request);
          final result = await respond(request);
          return http.Response.bytes(
            result.bodyBytes,
            result.statusCode,
            headers: result.headers,
            request: request,
          );
        }),
      );
      await session('approval-a');
      repository = AdminRepository(client);
    });
    tearDown(() => client.dispose());

    Future<void> drain(WidgetTester tester) async {
      for (var index = 0; index < 8; index++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<void> panel(
      WidgetTester tester,
      Future<void> Function(ProviderContainer) run,
    ) async {
      final container = ProviderContainer(
        overrides: [supabaseClientProvider.overrideWithValue(client)],
      );
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const Scaffold(
                body: SingleChildScrollView(
                  child: AdminPlatformAccessPanel(userId: sdk.target),
                ),
              ),
            ),
          ),
        );
        await drain(tester);
        await run(container);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      }
    }

    Future<void> fill(WidgetTester tester, String label) async {
      await tester.tap(find.widgetWithText(FilledButton, label).first);
      await tester.pumpAndSettle();
      if (label == 'Approve email') {
        await tester.enterText(
          find.widgetWithText(TextField, 'Verified operator email'),
          ' OPERATOR@Collect.Example ',
        );
      }
      await tester.enterText(
        find.widgetWithText(TextField, 'Reason'),
        'Reviewed synthetic account',
      );
      await tester.pump();
    }

    for (final scenario in [
      'success',
      'cancel',
      'invalid',
      'denied',
      'uncertain',
      'permission-loss',
      'late-session',
    ]) {
      testWidgets('email approval production SDK panel $scenario', (
        tester,
      ) async {
        var approved = false;
        var canManage = true;
        final entered = Completer<void>(), release = Completer<void>();
        respond = (request) async {
          if (request.url.path.endsWith('/admin_current_user')) {
            return sdk.response({
              'user_id': sdk.actor,
              'display_name': 'Synthetic operator',
              'phone_masked': null,
              'roles': ['admin'],
              'permissions': [
                'admin_users.read',
                if (canManage) 'admin_users.manage',
              ],
            });
          }
          if (request.url.path.endsWith('/admin_get_operator_approval_v1')) {
            return sdk.response(_approval(approved: approved));
          }
          if (request.url.path.endsWith('/admin_approve_email_operator_v1')) {
            if (scenario == 'denied') {
              return sdk.response({
                'code': '42501',
                'message': 'PRIVATE_CANARY',
              }, 403);
            }
            if (scenario == 'uncertain') {
              return sdk.response({'ok': true});
            }
            if (scenario == 'late-session') {
              entered.complete();
              await release.future;
            }
            approved = true;
            return sdk.response({
              'ok': true,
              'status': 'approved',
              'user_id': sdk.target,
            });
          }
          throw StateError(
            'Unexpected synthetic approval path: ${request.url.path}',
          );
        };
        await panel(tester, (container) async {
          expect(find.text('Approve email'), findsOneWidget);
          expect(find.text('Approve WhatsApp'), findsNothing);
          final token = client.auth.currentSession!.accessToken;
          await fill(tester, 'Approve email');
          final submit = find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(FilledButton, 'Approve email'),
          );
          if (scenario == 'cancel') {
            await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
          } else if (scenario == 'invalid') {
            await tester.enterText(
              find.widgetWithText(TextField, 'Reason'),
              'short',
            );
            await tester.pump();
            expect(tester.widget<FilledButton>(submit).onPressed, isNull);
            await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
          } else if (scenario == 'permission-loss') {
            canManage = false;
            container.invalidate(adminIdentityProvider);
            await drain(tester);
            expect(find.byType(AlertDialog), findsNothing);
          } else {
            await tester.tap(submit);
            if (scenario == 'late-session') {
              await tester.runAsync(() => entered.future);
              await tester.runAsync(() => session('approval-b'));
              await tester.runAsync(() => session('approval-a'));
              release.complete();
            }
          }
          await drain(tester);
          final writes = requests
              .where(
                (r) => r.url.path.endsWith('/admin_approve_email_operator_v1'),
              )
              .toList();
          final sent = !{
            'cancel',
            'invalid',
            'permission-loss',
          }.contains(scenario);
          expect(writes, hasLength(sent ? 1 : 0));
          if (sent) {
            expect(jsonDecode(writes.single.body), {
              'p_user_id': sdk.target,
              'p_email': 'operator@collect.example',
              'p_reason': 'Reviewed synthetic account',
            });
            expect(writes.single.headers['Authorization'], 'Bearer $token');
          }
          expect(
            find.text('Email approved. A new sign-in is required.'),
            scenario == 'success' ? findsOneWidget : findsNothing,
          );
          expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
          if (scenario == 'denied' || scenario == 'uncertain') {
            expect(
              find.text(
                'Change not confirmed. Refresh access before trying again.',
              ),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
        });
      });
    }

    testWidgets(
      'email revocation production SDK panel selects exact operation',
      (tester) async {
        var approved = true;
        respond = (request) async {
          if (request.url.path.endsWith('/admin_current_user')) {
            return sdk.response({
              'user_id': sdk.actor,
              'display_name': 'Synthetic operator',
              'phone_masked': null,
              'roles': ['admin'],
              'permissions': ['admin_users.read', 'admin_users.manage'],
            });
          }
          if (request.url.path.endsWith('/admin_get_operator_approval_v1')) {
            return sdk.response(_approval(approved: approved));
          }
          if (request.url.path.endsWith('/admin_revoke_email_operator_v1')) {
            approved = false;
            return sdk.response({
              'ok': true,
              'status': 'revoked',
              'user_id': sdk.target,
            });
          }
          throw StateError(
            'Unexpected synthetic revoke path: ${request.url.path}',
          );
        };
        await panel(tester, (_) async {
          final token = client.auth.currentSession!.accessToken;
          await tester.tap(
            find.widgetWithText(OutlinedButton, 'Revoke approval'),
          );
          await tester.pumpAndSettle();
          expect(
            find.widgetWithText(TextField, 'Verified operator email'),
            findsNothing,
          );
          await tester.enterText(
            find.widgetWithText(TextField, 'Reason'),
            'Reviewed synthetic account',
          );
          await tester.pump();
          await tester.tap(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.widgetWithText(FilledButton, 'Revoke approval'),
            ),
          );
          await drain(tester);
          final writes = requests
              .where(
                (r) => r.url.path.endsWith('/admin_revoke_email_operator_v1'),
              )
              .toList();
          expect(writes, hasLength(1));
          expect(jsonDecode(writes.single.body), {
            'p_user_id': sdk.target,
            'p_reason': 'Reviewed synthetic account',
          });
          expect(writes.single.headers['Authorization'], 'Bearer $token');
          expect(
            find.text('Approval and platform access revoked.'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        });
      },
    );

    for (final (rpc, params, ack) in [
      (
        'admin_get_operator_approval_v1',
        <String, dynamic>{'p_user_id': sdk.target},
        _approval(),
      ),
      (
        'admin_approve_email_operator_v1',
        <String, dynamic>{
          'p_user_id': sdk.target,
          'p_email': 'operator@collect.example',
          'p_reason': 'Reviewed synthetic account',
        },
        <String, dynamic>{
          'ok': true,
          'status': 'approved',
          'user_id': sdk.target,
        },
      ),
      (
        'admin_revoke_email_operator_v1',
        <String, dynamic>{
          'p_user_id': sdk.target,
          'p_reason': 'Reviewed synthetic account',
        },
        <String, dynamic>{
          'ok': true,
          'status': 'revoked',
          'user_id': sdk.target,
        },
      ),
    ]) {
      test(
        '$rpc pins current Bearer exact target request and receipt',
        () async {
          final bearer = client.auth.currentSession!.accessToken;
          respond = (_) async => sdk.response(ack);
          expect(await repository.action(rpc, params), ack);
          expect(requests, hasLength(1));
          expect(requests.single.method, 'POST');
          expect(requests.single.url.path, '/rest/v1/rpc/$rpc');
          expect(requests.single.headers['Authorization'], 'Bearer $bearer');
          expect(jsonDecode(requests.single.body), params);
        },
      );
      for (final corrupt in ['missing', 'wrong-target', 'private-extra']) {
        test(
          '$rpc rejects $corrupt receipt without false acceptance',
          () async {
            respond = (_) async => sdk.response(
              corrupt == 'missing'
                  ? {}
                  : {
                      ...ack,
                      if (corrupt == 'wrong-target') 'user_id': sdk.actor,
                      if (corrupt == 'private-extra')
                        'private_context': 'PRIVATE_CANARY',
                    },
            );
            await expectLater(
              repository.action(rpc, params),
              throwsFormatException,
            );
            expect(requests, hasLength(1));
          },
        );
      }
      for (final failure in ['permission', '503', 'network']) {
        test('$rpc $failure is one SDK dispatch with no fallback', () async {
          respond = (_) async {
            if (failure == 'network') {
              throw http.ClientException('Synthetic lost response');
            }
            return sdk.response({
              'code': failure == 'permission'
                  ? '42501'
                  : 'synthetic_unavailable',
              'message': 'Synthetic service denial',
            }, failure == 'permission' ? 403 : 503);
          };
          await expectLater(
            repository.action(rpc, params),
            throwsA(
              failure == 'network'
                  ? isA<http.ClientException>()
                  : isA<PostgrestException>(),
            ),
          );
          expect(requests, hasLength(1));
        });
      }
      for (final back in [false, true]) {
        test('$rpc suppresses departed session response A-B-A=$back', () async {
          final entered = Completer<void>(), release = Completer<void>();
          respond = (_) async {
            entered.complete();
            await release.future;
            return sdk.response(ack);
          };
          final pending = repository.action(rpc, params);
          final rejected = expectLater(
            pending,
            throwsA(isA<AdminSessionChanged>()),
          );
          await entered.future;
          await session('approval-b');
          if (back) {
            await session('approval-a');
          }
          release.complete();
          await rejected;
          expect(requests, hasLength(1));
        });
      }
      test('$rpc signed out cannot dispatch', () async {
        await client.auth.signOut();
        await expectLater(
          repository.action(rpc, params),
          throwsA(isA<AdminSessionChanged>()),
        );
        expect(requests, isEmpty);
      });
    }
  });
}
