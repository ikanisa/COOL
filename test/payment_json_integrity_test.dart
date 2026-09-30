import 'package:collect_app/shared/models/collect_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _intent() => {
  'id': 'intent-test-1',
  'collection_id': 'group-test-1',
  'amount_minor': 1000,
  'rail': 'rwanda_momo',
  'currency': 'RWF',
  'status': 'pending',
  'created_at': '2026-09-27T10:00:00Z',
  'expires_at': '2026-09-28T10:00:00Z',
};

Map<String, dynamic> _contribution() => {
  'payment_id': 'momo:test-1',
  'collection_id': 'group-test-1',
  'amount_minor': 1000,
  'currency': 'RWF',
  'posted_at': '2026-09-27T10:00:00Z',
  'supporter_label': 'Collect member',
  'is_current_user_contribution': true,
};

void main() {
  test('intent: accepts one amount', () {
    final row = _intent()..['amount_minor'] = 1;
    expect(PaymentIntentModel.fromJson(row).expectedAmountMinor, 1);
  });

  test('intent: accepts normal amount', () {
    final row = _intent()..['amount_minor'] = 1000;
    expect(PaymentIntentModel.fromJson(row).expectedAmountMinor, 1000);
  });

  test('intent: accepts whole double amount', () {
    final row = _intent()..['amount_minor'] = 1000.0;
    expect(PaymentIntentModel.fromJson(row).expectedAmountMinor, 1000.0);
  });

  test('intent: accepts safe maximum amount', () {
    final row = _intent()..['amount_minor'] = 9007199254740991;
    expect(
      PaymentIntentModel.fromJson(row).expectedAmountMinor,
      9007199254740991,
    );
  });

  test('intent: rejects missing amount', () {
    final row = _intent()..['amount_minor'] = null;
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('intent: rejects zero amount', () {
    final row = _intent()..['amount_minor'] = 0;
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('intent: rejects negative amount', () {
    final row = _intent()..['amount_minor'] = -1;
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('intent: rejects fraction amount', () {
    final row = _intent()..['amount_minor'] = 1.5;
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('intent: rejects numeric string amount', () {
    final row = _intent()..['amount_minor'] = '1000';
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('intent: rejects boolean amount', () {
    final row = _intent()..['amount_minor'] = true;
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('intent: rejects not a number amount', () {
    final row = _intent()..['amount_minor'] = double.nan;
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('intent: rejects infinity amount', () {
    final row = _intent()..['amount_minor'] = double.infinity;
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('intent: rejects negative infinity amount', () {
    final row = _intent()..['amount_minor'] = double.negativeInfinity;
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('intent: rejects outside exact range amount', () {
    final row = _intent()..['amount_minor'] = 9007199254740992;
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('intent: rejects object amount', () {
    final row = _intent()
      ..['amount_minor'] = <String, dynamic>{'secret': 'not money'};
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('intent: accepts legacy amount without current amount', () {
    final row = _intent()..remove('amount_minor');
    row['expected_amount_rwf'] = 2500;
    expect(PaymentIntentModel.fromJson(row).expectedAmountMinor, 2500);
  });

  test('intent: current null preserves legacy compatibility', () {
    final row = _intent()..['amount_minor'] = null;
    row['expected_amount_rwf'] = 2500;
    expect(PaymentIntentModel.fromJson(row).expectedAmountMinor, 2500);
  });

  test('intent: equal aliases accepted', () {
    final row = _intent()..['expected_amount_rwf'] = 1000.0;
    expect(PaymentIntentModel.fromJson(row).expectedAmountMinor, 1000);
  });

  test('intent: conflicting aliases rejected', () {
    final row = _intent()..['expected_amount_rwf'] = 2000;
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('intent: invalid alias cannot hide behind valid amount', () {
    final row = _intent()..['expected_amount_rwf'] = 1.5;
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('intent: errors do not echo received amounts', () {
    final row = _intent()..['amount_minor'] = 'private-value-918273';
    try {
      PaymentIntentModel.fromJson(row);
      fail('Expected an amount rejection');
    } on FormatException catch (error) {
      expect(error.toString(), isNot(contains('private-value-918273')));
      expect(error.source, isNull);
    }
  });

  test('intent: rejects blank collection_id', () {
    final row = _intent()..['collection_id'] = '  ';
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('intent: rejects control character in collection_id', () {
    final row = _intent()..['collection_id'] = 'bad\nidentifier';
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('intent: rejects blank id', () {
    final row = _intent()..['id'] = '  ';
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('intent: rejects control character in id', () {
    final row = _intent()..['id'] = 'bad\nidentifier';
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('intent: rejects non-RWF', () {
    final row = _intent()..['currency'] = 'USD';
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('intent: rejects malformed currency', () {
    final row = _intent()..['currency'] = 42;
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('intent: legacy absent currency remains RWF', () {
    final row = _intent()..remove('currency');
    expect(PaymentIntentModel.fromJson(row).currency, 'RWF');
  });

  test('intent: missing created_at is never now', () {
    final row = _intent()..remove('created_at');
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('intent: missing expires_at is never now', () {
    final row = _intent()..remove('expires_at');
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('contribution: accepts one amount', () {
    final row = _contribution()..['amount_minor'] = 1;
    expect(Contribution.fromJson(row).amountMinor, 1);
  });

  test('contribution: accepts normal amount', () {
    final row = _contribution()..['amount_minor'] = 1000;
    expect(Contribution.fromJson(row).amountMinor, 1000);
  });

  test('contribution: accepts whole double amount', () {
    final row = _contribution()..['amount_minor'] = 1000.0;
    expect(Contribution.fromJson(row).amountMinor, 1000.0);
  });

  test('contribution: accepts safe maximum amount', () {
    final row = _contribution()..['amount_minor'] = 9007199254740991;
    expect(Contribution.fromJson(row).amountMinor, 9007199254740991);
  });

  test('contribution: rejects missing amount', () {
    final row = _contribution()..['amount_minor'] = null;
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('contribution: rejects zero amount', () {
    final row = _contribution()..['amount_minor'] = 0;
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('contribution: rejects negative amount', () {
    final row = _contribution()..['amount_minor'] = -1;
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('contribution: rejects fraction amount', () {
    final row = _contribution()..['amount_minor'] = 1.5;
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('contribution: rejects numeric string amount', () {
    final row = _contribution()..['amount_minor'] = '1000';
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('contribution: rejects boolean amount', () {
    final row = _contribution()..['amount_minor'] = true;
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('contribution: rejects not a number amount', () {
    final row = _contribution()..['amount_minor'] = double.nan;
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('contribution: rejects infinity amount', () {
    final row = _contribution()..['amount_minor'] = double.infinity;
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('contribution: rejects negative infinity amount', () {
    final row = _contribution()..['amount_minor'] = double.negativeInfinity;
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('contribution: rejects outside exact range amount', () {
    final row = _contribution()..['amount_minor'] = 9007199254740992;
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('contribution: rejects object amount', () {
    final row = _contribution()
      ..['amount_minor'] = <String, dynamic>{'secret': 'not money'};
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('contribution: accepts legacy amount without current amount', () {
    final row = _contribution()..remove('amount_minor');
    row['amount_rwf'] = 2500;
    expect(Contribution.fromJson(row).amountMinor, 2500);
  });

  test('contribution: current null preserves legacy compatibility', () {
    final row = _contribution()..['amount_minor'] = null;
    row['amount_rwf'] = 2500;
    expect(Contribution.fromJson(row).amountMinor, 2500);
  });

  test('contribution: equal aliases accepted', () {
    final row = _contribution()..['amount_rwf'] = 1000.0;
    expect(Contribution.fromJson(row).amountMinor, 1000);
  });

  test('contribution: conflicting aliases rejected', () {
    final row = _contribution()..['amount_rwf'] = 2000;
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('contribution: invalid alias cannot hide behind valid amount', () {
    final row = _contribution()..['amount_rwf'] = 1.5;
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('contribution: errors do not echo received amounts', () {
    final row = _contribution()..['amount_minor'] = 'private-value-918273';
    try {
      Contribution.fromJson(row);
      fail('Expected an amount rejection');
    } on FormatException catch (error) {
      expect(error.toString(), isNot(contains('private-value-918273')));
      expect(error.source, isNull);
    }
  });

  test('contribution: rejects blank collection_id', () {
    final row = _contribution()..['collection_id'] = '  ';
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('contribution: rejects control character in collection_id', () {
    final row = _contribution()..['collection_id'] = 'bad\nidentifier';
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('contribution: rejects blank payment_id', () {
    final row = _contribution()..['payment_id'] = '  ';
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('contribution: rejects control character in payment_id', () {
    final row = _contribution()..['payment_id'] = 'bad\nidentifier';
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('contribution: rejects non-RWF', () {
    final row = _contribution()..['currency'] = 'USD';
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('contribution: rejects malformed currency', () {
    final row = _contribution()..['currency'] = 42;
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('contribution: legacy absent currency remains RWF', () {
    final row = _contribution()..remove('currency');
    expect(Contribution.fromJson(row).currency, 'RWF');
  });

  test('contribution: missing posted_at is never now', () {
    final row = _contribution()..remove('posted_at');
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('timestamp rejects impossible day', () {
    final row = _contribution()..['posted_at'] = '2026-02-30T12:00:00Z';
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('timestamp rejects non-leap February', () {
    final row = _contribution()..['posted_at'] = '2025-02-29T12:00:00Z';
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('timestamp rejects month zero', () {
    final row = _contribution()..['posted_at'] = '2026-00-01T12:00:00Z';
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('timestamp rejects month thirteen', () {
    final row = _contribution()..['posted_at'] = '2026-13-01T12:00:00Z';
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('timestamp rejects day zero', () {
    final row = _contribution()..['posted_at'] = '2026-09-00T12:00:00Z';
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('timestamp rejects April 31', () {
    final row = _contribution()..['posted_at'] = '2026-04-31T12:00:00Z';
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('timestamp rejects hour overflow', () {
    final row = _contribution()..['posted_at'] = '2026-09-27T24:00:00Z';
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('timestamp rejects minute overflow', () {
    final row = _contribution()..['posted_at'] = '2026-09-27T10:60:00Z';
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('timestamp rejects second overflow', () {
    final row = _contribution()..['posted_at'] = '2026-09-27T10:00:60Z';
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('timestamp rejects offset hour overflow', () {
    final row = _contribution()..['posted_at'] = '2026-09-27T10:00:00+24:00';
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('timestamp rejects offset minute overflow', () {
    final row = _contribution()..['posted_at'] = '2026-09-27T10:00:00+02:60';
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('timestamp rejects naive timestamp', () {
    final row = _contribution()..['posted_at'] = '2026-09-27T10:00:00';
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('timestamp rejects date only', () {
    final row = _contribution()..['posted_at'] = '2026-09-27';
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('timestamp rejects numeric timestamp', () {
    final row = _contribution()..['posted_at'] = 1790503200;
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('timestamp rejects overprecision', () {
    final row = _contribution()..['posted_at'] = '2026-09-27T10:00:00.1234567Z';
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('timestamp rejects trailing newline', () {
    final row = _contribution()..['posted_at'] = '2026-09-27T10:00:00Z\n';
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('timestamp rejects year zero', () {
    final row = _contribution()..['posted_at'] = '0000-09-27T10:00:00Z';
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('timestamp rejects malformed timestamp', () {
    final row = _contribution()..['posted_at'] = 'private-secret-timestamp';
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('timestamp accepts UTC', () {
    final row = _contribution()..['posted_at'] = '2026-09-27T10:00:00Z';
    final result = Contribution.fromJson(row);
    expect(result.createdAt, DateTime.utc(2026, 9, 27, 10));
    expect(result.createdAt.isUtc, isTrue);
  });

  test('timestamp accepts positive offset', () {
    final row = _contribution()..['posted_at'] = '2026-09-27T12:00:00+02:00';
    final result = Contribution.fromJson(row);
    expect(result.createdAt, DateTime.utc(2026, 9, 27, 10));
    expect(result.createdAt.isUtc, isTrue);
  });

  test('timestamp accepts negative offset', () {
    final row = _contribution()..['posted_at'] = '2026-09-27T06:00:00-04:00';
    final result = Contribution.fromJson(row);
    expect(result.createdAt, DateTime.utc(2026, 9, 27, 10));
    expect(result.createdAt.isUtc, isTrue);
  });

  test('timestamp accepts PostgreSQL short UTC offset', () {
    final row = _contribution()..['posted_at'] = '2026-09-27T10:00:00+00';
    final result = Contribution.fromJson(row);
    expect(result.createdAt, DateTime.utc(2026, 9, 27, 10));
    expect(result.createdAt.isUtc, isTrue);
  });

  test('timestamp accepts compact offset', () {
    final row = _contribution()..['posted_at'] = '2026-09-27T12:00:00+0200';
    final result = Contribution.fromJson(row);
    expect(result.createdAt, DateTime.utc(2026, 9, 27, 10));
    expect(result.createdAt.isUtc, isTrue);
  });

  test('timestamp accepts space separator', () {
    final row = _contribution()..['posted_at'] = '2026-09-27 10:00:00+00:00';
    final result = Contribution.fromJson(row);
    expect(result.createdAt, DateTime.utc(2026, 9, 27, 10));
    expect(result.createdAt.isUtc, isTrue);
  });

  test('timestamp accepts leap day', () {
    final row = _contribution()..['posted_at'] = '2024-02-29T10:00:00Z';
    final result = Contribution.fromJson(row);
    expect(result.createdAt, DateTime.utc(2024, 2, 29, 10));
    expect(result.createdAt.isUtc, isTrue);
  });

  test('timestamp accepts milliseconds', () {
    final row = _contribution()..['posted_at'] = '2026-09-27T10:00:00.123Z';
    final result = Contribution.fromJson(row);
    expect(result.createdAt, DateTime.utc(2026, 9, 27, 10, 0, 0, 123));
    expect(result.createdAt.isUtc, isTrue);
  });

  test('timestamp accepts microseconds', () {
    final row = _contribution()..['posted_at'] = '2026-09-27T10:00:00.123456Z';
    final result = Contribution.fromJson(row);
    expect(result.createdAt, DateTime.utc(2026, 9, 27, 10, 0, 0, 123, 456));
    expect(result.createdAt.isUtc, isTrue);
  });

  test('timestamp accepts typed instant', () {
    final row = _contribution()..['posted_at'] = DateTime.utc(2026, 9, 27, 10);
    final result = Contribution.fromJson(row);
    expect(result.createdAt, DateTime.utc(2026, 9, 27, 10));
    expect(result.createdAt.isUtc, isTrue);
  });

  test('timestamp errors do not leak input', () {
    final row = _contribution()..['posted_at'] = 'private-secret-timestamp';
    try {
      Contribution.fromJson(row);
      fail('Expected a timestamp rejection');
    } on FormatException catch (error) {
      expect(error.toString(), isNot(contains('private-secret-timestamp')));
      expect(error.source, isNull);
    }
  });

  test('intent status: missing is not pending', () {
    final row = _intent()..['status'] = null;
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('intent status: blank is not pending', () {
    final row = _intent()..['status'] = '';
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('intent status: non-string is not pending', () {
    final row = _intent()..['status'] = 12;
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('future non-pending status remains non-actionable', () {
    final row = _intent()
      ..['status'] = 'future_review_state'
      ..['created_at'] = '2099-01-01T00:00:00Z'
      ..['expires_at'] = '2099-01-02T00:00:00Z';
    final intent = PaymentIntentModel.fromJson(row);
    expect(intent.status, 'future_review_state');
    expect(intent.isAwaitingTransfer, isFalse);
  });

  test('expired intent retained as history, not made fresh', () {
    final row = _intent()
      ..['created_at'] = '2000-01-01T00:00:00Z'
      ..['expires_at'] = '2000-01-02T00:00:00Z';
    final intent = PaymentIntentModel.fromJson(row);
    expect(intent.createdAt, DateTime.utc(2000, 1, 1));
    expect(intent.isAwaitingTransfer, isFalse);
  });

  test('intent rejects equal lifetime', () {
    final row = _intent()..['expires_at'] = '2026-09-27T10:00:00Z';
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('intent rejects inverted lifetime', () {
    final row = _intent()..['expires_at'] = '2026-09-27T09:00:00Z';
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('lifetime compares actual instants across offsets', () {
    final row = _intent()
      ..['created_at'] = '2026-09-27T12:00:00+02:00'
      ..['expires_at'] = '2026-09-27T11:00:00Z';
    final intent = PaymentIntentModel.fromJson(row);
    expect(
      intent.expiresAt.difference(intent.createdAt),
      const Duration(hours: 1),
    );
  });

  test('contribution retains posting precedence over creation', () {
    final row = _contribution()..['created_at'] = '2026-09-26T10:00:00Z';
    expect(Contribution.fromJson(row).createdAt, DateTime.utc(2026, 9, 27, 10));
  });

  test('contribution uses legacy creation when posting absent', () {
    final row = _contribution()..remove('posted_at');
    row['created_at'] = '2026-09-26T10:00:00Z';
    expect(Contribution.fromJson(row).createdAt, DateTime.utc(2026, 9, 26, 10));
  });

  test('invalid posting does not fall back to valid creation', () {
    final row = _contribution()
      ..['posted_at'] = 'not-a-date'
      ..['created_at'] = '2026-09-26T10:00:00Z';
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('payment id precedence does not compare distinct identity schemas', () {
    final row = _contribution()..['id'] = 'legacy-different-id';
    expect(Contribution.fromJson(row).id, 'momo:test-1');
  });

  test('legacy contribution id remains accepted', () {
    final row = _contribution()..remove('payment_id');
    row['id'] = 'legacy-id';
    expect(Contribution.fromJson(row).id, 'legacy-id');
  });

  test('malformed ownership is not silently converted', () {
    final row = _contribution()..['is_current_user_contribution'] = 'true';
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('missing ownership stays false', () {
    final row = _contribution()..remove('is_current_user_contribution');
    expect(Contribution.fromJson(row).isCurrentUserContribution, isFalse);
  });

  test('explicit foreign rail cannot masquerade as RWF MoMo', () {
    final row = _contribution()..['rail'] = 'bank_transfer';
    expect(() => Contribution.fromJson(row), throwsFormatException);
  });

  test('optional malformed metadata yields safe format error', () {
    final row = _intent()..['receiver_momo_number'] = 123;
    expect(() => PaymentIntentModel.fromJson(row), throwsFormatException);
  });

  test('valid metadata is preserved and input remains untouched', () {
    final row = _intent()
      ..['receiver_momo_number'] = ' 250780000000 '
      ..['receiver_label'] = ' Test receiver '
      ..['network'] = 'airtel_money';
    final before = Map<String, dynamic>.from(row);
    final intent = PaymentIntentModel.fromJson(row);
    expect(intent.receiverMomoNumber, '250780000000');
    expect(intent.receiverMomoLabel, 'Test receiver');
    expect(intent.momoNetwork, 'airtel_money');
    expect(row, before);
  });
}
