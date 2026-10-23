import 'dart:async';
import 'dart:convert';

import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:collect_app/features/privacy/privacy_providers.dart';
import 'package:collect_app/features/privacy/privacy_request_controller.dart';
import 'package:collect_app/features/privacy/privacy_request_screen.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'privacy_email_verification_test.dart' as fixtures;
import '../../core/supabase_backend_test.dart' as backend;

Future<PrivacyRequestController> mount(
  WidgetTester tester,
  fixtures.Harness h,
) async {
  final controller = PrivacyRequestController(
    authority: h.authority,
    transport: h.transport,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collectBackendClientProvider.overrideWithValue(h.backend),
        collectAuthenticatedUserIdProvider.overrideWithValue(backend.principal),
        privacyRequestControllerProvider.overrideWithValue(controller),
        collectAccountDeletionReasonsProvider.overrideWith((ref) async => []),
        offlineSnapshotStatusProvider.overrideWithValue(
          const OfflineSnapshotStatus(
            usingStaleCache: false,
            hasReadableData: false,
            lastSuccessfulSyncAt: null,
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: const DeleteAccountRequestScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  // Scroll position changes require a frame before pointer hit testing.
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
}

void main() {
  testWidgets(
    'compact email task accepts ten digits and unknown status cannot enable intake',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = (await tester.runAsync(
        () => fixtures.Harness.create((r, now) async {
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          if (r.url.path.endsWith(
            '/get_current_account_deletion_request_status_v1',
          )) {
            return fixtures.response(null);
          }
          if (r.url.path.endsWith('/challenge')) {
            return fixtures.response(fixtures.descriptor(body, now), 202);
          }
          if (r.url.path.endsWith('/status')) {
            return fixtures.response(
              fixtures.descriptor(
                body,
                now,
                state: 'verified',
                cleanup: 'unconfirmed',
              ),
            );
          }
          if (r.url.path.endsWith('/cancel')) {
            return fixtures.response(
              fixtures.descriptor(
                body,
                now,
                state: 'verified',
                cancelled: true,
                cleanup: 'unconfirmed',
              ),
            );
          }
          expect(body['code'], '1234567890');
          return fixtures.response({
            'code': 'privacy_email_operation_unknown',
          }, 503);
        }),
      ))!;
      final controller = await mount(tester, h);
      try {
        final send = find.byKey(const ValueKey('privacy_send_code'));
        await reveal(tester, send);
        await tester.tap(send);
        await tester.pumpAndSettle();
        final code = find.byKey(const ValueKey('privacy_email_code'));
        await reveal(tester, code);
        await tester.enterText(code, '1234567890');
        final verify = find.byKey(const ValueKey('privacy_verify_code'));
        await reveal(tester, verify);
        await tester.tap(verify);
        await tester.pumpAndSettle();
        expect(controller.emailVerificationUnknown, isTrue);
        expect(controller.hasFreshVerification, isFalse);
        final status = find.byKey(
          const ValueKey('privacy_check_email_verification'),
        );
        await reveal(tester, status);
        await tester.tap(status);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('privacy_verify_code')), findsNothing);
        expect(controller.hasFreshVerification, isFalse);
        expect(
          h.calls.where(
            (r) => r.url.path.endsWith('/request_account_deletion_v1'),
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        controller.dispose();
        final closing = h.close();
        await tester.runAsync(
          () => closing.timeout(const Duration(seconds: 3)),
        );
      }
    },
  );

  testWidgets(
    'disposing actual email task fences late response and cleans captured candidate without adopting',
    (tester) async {
      final entered = Completer<void>(), answer = Completer<http.Response>();
      late Map<String, dynamic> originalBody;
      late int issued;
      final h = (await tester.runAsync(
        () => fixtures.Harness.create((r, now) async {
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          if (r.url.path.endsWith(
            '/get_current_account_deletion_request_status_v1',
          )) {
            return fixtures.response(null);
          }
          if (r.url.path.endsWith('/challenge')) {
            return fixtures.response(fixtures.descriptor(body, now), 202);
          }
          if (r.url.path.endsWith('/verify')) {
            originalBody = body;
            issued = now;
            entered.complete();
            return answer.future;
          }
          return fixtures.response(
            fixtures.descriptor(
              body,
              now,
              state: 'verified',
              cancelled: true,
              cleanup: body.containsKey('candidate_access_token')
                  ? 'confirmed'
                  : 'unconfirmed',
            ),
          );
        }),
      ))!;
      final controller = await mount(tester, h);
      try {
        final send = find.byKey(const ValueKey('privacy_send_code'));
        await reveal(tester, send);
        await tester.tap(send);
        await tester.pumpAndSettle();
        final code = find.byKey(const ValueKey('privacy_email_code'));
        await reveal(tester, code);
        await tester.enterText(code, '123456');
        final verify = find.byKey(const ValueKey('privacy_verify_code'));
        await reveal(tester, verify);
        await tester.tap(verify);
        await tester.pump();
        for (var i = 0; i < 20 && !entered.isCompleted; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(
          entered.isCompleted,
          isTrue,
          reason:
              'The synthetic verification request must dispatch before disposal',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        answer.complete(
          fixtures.response(fixtures.candidate(originalBody, issued)),
        );
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(
          h.backend.auth.currentSession!.claims['session_id'],
          fixtures.oldSid,
        );
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
          (jsonDecode(cleanup.body) as Map)['candidate_access_token'],
          fixtures.candidate(originalBody, issued)['access_token'],
        );
        expect(
          h.calls.where(
            (r) => r.url.path.endsWith('/request_account_deletion_v1'),
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        controller.dispose();
        final closing = h.close();
        await tester.runAsync(
          () => closing.timeout(const Duration(seconds: 3)),
        );
      }
    },
  );
}
