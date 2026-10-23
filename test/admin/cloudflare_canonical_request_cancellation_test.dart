import 'dart:convert';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/cloudflare_admin_operating_pages.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_request_identity.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/core/cloudflare_canonical_reconciliation_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cloudflare_canonical_reconciliation_support.dart';

const target = '11111111-1111-4111-8111-111111111111';
Map<String, dynamic> outcome(String principal) => {
  'contract_version': 2,
  'model': 'canonical_evidence_ledger',
  'status': 'cancelled',
  'request_id': canonicalAdminRequestId(principal, target),
  'receipt': null,
};

Future<VoidCallback> mount(WidgetTester tester, FinancialHarness h) async {
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      cloudflareAdminSessionProvider.overrideWith((_) => h.session),
      adminRepositoryProvider.overrideWithValue(
        CloudflareAdminRepository(h.session),
      ),
      adminPendingAttemptStorageProvider.overrideWithValue(h.storage),
    ],
  );
  var closed = false;
  void close() {
    if (!closed) {
      closed = true;
      container.dispose();
    }
  }

  addTearDown(close);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: CloudflareOperatingRequestPage(requestKey: target),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return close;
}

Future<void> finish(WidgetTester tester, VoidCallback close) async {
  await tester.pumpWidget(const SizedBox.shrink());
  close();
  await tester.pumpAndSettle();
}

