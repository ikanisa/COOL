import 'dart:convert';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart'
    show
        adminClockProvider,
        adminLastSuccessfulRefreshProvider,
        adminRealtimeTickProvider;
import 'package:collect_app/admin/core/cloudflare_canonical_reconciliation_pages.dart';
import 'package:collect_app/admin/core/cloudflare_canonical_reconciliation_api.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'cloudflare_canonical_reconciliation_support.dart';

// The production cookie workspace supplies these shared identity boundaries.
// Bind the same fixture session rather than initializing a legacy bearer client.
class _FinancialSessionScope extends AdminSessionController {
  _FinancialSessionScope() : super(null);
  int _generation = 0;
  Object? _authority;

  void update(CloudflareAdminUser? user) {
    final authority = user?.authorityKey;
    if (_authority == authority) return;
    _authority = authority;
    _generation++;
    state = user == null
        ? null
        : (
            key: (userId: user.id, sessionId: user.sessionId),
            generation: _generation,
          );
  }
}

Future<VoidCallback> pump(
  WidgetTester tester,
  FinancialHarness h,
  Widget page, {
  DateTime? readAt,
  DateTime Function()? clock,
}) async {
  tester.view.physicalSize = const Size(1500, 2100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      cloudflareAdminSessionProvider.overrideWith((_) => h.session),
      adminAuthUserIdProvider.overrideWith(
        (ref) => ref.watch(cloudflareAdminSessionProvider).asData?.value?.id,
      ),
      adminAuthSessionScopeProvider.overrideWith((ref) {
        final scope = _FinancialSessionScope();
        scope.update(ref.read(cloudflareAdminSessionProvider).asData?.value);
        ref.listen(
          cloudflareAdminSessionProvider,
          (_, next) => scope.update(next.asData?.value),
        );
        return scope;
      }),
      adminPendingAttemptStorageProvider.overrideWithValue(h.storage),
      if (clock != null)
        adminClockProvider.overrideWithValue(clock)
      else if (readAt != null)
        adminClockProvider.overrideWithValue(() => readAt),
    ],
  );
  var disposed = false;
  void dispose() {
    if (!disposed) {
      disposed = true;
      container.dispose();
    }
  }

  addTearDown(dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: page)),
    ),
  );
  await tester.pumpAndSettle();
  return dispose;
}

Future<void> finish(WidgetTester tester, VoidCallback dispose) async {
  await tester.pumpWidget(const SizedBox.shrink());
  dispose();
  await tester.pumpAndSettle();
}

