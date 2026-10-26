import 'dart:convert';

import 'package:collect_app/admin/core/cloudflare_admin_request_identity.dart';
import 'package:collect_app/admin/core/cloudflare_canonical_reconciliation_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cloudflare_canonical_reconciliation_pages_test.dart' as pages;
import 'cloudflare_canonical_reconciliation_support.dart';
import '../core/supabase_backend_test.dart' as fixtures;

void main() {
  testWidgets(
    'immutable missing reference explains correction, blocks approval and allows rejection',
    (tester) async {
      final posts = <Map<String, dynamic>>[];
      final id = financialFixture('detail')['resource']['id'] as String;
      late String principal;
      final proof = financialSupabaseEmailProof(
        DateTime.now()
            .toUtc()
            .subtract(const Duration(seconds: 1))
            .toIso8601String(),
      );
      final h = await FinancialHarness.create(
        ownsSession: false,
        auth: canonicalSupabaseFinancialSession(),
        environment: fixtures.environment(),
        origin: Uri.parse('https://admin.collect.ikanisa.com'),
        emailVerification: proof,
        reply: (request) async {
          if (request.method == 'POST') {
            expect(request.headers['X-Collect-CSRF'], 'a' * 64);
            expect(request.headers.containsKey('Authorization'), isFalse);
            final body = Map<String, dynamic>.from(
              jsonDecode(request.body) as Map,
            );
            posts.add(body);
            expect(body['outcome'], 'rejected');
            final key =
                request.headers['Idempotency-Key'] ??
                request.headers['idempotency-key']!;
            return financialResponse({
              ...financialFixture('review_receipt'),
              'request_id': canonicalAdminRequestId(principal, key),
              'proposal_status': 'rejected',
              'transaction_version': 1,
            });
          }
          if (request.url.path.endsWith('/reconciliations/$id')) {
            final detail =
                jsonDecode(jsonEncode(financialFixture('detail')))
                    as Map<String, dynamic>;
            detail['resource']['provider_reference'] = null;
            detail['resource']['title'] = id;
            return financialResponse(detail);
          }
          return FinancialHarness.defaultRead(request);
        },
      );
      principal = h.session.user!.principalId!;
      expect(h.session.usesEmailVerification, isTrue);
      expect(h.session.user!.usesEmailVerification, isTrue);
      expect(h.session.user!.assuranceLevel, 1);
      expect(h.session.user!.mfaAt, isNull);
      expect(h.session.user!.sessionId, financialSupabaseSessionId);
      expect(h.session.user!.emailVerifiedAt, isNotNull);
      expect(h.session.user!.hasRecentSensitiveVerification(), isTrue);
      expect(
        h.session.user!.permissions.contains('reconciliations.review'),
        isTrue,
      );
      final dispose = await pages.pump(
        tester,
        h,
        CanonicalReconciliationDetailPage(transactionId: id),
      );
      const immutableRecovery =
          'Approval is unavailable without an event-specific evidence reference. Retained evidence cannot be edited. Leave this record unposted or reject its proposal. Record corrected evidence separately only after review, retaining the original record reference in the reason. Recording alone does not credit a contribution.';
      expect(find.text(immutableRecovery), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Evidence reference'),
        findsNothing,
      );
      final review = find.widgetWithText(TextButton, 'Independent review');
      await tester.ensureVisible(review);
      await tester.tap(review);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Independent review reason'),
        'Reject immutable evidence without an independent event reference',
      );
      await tester.tap(
        find.widgetWithText(
          CheckboxListTile,
          'I independently reviewed the event-specific evidence reference and this recorded member identity.',
        ),
      );
      await tester.pumpAndSettle();
      final approve = find.widgetWithText(
        FilledButton,
        'Record independent approval',
      );
      await tester.ensureVisible(approve);
      await tester.tap(approve);
      await tester.pumpAndSettle();
      expect(posts, isEmpty);
      expect(
        find.text(
          'The records could not be verified. Refresh before continuing.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'A missing, ambiguous or repeated statement reference is not a verified transaction ID.',
        ),
        findsOneWidget,
      );
      final reject = find.widgetWithText(OutlinedButton, 'Record rejection');
      await tester.tap(reject);
      await tester.pumpAndSettle();
      expect(posts, hasLength(1));
      expect(posts.single['outcome'], 'rejected');
      expect(posts.single.containsKey('provider_reference'), isFalse);
      expect(find.text('Recorded decision receipt'), findsOneWidget);
      expect(find.text(immutableRecovery), findsOneWidget);
      expect(tester.takeException(), isNull);
      await pages.finish(tester, dispose);
    },
  );

  testWidgets(
    'refused approval retains original lookup and retries only the identical reviewed request',
    (tester) async {
      final posts = <({String key, String body})>[];
      final lookups = <String>[];
      final id = financialFixture('detail')['resource']['id'] as String;
      final reference = financialFixture(
        'detail',
      )['resource']['provider_reference'];
      final proof = financialSupabaseEmailProof(
        DateTime.now()
            .toUtc()
            .subtract(const Duration(seconds: 1))
            .toIso8601String(),
      );
      final h = await FinancialHarness.create(
        ownsSession: false,
        auth: canonicalSupabaseFinancialSession(),
        environment: fixtures.environment(),
        origin: Uri.parse('https://admin.collect.ikanisa.com'),
        emailVerification: proof,
        reply: (request) async {
          if (request.method == 'POST') {
            expect(request.headers['X-Collect-CSRF'], 'a' * 64);
            expect(request.headers.containsKey('Authorization'), isFalse);
            posts.add((
              key:
                  request.headers['Idempotency-Key'] ??
                  request.headers['idempotency-key']!,
              body: request.body,
            ));
            return financialResponse({
              'error': {
                'code': 'stale_state',
                'message': 'The record changed. Refresh and try again.',
              },
            }, 409);
          }
          if (request.url.path.contains('/operations/requests/')) {
            lookups.add(request.url.path.split('/').last);
            return financialResponse({
              'contract_version': 2,
              'model': 'canonical_evidence_ledger',
              'status': 'not_found',
            });
          }
          return FinancialHarness.defaultRead(request);
        },
      );
      expect(h.session.usesEmailVerification, isTrue);
      expect(h.session.user!.usesEmailVerification, isTrue);
      expect(h.session.user!.assuranceLevel, 1);
      expect(h.session.user!.mfaAt, isNull);
      expect(h.session.user!.sessionId, financialSupabaseSessionId);
      expect(h.session.user!.emailVerifiedAt, isNotNull);
      expect(h.session.user!.hasRecentSensitiveVerification(), isTrue);
      expect(
        h.session.user!.permissions.contains('reconciliations.review'),
        isTrue,
      );
      final dispose = await pages.pump(
        tester,
        h,
        CanonicalReconciliationDetailPage(transactionId: id),
      );
      final review = find.widgetWithText(TextButton, 'Independent review');
      await tester.ensureVisible(review);
      await tester.tap(review);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Independent review reason'),
        'Independently reviewed synthetic event, receiver and member identity',
      );
      await tester.tap(
        find.widgetWithText(
          CheckboxListTile,
          'I independently reviewed the event-specific evidence reference and this recorded member identity.',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Record independent approval'),
      );
      await tester.pumpAndSettle();
      expect(posts, hasLength(1));
      final original = posts.single;
      expect(jsonDecode(original.body)['outcome'], 'approved');
      expect(find.text('Unconfirmed request: ${original.key}'), findsOneWidget);
      expect(
        find.textContaining(
          'Check the original request first. Before retrying approval',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Do not change the reference to bypass review.'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextButton, 'Open original request lookup'),
        findsOneWidget,
      );
      expect(find.text('Review identical retry'), findsNothing);
      expect(lookups, isEmpty);
      expect(
        find.widgetWithText(TextField, 'Evidence reference'),
        findsNothing,
      );
      final check = find.widgetWithText(FilledButton, 'Check original request');
      await tester.ensureVisible(check);
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(lookups, [original.key]);
      expect(
        posts,
        hasLength(1),
        reason: 'Lookup must never automatically retry approval',
      );
      expect(find.text('Unconfirmed request: ${original.key}'), findsOneWidget);
      final retry = find.widgetWithText(
        OutlinedButton,
        'Review identical retry',
      );
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.text('Review identical request'), findsOneWidget);
      expect(find.text('Request reference: ${original.key}'), findsOneWidget);
      expect(
        posts,
        hasLength(1),
        reason: 'Opening review is not permission to resend',
      );
      await tester.tap(
        find.widgetWithText(
          CheckboxListTile,
          'I reviewed this exact member, amount and recorded evidence.',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Save reviewed request'),
      );
      await tester.pumpAndSettle();
      expect(posts, hasLength(2));
      expect(
        posts.last,
        original,
        reason: 'Explicit retry keeps the exact original key and encoded body',
      );
      expect(
        financialFixture('detail')['resource']['provider_reference'],
        reference,
      );
      expect(find.text('Unconfirmed request: ${original.key}'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await pages.finish(tester, dispose);
    },
  );
}
