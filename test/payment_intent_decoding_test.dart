import 'dart:convert';

import 'package:collect_app/shared/models/collect_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Synthetic, in-memory fixtures. No RPC, SMS, USSD, or real identity.
Map<String, dynamic> _payload() => {
  'id': 'synthetic-intent',
  'collection_id': 'synthetic-group',
  'amount_minor': 1000,
  'rail': 'rwanda_momo',
  'currency': 'RWF',
  'status': 'pending',
  'created_at': '2026-01-01T10:00:00Z',
  'expires_at': '2026-01-02T10:00:00Z',
};

void main() {
  test('current amount and timestamps are preserved', () {
    final intent = PaymentIntentModel.fromJson(_payload());
    expect(intent.expectedAmountMinor, 1000);
    expect(intent.id, 'synthetic-intent');
    expect(intent.collectionId, 'synthetic-group');
    expect(intent.createdAt, DateTime.utc(2026, 1, 1, 10));
    expect(intent.expiresAt, DateTime.utc(2026, 1, 2, 10));
  });
  test('legacy amount spelling remains supported', () {
    final payload = _payload()..remove('amount_minor');
    payload['expected_amount_rwf'] = 1300;
    expect(PaymentIntentModel.fromJson(payload).expectedAmountMinor, 1300);
  });
  test('equal aliases and exact whole-valued doubles agree', () {
    final payload = _payload()..['expected_amount_rwf'] = 1000.0;
    expect(PaymentIntentModel.fromJson(payload).expectedAmountMinor, 1000);
  });
  test('null current alias permits a supplied valid legacy value', () {
    final payload = _payload()
      ..['amount_minor'] = null
      ..['expected_amount_rwf'] = 1000;
    expect(PaymentIntentModel.fromJson(payload).expectedAmountMinor, 1000);
  });
  test('null legacy alias permits a supplied valid current value', () {
    final payload = _payload()..['expected_amount_rwf'] = null;
    expect(PaymentIntentModel.fromJson(payload).expectedAmountMinor, 1000);
  });
  test('conflicting aliases are rejected rather than preferred', () {
    final payload = _payload()..['expected_amount_rwf'] = 1001;
    expect(() => PaymentIntentModel.fromJson(payload), throwsFormatException);
  });
  test('missing amount does not become zero', () {
    final payload = _payload()..remove('amount_minor');
    expect(() => PaymentIntentModel.fromJson(payload), throwsFormatException);
  });
  test('null amounts do not become zero', () {
    final payload = _payload()
      ..['amount_minor'] = null
      ..['expected_amount_rwf'] = null;
    expect(() => PaymentIntentModel.fromJson(payload), throwsFormatException);
  });
  final invalidAmounts = <String, Object?>{
    'zero': 0,
    'negative': -1,
    'fraction': 1.5,
    'numeric string': '1000',
    'boolean': true,
    'list': [1000],
    'map': {'amount': 1000},
    'NaN': double.nan,
    'infinity': double.infinity,
    'negative infinity': double.negativeInfinity,
    'unsafe integer': 9007199254740992,
  };
  for (final entry in invalidAmounts.entries) {
    for (final key in ['amount_minor', 'expected_amount_rwf']) {
      test('${entry.key} in $key cannot be hidden by the other alias', () {
        final payload = _payload()
          ..['expected_amount_rwf'] = 1000
          ..[key] = entry.value;
        expect(
          () => PaymentIntentModel.fromJson(payload),
          throwsFormatException,
        );
      });
    }
  }
  test('upper exact transport boundary is accepted', () {
    final payload = _payload()..['amount_minor'] = 9007199254740991;
    expect(
      PaymentIntentModel.fromJson(payload).expectedAmountMinor,
      9007199254740991,
    );
  });
  test('positive whole-valued double is accepted', () {
    final payload = _payload()..['amount_minor'] = 1000.0;
    expect(PaymentIntentModel.fromJson(payload).expectedAmountMinor, 1000);
  });
  final badRequiredText = <String, Object?>{
    'null': null,
    'empty': '',
    'leading space': ' pending',
    'trailing space': 'pending ',
    'number': 42,
    'control': 'value\n',
  };
  for (final key in ['id', 'collection_id', 'status']) {
    for (final entry in badRequiredText.entries) {
      test('${entry.key} $key is not silently repaired', () {
        final payload = _payload()..[key] = entry.value;
        expect(
          () => PaymentIntentModel.fromJson(payload),
          throwsFormatException,
        );
      });
    }
  }
  test('missing status does not become pending', () {
    final payload = _payload()..remove('status');
    expect(() => PaymentIntentModel.fromJson(payload), throwsFormatException);
  });
  for (final status in ['confirmed', 'expired', 'cancelled', 'future_state']) {
    test('$status remains readable and is never rewritten to pending', () {
      final payload = _payload()..['status'] = status;
      final intent = PaymentIntentModel.fromJson(payload);
      expect(intent.status, status);
      expect(intent.isAwaitingTransfer, isFalse);
    });
  }
  final invalidTimestamps = <String, Object?>{
    'missing': null,
    'empty': '',
    'number': 0,
    'date only': '2026-01-01',
    'local datetime': '2026-01-01T10:00:00',
    'invalid day': '2026-02-30T10:00:00Z',
    'invalid leap day': '2025-02-29T10:00:00Z',
    'zero month': '2026-00-01T10:00:00Z',
    'invalid hour': '2026-01-01T24:00:00Z',
    'invalid minute': '2026-01-01T10:60:00Z',
    'invalid second': '2026-01-01T10:00:60Z',
    'invalid offset': '2026-01-01T10:00:00+24:00',
    'invalid offset minute': '2026-01-01T10:00:00+02:60',
    'submicrosecond fraction': '2026-01-01T10:00:00.1234567Z',
    'trailing newline': '2026-01-01T10:00:00Z\n',
  };
  for (final key in ['created_at', 'expires_at']) {
    for (final entry in invalidTimestamps.entries) {
      test('${entry.key} $key is rejected without a clock fallback', () {
        final payload = _payload()..[key] = entry.value;
        expect(
          () => PaymentIntentModel.fromJson(payload),
          throwsFormatException,
        );
      });
    }
  }
  for (final stamp in [
    '2026-01-01T12:00:00+02:00',
    '2026-01-01T12:00:00+0200',
    '2026-01-01T12:00:00+02',
    '2026-01-01 10:00:00+00',
    '2026-01-01T10:00:00z',
  ]) {
    test('zoned timestamp $stamp preserves its instant', () {
      final payload = _payload()..['created_at'] = stamp;
      final intent = PaymentIntentModel.fromJson(payload);
      expect(intent.createdAt, DateTime.utc(2026, 1, 1, 10));
      expect(intent.createdAt.isUtc, isTrue);
    });
  }
  test('valid leap day remains valid', () {
    final payload = _payload()
      ..['created_at'] = '2024-02-29T10:00:00Z'
      ..['expires_at'] = '2024-03-01T10:00:00Z';
    expect(
      PaymentIntentModel.fromJson(payload).createdAt,
      DateTime.utc(2024, 2, 29, 10),
    );
  });
  test('six fractional digits are preserved to Dart precision', () {
    final payload = _payload()..['created_at'] = '2026-01-01T10:00:00.123456Z';
    expect(
      PaymentIntentModel.fromJson(payload).createdAt,
      DateTime.parse('2026-01-01T10:00:00.123456Z'),
    );
  });
  test('typed DateTime adapter inputs preserve the instant', () {
    final created = DateTime(2026, 1, 1, 10);
    final payload = _payload()
      ..['created_at'] = created
      ..['expires_at'] = created.add(const Duration(hours: 1));
    expect(PaymentIntentModel.fromJson(payload).createdAt, created.toUtc());
  });
  for (final expiry in ['2026-01-01T10:00:00Z', '2025-12-31T10:00:00Z']) {
    test('nonpositive lifetime ending $expiry is rejected', () {
      final payload = _payload()..['expires_at'] = expiry;
      expect(() => PaymentIntentModel.fromJson(payload), throwsFormatException);
    });
  }
  test('lifetime comparison uses instants not timezone clock labels', () {
    final payload = _payload()
      ..['created_at'] = '2026-01-01T12:00:00+02:00'
      ..['expires_at'] = '2026-01-01T10:30:00Z';
    expect(
      PaymentIntentModel.fromJson(payload).expiresAt,
      DateTime.utc(2026, 1, 1, 10, 30),
    );
  });
  for (final field in [
    'rail',
    'currency',
    'network',
    'receiver_momo_number',
    'receiver_momo_number_hash',
    'receiver_label',
    'sender_phone_hash',
  ]) {
    test('wrong optional text type in $field yields a safe format error', () {
      final payload = _payload()..[field] = {'secret': 'must-not-appear'};
      try {
        PaymentIntentModel.fromJson(payload);
        fail('Expected FormatException');
      } on FormatException catch (error) {
        expect(error.source, isNull);
        expect(error.toString(), isNot(contains('must-not-appear')));
      }
    });
  }
  test('existing optional routing and display defaults are preserved', () {
    final payload = _payload()
      ..remove('rail')
      ..remove('currency');
    final intent = PaymentIntentModel.fromJson(payload);
    expect(intent.rail, 'rwanda_momo');
    expect(intent.currency, 'RWF');
    expect(intent.momoNetwork, 'mtn_momo');
    expect(intent.receiverMomoNumber, '');
  });
  test('unsupported rail and currency remain rejected', () {
    for (final entry in {'rail': 'bank', 'currency': 'USD'}.entries) {
      final payload = _payload()..[entry.key] = entry.value;
      expect(() => PaymentIntentModel.fromJson(payload), throwsFormatException);
    }
  });
  test('optional display whitespace behavior is preserved', () {
    final payload = _payload()..['receiver_label'] = ' Receiver ';
    expect(PaymentIntentModel.fromJson(payload).receiverMomoLabel, 'Receiver');
  });
  test('decoder never mutates the supplied map', () {
    final payload = _payload()..['expected_amount_rwf'] = 1000;
    final before = jsonEncode(payload);
    PaymentIntentModel.fromJson(payload);
    expect(jsonEncode(payload), before);
  });
  test('invalid monetary payload is not attached to a format error', () {
    final payload = _payload()..['amount_minor'] = 'sensitive-source-text';
    try {
      PaymentIntentModel.fromJson(payload);
      fail('Expected FormatException');
    } on FormatException catch (error) {
      expect(error.source, isNull);
      expect(error.toString(), isNot(contains('sensitive-source-text')));
    }
  });
}
