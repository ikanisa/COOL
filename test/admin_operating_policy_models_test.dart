import 'package:collect_app/admin/core/admin_operating_policy_models.dart';
import 'package:collect_app/admin/core/admin_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/admin_operating_policy_fixture.dart';

void main() {
  test(
    'actual SQL policy sample is read-only preparation with exact freshness',
    () {
      final raw = operatingPolicyFixture();
      final sample = AdminOperatingPolicySnapshot.parse(raw);
      expect(sample.id, raw['policy_id']);
      expect(sample.configuredMode, AdminPolicyMode.paused);
      expect(sample.emergencyStop, isTrue);
      expect(sample.lastChangeRequestId, isNull);
      expect(sample.isFresh(sample.checkedAt), isTrue);
      expect(sample.isFresh(sample.validUntil), isFalse);
      expect(
        sample.isFresh(
          sample.checkedAt.subtract(const Duration(microseconds: 1)),
        ),
        isFalse,
      );
    },
  );

  for (final mode in [AdminPolicyMode.shadow, AdminPolicyMode.dryRun]) {
    for (final stop in [false, true]) {
      test(
        'later ${mode.label} preference preserves stop=$stop derivation',
        () {
          final raw = operatingPolicyFixture()
            ..['revision'] = 2
            ..['last_change_request_id'] =
                'abcd0000-0000-4000-8000-000000000001'
            ..['configured_mode'] = mode.label
            ..['emergency_stop'] = stop
            ..['effective_mode'] = stop ? 'Paused' : mode.label;
          final sample = AdminOperatingPolicySnapshot.parse(raw);
          expect(sample.configuredMode, mode);
          expect(sample.effectiveMode, stop ? AdminPolicyMode.paused : mode);
        },
      );
    }
  }

  final mutations = <String, void Function(Map<String, dynamic>)>{
    'extra private field': (v) => v['PRIVATE_CANARY'] = 'sensitive',
    'missing revision': (v) => v.remove('revision'),
    'double contract version': (v) => v['contract_version'] = 1.0,
    'double revision': (v) => v['revision'] = 1.0,
    'zero revision': (v) => v['revision'] = 0,
    'exhausted revision': (v) => v['revision'] = 1000000001,
    'wrong purpose': (v) => v['purpose'] = 'live_dispatch',
    'wrong scope': (v) => v['scope'] = 'RW',
    'noncanonical UUID': (v) =>
        v['policy_id'] = (v['policy_id'] as String).toUpperCase(),
    'live preference': (v) => v['configured_mode'] = 'Live',
    'live-limited preference': (v) => v['configured_mode'] = 'Live-limited',
    'string stop': (v) => v['emergency_stop'] = 'true',
    'paused without stop': (v) => v['emergency_stop'] = false,
    'wrong derived preference': (v) => v['effective_mode'] = 'Shadow',
    'TTL extended': (v) => v['sample_valid_until'] = DateTime.parse(
      v['checked_at'] as String,
    ).add(const Duration(seconds: 61)).toIso8601String(),
    'offset timestamp': (v) => v['checked_at'] = (v['checked_at'] as String)
        .replaceFirst('Z', '+00:00'),
    'invalid Gregorian date': (v) =>
        v['checked_at'] = '2026-02-30T00:00:00.000000Z',
    'updated after read': (v) => v['updated_at'] = v['sample_valid_until'],
    'initialized after update': (v) => v['initialized_at'] = v['checked_at'],
    'missing changed head': (v) => v['revision'] = 2,
    'fabricated default actor action': (v) =>
        v['last_change_request_id'] = v['policy_id'],
    'short mode list': (v) => (v['modes'] as List).removeLast(),
    'reordered modes': (v) =>
        v['modes'] = (v['modes'] as List).reversed.toList(),
    'live selectable': (v) => (v['modes'] as List)[3]['selectable'] = true,
    'invented limit': (v) => v['limits']['global_sms'] = 100,
    'enforcement assertion': (v) => v['limits']['enforcement'] = true,
    'invented schedule owner': (v) => v['schedule']['owner'] = 'AI',
    'invented cadence': (v) => v['schedule']['cadence_seconds'] = 60,
    'unverified financial approval': (v) =>
        v['approvals']['financial'] = 'approved',
    'dispatch authority assertion': (v) =>
        v['execution']['unattended_dispatch_available'] = true,
    'assisted boundary unknown': (v) =>
        v['boundaries']['assisted_dispatch'] = 'live',
    'assisted mutation capability': (v) =>
        v['boundaries']['policy_changes_assisted_dispatch'] = true,
  };
  for (final entry in mutations.entries) {
    test(
      'rejects ${entry.key} instead of displaying unsupported authority',
      () {
        final raw = operatingPolicyFixture();
        entry.value(raw);
        expect(
          () => AdminOperatingPolicySnapshot.parse(raw),
          throwsFormatException,
        );
      },
    );
  }
  test(
    'read access requires platform owner and both independent permissions',
    () {
      AdminIdentity actor(List<String> roles, List<String> permissions) =>
          AdminIdentity(
            userId: 'abcd0000-0000-4000-8000-000000000001',
            displayName: 'Synthetic policy reviewer',
            roles: roles,
            permissions: permissions,
          );
      const reads = ['notifications.read', 'system_health.read'];
      expect(
        adminOperatingPolicyCanRead(actor(['platform_owner'], reads)),
        isTrue,
      );
      expect(adminOperatingPolicyCanRead(actor(['admin'], reads)), isFalse);
      for (final missing in reads) {
        expect(
          adminOperatingPolicyCanRead(
            actor([
              'platform_owner',
            ], reads.where((p) => p != missing).toList()),
          ),
          isFalse,
        );
      }
      expect(adminOperatingPolicyCanRead(null), isFalse);
    },
  );
}
