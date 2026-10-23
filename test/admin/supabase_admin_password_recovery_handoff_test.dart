import 'dart:convert';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/admin_account_pages.dart';
import 'package:collect_app/admin/core/cloudflare_admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_mfa.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../core/supabase_backend_test.dart' as fixtures;

void main() {
  testWidgets(
    'password recovery denial keeps AAL1 and requires explicit recovery email action',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const sid = '00000000-0000-4000-8000-000000000001';
      final mutations = <http.Request>[];
      http.Response reply(Object value, [int status = 200]) =>
          http.Response(jsonEncode(value), status);
      final session = CloudflareAdminSession(
        MockClient((r) async {
          if (r.url.path.endsWith('/auth/session')) {
            return reply({
              'user': {
                'id': sid,
                'email': 'info@ikanisa.com',
                'role': 'owner',
                'sessionId': sid,
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
          if (r.url.path.endsWith('/auth/email-verification')) {
            return reply({
              'contractVersion': 1,
              'sessionId': sid,
              'emailVerifiedAt': DateTime.now()
                  .toUtc()
                  .subtract(const Duration(seconds: 1))
                  .toIso8601String(),
            });
          }
          mutations.add(r);
          if (r.url.path.endsWith('/auth/change-password')) {
            return reply({
              'error': {'code': 'password_recovery_required'},
            }, 403);
          }
          expect(r.url.path.endsWith('/auth/forgot-password'), isTrue);
          return reply({'ok': true});
        }),
        origin: Uri.parse('https://admin.collect.ikanisa.com'),
        environment: fixtures.environment(),
      );
      await session.refresh();
      final actor = session.authorityFence;
      final router = GoRouter(
        initialLocation: '/admin/security',
        routes: [
          GoRoute(
            path: '/admin/security',
            builder: (_, _) =>
                const Scaffold(body: CloudflareAdminSecurityPage()),
          ),
          GoRoute(
            path: '/admin/forgot-password',
            builder: (context, _) => AdminAccountForgotPasswordPage(
              onBackToLogin: () => context.go('/admin/security'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cloudflareAdminSessionProvider.overrideWith((ref) => session),
            adminAccountApiProvider.overrideWithValue(
              CloudflareAdminAccountApi(session),
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Verify email'), findsOneWidget);
      expect(find.text('Authenticator'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Current password'),
        'CurrentFixture123!',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'New password'),
        'NewFixturePassword456!',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm new password'),
        'NewFixturePassword456!',
      );
      final change = find.widgetWithText(FilledButton, 'Change password');
      await tester.ensureVisible(change);
      await tester.tap(change);
      await tester.pumpAndSettle();
      expect(mutations, hasLength(1));
      expect(jsonDecode(mutations.single.body), {
        'currentPassword': 'CurrentFixture123!',
        'newPassword': 'NewFixturePassword456!',
      });
      expect(
        find.textContaining('Use Set or reset password by email'),
        findsOneWidget,
      );
      expect(session.authorityFence, actor);
      expect(session.user!.assuranceLevel, 1);
      final recovery = find.text('Set or reset password by email');
      await tester.ensureVisible(recovery);
      await tester.tap(recovery);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/admin/forgot-password',
      );
      expect(
        mutations,
        hasLength(1),
        reason: 'Opening recovery must not send email.',
      );
      await tester.enterText(find.byType(TextFormField), 'info@ikanisa.com');
      await tester.tap(find.widgetWithText(FilledButton, 'Send reset email'));
      await tester.pumpAndSettle();
      expect(mutations, hasLength(2));
      expect(jsonDecode(mutations.last.body), {'email': 'info@ikanisa.com'});
      expect(session.authorityFence, actor);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
