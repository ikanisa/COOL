import 'package:flutter_test/flutter_test.dart';
import 'package:collect_app/admin/core/admin_sender_retention_models.dart';
import 'support/retention_fixture.dart';

void main() {
  test('v1 snapshot refuses a different valid retention protocol hash', () {
    final r = decoded(readInitialRaw);
    (r['retention'] as Map)['protocol_sha256'] = 'a' * 64;
    expect(() => AdminRetentionSnapshot.parse(r, actor, session), throwsFormatException);
  });
  test('v1 intent refuses a different valid retention protocol hash', () {
    expect(() => AdminRetentionIntent.parse({
      ...originalIntent().row,
      'protocol_sha256': 'a' * 64,
    }), throwsFormatException);
  });
  for (final raw in [
    readInitialRaw,
    readNoManageRaw,
    cronUnavailableRaw,
    readEnabledRaw,
  ]) {
    test('real closed11 producer read ${raw.hashCode}', () {
      final s = AdminRetentionSnapshot.parse(decoded(raw), actor, session);
      expect(s.fresh(s.checkedAt), isTrue);
      expect(s.fresh(s.validUntil), isFalse);
      expect((s.row['retention'] as Map)['cold_expiry_allowed'], isFalse);
    });
  }
  test(
    'exact real configure/recovery producer intent yields portable SQL fingerprint',
    () {
      final i = originalIntent(), r = recorded();
      expect(i.fingerprint, decoded(recordedRaw)['fingerprint_sha256']);
      expect(AdminRetentionRequest.parse(decoded(recoveredRaw), i).row, r.row);
    },
  );
  test('all source intent binding fields alter or refuse the fingerprint', () {
    final i = originalIntent();
    for (final e in {
      'request_id': '11111111-1111-4111-8111-111111111111',
      'actor_id': '22222222-2222-4222-8222-222222222222',
      'session_id': '33333333-3333-4333-8333-333333333333',
      'expected_revision': i.row['expected_revision'] + 1,
      'enabled': true,
      'batch_limit': 13,
      'byte_limit': 1048577,
      'reason': 'Changed exact recorded reason',
      'expires_at': retentionUtc(i.expiresAt.add(const Duration(seconds: 1))),
      'protocol_sha256': 'f' * 64,
    }.entries) {
      final next = AdminRetentionIntent.parse({...i.row, e.key: e.value});
      expect(next.fingerprint, isNot(i.fingerprint));
    }
  });
  test('closed read shapes and impossible authority claims refuse', () {
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (r) => r['extra'] = true,
      (r) => r['actor_id'] = session,
      (r) => (r['configuration'] as Map)['revision'] = 6.5,
      (r) => (r['cron'] as Map)['command_sha256'] = 'f' * 64,
      (r) => (r['retention'] as Map)['cold_expiry_allowed'] = true,
      (r) => (r['platform_policies']['android'] as Map)['verification_state'] =
          'runtime_observed',
      (r) => (r['platform_policies']['scheduler'] as Map)['observed_at'] =
          r['checked_at'],
    ]) {
      final r = decoded(readInitialRaw);
      mutate(r);
      expect(
        () => AdminRetentionSnapshot.parse(r, actor, session),
        throwsFormatException,
      );
    }
  });
  test('recorded bindings and exact revision/cron/time cannot be replaced', () {
    final i = originalIntent();
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (r) => r['fingerprint_sha256'] = 'f' * 64,
      (r) => (r['after_configuration'] as Map)['revision'] = 999,
      (r) => (r['after_configuration'] as Map)['byte_limit'] = 2,
      (r) => (r['after_cron'] as Map)['state'] = 'active',
      (r) => r['recorded_at'] = i.row['expires_at'],
      (r) => r['actor_id'] = session,
    ]) {
      final r = decoded(recordedRaw);
      mutate(r);
      expect(() => AdminRetentionRequest.parse(r, i), throwsFormatException);
    }
  });
  test('unavailable cron is distinct from absent with exactly null fields', () {
    final r = decoded(cronUnavailableRaw);
    expect(
      AdminRetentionSnapshot.parse(r, actor, session).cron['state'],
      'unavailable',
    );
    (r['cron'] as Map)['job_id'] = 1;
    expect(
      () => AdminRetentionSnapshot.parse(r, actor, session),
      throwsFormatException,
    );
  });
  test('protected DTOs are deeply immutable', () {
    final s = initial();
    expect(() => s.configuration['enabled'] = true, throwsUnsupportedError);
    expect(
      () => s.policies['android']['observed_at'] = 'made up',
      throwsUnsupportedError,
    );
  });
}