void main() {
  for (final outcome in ['verified', 'malformed', 'denied']) {
    testWidgets('queue freshness requires a verified typed read: $outcome', (
      tester,
    ) async {
      final readAt = DateTime.utc(2026, 10, 15, 17);
      final h = await FinancialHarness.create(
        ownsSession: false,
        reply: (request) async {
          if (request.url.path != '/api/admin/reconciliations') {
            return FinancialHarness.defaultRead(request);
          }
          return switch (outcome) {
            'verified' => financialResponse(financialFixture('queue')),
            'denied' => financialResponse({'code': 'permission_denied'}, 403),
            _ => financialResponse({
              ...financialFixture('queue'),
              'contract_version': 999,
            }),
          };
        },
      );
      final dispose = await pump(
        tester,
        h,
        const CanonicalReconciliationQueuePage(),
        readAt: readAt,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CanonicalReconciliationQueuePage)),
      );
      expect(
        container.read(adminLastSuccessfulRefreshProvider),
        outcome == 'verified' ? readAt : isNull,
      );
      expect(tester.takeException(), isNull);
      await finish(tester, dispose);
    });
  }
  testWidgets(
    'canonical invalidation retains an unknown original request and never resends it',
    (tester) async {
      var writes = 0;
      final h = await FinancialHarness.create(
        ownsSession: false,
        reply: (request) async {
          if (request.method == 'POST') {
            writes++;
            throw http.ClientException('Controlled response loss');
          }
          return FinancialHarness.defaultRead(request);
        },
      );
      final id = financialFixture('detail')['resource']['id'] as String;
      // The separately owned harness store uses a real expiry timer, just as
      // repository-only fixtures do. Mounted UI time stays under tester.pump.
      final original = (await tester.runAsync(() async {
        final api = h.api;
        final detail = await api.detail(id),
            members = await api.members(detail);
        final attempt = api.propose(
          detail,
          members.rows.single,
          'Retain this exact synthetic member attribution',
        );
        try {
          await api.submit(attempt);
        } on CloudflareAdminRequestException {
          // The following assertion requires the exact retained unknown state.
        }
        return attempt;
      }))!;
      expect(original.needsLookup, isTrue);
      final dispose = await pump(
        tester,
        h,
        CanonicalReconciliationDetailPage(transactionId: id),
      );
      expect(find.text('Unconfirmed request: ${original.key}'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CanonicalReconciliationDetailPage)),
      );
      container.read(adminRealtimeTickProvider.notifier).state++;
      await tester.pumpAndSettle();
      expect(find.text('Unconfirmed request: ${original.key}'), findsOneWidget);
      expect(h.api.restore(id)?.key, original.key);
      expect(writes, 1);
      await finish(tester, dispose);
    },
  );
  testWidgets(
    'canonical changes retain the mounted member draft and announce review without a write',
    (tester) async {
      var writes = 0;
      final h = await FinancialHarness.create(
        ownsSession: false,
        reply: (request) async {
          if (request.method != 'GET') writes++;
          return FinancialHarness.defaultRead(request);
        },
      );
      final dispose = await pump(
        tester,
        h,
        CanonicalReconciliationDetailPage(
          transactionId: financialFixture('detail')['resource']['id'] as String,
        ),
      );
      final field = find.widgetWithText(TextField, 'Find a group member');
      await tester.ensureVisible(field);
      await tester.enterText(field, 'Unsubmitted member search');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CanonicalReconciliationDetailPage)),
      );
      container.read(adminRealtimeTickProvider.notifier).state++;
      await tester.pumpAndSettle();
      expect(find.text('Unsubmitted member search'), findsOneWidget);
      expect(
        find.textContaining(
          'Your current selection and request are unchanged.',
        ),
        findsOneWidget,
      );
      expect(writes, 0);
      expect(tester.takeException(), isNull);
      await finish(tester, dispose);
    },
  );
  testWidgets(
    'the new evidence review renders recorded amounts, identities and independent review as tables',
    (tester) async {
      final h = await FinancialHarness.create(ownsSession: false);
      final dispose = await pump(
        tester,
        h,
        CanonicalReconciliationDetailPage(
          transactionId: financialFixture('detail')['resource']['id'] as String,
        ),
      );
      expect(find.text('Retained payment review'), findsOneWidget);
      expect(find.byType(AdminDataTable), findsWidgets);
      expect(find.text('Recorded amount (RWF)'), findsOneWidget);
      expect(find.text('Independent review'), findsOneWidget);
      expect(
        find.textContaining(
          'Provider verification and settlement are not asserted.',
        ),
        findsOneWidget,
      );
      expect(find.text('Approve allocation'), findsNothing);
      expect(tester.takeException(), isNull);
      await finish(tester, dispose);
    },
  );
  testWidgets(
    'a visible retained-evidence dialog removes plaintext when the account changes',
    (tester) async {
      const evidence =
          'Exact controlled retained receiver evidence. No provider confirmation claim.';
      final h = await FinancialHarness.create(
        ownsSession: false,
        reply: (request) async {
          if (request.url.path.contains('/api/admin/evidence/')) {
            return http.Response.bytes(
              utf8.encode(evidence),
              200,
              headers: {
                'content-type': 'text/plain',
                'x-collect-evidence-sensitivity': 'ordinary',
              },
            );
          }
          if (request.url.path.contains('/api/admin/reconciliations/')) {
            final detail = financialFixture('detail');
            (detail['related']['evidence']['rows'] as List)
                    .single['source_sensitivity'] =
                'ordinary';
            return financialResponse(detail);
          }
          return FinancialHarness.defaultRead(request);
        },
      );
      final dispose = await pump(
        tester,
        h,
        CanonicalReconciliationDetailPage(
          transactionId: financialFixture('detail')['resource']['id'] as String,
        ),
      );
      final read = find.text('Read retained evidence');
      await tester.ensureVisible(read);
      await tester.tap(read);
      await tester.pumpAndSettle();
      expect(find.text(evidence), findsOneWidget);
      h.auth = {
        ...h.auth,
        'user': {
          ...h.auth['user'] as Map,
          'id': '11111111-1111-4111-8111-111111111111',
          'sessionId': 'different-account-session',
        },
      };
      await h.session.refresh();
      await tester.pumpAndSettle();
      expect(find.text(evidence), findsNothing);
      expect(
        find.text('Account access changed. Close this evidence view.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await finish(tester, dispose);
    },
  );
  testWidgets(
    'queue search fetches a new scoped page and presents a truthful empty result',
    (tester) async {
      final searches = <String>[];
      final h = await FinancialHarness.create(
        ownsSession: false,
        reply: (request) async {
          if (request.url.path == '/api/admin/reconciliations') {
            final search = request.url.queryParameters['search'] ?? '';
            searches.add(search);
            return financialResponse(
              search.isEmpty
                  ? financialFixture('queue')
                  : {
                      'contract_version': 2,
                      'model': 'canonical_evidence_ledger',
                      'rows': [],
                      'total': 0,
                      'limit': 25,
                      'offset': 0,
                      'next_offset': null,
                    },
            );
          }
          return FinancialHarness.defaultRead(request);
        },
      );
      final dispose = await pump(
        tester,
        h,
        const CanonicalReconciliationQueuePage(),
      );
      final search = find.widgetWithText(TextField, 'Search payment evidence');
      await tester.enterText(search, 'missing evidence');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(searches, ['', 'missing evidence']);
      expect(find.text('No matching evidence'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CanonicalReconciliationQueuePage)),
      );
      container.read(adminRealtimeTickProvider.notifier).state++;
      await tester.pumpAndSettle();
      expect(searches, ['', 'missing evidence', 'missing evidence']);
      expect(find.text('missing evidence'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester, dispose);
    },
  );
}
