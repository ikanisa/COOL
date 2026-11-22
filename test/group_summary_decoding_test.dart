import 'dart:convert';

import 'package:collect_app/shared/models/collect_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Synthetic payloads only. No server or payment operations.
Map<String, dynamic> _legacy({bool rwfNames = false}) => {
  'currency': 'RWF',
  (rwfNames ? 'amount_raised_rwf' : 'amount_raised_minor'): 1200,
  (rwfNames ? 'current_user_balance_rwf' : 'current_user_balance_minor'): 400,
  'supporter_count': 3,
};

Map<String, dynamic> _modern() => {
  'currency': 'RWF',
  'supporter_count': 3,
  'balances': [
    {
      'currency': 'RWF',
      'amount_raised_minor': 1200,
      'current_user_balance_minor': 400,
    },
  ],
};

void main() {
  group('legacy summary decoding', () {
    for (final rwfNames in [false, true]) {
      final totalKey = rwfNames ? 'amount_raised_rwf' : 'amount_raised_minor';
      final ownKey = rwfNames
          ? 'current_user_balance_rwf'
          : 'current_user_balance_minor';
      final dialect = rwfNames ? 'rwf aliases' : 'minor fields';
      test('$dialect preserves supplied amounts and count', () {
        final summary = CollectionSummary.fromJson(_legacy(rwfNames: rwfNames));
        expect(summary.amountRaisedRwf, 1200);
        expect(summary.currentUserBalanceRwf, 400);
        expect(summary.supporterCount, 3);
      });
      test('$dialect preserves real zero', () {
        final payload = _legacy(rwfNames: rwfNames)
          ..[totalKey] = 0
          ..[ownKey] = 0
          ..['supporter_count'] = 0;
        final summary = CollectionSummary.fromJson(payload);
        expect(summary.totalsByCurrency, {'RWF': 0});
        expect(summary.ownBalancesByCurrency, {'RWF': 0});
        expect(summary.supporterCount, 0);
      });
      test('$dialect does not invent an omitted contributor count', () {
        final payload = _legacy(rwfNames: rwfNames)..remove('supporter_count');
        final summary = CollectionSummary.fromJson(payload);
        expect(summary.amountRaisedRwf, 1200);
        expect(summary.supporterCount, isNull);
        expect(summary.supporterCountSemantics, contains('unavailable'));
      });
      test('$dialect rejects a missing group total', () {
        final payload = _legacy(rwfNames: rwfNames)..remove(totalKey);
        expect(
          () => CollectionSummary.fromJson(payload),
          throwsFormatException,
        );
      });
      test('$dialect rejects a missing member balance', () {
        final payload = _legacy(rwfNames: rwfNames)..remove(ownKey);
        expect(
          () => CollectionSummary.fromJson(payload),
          throwsFormatException,
        );
      });
    }
    test('null contributor count remains unknown', () {
      final payload = _legacy()..['supporter_count'] = null;
      expect(CollectionSummary.fromJson(payload).supporterCount, isNull);
    });
    test('whole-valued doubles remain exact', () {
      final payload = _legacy()
        ..['amount_raised_minor'] = 1200.0
        ..['current_user_balance_minor'] = 400.0
        ..['supporter_count'] = 3.0;
      final summary = CollectionSummary.fromJson(payload);
      expect(summary.amountRaisedRwf, 1200);
      expect(summary.currentUserBalanceRwf, 400);
      expect(summary.supporterCount, 3);
    });
    test(
      'signed supplied amounts are not changed into a new business policy',
      () {
        final payload = _legacy()
          ..['amount_raised_minor'] = -1200
          ..['current_user_balance_minor'] = -400;
        final summary = CollectionSummary.fromJson(payload);
        expect(summary.amountRaisedRwf, -1200);
        expect(summary.currentUserBalanceRwf, -400);
      },
    );
    final invalidAmounts = <String, Object?>{
      'null': null,
      'fraction': 10.75,
      'negative fraction': -10.75,
      'numeric text': '1200',
      'boolean': true,
      'list': <int>[1200],
      'not a number': double.nan,
      'infinity': double.infinity,
      'negative infinity': double.negativeInfinity,
      'unsafe positive integer': 9007199254740992,
      'unsafe negative integer': -9007199254740992,
    };
    for (final field in ['amount_raised_minor', 'current_user_balance_minor']) {
      for (final entry in invalidAmounts.entries) {
        test('$field rejects ${entry.key}', () {
          final payload = _legacy()..[field] = entry.value;
          expect(
            () => CollectionSummary.fromJson(payload),
            throwsFormatException,
          );
        });
      }
    }
    test('both exact-integer boundary values are retained', () {
      final payload = _legacy()
        ..['amount_raised_minor'] = 9007199254740991
        ..['current_user_balance_minor'] = -9007199254740991;
      final summary = CollectionSummary.fromJson(payload);
      expect(summary.amountRaisedRwf, 9007199254740991);
      expect(summary.currentUserBalanceRwf, -9007199254740991);
    });
    for (final entry in <String, Object>{
      'negative': -1,
      'fractional': 1.5,
      'text': '3',
      'boolean': false,
      'infinite': double.infinity,
      'unsafe integer': 9007199254740992,
    }.entries) {
      test('contributor count rejects ${entry.key}', () {
        final payload = _legacy()..['supporter_count'] = entry.value;
        expect(
          () => CollectionSummary.fromJson(payload),
          throwsFormatException,
        );
      });
    }
    test('equal dual aliases are accepted', () {
      final payload = _legacy()
        ..['amount_raised_rwf'] = 1200.0
        ..['current_user_balance_rwf'] = 400;
      expect(CollectionSummary.fromJson(payload).amountRaisedRwf, 1200);
    });
    for (final alias in ['amount_raised_rwf', 'current_user_balance_rwf']) {
      test('conflicting $alias is rejected', () {
        final payload = _legacy()..[alias] = 999;
        expect(
          () => CollectionSummary.fromJson(payload),
          throwsFormatException,
        );
      });
      test('malformed $alias is not hidden by the preferred field', () {
        final payload = _legacy()..[alias] = 0.25;
        expect(
          () => CollectionSummary.fromJson(payload),
          throwsFormatException,
        );
      });
    }
    test('null unused preferred aliases may use valid legacy aliases', () {
      final payload = _legacy(rwfNames: true)
        ..['amount_raised_minor'] = null
        ..['current_user_balance_minor'] = null;
      expect(CollectionSummary.fromJson(payload).amountRaisedRwf, 1200);
    });
    test('a malformed preferred field cannot fall back to an old value', () {
      final payload = _legacy()
        ..['amount_raised_minor'] = 'untrusted payload'
        ..['amount_raised_rwf'] = 1200;
      expect(() => CollectionSummary.fromJson(payload), throwsFormatException);
    });
    test('empty legacy object is not a zero summary', () {
      expect(() => CollectionSummary.fromJson(const {}), throwsFormatException);
    });
    test('decoding does not mutate the supplied map', () {
      final payload = _legacy();
      final before = jsonEncode(payload);
      CollectionSummary.fromJson(payload);
      expect(jsonEncode(payload), before);
    });
    test('errors contain no received values or source payload', () {
      const privateMarker = 'private-payload-never-log';
      final payload = _legacy()..['amount_raised_minor'] = privateMarker;
      try {
        CollectionSummary.fromJson(payload);
        fail('Expected malformed payload to fail');
      } on FormatException catch (error) {
        expect(error.message, isNot(contains(privateMarker)));
        expect(error.source, isNull);
      }
    });
  });

  group('currency metadata compatibility', () {
    test('absent currency retains the existing RWF default', () {
      final payload = _legacy()..remove('currency');
      expect(CollectionSummary.fromJson(payload).currency, 'RWF');
    });
    test('existing nonblank legacy currencies are not converted', () {
      final payload = _legacy()..['currency'] = 'EUR';
      final summary = CollectionSummary.fromJson(payload);
      expect(summary.currency, 'EUR');
      expect(summary.totalsByCurrency, {'EUR': 1200});
    });
    for (final value in <Object>['', '   ', 123, <String>[]]) {
      test('invalid currency ${value.runtimeType}: $value is rejected', () {
        final payload = _legacy()..['currency'] = value;
        expect(
          () => CollectionSummary.fromJson(payload),
          throwsFormatException,
        );
      });
    }
  });

  group('modern balances contract remains separate', () {
    test('valid modern payload is unchanged', () {
      final summary = CollectionSummary.fromJson(_modern());
      expect(summary.totalsByCurrency, {'RWF': 1200});
      expect(summary.ownBalancesByCurrency, {'RWF': 400});
      expect(summary.supporterCount, 3);
    });
    test('explicit empty balances retains existing zero semantics', () {
      final payload = _modern()..['balances'] = <Object>[];
      expect(CollectionSummary.fromJson(payload).totalsByCurrency, {'RWF': 0});
    });
    test('missing modern count is still unknown', () {
      final payload = _modern()..remove('supporter_count');
      expect(CollectionSummary.fromJson(payload).supporterCount, isNull);
    });
    test('malformed modern balances cannot fall through to legacy values', () {
      final payload = _legacy()..['balances'] = null;
      expect(() => CollectionSummary.fromJson(payload), throwsFormatException);
    });
    test('duplicate modern currency remains rejected', () {
      final payload = _modern();
      final rows = List<dynamic>.from(payload['balances'] as List);
      rows.add(Map<String, dynamic>.from(rows.first as Map));
      payload['balances'] = rows;
      expect(() => CollectionSummary.fromJson(payload), throwsFormatException);
    });
    test('modern non-RWF rows remain rejected', () {
      final payload = _modern();
      ((payload['balances'] as List).first as Map)['currency'] = 'EUR';
      expect(() => CollectionSummary.fromJson(payload), throwsFormatException);
    });
    test('modern missing amounts remain rejected', () {
      final payload = _modern();
      ((payload['balances'] as List).first as Map).remove(
        'amount_raised_minor',
      );
      expect(() => CollectionSummary.fromJson(payload), throwsFormatException);
    });
  });
}
