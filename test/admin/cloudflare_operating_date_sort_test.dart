import 'package:collect_app/admin/core/admin_models.dart';
import 'package:collect_app/admin/core/cloudflare_admin_operating_pages.dart';
import 'package:flutter_test/flutter_test.dart';

AdminTableRowData _row(String id, Object? value, {String key = 'created_at'}) =>
    AdminTableRowData(
      id: id,
      title: id,
      subtitle: '',
      status: '',
      amount: '',
      extra: {key: value},
    );

void main() {
  test('date comparators are limited to normalized display date keys', () {
    for (final key in [
      'created_at',
      'updated_at',
      'observed_at',
      'posted_at',
      'retained_until',
    ]) {
      expect(operatingDateComparator(key), isNotNull, reason: key);
    }
    for (final key in [
      'provider_timestamp_raw',
      'received_at_provider_raw',
      'raw_provider_time',
      'received_at_device_text',
      'title',
      'amount_rwf',
    ]) {
      expect(operatingDateComparator(key), isNull, reason: key);
    }
  });

  test(
    'raw instants sort across days, months and years in both directions',
    () {
      final compare = operatingDateComparator('created_at')!;
      final rows = [
        _row('february', '2026-02-01T00:00:00Z'),
        _row('january-last-day', '2026-01-31T10:00:00Z'),
        _row(
          'january-second-day',
          DateTime.utc(2026, 1, 2).millisecondsSinceEpoch ~/ 1000,
        ),
        _row('new-year', DateTime.utc(2026)),
        _row('old-year', '2025-12-31T23:59:00Z'),
      ];
      rows.sort(compare);
      expect(rows.map((row) => row.id), [
        'old-year',
        'new-year',
        'january-second-day',
        'january-last-day',
        'february',
      ]);
      rows.sort((left, right) => -compare(left, right));
      expect(rows.map((row) => row.id), [
        'february',
        'january-last-day',
        'january-second-day',
        'new-year',
        'old-year',
      ]);
    },
  );

  test('DateTime, epoch seconds and offset strings compare as instants', () {
    for (final key in ['observed_at', 'retained_until']) {
      final compare = operatingDateComparator(key)!;
      final utc = DateTime.utc(2025, 12, 31, 22, 30);
      final native = _row('native', utc, key: key);
      final seconds = _row(
        'seconds',
        utc.millisecondsSinceEpoch ~/ 1000,
        key: key,
      );
      final offset = _row('offset', '2026-01-01T00:30:00+02:00', key: key);
      expect(compare(native, seconds), 0);
      expect(compare(seconds, offset), 0);
      expect(compare(offset, native), 0);
      expect(
        compare(
          _row('earlier', '2026-01-01T00:15:00+02:00', key: key),
          _row('later', '2025-12-31T23:30:00Z', key: key),
        ),
        lessThan(0),
      );
      expect(
        compare(
          _row('earlier', '2026-01-01T23:30:00Z', key: key),
          _row('later', '2026-01-01T23:00:00-02:00', key: key),
        ),
        lessThan(0),
      );
    }
  });

  test(
    'null and unknown values retain an explicit order distinct from zero',
    () {
      final compare = operatingDateComparator('created_at')!;
      final epoch = _row('epoch', 0);
      for (final unknown in [
        null,
        'not recorded',
        '',
        true,
        0.5,
        9007199254740991,
      ]) {
        final row = _row('unknown', unknown);
        expect(compare(row, epoch), lessThan(0));
        expect(compare(epoch, row), greaterThan(0));
        expect(compare(row, _row('null', null)), 0);
        expect(-compare(row, epoch), greaterThan(0));
      }
      expect(compare(epoch, _row('epoch-string', '1970-01-01T00:00:00Z')), 0);
    },
  );
}
