import 'package:cool_app/core/utils/json_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('asMap', () {
    test('returns Map<String, dynamic> as-is', () {
      final input = <String, dynamic>{'key': 'value'};
      expect(asMap(input), same(input));
    });

    test('converts Map<dynamic, dynamic> to Map<String, dynamic>', () {
      final input = <dynamic, dynamic>{'key': 42};
      expect(asMap(input), isA<Map<String, dynamic>>());
      expect(asMap(input)['key'], 42);
    });

    test('throws StateError for non-Map', () {
      expect(() => asMap('not a map'), throwsStateError);
      expect(() => asMap(42), throwsStateError);
      expect(() => asMap(null), throwsStateError);
    });
  });

  group('asMapOrNull', () {
    test('returns map for valid input', () {
      expect(asMapOrNull(<String, dynamic>{'a': 1}), isNotNull);
    });

    test('returns null for non-map', () {
      expect(asMapOrNull('string'), isNull);
      expect(asMapOrNull(null), isNull);
      expect(asMapOrNull(42), isNull);
    });
  });

  group('asMapOrEmpty', () {
    test('returns map for valid input', () {
      expect(asMapOrEmpty(<String, dynamic>{'a': 1}), {'a': 1});
    });

    test('returns empty map for non-map', () {
      expect(asMapOrEmpty(null), isEmpty);
      expect(asMapOrEmpty('string'), isEmpty);
    });
  });

  group('asListOfMaps', () {
    test('converts list of maps', () {
      final input = [
        <String, dynamic>{'id': 1},
        <String, dynamic>{'id': 2},
      ];
      final result = asListOfMaps(input);
      expect(result, hasLength(2));
      expect(result[0]['id'], 1);
    });

    test('skips non-map entries', () {
      final input = [
        <String, dynamic>{'id': 1},
        'not a map',
        42,
      ];
      final result = asListOfMaps(input);
      expect(result, hasLength(1));
    });

    test('throws StateError for non-list', () {
      expect(() => asListOfMaps('not a list'), throwsStateError);
    });
  });

  group('asBool', () {
    test('returns bool values directly', () {
      expect(asBool(true), isTrue);
      expect(asBool(false), isFalse);
    });

    test('converts numeric values', () {
      expect(asBool(1), isTrue);
      expect(asBool(0), isFalse);
      expect(asBool(-1), isTrue);
    });

    test('converts string values', () {
      expect(asBool('true'), isTrue);
      expect(asBool('TRUE'), isTrue);
      expect(asBool('1'), isTrue);
      expect(asBool('false'), isFalse);
      expect(asBool('0'), isFalse);
      expect(asBool(''), isFalse);
    });

    test('returns false for null/other', () {
      expect(asBool(null), isFalse);
      expect(asBool(<String>[]), isFalse);
    });
  });

  group('asDouble', () {
    test('returns double values directly', () {
      expect(asDouble(3.14), 3.14);
    });

    test('converts int to double', () {
      expect(asDouble(42), 42.0);
    });

    test('parses string to double', () {
      expect(asDouble('3.14'), 3.14);
      expect(asDouble('invalid'), isNull);
    });

    test('returns null for null', () {
      expect(asDouble(null), isNull);
    });
  });

  group('asInt', () {
    test('returns int values directly', () {
      expect(asInt(42), 42);
    });

    test('converts double to int', () {
      expect(asInt(3.9), 3);
    });

    test('parses string to int', () {
      expect(asInt('42'), 42);
      expect(asInt('invalid'), isNull);
    });

    test('returns null for null', () {
      expect(asInt(null), isNull);
    });
  });

  group('asStringOrNull', () {
    test('returns string for non-null', () {
      expect(asStringOrNull('hello'), 'hello');
      expect(asStringOrNull(42), '42');
    });

    test('returns null for null', () {
      expect(asStringOrNull(null), isNull);
    });
  });

  group('parseDateTime', () {
    test('parses valid ISO-8601', () {
      final result = parseDateTime('2026-01-15T10:30:00.000Z');
      expect(result, isNotNull);
      expect(result!.year, 2026);
      expect(result.month, 1);
      expect(result.day, 15);
    });

    test('returns null for null', () {
      expect(parseDateTime(null), isNull);
    });

    test('returns null for invalid string', () {
      expect(parseDateTime('not-a-date'), isNull);
    });
  });
}
