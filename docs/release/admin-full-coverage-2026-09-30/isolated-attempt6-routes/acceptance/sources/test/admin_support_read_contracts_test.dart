import 'package:collect_app/admin/core/admin_read_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/admin_read_fixture.dart';

Map<String, dynamic> _sla() => {
  'queue_key': 'admin_list_collect_reconciliations',
  'target': 'Clear allocation exceptions by the next business day',
  'owner': 'Payments operations',
  'escalation':
      'Escalate unresolved variance without bypassing maker-checker controls',
  'updated_at': adminReadDate,
};
Map<String, dynamic> _approval() => {
  'user_id': adminReadTarget,
  'phone_masked': null,
  'approved_at': null,
  'expires_at': null,
  'status': 'not_approved',
  'approved': false,
  'role_granted': false,
  'admin_access': false,
  'access_status': 'revoked',
};

void main() {
  const queue = 'admin_list_collect_reconciliations';
  test('SLA accepts exact source policy and explicit policy-not-found', () {
    final result = parseAdminQueueSla(_sla(), queueKey: ' $queue ')!;
    expect(result.target, _sla()['target']);
    expect(result.owner, _sla()['owner']);
    expect(parseAdminQueueSla({}, queueKey: queue), isNull);
  });
  for (final field in _sla().keys) {
    test('SLA missing $field is not presentation defaults', () {
      expect(
        () => parseAdminQueueSla(_sla()..remove(field), queueKey: queue),
        throwsFormatException,
      );
    });
  }
  for (final (key, value) in <(String, Object?)>[
    ('queue_key', 'admin_list_collect_payees'),
    ('target', null),
    ('target', ''),
    ('owner', 1),
    ('escalation', true),
    ('updated_at', '2026-02-30T08:00:00Z'),
    ('private_context', 'secret'),
  ]) {
    test('SLA rejects $key=$value', () {
      expect(
        () => parseAdminQueueSla({..._sla(), key: value}, queueKey: queue),
        throwsFormatException,
      );
    });
  }
  for (final value in [null, [], true, 'policy']) {
    test('SLA refuses null or nonobject $value', () {
      expect(
        () => parseAdminQueueSla(value, queueKey: queue),
        throwsFormatException,
      );
    });
  }
  for (final key in [
    '',
    'notifications',
    'admin_list_',
    'admin_list_x\nprivate',
    'x' * 129,
  ]) {
    test('SLA malformed request is rejected: $key', () {
      expect(() => validateAdminQueueSlaRequest(key), throwsFormatException);
    });
  }
  for (final status in [
    'not_approved',
    'revoked',
    'expired',
    'identity_changed',
    'approved',
  ]) {
    for (final granted in [false, true]) {
      test(
        'approval source state $status role=$granted has exact semantics',
        () {
          final approved = status == 'approved';
          final row = {
            ..._approval(),
            'status': status,
            'approved': approved,
            'role_granted': granted,
            'admin_access': approved && granted,
            'access_status': approved && granted
                ? 'active'
                : granted
                ? 'approval_required'
                : approved
                ? 'approved'
                : 'revoked',
          };
          expect(adminApprovalReadMatches(adminReadTarget, row), isTrue);
        },
      );
    }
  }
  for (final key in _approval().keys) {
    test('approval requires declared nullable field $key', () {
      expect(
        adminApprovalReadMatches(adminReadTarget, _approval()..remove(key)),
        isFalse,
      );
    });
  }
  for (final (key, value) in <(String, Object?)>[
    ('user_id', adminReadActor),
    ('phone_masked', 1),
    ('approved_at', true),
    ('expires_at', '2026-02-30T08:00:00Z'),
    ('approved', 'false'),
    ('role_granted', null),
    ('admin_access', true),
    ('status', 'unknown'),
    ('access_status', 'active'),
    ('private_context', 'secret'),
  ]) {
    test('approval rejects decision substitution $key=$value', () {
      expect(
        adminApprovalReadMatches(adminReadTarget, {..._approval(), key: value}),
        isFalse,
      );
    });
  }
}
