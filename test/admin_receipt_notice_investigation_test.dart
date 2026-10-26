import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_investigation.dart';
import 'package:collect_app/admin/core/admin_receipt_notice_investigation.dart';
import 'package:flutter_test/flutter_test.dart';

const receiptId = '44444444-4444-4444-8444-444444444444';
const reversalSnapshot = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
final checkedAt = DateTime.utc(2026, 9, 30, 19, 0, 30);

Map<String, dynamic> fixture() =>
    jsonDecode(
          File('test/fixtures/admin_investigation_v1.json').readAsStringSync(),
        )
        as Map<String, dynamic>;

Map<String, dynamic> withReversal({String amount = '1200'}) {
  final raw = fixture();
  (raw['payment']['journals'] as List).add(<String, dynamic>{
    'id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'entry_type': 'reversal',
    'amount_rwf': amount,
    'posted_at': '2026-09-30T19:00:22Z',
    'snapshot': {
      'id': reversalSnapshot,
      'captured_at': '2026-09-30T19:00:23Z',
      'delta_rwf': '-$amount',
      'member_balance_rwf': '5500',
      'group_balance_rwf': '23800',
    },
  });
  return raw;
}

String? select(Map<String, dynamic> raw, {DateTime? now, String? outboxId}) =>
    receiptNoticeReversalSnapshotId(
      AdminInvestigationSnapshot.parse(raw),
      outboxId: outboxId ?? receiptId,
      now: now ?? checkedAt,
    );

void main() {
  test(
    'full compensation uses immutable reversal ID despite current balances',
    () {
      final raw = withReversal();
      raw['payment']['current_balances']['member_rwf'] = '999999';
      raw['payment']['current_balances']['group_rwf'] = '999999';
      expect(select(raw), reversalSnapshot);
      expect(select(fixture()), isNull);
    },
  );

  test('partial reversal cannot select a full compensation notice', () {
    expect(select(withReversal(amount: '600')), isNull);
  });

  test('missing reversal snapshot cannot borrow original posting snapshot', () {
    final raw = withReversal();
    raw['payment']['journals'][1]['snapshot'] = null;
    expect(select(raw), isNull);
  });

  test('reused original snapshot cannot be a compensation identifier', () {
    final raw = withReversal();
    raw['payment']['journals'][1]['snapshot']['id'] =
        raw['receipt']['snapshot_id'];
    expect(select(raw), isNull);
  });

  test(
    'expired or future evidence and different receipt remain unavailable',
    () {
      expect(
        select(withReversal(), now: checkedAt.add(const Duration(seconds: 60))),
        isNull,
      );
      expect(
        select(
          withReversal(),
          now: checkedAt.subtract(const Duration(seconds: 6)),
        ),
        isNull,
      );
      expect(select(withReversal(), outboxId: reversalSnapshot), isNull);
    },
  );

  test('denied payment cannot infer a reversal from receipt balances', () {
    final raw = withReversal();
    raw['kind'] = 'receipt';
    raw['target_id'] = receiptId;
    raw['payment_state'] = 'denied';
    raw['payment'] = null;
    expect(select(raw), isNull);
  });

  test(
    'malformed sign, duplicate or mismatched joined evidence is refused',
    () {
      final sign = withReversal();
      sign['payment']['journals'][1]['snapshot']['delta_rwf'] = '1200';
      expect(() => select(sign), throwsFormatException);
      final duplicate = withReversal();
      duplicate['payment']['journals'][0] = duplicate['payment']['journals'][1];
      expect(() => select(duplicate), throwsFormatException);
      final different = withReversal();
      different['payment']['payment_id'] = reversalSnapshot;
      expect(() => select(different), throwsFormatException);
    },
  );
}
