import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_privacy_review_sdk.dart';
import 'package:collect_app/admin/core/cloudflare_admin_retention_inspection.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/privacy_review_fixtures.dart';

Map<String, dynamic> _context(DateTime checked, DateTime until) => {
  'contract_version': 1,
  'scope': 'account_retention_inspection_context',
  'source_id': '1' * 64,
  'checked_at': checked.toIso8601String(),
  'valid_until': until.toIso8601String(),
  'approval_granted': false,
  'erasure_completed': false,
};

void main() {
  final checked = privacyNow.add(const Duration(milliseconds: 260));
  final until = privacyNow.add(const Duration(minutes: 5));

  testWidgets(
    'context waits for observed subsecond skew without moving expiry',
    (tester) async {
      var now = privacyNow;
      final response = _context(checked, until);
      expect(
        () => CloudflareAdminRetentionContext.parse(response, now),
        throwsFormatException,
      );
      final receiving = CloudflareAdminRetentionContext.receive(
        response,
        () => now,
      );
      now = privacyNow.add(const Duration(milliseconds: 261));
      await tester.pump(const Duration(milliseconds: 261));
      final context = await receiving;
      expect(context.checkedAt, checked);
      expect(context.validUntil, until);
      expect(context.fresh(now), isTrue);
      expect(
        context.fresh(checked.subtract(const Duration(microseconds: 1))),
        isFalse,
      );
      expect(context.fresh(until), isFalse);
    },
  );

  testWidgets('a frozen or regressed clock still rejects future context', (
    tester,
  ) async {
    final receiving = CloudflareAdminRetentionContext.receive(
      _context(checked, until),
      () => privacyNow,
    );
    final assertion = expectLater(receiving, throwsFormatException);
    await tester.pump(const Duration(milliseconds: 261));
    await assertion;
  });

  testWidgets('waiting never extends a server expiry', (tester) async {
    var now = privacyNow;
    final expiry = privacyNow.add(const Duration(milliseconds: 261));
    final receiving = CloudflareAdminRetentionContext.receive(
      _context(checked, expiry),
      () => now,
    );
    final assertion = expectLater(receiving, throwsFormatException);
    now = expiry;
    await tester.pump(const Duration(milliseconds: 261));
    await assertion;
  });

  test('a clock difference of one second is rejected immediately', () async {
    await expectLater(
      CloudflareAdminRetentionContext.receive(
        _context(privacyNow.add(const Duration(seconds: 1)), until),
        () => privacyNow,
      ),
      throwsFormatException,
    );
  });

  testWidgets('clock rounding across a UTC second keeps strict freshness', (
    tester,
  ) async {
    var now = privacyNow.subtract(const Duration(microseconds: 200));
    final receiving = CloudflareAdminRetentionContext.receive(
      _context(privacyNow, until),
      () => now,
    );
    now = privacyNow.add(const Duration(microseconds: 800));
    await tester.pump(const Duration(milliseconds: 1));
    final context = await receiving;
    expect(context.fresh(now), isTrue);
    expect(context.fresh(until), isFalse);
  });

  for (final outcome in ['current', 'revoked', 'expired', 'frozen']) {
    testWidgets('review list rechecks $outcome after its bounded clock wait', (
      tester,
    ) async {
      var now = privacyNow;
      var current = true;
      var calls = 0;
      final sdk = AdminPrivacyReviewSdk(
        rpc: (name, parameters) async {
          expect(name, 'admin_list_account_deletion_reviews_v1');
          calls++;
          return privacyPageRaw(checked: checked, limit: 25);
        },
        actorId: privacyActor,
        sessionId: privacySession,
        isCurrent: () => current,
        now: () => now,
      );
      final receiving = sdk.list();
      final assertion = outcome == 'current'
          ? expectLater(receiving, completes)
          : expectLater(
              receiving,
              outcome == 'revoked'
                  ? throwsA(isA<AdminSessionChanged>())
                  : throwsFormatException,
            );
      await tester.pump();
      if (outcome == 'revoked') current = false;
      if (outcome == 'expired') {
        now = checked.add(const Duration(minutes: 10));
      } else if (outcome != 'frozen') {
        now = privacyNow.add(const Duration(milliseconds: 261));
      }
      await tester.pump(const Duration(milliseconds: 261));
      await assertion;
      expect(calls, 1);
    });
  }
}
