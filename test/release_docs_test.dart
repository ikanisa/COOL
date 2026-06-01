import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> approvedReleaseManifest() {
    final manifest =
        jsonDecode(
              File(
                'docs/release/RELEASE_APPROVALS.example.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    manifest['secret_handling'] =
        'Signed approval evidence metadata only; no secrets or production customer data.';
    return manifest;
  }

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
      'approval': File(
        'docs/release/RELEASE_APPROVAL_PACKET.md',
      ).readAsStringSync(),
      'signoff': File(
        'docs/release/UAT_SIGNOFF_CHECKLIST_2026-05-24.md',
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
      expect(text, isNot(contains('20260527T041454Z')));
      expect(text, isNot(contains('.cache/admin_pwa_render_smoke/')));
      expect(text, isNot(contains('commit `5eea474`')));
    }

    for (final key in ['decision', 'blockers', 'qa', 'uat', 'packet']) {
      expect(docs[key], contains('NO-GO'));
    }

    expect(
      docs['decision'],
      contains('group creation is available only on Android'),
    );
    expect(docs['blockers'], contains('Android release signing'));
    expect(docs['blockers'], contains('https://cool-admin-212.pages.dev'));
    expect(docs['checklist'], contains('release_owner_signoff'));
    expect(docs['qa'], contains('101'));
    expect(docs['packet'], contains('Final GO Criteria'));
    expect(docs['approval'], contains('20260601T205424Z'));
    expect(docs['approval'], contains('product_signoff'));
    expect(docs['approval'], contains('android_sms_access_uat'));
    expect(docs['approval'], contains('android_release_signing_review'));
    expect(docs['approval'], contains('ios_release_scope'));
    expect(docs['approval'], contains('release_owner_signoff'));
    expect(docs['approval'], contains('mobile_route_render_smoke'));
    expect(docs['signoff'], contains('20260601T205424Z'));
    expect(docs['qa'], contains('scripts/mobile_route_render_smoke.sh'));
    expect(docs['qa'], contains('20260601T211529Z'));
    expect(docs['checklist'], contains('20260601T205424Z'));
    expect(docs['checklist'], contains('20260601T211529Z'));
    expect(
      File('docs/release/RELEASE_APPROVALS.json').readAsStringSync(),
      contains('"status": "pending"'),
    );
    expect(
      File('docs/release/RELEASE_APPROVALS.example.json').readAsStringSync(),
      contains('"status": "approved"'),
    );
  });

  test('release status reports current blocker keys', () {
    final result = Process.runSync(
      './scripts/release_status.sh',
      ['--json'],
      environment: {'ADMIN_PWA_LIVE_URL': 'https://cool-admin-212.pages.dev'},
    );
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
        'release_owner_signoff',
      ]),
    );
    expect(decoded['blocker_keys'], isNot(contains('admin_pwa_live_url')));
    expect(jsonEncode(decoded), isNot(contains('auth_captcha_bot_protection')));
    expect(jsonEncode(decoded), isNot(contains('supabase_pitr')));
  });

  test('release status ignores direct approval environment overrides', () {
    final result = Process.runSync(
      './scripts/release_status.sh',
      ['--json'],
      environment: {
        'ADMIN_PWA_LIVE_URL': 'https://cool-admin-212.pages.dev',
        'COLLECT_PRODUCT_SIGNOFF_APPROVED': '1',
        'COLLECT_ANDROID_SMS_UAT_APPROVED': '1',
        'COLLECT_RELEASE_OWNER_SIGNOFF_APPROVED': '1',
      },
    );

    expect(result.exitCode, 0);
    final decoded = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(decoded['decision'], 'NO-GO');
    expect(
      decoded['blocker_keys'],
      containsAll(<String>[
        'product_signoff',
        'android_sms_access_uat',
        'release_owner_signoff',
      ]),
    );
    expect(decoded['evidence_flags']['product_signoff'], '0');
    expect(decoded['evidence_flags']['android_sms_uat'], '0');
    expect(decoded['evidence_flags']['release_owner_signoff'], '0');
  });

  test('mobile release gate ignores direct approval environment overrides', () {
    final result = Process.runSync(
      './scripts/flutter_mobile_release_gate.sh',
      ['--json'],
      environment: {
        'ANDROID_RELEASE_SIGNING_REVIEWED': '1',
        'ANDROID_RELEASE_SIGNING_NOTE': 'Current release signing reviewed.',
        'ANDROID_RELEASE_SIGNING_REVIEWER': 'Release Reviewer',
        'ANDROID_RELEASE_SIGNING_REVIEWED_AT': '2026-06-01T00:00:00Z',
        'ANDROID_RELEASE_SIGNING_EVIDENCE':
            'docs/release/BUILD_ARTIFACT_CHECKSUMS_2026-05-31.sha256',
        'IOS_RELEASE_OUT_OF_SCOPE': '1',
        'IOS_RELEASE_SCOPE_NOTE': 'Android-only scope for this go-live.',
        'IOS_RELEASE_SCOPE_REVIEWER': 'Release Reviewer',
        'IOS_RELEASE_SCOPE_REVIEWED_AT': '2026-06-01T00:00:00Z',
        'IOS_RELEASE_SCOPE_EVIDENCE': 'docs/release/RELEASE_APPROVAL_PACKET.md',
      },
    );

    expect(result.exitCode, 99);
    final decoded = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(decoded['status'], 'blocked');
    expect(
      decoded['blocker_keys'],
      containsAll(<String>[
        'android_release_signing_review',
        'ios_release_scope',
      ]),
    );
  });

  test('go-live gate blocks on current SMS-first blockers', () {
    final status = jsonEncode({
      'decision': 'NO-GO',
      'status': 'blocked',
      'blocker_keys': [
        'linked_supabase_sms_first_migration',
        'android_release_signing_review',
        'ios_release_scope',
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
      isNot(
        contains(
          'Deploy Admin PWA and rerun the live gate with ADMIN_PWA_LIVE_URL.',
        ),
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

  test('release approval packet enumerates the remaining approval gates', () {
    final status = jsonEncode({
      'decision': 'NO-GO',
      'status': 'blocked',
      'blocker_keys': [
        'product_signoff',
        'android_sms_access_uat',
        'android_release_signing_review',
        'ios_release_scope',
        'release_owner_signoff',
      ],
    });
    final result = Process.runSync(
      './scripts/release_approval_packet.sh',
      ['--json'],
      environment: {
        'RELEASE_APPROVAL_PACKET_STATUS_JSON': status,
        'ADMIN_PWA_LIVE_URL': 'https://cool-admin-212.pages.dev',
      },
    );

    expect(result.exitCode, 0);
    final decoded = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    final records = decoded['approval_records'] as List<dynamic>;
    expect(records, hasLength(5));
    expect(
      records.map((record) => (record as Map<String, dynamic>)['key']),
      containsAll(<String>[
        'product_signoff',
        'android_sms_access_uat',
        'android_release_signing_review',
        'ios_release_scope',
        'release_owner_signoff',
      ]),
    );
    expect(jsonEncode(decoded), contains('https://cool-admin-212.pages.dev'));
    expect(jsonEncode(decoded), isNot(contains('SUPABASE_SERVICE_ROLE_KEY')));
    expect(jsonEncode(decoded), isNot(contains('AUTH_CAPTCHA_SECRET')));
  });

  test('repo-wide evidence indexes mobile route render screenshots', () {
    final makefile = File('Makefile').readAsStringSync();
    final repoWide = File('scripts/repo_wide_qa_uat.sh').readAsStringSync();
    final evidenceIndex = File(
      'scripts/release_evidence_index.sh',
    ).readAsStringSync();

    expect(makefile, contains('mobile-route-render-smoke:'));
    expect(repoWide, contains('mobile_route_render_smoke'));
    expect(repoWide, contains('MOBILE_ROUTE_RENDER_EVIDENCE_DIR'));
    expect(repoWide, contains('"mobile_route_render"'));
    expect(evidenceIndex, contains('mobile_route_render_summary = read_json'));
    expect(evidenceIndex, contains('required_mobile_routes'));
    expect(evidenceIndex, contains('/groups/col-church/pay/intent-render'));
    expect(evidenceIndex, contains('non_background_pixels'));
    expect(evidenceIndex, contains('"mobile_route_render"'));
  });

  test('release approval evidence gate fails closed on pending approvals', () {
    final result = Process.runSync(
      './scripts/release_approval_evidence_gate.sh',
      ['--json'],
    );

    expect(result.exitCode, 99);
    final decoded = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(decoded['status'], 'blocked');
    expect(
      decoded['blocker_keys'],
      containsAll(<String>[
        'product_signoff',
        'android_sms_access_uat',
        'android_release_signing_review',
        'ios_release_scope',
        'release_owner_signoff',
      ]),
    );
  });

  test(
    'release approval evidence gate requires reachable evidence references',
    () {
      final tempDir = Directory.systemTemp.createTempSync(
        'cool_release_approvals_',
      );
      try {
        final manifest = approvedReleaseManifest();
        final approvals = manifest['approvals'] as List<dynamic>;
        final product = approvals.cast<Map<String, dynamic>>().firstWhere(
          (record) => record['key'] == 'product_signoff',
        );
        product['evidence_reference'] =
            'docs/release/DOES_NOT_EXIST_APPROVAL_EVIDENCE.md';

        final manifestFile = File('${tempDir.path}/approvals.json')
          ..writeAsStringSync(jsonEncode(manifest));
        final result = Process.runSync(
          './scripts/release_approval_evidence_gate.sh',
          ['--json'],
          environment: {'RELEASE_APPROVALS_JSON': manifestFile.path},
        );

        expect(result.exitCode, 99);
        final decoded =
            jsonDecode(result.stdout as String) as Map<String, dynamic>;
        expect(decoded['status'], 'blocked');
        expect(decoded['blocker_keys'], contains('product_signoff'));
        expect(
          decoded['approvals']['product_signoff']['blockers'],
          contains('evidence_reference_missing'),
        );
        expect(
          decoded['approvals']['product_signoff']['evidence_reference_valid'],
          isFalse,
        );
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    },
  );

  test(
    'release approval evidence gate requires manifest evidence references',
    () {
      final tempDir = Directory.systemTemp.createTempSync(
        'cool_release_approvals_',
      );
      try {
        final manifest = approvedReleaseManifest();
        manifest['qa_summary'] =
            '.cache/repo_wide_qa_uat/DOES_NOT_EXIST/summary.json';

        final manifestFile = File('${tempDir.path}/approvals.json')
          ..writeAsStringSync(jsonEncode(manifest));
        final result = Process.runSync(
          './scripts/release_approval_evidence_gate.sh',
          ['--json'],
          environment: {'RELEASE_APPROVALS_JSON': manifestFile.path},
        );

        expect(result.exitCode, 99);
        final decoded =
            jsonDecode(result.stdout as String) as Map<String, dynamic>;
        expect(decoded['status'], 'blocked');
        expect(decoded['blocker_keys'], contains('qa_summary_reference'));
        expect(decoded['checks']['qa_summary']['status'], 'blocked');
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    },
  );

  test('release approval example manifest cannot approve production GO', () {
    final result = Process.runSync(
      './scripts/release_status.sh',
      ['--json'],
      environment: {
        'RELEASE_APPROVALS_JSON': 'docs/release/RELEASE_APPROVALS.example.json',
        'ADMIN_PWA_LIVE_URL': 'https://cool-admin-212.pages.dev',
      },
    );

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
        'release_owner_signoff',
      ]),
    );
  });

  test('approved release manifest can drive final release status', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'cool_release_approvals_',
    );
    try {
      final manifestFile = File('${tempDir.path}/approvals.json')
        ..writeAsStringSync(jsonEncode(approvedReleaseManifest()));
      final result = Process.runSync(
        './scripts/release_status.sh',
        ['--json'],
        environment: {
          'RELEASE_APPROVALS_JSON': manifestFile.path,
          'ADMIN_PWA_LIVE_URL': 'https://cool-admin-212.pages.dev',
        },
      );

      expect(result.exitCode, 0);
      final decoded =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(decoded['decision'], 'GO');
      expect(decoded['blocker_keys'], isEmpty);
      expect(decoded['evidence_flags']['product_signoff'], '1');
      expect(decoded['evidence_flags']['android_sms_uat'], '1');
      expect(
        decoded['evidence_flags']['android_release_signing_review'],
        'current',
      );
      expect(decoded['evidence_flags']['ios_release_scope'], 'current');
      expect(decoded['evidence_flags']['release_owner_signoff'], '1');
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });
}
