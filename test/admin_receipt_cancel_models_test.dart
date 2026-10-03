import 'dart:convert';
import 'dart:io';
import 'package:collect_app/admin/core/admin_receipt_cancel_models.dart';
import 'package:collect_app/admin/core/admin_receipt_cancel_checkpoint.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> cancelFixture(String name) =>
    jsonDecode(
          File(
            'test/fixtures/admin_receipt_cancel_v1/observed-$name.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;
Map<String, dynamic> cancelCopy(Map<String, dynamic> raw) =>
    jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
AdminReceiptCancelIntent cancelIntent() =>
    AdminReceiptCancelIntent.fromParameters({
      'p_request_id': cancelFixture('cancelled-action')['request_id'],
      'p_outbox_id': cancelFixture('cancelled-action')['outbox_id'],
      'p_expected_revision': 1,
      'p_reason_code': 'operator_cancelled',
    });
void main() {
  for (final name in [
    'linked-rwanda-inspection',
    'revision-exhausted-inspection',
    'unavailable-inspection',
    'prior-attempt-inspection',
    'unclassified-inspection',
    'cancelled-inspection',
    'preexisting-eligible-inspection',
  ]) {
    test('actual isolated SQL $name passes strict inspection', () {
      final raw = cancelFixture(name);
      final result = AdminReceiptCancelInspection.parse(
        raw,
        outboxId: raw['outbox_id'] as String,
      );
      expect(result.isFresh(result.checkedAt), isTrue);
      expect(result.isFresh(result.validUntil), isFalse);
    });
  }
  for (final name in [
    'recorded-lookup',
    'in-progress-lookup',
    'reauthenticated-original-lookup',
    'not-recorded-lookup',
  ]) {
    test('actual isolated SQL $name passes original-actor lookup', () {
      final raw = cancelFixture(name);
      final result = AdminReceiptCancelLookup.parse(
        raw,
        requestId: raw['request_id'] as String,
      );
      expect(result.isFresh(result.checkedAt), isTrue);
      expect(result.isFresh(result.validUntil), isFalse);
    });
  }
  test(
    'actual immutable cancellation receipt matches original revision and reason',
    () {
      final result = AdminReceiptCancelReceipt.parse(
        cancelFixture('cancelled-action'),
        intent: cancelIntent(),
      );
      expect(result.revision, 2);
    },
  );
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'private field': (raw) => raw['body'] = 'PRIVATE_CANARY',
    'wrong scope': (raw) => raw['scope'] = 'global',
    'boolean version': (raw) => raw['contract_version'] = true,
    'wrong target': (raw) => raw['outbox_id'] = cancelIntent().requestId,
    'wrong receipt target': (raw) =>
        (raw['receipt'] as Map)['outbox_id'] = cancelIntent().requestId,
    'renewed TTL': (raw) =>
        raw['sample_valid_until'] = '2026-10-01T01:27:21.274310Z',
    'noncanonical timestamp': (raw) =>
        raw['checked_at'] = '2026-10-01T00:26:21Z',
    'impossible date': (raw) =>
        raw['checked_at'] = '2026-02-30T00:26:21.274310Z',
    'missing receipt': (raw) => raw['receipt'] = null,
    'hidden ineligible': (raw) => (raw['receipt'] as Map)['can_cancel'] = false,
    'queued-only reason on attempted state': (raw) =>
        (raw['receipt'] as Map)['state'] = 'send_started',
    'unknown reason': (raw) => (raw['receipt'] as Map)['reason_code'] = 'retry',
    'unbounded revision': (raw) =>
        (raw['receipt'] as Map)['revision'] = 1000000001,
    'exhausted eligible revision': (raw) =>
        (raw['receipt'] as Map)['revision'] = 1000000000,
    'string revision': (raw) => (raw['receipt'] as Map)['revision'] = '1',
  };
  for (final entry in mutations.entries) {
    test('inspection rejects ${entry.key}', () {
      final raw = cancelFixture('preexisting-eligible-inspection');
      entry.value(raw);
      expect(
        () => AdminReceiptCancelInspection.parse(
          raw,
          outboxId:
              cancelFixture('preexisting-eligible-inspection')['outbox_id']
                  as String,
        ),
        throwsFormatException,
      );
    });
  }
  test(
    'immutable receipt rejects delivery or finance claims and changed reviewed inputs',
    () {
      for (final field in [
        'financial_action',
        'send_action',
        'provider_delivery_verified',
        'primary_receipt_retained',
      ]) {
        final raw = cancelFixture('cancelled-action');
        raw[field] = field != 'primary_receipt_retained';
        expect(
          () => AdminReceiptCancelReceipt.parse(raw),
          throwsFormatException,
        );
      }
      final changed = cancelFixture('cancelled-action')..['revision'] = 3;
      expect(
        () => AdminReceiptCancelReceipt.parse(changed),
        throwsFormatException,
      );
      final wrong = cancelFixture('cancelled-action')
        ..['reason_code'] = 'content_review_required';
      expect(
        () => AdminReceiptCancelReceipt.parse(wrong, intent: cancelIntent()),
        throwsFormatException,
      );
    },
  );
  test('lookup rejects wrong original UUID and mismatched nested receipt', () {
    final raw = cancelFixture('recorded-lookup');
    (raw['receipt'] as Map)['request_id'] = cancelIntent().outboxId;
    expect(
      () => AdminReceiptCancelLookup.parse(
        raw,
        requestId: raw['request_id'] as String,
      ),
      throwsFormatException,
    );
  });
  test(
    'bounded owner-purpose checkpoint contains only original references and closed reason',
    () {
      final owner = adminReceiptCancelOwnerDigest('synthetic-owner');
      final saved = AdminReceiptCancelCheckpoint(owner, cancelIntent());
      expect(jsonDecode(saved.encode()).keys.toSet(), {
        'version',
        'owner_digest',
        'request',
      });
      expect(
        AdminReceiptCancelCheckpoint.parse(
          saved.encode(),
          owner,
        ).intent.parameters,
        cancelIntent().parameters,
      );
      expect(
        () => AdminReceiptCancelCheckpoint.parse(
          saved.encode(),
          adminReceiptCancelOwnerDigest('other'),
        ),
        throwsFormatException,
      );
      expect(
        () => AdminReceiptCancelCheckpoint.parse('x' * 2049, owner),
        throwsFormatException,
      );
    },
  );
}
