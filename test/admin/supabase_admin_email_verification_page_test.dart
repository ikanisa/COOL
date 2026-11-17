import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/cloudflare_admin_email_verification_page.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_types.dart';
import 'package:collect_app/core/cloudflare/collect_turnstile.dart';
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
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
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
            proof = now.subtract(const Duration(seconds: 1)).toIso8601String();
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
  for (final check in [
    'owned challenge focus returns',
    'real inactive before dispatch',
    'hidden before dispatch',
    'paused before dispatch',
    'detached before dispatch',
    'window blur while challenge already inactive',
    'last boundary has no foreground',
    'route exit before dispatch',
    'authority exit before dispatch',
    'logout before dispatch',
    'manual challenge cancel',
    'paused after dispatch',
  ]) {
    testWidgets(check, (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      var now = DateTime.now().toUtc();
      final challenge = _OwnedChallenge();
      var sends = 0;
      final dispatched = Completer<http.Response>();
      final session = CloudflareAdminSession(
        MockClient((request) async {
          if (request.url.path.endsWith('/auth/session')) {
            return _json({
              'user': {
                'id': _challenge,
                'email': 'owner@synthetic.invalid',
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
              'ownerEmail': 'owner@synthetic.invalid',
              'csrfToken': 'a' * 64,
            });
          }
          if (request.url.path.endsWith('/auth/email/request')) {
            sends++;
            expect(
              jsonDecode(request.body)['captcha_token'],
              'SYNTHETIC_SECURITY_CANDIDATE',
            );
            if (check == 'paused after dispatch') return dispatched.future;
            return _json({
              'challenge_id': _challenge,
              'retry_after': 60,
              'expires_in': 1800,
              'delivery_status': 'accepted',
            }, 202);
          }
          if (request.url.path.endsWith('/auth/logout')) {
            return _json({'ok': true, 'providerLogout': 'confirmed'});
          }
          return _json({
            'contractVersion': 1,
            'sessionId': _sid,
            'emailVerifiedAt': null,
          });
        }),
        origin: Uri.parse('https://admin.collect.ikanisa.com'),
        environment: fixtures.environment(
          captcha: true,
          api: 'https://api.synthetic.invalid',
        ),
        authChallenge: challenge,
      );
      await session.refresh();
      final router = GoRouter(
        initialLocation: '/admin/security/verify-email',
        routes: [
          GoRoute(
            path: '/admin/security/verify-email',
            builder: (_, _) =>
                const Scaffold(body: CloudflareAdminEmailVerificationPage()),
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
      await tester.tap(find.text('Send email code'));
      await tester.pump();
      expect(challenge.started, isTrue);
      expect(sends, 0, reason: 'Security challenge is not an OTP dispatch.');

      if (check == 'owned challenge focus returns' ||
          check == 'window blur while challenge already inactive') {
        challenge.ownsFocus = true;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        expect(challenge.cancelled, isFalse);
        if (check == 'window blur while challenge already inactive') {
          // The browser helper observes real document blur even when Flutter
          // is already inactive from the owned iframe, with no second event.
          challenge.leaveWindow();
        } else {
          challenge.complete();
          await tester.pump();
          expect(sends, 0, reason: 'Wait for actual resumed foreground.');
        }
      } else if (check == 'route exit before dispatch') {
        router.go('/admin/security');
        await tester.pumpAndSettle();
      } else if (check == 'authority exit before dispatch') {
        session.clear();
        await tester.pump();
      } else if (check == 'logout before dispatch') {
        await session.signOut();
        await tester.pump();
      } else if (check == 'manual challenge cancel') {
        challenge.cancel();
      } else if (check == 'last boundary has no foreground') {
        challenge.foreground = false;
        challenge.complete();
      } else if (check == 'paused after dispatch') {
        challenge.complete();
        await tester.pumpAndSettle();
        expect(sends, 1);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        dispatched.complete(
          _json({
            'challenge_id': _challenge,
            'retry_after': 60,
            'expires_in': 1800,
            'delivery_status': 'accepted',
          }, 202),
        );
      } else {
        challenge.foreground = false;
        tester.binding.handleAppLifecycleStateChanged(switch (check) {
          'real inactive before dispatch' => AppLifecycleState.inactive,
          'hidden before dispatch' => AppLifecycleState.hidden,
          'paused before dispatch' => AppLifecycleState.paused,
          _ => AppLifecycleState.detached,
        });
      }
      await tester.pump();
      challenge.foreground = true;
      challenge.ownsFocus = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      if (check == 'owned challenge focus returns') {
        expect(sends, 1);
        expect(find.widgetWithText(TextField, 'Email code'), findsOneWidget);
        now = now.add(const Duration(seconds: 301));
        await tester.pump(const Duration(seconds: 1));
        expect(
          find.widgetWithText(TextField, 'Email code'),
          findsOneWidget,
          reason: 'An accepted 30-minute receipt keeps its full lifetime.',
        );
        expect(
          find.text('Check verification after returning to this page.'),
          findsNothing,
        );
      } else if (check == 'paused after dispatch') {
        expect(sends, 1);
        expect(find.widgetWithText(TextField, 'Email code'), findsNothing);
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Send email code'),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Check verification'),
              )
              .onPressed,
          isNotNull,
        );
      } else {
        expect(sends, 0);
        expect(
          find.text('Check verification after returning to this page.'),
          findsNothing,
        );
        final button = find.widgetWithText(TextButton, 'Send email code');
        if (button.evaluate().isNotEmpty) {
          expect(tester.widget<TextButton>(button).onPressed, isNotNull);
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

class _OwnedChallenge implements CollectAuthChallenge {
  final result = Completer<String>();
  bool started = false, cancelled = false, ownsFocus = false, foreground = true;
  @override
  bool get ownsInactiveFocus =>
      started && !cancelled && ownsFocus && foreground;
  @override
  bool get hasForeground => foreground;
  @override
  Future<String> acquire() {
    started = true;
    return result.future;
  }

  void complete() {
    if (!result.isCompleted) result.complete('SYNTHETIC_SECURITY_CANDIDATE');
  }

  void leaveWindow() {
    foreground = false;
    cancel();
  }

  @override
  void cancel() {
    cancelled = true;
    if (!result.isCompleted) {
      result.completeError(
        const CollectAuthException(
          'Security verification was cancelled.',
          code: 'captcha_cancelled',
        ),
      );
    }
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
