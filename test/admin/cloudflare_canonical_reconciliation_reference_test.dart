import 'dart:convert';
import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_canonical_reconciliation_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'cloudflare_canonical_reconciliation_support.dart';

void main() {
  Future<void> check({
    required bool missingReference,
    bool own = false,
    bool canReview = true,
    String role = 'owner',
    String outcome = 'approved',
    String? expectedError,
  }) async {
    var posts = 0;
    final h = await FinancialHarness.create(
      auth: canonicalSession(role: role),
      reply: (request) async {
        if (request.method == 'POST') posts++;
        if (request.url.path.endsWith(
          '/reconciliations/${financialFixture('detail')['resource']['id']}',
        )) {
          final data =
              jsonDecode(jsonEncode(financialFixture('detail')))
                  as Map<String, dynamic>;
          data['can_review'] = canReview;
          if (missingReference) {
            data['resource']['provider_reference'] = null;
            data['resource']['title'] = data['resource']['id'];
          }
          return financialResponse(data);
        }
        return FinancialHarness.defaultRead(request);
      },
    );
    final api = h.api,
        detail = await api.detail(
          financialFixture('detail')['resource']['id'] as String,
        ),
        members = await api.members(detail);
    final row = Map<String, dynamic>.from(
      detail.related['proposals']!.rows.single,
    );
    if (own) row['proposed_by_principal_id'] = detail.principalId;
    final proposal = CanonicalReconciliationProposal.parse(
      row,
      transactionId: detail.id,
      evidenceId: detail.transaction['evidence_id'] as String,
    );
    void action() => api.review(
      detail,
      proposal,
      outcome,
      'Independently reviewed synthetic event and identity',
      member: members.rows.single,
    );
    if (role == 'staff') {
      expect(
        action,
        throwsA(
          isA<AdminAccountException>().having(
            (e) => e.message,
            'original authority error',
            'Reopen this view with the current authorized account.',
          ),
        ),
      );
    } else if (expectedError != null) {
      expect(
        action,
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'error precedence',
            expectedError,
          ),
        ),
      );
    } else {
      expect(action, returnsNormally);
    }
    expect(
      posts,
      0,
      reason: 'Validation/attempt creation must never send or weaken authority',
    );
  }

  const originalEligibility =
      'An independent reviewer must confirm the current retained evidence and member identity.';
  const missing =
      'Approval needs an independently reviewed event-specific evidence reference. Recording and rejection remain available.';
  test(
    'own proposal with missing reference preserves original independent-review denial',
    () => check(
      missingReference: true,
      own: true,
      expectedError: originalEligibility,
    ),
  );
  test(
    'canReview false with missing reference preserves original eligibility denial',
    () => check(
      missingReference: true,
      canReview: false,
      expectedError: originalEligibility,
    ),
  );
  test(
    'Staff with missing reference preserves authority denial',
    () => check(missingReference: true, role: 'staff', canReview: false),
  );
  test(
    'eligible missing-reference approval is blocked without transport',
    () => check(missingReference: true, expectedError: missing),
  );
  test(
    'eligible rejection remains available without reference',
    () => check(missingReference: true, outcome: 'rejected'),
  );
  test(
    'eligible event-specific synthetic reference creates approval attempt without transport',
    () => check(missingReference: false),
  );
}
