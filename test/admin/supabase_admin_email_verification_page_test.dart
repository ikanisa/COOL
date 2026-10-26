import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/cloudflare_admin_email_verification_page.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../core/supabase_backend_test.dart' as fixtures;

const _sid = '00000000-0000-4000-8000-000000000001';
const _challenge = '00000000-0000-4000-8000-000000000002';
http.Response _json(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status);

void main() {
  for (final check in [
    'fresh return',
    'idle background',
    'new unknown send',
    'unknown background',
  ]) {
    testWidgets(check, (tester) async {
      var now = DateTime.now().toUtc();
      Object? proof;
      var sends = 0, verifies = 0, taskReads = 0, mutations = 0;
      final backgroundSend = Completer<http.Response>();
      final session = CloudflareAdminSession(
        MockClient((request) async {
          if (request.url.path.endsWith('/auth/session')) {
            return _json({
              'user': {
                'id': _challenge,
                'email': 'info@ikanisa.com',
                'role': 'owner',
                'sessionId': _sid,
                'permissions': ['account.manage'],
                'assuranceLevel': 1,
                'mfaAt': null,
              },
              'expiresAt': DateTime.now()
                  .toUtc()
                  .add(const Duration(hours: 1))
                  .toIso8601String(),
              'ownerEmail': 'info@ikanisa.com',
              'csrfToken': 'a' * 64,
            });
          }
          if (request.url.path.endsWith('/auth/email/request')) {
            sends++;
            if (sends == 2 &&
                const {
                  'new unknown send',
                  'unknown background',
                }.contains(check)) {
              return _json({'error': 'admin_email_operation_unknown'}, 503);
            }
            if (sends == 3 && check == 'unknown background') {
              return backgroundSend.future;
            }
            return _json({
              'challenge_id': _challenge,
              'retry_after': 60,
              'expires_in': 300,
              'delivery_status': 'accepted',
            }, 202);
          }
          if (request.url.path.endsWith('/auth/email/verify')) {
            verifies++;
            proof = DateTime.now()
                .toUtc()
                .subtract(const Duration(seconds: 1))
                .toIso8601String();
          }
          return _json({
            'contractVersion': 1,
            'sessionId': _sid,
            'emailVerifiedAt': proof,
          });
        }),
        origin: Uri.parse('https://admin.collect.ikanisa.com'),
        environment: fixtures.environment(),
      );
      await session.refresh();
      final router = GoRouter(
        initialLocation: '/admin/payments',
        routes: [
          GoRoute(
            path: '/admin/payments',
            builder: (_, _) => _FreshTask(
              onRead: () => taskReads++,
              onMutation: () => mutations++,
            ),
          ),
          GoRoute(
            path: '/admin/security/verify-email',
            builder: (_, state) => Scaffold(
              body: CloudflareAdminEmailVerificationPage(
                returnTo: state.uri.queryParameters['returnTo'],
              ),
            ),
          ),
          GoRoute(
            path: '/admin/security',
            builder: (_, _) => const Scaffold(body: Text('Account security')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cloudflareAdminSessionProvider.overrideWith((ref) => session),
            cloudflareAdminEmailVerificationClockProvider.overrideWithValue(
              () => now,
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'sensitive draft');
      await tester.tap(find.text('Verify email'));
      await tester.pumpAndSettle();
      if (check == 'idle background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
      }
      await tester.tap(find.text('Send email code'));
      await tester.pumpAndSettle();
      expect(sends, 1);
      if (const {'new unknown send', 'unknown background'}.contains(check)) {
        now = now.add(const Duration(seconds: 301));
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.text('Request a new code'));
        await tester.pumpAndSettle();
        expect(sends, 2);
        await tester.tap(find.text('Check verification'));
        await tester.pumpAndSettle();
        final send = tester.widget<TextButton>(
          find.widgetWithText(TextButton, 'Send email code'),
        );
        expect(
          send.onPressed,
          isNull,
          reason:
              'Old expired receipt must not shorten the NEW unknown SEND deadline.',
        );
        now = now.add(const Duration(seconds: 301));
        await tester.pump(const Duration(seconds: 1));
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Send email code'),
              )
              .onPressed,
          isNotNull,
        );
        expect(verifies, 0);
        if (check == 'unknown background') {
          await tester.tap(find.text('Send email code'));
          await tester.pump();
          expect(sends, 3);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          await tester.pump();
          backgroundSend.complete(
            _json({'error': 'admin_email_operation_unknown'}, 503),
          );
          await tester.pump();
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Check verification'));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<TextButton>(
                  find.widgetWithText(TextButton, 'Send email code'),
                )
                .onPressed,
            isNull,
            reason:
                'A third send backgrounded in flight needs its own fresh uncertainty deadline.',
          );
          expect(sends, 3);
        }
      } else {
        await tester.enterText(find.byType(TextField), '123456');
        await tester.tap(find.widgetWithText(FilledButton, 'Verify email'));
        await tester.pumpAndSettle();
        expect(verifies, 1);
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(taskReads, 2);
        expect(find.text('sensitive draft'), findsNothing);
        expect(mutations, 0);
        expect(session.user!.assuranceLevel, 1);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

class _FreshTask extends StatefulWidget {
  const _FreshTask({required this.onRead, required this.onMutation});
  final VoidCallback onRead, onMutation;
  @override
  State<_FreshTask> createState() => _FreshTaskState();
}

class _FreshTaskState extends State<_FreshTask> {
  final draft = TextEditingController();
  @override
  void initState() {
    super.initState();
    widget.onRead();
  }

  @override
  void dispose() {
    draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        TextField(controller: draft),
        TextButton(
          onPressed: () => context.go(
            Uri(
              path: '/admin/security/verify-email',
              queryParameters: {'returnTo': '/admin/payments'},
            ).toString(),
          ),
          child: const Text('Verify email'),
        ),
        FilledButton(
          onPressed: widget.onMutation,
          child: const Text('Confirm change'),
        ),
      ],
    ),
  );
}
