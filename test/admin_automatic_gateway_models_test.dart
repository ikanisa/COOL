import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_automatic_gateway_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> automaticFixture(String name) =>
    jsonDecode(
          File(
            'test/fixtures/admin_automatic_gateway_observed/admin-$name.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

AdminAutomaticReceiptEvidence receipt(
  Map<String, dynamic> value, {
  AdminAutomaticHistoryCursor? before,
}) => AdminAutomaticReceiptEvidence.parse(
  value,
  receiptId: value['receipt_id'] as String,
  limit: value['limit'] as int,
  before: before,
);

void main() {
  for (final name in [
    'current-receipt-before-automatic-grant',
    'missing-receipt-is-unavailable',
    'prior-grant-before-arm',
    'arm-expected-callback-plan',
    'partial-multipart-observations',
    'all-framework-callbacks-before-archive',
    'actual-terminal-archive-acknowledgement',
    'late-contradictory-observation',
    'bounded-duplicate-heavy-history',
  ]) {
    test('decodes actual SQL observation: $name', () {
      final value = receipt(automaticFixture(name));
      expect(value.isFresh(value.checkedAt), isTrue);
      expect(value.isFresh(value.validUntil), isFalse);
    });
  }
  test('historical acknowledgement survives current contradiction', () {
    final value = receipt(automaticFixture('late-contradictory-observation'));
    expect(value.attempt!.state, 'uncertain');
    expect(value.archiveAck, isNotNull);
    expect(value.expectedCallbacks.where((c) => !c.consistent), hasLength(1));
  });
  for (final field in ['send_authority', 'carrier_proof', 'delivery_proven']) {
    test('refuses invented $field authority', () {
      final data = automaticFixture('late-contradictory-observation')
        ..[field] = true;
      expect(() => receipt(data), throwsFormatException);
    });
  }
  test('refuses receipt evidence substituted from a different target', () {
    final data = automaticFixture('late-contradictory-observation');
    expect(
      () => AdminAutomaticReceiptEvidence.parse(
        data,
        receiptId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      ),
      throwsFormatException,
    );
  });
  test('refuses a body injected into redacted attempt evidence', () {
    final data = automaticFixture('late-contradictory-observation');
    (data['attempt'] as Map)['body_text'] = 'unexpected private text';
    expect(() => receipt(data), throwsFormatException);
  });
  test('refuses a historical callback from another callback plan', () {
    final data = automaticFixture('late-contradictory-observation');
    (data['rows'] as List).first['callback_id'] =
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    expect(() => receipt(data), throwsFormatException);
  });
  test(
    'refuses incomplete bindings presented beside a terminal acknowledgement',
    () {
      final data = automaticFixture('late-contradictory-observation');
      (data['expected_callbacks'] as List).removeLast();
      expect(() => receipt(data), throwsFormatException);
    },
  );
  test('refuses history crossing its original paired cursor', () {
    final data = automaticFixture('late-contradictory-observation');
    final first = (data['rows'] as List).first;
    expect(
      () => receipt(
        data,
        before: AdminAutomaticHistoryCursor(
          DateTime.parse(first['recorded_at'] as String),
          first['request_id'] as String,
        ),
      ),
      throwsFormatException,
    );
  });
  test('decodes actual device page and the independent scanned anchor', () {
    final data = automaticFixture('directory-first');
    final value = AdminAutomaticDeviceEvidence.parse(
      data,
      deviceId: data['device_id'] as String,
      limit: 1,
    );
    expect(value.rows, hasLength(1));
    expect(value.scannedCount, 1);
    expect(value.nextCursor, isNotNull);
  });
  test('actual filtered empty page can continue without any visible row', () {
    final data = automaticFixture('filtered-empty-directory');
    final value = AdminAutomaticDeviceEvidence.parse(
      data,
      deviceId: data['device_id'] as String,
      limit: 1,
    );
    expect(value.rows, isEmpty);
    expect(value.scannedCount, 1);
    expect(value.nextCursor, isNotNull);
  });
  test('refuses device page containing a foreign device attempt', () {
    final data = automaticFixture('directory-first');
    (data['rows'] as List).first['device_id'] =
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    expect(
      () => AdminAutomaticDeviceEvidence.parse(
        data,
        deviceId: data['device_id'] as String,
        limit: 1,
      ),
      throwsFormatException,
    );
  });
  test('refuses a device cursor that loops back to the same scan', () {
    final data = automaticFixture('filtered-empty-directory');
    final first = AdminAutomaticDeviceEvidence.parse(
      data,
      deviceId: data['device_id'] as String,
      limit: 1,
    );
    expect(
      () => AdminAutomaticDeviceEvidence.parse(
        data,
        deviceId: data['device_id'] as String,
        limit: 1,
        before: first.nextCursor,
      ),
      throwsFormatException,
    );
  });
  test('retained observations cannot extend their freshness window', () {
    final data = automaticFixture('late-contradictory-observation');
    data['sample_valid_until'] = DateTime.parse(
      data['checked_at'] as String,
    ).add(const Duration(seconds: 61)).toIso8601String();
    expect(() => receipt(data), throwsFormatException);
  });
}
