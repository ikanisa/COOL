import 'package:collect_app/shared/models/collect_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _event() => {
  'id': 'synthetic-event',
  'collection_id': 'synthetic-group',
  'amount_rwf': 2500,
  'currency': 'RWF',
  'transaction_id': 'synthetic-transaction',
  'allocation_status': 'needs_review',
  'confidence': 0.82,
  'created_at': '2026-09-27T12:00:00+02:00',
};

void main() {
  test('review event preserves exact RWF amount and zoned instant', () {
    final event = ParsedPaymentEvent.fromJson(_event());
    expect(event.id, 'synthetic-event');
    expect(event.collectionId, 'synthetic-group');
    expect(event.amountRwf, 2500);
    expect(event.transactionId, 'synthetic-transaction');
    expect(event.senderLabel, 'MoMo receipt');
    expect(event.allocationStatus, 'needs_review');
    expect(event.confidence, 0.82);
    expect(event.createdAt, DateTime.utc(2026, 9, 27, 10));
  });

  test('legacy amount alias remains exact when current field is absent', () {
    final row = _event()..remove('amount_rwf');
    row['amount_minor'] = 2500.0;
    expect(ParsedPaymentEvent.fromJson(row).amountRwf, 2500);
  });

  test('conflicting amount aliases are rejected', () {
    final row = _event()..['amount_minor'] = 2501;
    expect(() => ParsedPaymentEvent.fromJson(row), throwsFormatException);
  });

  for (final invalid in <Object?>[
    null,
    0,
    -1,
    2500.75,
    '2500',
    double.nan,
    double.infinity,
    9007199254740992,
  ]) {
    test('invalid event amount $invalid never becomes a display amount', () {
      final row = _event()..['amount_rwf'] = invalid;
      expect(() => ParsedPaymentEvent.fromJson(row), throwsFormatException);
    });
  }

  test('missing event timestamp never becomes the current clock', () {
    final row = _event()..remove('created_at');
    expect(() => ParsedPaymentEvent.fromJson(row), throwsFormatException);
  });

  for (final invalid in [
    '2026-02-30T10:00:00Z',
    '2026-09-27T10:00:00',
    '2026-09-27T10:00:00+24:00',
  ]) {
    test('invalid event timestamp $invalid is rejected', () {
      final row = _event()..['created_at'] = invalid;
      expect(() => ParsedPaymentEvent.fromJson(row), throwsFormatException);
    });
  }

  for (final invalid in <Object?>[
    null,
    -0.01,
    1.01,
    double.nan,
    double.infinity,
    '0.82',
  ]) {
    test('invalid confidence $invalid is not displayed', () {
      final row = _event()..['confidence'] = invalid;
      expect(() => ParsedPaymentEvent.fromJson(row), throwsFormatException);
    });
  }

  test('missing status and unknown or missing currency are rejected', () {
    final noStatus = _event()..remove('allocation_status');
    final unknownCurrency = _event()..['currency'] = 'unknown';
    final missingCurrency = _event()..remove('currency');
    expect(() => ParsedPaymentEvent.fromJson(noStatus), throwsFormatException);
    expect(
      () => ParsedPaymentEvent.fromJson(unknownCurrency),
      throwsFormatException,
    );
    expect(
      () => ParsedPaymentEvent.fromJson(missingCurrency),
      throwsFormatException,
    );
  });

  test('optional identifiers can be absent but cannot contain controls', () {
    final absent = _event()
      ..remove('collection_id')
      ..remove('transaction_id');
    expect(ParsedPaymentEvent.fromJson(absent).collectionId, isNull);
    expect(ParsedPaymentEvent.fromJson(absent).transactionId, isNull);

    final invalid = _event()..['transaction_id'] = 'private-value\n';
    try {
      ParsedPaymentEvent.fromJson(invalid);
      fail('Expected invalid transaction identifier');
    } on FormatException catch (error) {
      expect(error.source, isNull);
      expect(error.toString(), isNot(contains('private-value')));
    }
  });
}