void main() {
  test(
    'cancellation reads back the original principal-bound state and never substitutes the new cancellation key',
    () async {
      final methods = <String>[];
      late String principal;
      final h = await FinancialHarness.create(
        reply: (request) async {
          methods.add(request.method);
          if (request.method == 'POST') {
            expect(
              request.url.path,
              '/api/admin/operations/requests/$target/cancel',
            );
            expect(
              request.headers['Idempotency-Key'] ??
                  request.headers['idempotency-key'],
              '22222222-2222-4222-8222-222222222222',
            );
            expect(jsonDecode(request.body), {
              'reason': 'Close the original uncommitted request',
            });
          }
          return financialResponse(outcome(principal));
        },
      );
      principal = h.session.user!.principalId!;
      final result = await CloudflareAdminRepository(h.session)
          .cancelOperatingRequest(
            target,
            cancellationKey: '22222222-2222-4222-8222-222222222222',
            reason: 'Close the original uncommitted request',
          );
      expect(result['status'], 'cancelled');
      expect(result['request_id'], canonicalAdminRequestId(principal, target));
      expect(methods, ['POST', 'GET']);
    },
  );
  test('password-only cancellation cannot dispatch', () async {
    var sent = 0;
    final auth = canonicalSession();
    (auth['user'] as Map)['assuranceLevel'] = 1;
    (auth['user'] as Map)['mfaAt'] = null;
    final h = await FinancialHarness.create(
      auth: auth,
      reply: (_) async {
        sent++;
        return financialResponse({});
      },
    );
    await expectLater(
      CloudflareAdminRepository(h.session).cancelOperatingRequest(
        target,
        cancellationKey: '22222222-2222-4222-8222-222222222222',
        reason: 'Close the original uncommitted request',
      ),
      throwsA(isA<AdminAccountException>()),
    );
    expect(sent, 0);
  });
  test(
    'a cancelled financial reference clears its original checkpoint and cannot retry',
    () async {
      late String principal, key;
      final h = await FinancialHarness.create(
        reply: (request) async {
          if (request.method == 'POST') {
            key =
                request.headers['Idempotency-Key'] ??
                request.headers['idempotency-key']!;
            return financialResponse({
              'error': {'code': 'service_unavailable'},
            }, 503);
          }
          if (request.url.path.contains('/operations/requests/')) {
            return financialResponse({
              'contract_version': 2,
              'model': 'canonical_evidence_ledger',
              'status': 'cancelled',
              'request_id': canonicalAdminRequestId(principal, key),
              'receipt': null,
            });
          }
          return FinancialHarness.defaultRead(request);
        },
      );
      principal = h.session.user!.principalId!;
      final api = h.api,
          detail = await api.detail(
            financialFixture('detail')['resource']['id'] as String,
          ),
          member = (await api.members(detail)).rows.single;
      final attempt = api.propose(
        detail,
        member,
        'Retain this original attribution request',
      );
      await expectLater(
        api.submit(attempt),
        throwsA(isA<CloudflareAdminRequestException>()),
      );
      expect(h.storage.values, isNotEmpty);
      expect((await api.lookup(attempt)).status, 'cancelled');
      expect(h.storage.values, isEmpty);
      expect(attempt.canRetry, isFalse);
      await expectLater(
        api.submit(attempt, confirmedRetry: true),
        throwsA(isA<AdminAccountException>()),
      );
    },
  );
  testWidgets(
    'lookup cancellation presents the verified blocked state and its history row',
    (tester) async {
      var cancelled = false, posts = 0;
      late String principal;
      final h = await FinancialHarness.create(
        ownsSession: false,
        reply: (request) async {
          if (request.method == 'POST') {
            posts++;
            cancelled = true;
            return financialResponse(outcome(principal));
          }
          if (request.url.path == '/api/admin/operations/requests') {
            return financialResponse({
              'contract_version': 2,
              'model': 'canonical_evidence_ledger',
              'rows': [
                if (cancelled)
                  {
                    'id': canonicalAdminRequestId(principal, target),
                    'idempotency_key': target,
                    'scope': 'requests.cancel',
                    'status': 'cancelled',
                    'receipt': null,
                    'created_at': DateTime.fromMillisecondsSinceEpoch(
                      DateTime.now().millisecondsSinceEpoch,
                      isUtc: true,
                    ).toIso8601String(),
                  },
              ],
              'total': cancelled ? 1 : 0,
            });
          }
          return financialResponse(
            cancelled
                ? outcome(principal)
                : {
                    'contract_version': 2,
                    'model': 'canonical_evidence_ledger',
                    'status': 'not_found',
                  },
          );
        },
      );
      principal = h.session.user!.principalId!;
      final close = await mount(tester, h);
      await tester.tap(find.text('Check request'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel original uncommitted reference'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Cancellation reason'),
        'Close this original uncommitted intent',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel uncommitted request'));
      await tester.pumpAndSettle();
      expect(posts, 1);
      expect(
        find.text(
          'The original reference is blocked. A delayed retry cannot apply it.',
        ),
        findsOneWidget,
      );
      expect(find.text('Cancelled'), findsWidgets);
      expect(find.text('Cancel original uncommitted reference'), findsNothing);
      expect(tester.takeException(), isNull);
      await finish(tester, close);
    },
  );
  testWidgets(
    'an account change hides a pending cancellation reason and disables dispatch',
    (tester) async {
      var posts = 0;
      final h = await FinancialHarness.create(
        ownsSession: false,
        reply: (request) async {
          if (request.method == 'POST') posts++;
          return financialResponse(
            request.url.path == '/api/admin/operations/requests'
                ? {
                    'contract_version': 2,
                    'model': 'canonical_evidence_ledger',
                    'rows': [],
                    'total': 0,
                  }
                : {
                    'contract_version': 2,
                    'model': 'canonical_evidence_ledger',
                    'status': 'not_found',
                  },
          );
        },
      );
      final close = await mount(tester, h);
      await tester.tap(find.text('Check request'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel original uncommitted reference'));
      await tester.pumpAndSettle();
      const reason = 'Private reviewed cancellation explanation';
      await tester.enterText(
        find.widgetWithText(TextField, 'Cancellation reason'),
        reason,
      );
      await tester.pump();
      h.auth = {
        ...h.auth,
        'user': {
          ...h.auth['user'] as Map,
          'id': '33333333-3333-4333-8333-333333333333',
          'sessionId': 'replacement-session',
        },
      };
      await h.session.refresh();
      await tester.pumpAndSettle();
      expect(find.text(reason), findsNothing);
      expect(
        find.text('Account access changed. Close this cancellation review.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Cancel uncommitted request'),
            )
            .onPressed,
        isNull,
      );
      expect(posts, 0);
      await finish(tester, close);
    },
  );
}
