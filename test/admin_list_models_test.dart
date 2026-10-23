import 'package:collect_app/admin/core/admin_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row(String id) => {'id': id, 'country_code': 'RW'};

void main() {
  for (final missing in [null, '', '   ']) {
    test('missing metric $missing is not shown as zero', () {
      expect(AdminMetric.fromJson({'value': missing}).value, 'Not available');
    });
    test('missing SLA fields $missing are not invented', () {
      final sla = AdminQueueSla.fromJson({
        'target': missing,
        'owner': missing,
        'escalation': missing,
      });
      expect([
        sla.target,
        sla.owner,
        sla.escalation,
      ], everyElement('Not available'));
    });
  }

  test('a measured zero is retained', () {
    expect(AdminMetric.fromJson({'value': 0}).value, '0');
    expect(AdminMetric.fromJson({'value': '0'}).value, '0');
  });

  test('configured SLA values are retained', () {
    final sla = AdminQueueSla.fromJson({
      'target': '2 hours',
      'owner': 'Support',
      'escalation': 'Duty manager',
    });
    expect(
      [sla.target, sla.owner, sla.escalation],
      ['2 hours', 'Support', 'Duty manager'],
    );
  });

  for (final total in [2, '2', ' 2 ', 2.0]) {
    test(
      'integral server total $total (${total.runtimeType}) is supported',
      () {
        final result = AdminListResult.fromJson({
          'rows': [_row('a'), _row('b')],
          'total': total,
        }).validateWindow(limit: 25, offset: 0);
        expect(result.total, 2);
        expect(result.rows, hasLength(2));
        expect(() => result.rows.clear(), throwsUnsupportedError);
      },
    );
  }

  for (final total in [
    -1,
    -1.0,
    2.5,
    '2.5',
    'unknown',
    true,
    double.nan,
    double.infinity,
  ]) {
    test('invalid server total $total (${total.runtimeType}) is rejected', () {
      expect(
        () => AdminListResult.fromJson({'rows': [], 'total': total}),
        throwsFormatException,
      );
    });
  }

  for (final rows in [null, {}, 'rows']) {
    test('invalid rows shape $rows is rejected', () {
      expect(
        () => AdminListResult.fromJson({'rows': rows, 'total': 0}),
        throwsFormatException,
      );
    });
  }

  for (final row in [
    null,
    3,
    {},
    {'id': ''},
    {'id': '   '},
    {'id': 4},
  ]) {
    test('invalid row $row is rejected', () {
      expect(
        () => AdminListResult.fromJson({
          'rows': [row],
          'total': 1,
        }),
        throwsFormatException,
      );
    });
  }

  test('absent total cannot be used as a paged response', () {
    final result = AdminListResult.fromJson({
      'rows': [_row('a')],
    });
    expect(result.total, isNull);
    expect(
      () => result.validateWindow(limit: 25, offset: 0),
      throwsFormatException,
    );
  });

  test('total smaller than returned rows is rejected', () {
    expect(
      () => AdminListResult.fromJson({
        'rows': [_row('a')],
        'total': 0,
      }),
      throwsFormatException,
    );
  });

  test('duplicate IDs within a server window are rejected', () {
    final result = AdminListResult.fromJson({
      'rows': [_row('a'), _row('a')],
      'total': 2,
    });
    expect(
      () => result.validateWindow(limit: 25, offset: 0),
      throwsFormatException,
    );
  });

  test('short or oversized batches cannot silently truncate a list', () {
    final short = AdminListResult.fromJson({
      'rows': [_row('a')],
      'total': 100,
    });
    expect(
      () => short.validateWindow(limit: 25, offset: 0),
      throwsFormatException,
    );
    final long = AdminListResult.fromJson({
      'rows': [_row('a'), _row('b')],
      'total': 2,
    });
    expect(
      () => long.validateWindow(limit: 1, offset: 0),
      throwsFormatException,
    );
  });

  test('a nonempty batch beyond its total is rejected', () {
    final result = AdminListResult.fromJson({
      'rows': [_row('a')],
      'total': 1,
    });
    expect(
      () => result.validateWindow(limit: 25, offset: 25),
      throwsFormatException,
    );
  });

  test('an empty out-of-range batch is allowed for page recovery', () {
    final result = AdminListResult.fromJson({'rows': [], 'total': 53});
    expect(result.validateWindow(limit: 25, offset: 100).total, 53);
  });
}
