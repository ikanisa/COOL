import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release docs describe current SMS-first Groups blockers only', () {
    final docs = <String, String>{
      'decision': File('docs/release/GO_NO_GO_DECISION.md').readAsStringSync(),
      'blockers': File('docs/release/RELEASE_BLOCKERS.md').readAsStringSync(),
      'checklist': File(
        'docs/release/PRODUCTION_READINESS_CHECKLIST.md',
      ).readAsStringSync(),
      'qa': File('docs/release/QA_TEST_REPORT.md').readAsStringSync(),
      'uat': File('docs/release/UAT_EXECUTION_REPORT.md').readAsStringSync(),
      'packet': File(
        'docs/release/UAT_GO_LIVE_PACKET_2026-05-24.md',
      ).readAsStringSync(),
      'security': File(
        'docs/release/SECURITY_PRIVACY_REVIEW.md',
      ).readAsStringSync(),
    };

    for (final text in docs.values) {
      expect(text, contains('SMS-first'));
      expect(text, isNot(contains('auth_captcha_bot_protection')));
      expect(text, isNot(contains('auth_hibp_leaked_password_protection')));
      expect(text, isNot(contains('supabase_organization_plan')));
      expect(text, isNot(contains('supabase_pitr')));
      expect(text, isNot(contains('`113` tests')));
      expect(text, isNot(contains('20260526T042822Z')));
    }

    for (final key in ['decision', 'blockers', 'qa', 'uat', 'packet']) {
      expect(docs[key], contains('NO-GO'));
    }

    expect(
      docs['decision'],
      contains('group creation is available only on Android'),
    );
    expect(docs['blockers'], contains('P0-003'));
    expect(docs['blockers'], contains('ADMIN_PWA_LIVE_URL'));
    expect(docs['checklist'], contains('release_owner_signoff'));
    expect(docs['qa'], contains('83'));
    expect(docs['packet'], contains('Final GO Criteria'));
  });

  test('release status reports current blocker keys', () {
    final result = Process.runSync('./scripts/release_status.sh', ['--json']);
    expect(result.exitCode, 0);

    final decoded = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(decoded['decision'], 'NO-GO');
    expect(
      decoded['blocker_keys'],
      containsAll(<String>[
        'product_signoff',
        'android_sms_access_uat',
        'android_release_signing_review',
        'ios_release_scope',
        'admin_pwa_live_url',
        'release_owner_signoff',
      ]),
    );
    expect(jsonEncode(decoded), isNot(contains('auth_captcha_bot_protection')));
    expect(jsonEncode(decoded), isNot(contains('supabase_pitr')));
  });

  test('go-live gate blocks on current SMS-first blockers', () {
    final status = jsonEncode({
      'decision': 'NO-GO',
      'status': 'blocked',
      'blocker_keys': [
        'linked_supabase_sms_first_migration',
        'android_release_signing_review',
        'ios_release_scope',
        'admin_pwa_live_url',
      ],
    });
    final result = Process.runSync(
      './scripts/supabase_go_live_gate.sh',
      ['--json'],
      environment: {'SUPABASE_GO_LIVE_STATUS_JSON': status},
    );

    expect(result.exitCode, 1);
    final decoded = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(decoded['decision'], 'NO-GO');
    expect(decoded['go_live_approved'], isFalse);
    expect(
      decoded['required_next_actions'],
      contains(
        'Deploy Admin PWA and rerun the live gate with ADMIN_PWA_LIVE_URL.',
      ),
    );
    expect(
      decoded['required_next_actions'],
      contains(
        'Record Android release signing / Play App Signing review evidence and rerun scripts/flutter_mobile_release_gate.sh --json.',
      ),
    );
    expect(
      decoded['required_next_actions'],
      contains(
        'Sign off iOS release scope or mark iOS explicitly out of scope, then rerun scripts/flutter_mobile_release_gate.sh --json.',
      ),
    );
  });

  test('current platform packet is redacted and SMS-first specific', () {
    final status = jsonEncode({
      'decision': 'NO-GO',
      'status': 'blocked',
      'blocker_keys': ['product_signoff', 'android_sms_access_uat'],
    });
    final result = Process.runSync(
      './scripts/supabase_platform_go_live_packet.sh',
      ['--json'],
      environment: {'SUPABASE_PLATFORM_PACKET_STATUS_JSON': status},
    );

    expect(result.exitCode, 0);
    final decoded = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(decoded['operator_actions'], hasLength(2));
    expect(jsonEncode(decoded), contains('Android SMS access UAT'));
    expect(jsonEncode(decoded), isNot(contains('AUTH_CAPTCHA_SECRET')));
    expect(jsonEncode(decoded), isNot(contains('HIBP')));
  });
}
