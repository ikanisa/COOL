import 'dart:convert';

import 'package:collect_app/admin/core/cloudflare_canonical_reconciliation_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../core/supabase_backend_test.dart' as fixtures;
import 'cloudflare_canonical_reconciliation_pages_test.dart' as pages;
import 'cloudflare_canonical_reconciliation_support.dart';
import 'supabase_retained_evidence_test.dart' as evidence;

const _retainedText =
    'Exact controlled retained receiver evidence. No provider confirmation claim.';
const _acknowledgement =
    'I need the original evidence for this review and understand that this access is audited.';

Future<FinancialHarness> _harness({
  required List<http.Request> reads,
  required Map<String, dynamic> proof,
  Map<String, dynamic>? auth,
}) => FinancialHarness.create(
  ownsSession: false,
  auth: auth ?? evidence.protectedEvidenceSession(),
  environment: fixtures.environment(),
  origin: Uri.parse('https://admin.collect.ikanisa.com'),
  emailVerification: proof,
  reply: (request) async {
    if (request.url.path.contains('/api/admin/evidence/')) {
      reads.add(request);
      return http.Response.bytes(
        utf8.encode(_retainedText),
        200,
        headers: {
          'content-type': 'text/plain',
          'x-collect-evidence-sensitivity': 'raw_sms',
        },
      );
    }
    // The frozen fixture has no classification. This is intentionally the
    // protected default, not a positively ordinary producer.
    return FinancialHarness.defaultRead(request);
  },
);

Widget _page() => CanonicalReconciliationDetailPage(
  transactionId: financialFixture('detail')['resource']['id'] as String,
);

Future<void> _openReview(WidgetTester tester) async {
  final read = find.text('Read retained evidence');
  await tester.ensureVisible(read);
  await tester.tap(read);
  await tester.pumpAndSettle();
}

Future<void> _completeReview(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextField, 'Evidence access reason'),
    evidence.reviewReason,
  );
  await tester.tap(find.widgetWithText(CheckboxListTile, _acknowledgement));
  await tester.pumpAndSettle();
  await tester.tap(
    find.widgetWithText(FilledButton, 'Reveal retained evidence'),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'unclassified evidence requires reason and acknowledgement, and proof removal permanently conceals plaintext',
    (tester) async {
      final reads = <http.Request>[], proof = evidence.currentEvidenceProof();
      final h = await _harness(reads: reads, proof: proof);
      final dispose = await pages.pump(tester, h, _page());
      await _openReview(tester);
      final reveal = find.widgetWithText(
        FilledButton,
        'Reveal retained evidence',
      );
      expect(reads, isEmpty);
      expect(tester.widget<FilledButton>(reveal).onPressed, isNull);
      await tester.enterText(
        find.widgetWithText(TextField, 'Evidence access reason'),
        'short',
      );
      await tester.tap(find.widgetWithText(CheckboxListTile, _acknowledgement));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(reveal).onPressed, isNull);
      expect(reads, isEmpty);
      await tester.enterText(
        find.widgetWithText(TextField, 'Evidence access reason'),
        evidence.reviewReason,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(reveal).onPressed, isNotNull);
      await tester.tap(reveal);
      await tester.pumpAndSettle();
      expect(reads, hasLength(1));
      expect(
        reads.single.headers['X-Collect-Review-Reason'],
        evidence.reviewReason,
      );
      expect(reads.single.url.query, isEmpty);
      expect(find.text(_retainedText), findsOneWidget);
      final before = h.session.authorityFence;
      proof['emailVerifiedAt'] = null;
      await h.session.refresh();
      await tester.pumpAndSettle();
      expect(h.session.authorityFence, before);
      expect(find.text(_retainedText), findsNothing);
      expect(
        find.text(
          'Account access changed or verification expired. Close this evidence view.',
        ),
        findsOneWidget,
      );
      proof['emailVerifiedAt'] = DateTime.now()
          .toUtc()
          .subtract(const Duration(seconds: 1))
          .toIso8601String();
      await h.session.refresh();
      await tester.pumpAndSettle();
      expect(find.text(_retainedText), findsNothing);
      expect(reads, hasLength(1));
      expect(h.storage.values, isEmpty);
      expect(tester.takeException(), isNull);
      await pages.finish(tester, dispose);
    },
  );

  for (final denied in ['permission', 'email']) {
    testWidgets('protected evidence explains $denied denial before any read', (
      tester,
    ) async {
      final reads = <http.Request>[];
      final h = await _harness(
        reads: reads,
        proof: denied == 'email'
            ? financialSupabaseEmailProof(null)
            : evidence.currentEvidenceProof(),
        auth: evidence.protectedEvidenceSession(
          withoutPermission: denied == 'permission' ? 'sms.reveal' : null,
        ),
      );
      final dispose = await pages.pump(tester, h, _page());
      await _openReview(tester);
      expect(reads, isEmpty);
      expect(find.text(_retainedText), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Reveal retained evidence'),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.text(
          denied == 'permission'
              ? 'This account does not have permission to reveal SMS-source evidence. Close this review.'
              : 'Account access changed or email verification expired. Close this review, verify your email and reopen the payment.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('verify your authenticator'), findsNothing);
      expect(tester.takeException(), isNull);
      await pages.finish(tester, dispose);
    });
  }

  testWidgets('visible plaintext expires without a session-provider update', (
    tester,
  ) async {
    var now = DateTime.now().toUtc();
    final reads = <http.Request>[];
    final proof = financialSupabaseEmailProof(
      now.subtract(const Duration(minutes: 4, seconds: 50)).toIso8601String(),
    );
    final h = await _harness(reads: reads, proof: proof);
    final dispose = await pages.pump(tester, h, _page(), clock: () => now);
    await _openReview(tester);
    await _completeReview(tester);
    expect(find.text(_retainedText), findsOneWidget);
    final before = h.session.user;
    now = now.add(const Duration(seconds: 11));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text(_retainedText), findsNothing);
    expect(reads, hasLength(1));
    expect(h.session.user?.authorityKey, before?.authorityKey);
    expect(tester.takeException(), isNull);
    await pages.finish(tester, dispose);
  });

  testWidgets(
    'an account switch during review cannot reveal using the new actor',
    (tester) async {
      final reads = <http.Request>[];
      final h = await _harness(
        reads: reads,
        proof: evidence.currentEvidenceProof(),
      );
      final dispose = await pages.pump(tester, h, _page());
      await _openReview(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Evidence access reason'),
        evidence.reviewReason,
      );
      await tester.tap(find.widgetWithText(CheckboxListTile, _acknowledgement));
      await tester.pumpAndSettle();
      h.auth = {
        ...h.auth,
        'user': {
          ...h.auth['user'] as Map,
          'id': '11111111-1111-4111-8111-111111111111',
        },
      };
      await h.session.refresh();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Reveal retained evidence'),
            )
            .onPressed,
        isNull,
      );
      expect(reads, isEmpty);
      expect(find.text(_retainedText), findsNothing);
      expect(tester.takeException(), isNull);
      await pages.finish(tester, dispose);
    },
  );
}
