import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_operational_health.dart';
import 'package:collect_app/admin/core/admin_receipt_overview.dart';
import 'package:collect_app/admin/core/admin_shadow_runs.dart';
import 'package:collect_app/admin/core/admin_sms_queue_health.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/admin_read_fixture.dart';

Object? _year(Object? value, String year) {
  if (value is Map) {
    return value.map((key, item) => MapEntry(key as String, _year(item, year)));
  }
  if (value is List) return value.map((item) => _year(item, year)).toList();
  if (value is String && RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(value)) {
    return year + value.substring(4);
  }
  return value;
}

Map<String, dynamic> _health() => Map<String, dynamic>.from(
  (jsonDecode(
            File(
              'test/fixtures/admin_operational_health148.json',
            ).readAsStringSync(),
          )
          as Map)['receipt']
      as Map,
);

Map<String, dynamic> _shadow() =>
    jsonDecode(
          File(
            'contracts/collect-shadow-supervisor-v1.fixture.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

Map<String, dynamic> _sms() => {
  'enabled': false,
  'queued': 1,
  'awaiting_confirmation': 0,
  'send_started': 0,
  'uncertain': 0,
  'suppressed': 0,
  'active_workers': 0,
  'oldest_queued_at': '2026-09-30T09:59:00Z',
  'observed_at': '2026-09-30T10:00:00Z',
};

void main() {
  final fixtures =
      <
        String,
        ({
          Map<String, dynamic> Function() value,
          void Function(Map<String, dynamic>) parse,
        })
      >{
        'operational health': (
          value: _health,
          parse: (raw) {
            AdminOperationalHealth.parse(raw);
          },
        ),
        'receipt overview': (
          value: () =>
              adminReceiptOverviewFixture(DateTime.utc(2026, 9, 30, 10)),
          parse: (raw) {
            AdminReceiptOverview.parse(raw);
          },
        ),
        'SMS queue': (
          value: _sms,
          parse: (raw) {
            AdminSmsQueueHealth.parse(raw);
          },
        ),
        'shadow history': (
          value: _shadow,
          parse: (raw) {
            AdminShadowRunsSnapshot.parse(raw);
          },
        ),
      };
  for (final entry in fixtures.entries) {
    final name = entry.key, fixture = entry.value;
    test('$name rejects coherent year0000 UTC observation', () {
      // Rewrite the entire timestamp lineage, preserving relative windows,
      // rather than causing an unrelated checked/expiry mismatch.
      final raw = _year(fixture.value(), '0000') as Map<String, dynamic>;
      expect(() => fixture.parse(raw), throwsFormatException);
    });
    for (final year in ['0001', '9999']) {
      test('$name accepts coherent valid UTC year$year observation', () {
        final raw = _year(fixture.value(), year) as Map<String, dynamic>;
        expect(() => fixture.parse(raw), returnsNormally);
      });
    }
  }
}
