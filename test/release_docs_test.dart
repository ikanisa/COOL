import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release decision documents current strict blockers', () {
    final decision = File(
      'docs/release/GO_NO_GO_DECISION.md',
    ).readAsStringSync();
    final blockers = File(
      'docs/release/RELEASE_BLOCKERS.md',
    ).readAsStringSync();
    final checklist = File(
      'docs/release/PRODUCTION_READINESS_CHECKLIST.md',
    ).readAsStringSync();
    final audit = File(
      'docs/release/GO_LIVE_AUDIT_REPORT.md',
    ).readAsStringSync();
    final qa = File('docs/release/QA_TEST_REPORT.md').readAsStringSync();
    final uat = File('docs/release/UAT_EXECUTION_REPORT.md').readAsStringSync();
    final uatPlan = File('docs/release/UAT_TEST_PLAN.md').readAsStringSync();
    final completionAudit = File(
      'docs/release/GO_LIVE_COMPLETION_AUDIT_2026-05-24.md',
    ).readAsStringSync();
    final signoff = File(
      'docs/release/UAT_SIGNOFF_CHECKLIST_2026-05-24.md',
    ).readAsStringSync();
    final security = File(
      'docs/release/SECURITY_PRIVACY_REVIEW.md',
    ).readAsStringSync();

    for (final text in [
      decision,
      blockers,
      checklist,
      audit,
      qa,
      uat,
      uatPlan,
      completionAudit,
      signoff,
      security,
    ]) {
      expect(text, contains('CAPTCHA'));
      expect(text, contains('HIBP'));
      expect(text, contains('PITR'));
      expect(text, contains('Free-plan'));
      expect(text, contains('NO-GO'));
      expect(text, isNot(contains('migration drift')));
      expect(text, isNot(contains('Analyzer exits non-zero')));
      expect(text, isNot(contains('release artifact not produced')));
      expect(text, isNot(contains('JDK 25 fails')));
      expect(text, isNot(contains('web artifacts are incomplete')));
      expect(text, isNot(contains('Release builds not green')));
      expect(text, isNot(contains('Web build incomplete')));
      expect(text, isNot(contains('Migration drift blocks readiness')));
      expect(
        text,
        isNot(contains('code-owned linked Supabase readiness passes')),
      );
      expect(text, isNot(contains('Code-owned release readiness is green')));
      expect(text, isNot(contains('| Linked Supabase readiness | Pass |')));
      expect(text, isNot(contains('Current result is `NO-GO` while CAPTCHA')));
      expect(
        text,
        isNot(contains('make supabase-ready-strict` fails because')),
      );
      expect(
        text,
        isNot(
          contains('Live Auth config reports `password_hibp_enabled=false`'),
        ),
      );
    }

    expect(decision, contains('database_connectivity'));
    expect(decision, contains('20260524T085150Z'));
    expect(audit, contains('database_connectivity'));
    expect(audit, contains('20260524T085150Z'));
    expect(qa, contains('database_connectivity'));
    expect(qa, contains('20260524T085150Z'));
    expect(security, contains('database_connectivity'));
    expect(blockers, contains('P0-005'));
    expect(blockers, contains('database_connectivity'));
    expect(checklist, contains('Supabase latest runner gate refresh'));
    expect(checklist, contains('Supabase Edge Function auth contract UAT'));
    expect(checklist, contains('Latest `make supabase-go-live-gate-json`'));
    expect(checklist, contains('local CAPTCHA provider'));
    expect(checklist, contains('CI/CD linked readiness | Conditional'));
    expect(uatPlan, contains('20260524T085150Z'));
    expect(uatPlan, contains('make supabase-edge-auth-uat'));
    expect(uatPlan, contains('missing receiver authorization'));
    expect(uatPlan, contains('failed Edge Function auth'));
    expect(uatPlan, contains('go_live_approved=true'));
    expect(completionAudit, contains('Requirement Audit'));
    expect(completionAudit, contains('go_live_approved=false'));
    expect(completionAudit, contains('human persona UAT signoff pending'));
    expect(completionAudit, contains('auth_captcha_bot_protection'));
    expect(completionAudit, contains('auth_hibp_leaked_password_protection'));
    expect(signoff, contains('pre-CAPTCHA staging UAT'));
    expect(signoff, contains('release-owner decision'));
    expect(signoff, contains('database_connectivity'));
    expect(signoff, contains('not usable for production GO'));
    expect(signoff, contains('GO_LIVE_COMPLETION_AUDIT_2026-05-24.md'));
  });

  test('release checklist points to the strict approval gate', () {
    final checklist = File(
      'docs/release/PRODUCTION_READINESS_CHECKLIST.md',
    ).readAsStringSync();

    expect(checklist, contains('make supabase-ready-strict'));
    expect(checklist, contains('make release-status'));
    expect(checklist, contains('make release-secret-scan'));
    expect(checklist, contains('flutter analyze --no-pub'));
    expect(checklist, contains('87` tests pass'));
  });

  test('UAT go-live packet contains required release review artifacts', () {
    final packet = File(
      'docs/release/UAT_GO_LIVE_PACKET_2026-05-24.md',
    ).readAsStringSync();

    expect(packet, contains('## Release Artifact Inventory'));
    expect(
      packet,
      contains('build/app/outputs/flutter-apk/app-production-release.apk'),
    );
    expect(
      packet,
      contains(
        'build/app/outputs/bundle/productionRelease/app-production-release.aab',
      ),
    );
    expect(packet, contains('build/web/main.dart.js'));
    expect(
      packet,
      contains('docs/release/BUILD_ARTIFACT_CHECKSUMS_2026-05-24.sha256'),
    );
    expect(
      File(
        'docs/release/BUILD_ARTIFACT_CHECKSUMS_2026-05-24.sha256',
      ).readAsStringSync(),
      allOf(
        contains('build/app/outputs/flutter-apk/app-production-release.apk'),
        contains(
          'build/app/outputs/bundle/productionRelease/app-production-release.aab',
        ),
        contains('build/web/main.dart.js'),
      ),
    );
    expect(
      packet,
      contains('docs/release/GO_LIVE_COMPLETION_AUDIT_2026-05-24.md'),
    );
    expect(
      packet,
      contains('.cache/supabase_go_live_evidence/20260524T085150Z'),
    );
    expect(packet, contains('## Device And Browser Matrix'));
    expect(packet, contains('Pixel_5_API_34_Lite'));
    expect(packet, contains('Chrome integration test target'));
    expect(packet, contains('Wireless iPhone target'));
    expect(packet, contains('## Test Data Ledger'));
    expect(packet, contains('synthetic Rwanda-format numbers'));
    expect(packet, contains('rollback transactions'));
    expect(packet, contains('## Risk Register'));
    expect(packet, contains('CAPTCHA/bot protection disabled'));
    expect(packet, contains('HIBP leaked-password protection disabled'));
    expect(packet, contains('Current runner database connectivity'));
    expect(packet, contains('database_connectivity'));
    expect(packet, contains('## Exception And Signoff Status'));
    expect(packet, contains('CAPTCHA and HIBP cannot be cleared by exception'));
    expect(packet, contains('## Rollback And Incident Plan'));
    expect(packet, contains('docs/SUPABASE_OPERATIONS_RUNBOOK.md'));
    expect(packet, isNot(contains('service_role key')));
    expect(packet, isNot(contains('provider-live-secret')));
  });

  test('linked Supabase CI runs readiness and operational report safely', () {
    final workflow = File(
      '.github/workflows/supabase-readiness.yml',
    ).readAsStringSync();
    final ciWorkflow = File('.github/workflows/ci.yml').readAsStringSync();
    final plan = File(
      'docs/SUPABASE_PRODUCTION_READINESS_PLAN.md',
    ).readAsStringSync();

    expect(workflow, contains('make supabase-ready'));
    expect(workflow, contains('make supabase-operational-report'));
    expect(ciWorkflow, contains('make release-secret-scan'));
    expect(plan, contains('supabase-advisor-warnings'));
    expect(workflow, contains('production Supabase secrets'));
    expect(plan, contains('trusted protected'));
    expect(workflow, isNot(contains('egress CIDR')));
    expect(plan, isNot(contains('runner egress CIDR is allowlisted')));
  });

  test('release status command is documented and secret-safe', () {
    final makefile = File('Makefile').readAsStringSync();
    final script = File('scripts/release_status.sh').readAsStringSync();

    expect(makefile, contains('release-status:'));
    expect(makefile, contains('release-status-json:'));
    expect(makefile, contains('supabase-go-live-gate:'));
    expect(makefile, contains('supabase-go-live-gate-json:'));
    expect(makefile, contains('supabase-platform-packet:'));
    expect(makefile, contains('supabase-platform-exception-gate:'));
    expect(makefile, contains('supabase-post-operator-checklist:'));
    expect(makefile, contains('supabase-post-operator-checklist-json:'));
    expect(makefile, contains('supabase-acceptance-matrix:'));
    expect(makefile, contains('supabase-acceptance-matrix-json:'));
    expect(makefile, contains('@./scripts/release_status.sh --json'));
    expect(
      makefile,
      contains('@./scripts/supabase_platform_go_live_packet.sh --json'),
    );
    expect(
      makefile,
      contains('@./scripts/supabase_schema_inventory.sh --json'),
    );
    expect(makefile, contains('@./scripts/supabase_go_live_gate.sh --json'));
    expect(
      makefile,
      contains('@./scripts/supabase_post_operator_checklist.sh --json'),
    );
    expect(
      makefile,
      contains('@./scripts/supabase_acceptance_matrix.sh --json'),
    );
    expect(script, contains('SUPABASE_READY_STRICT_PLATFORM=1'));
    expect(script, contains('RELEASE_STATUS_STRICT_COMMAND'));
    expect(script, contains('--json'));
    expect(script, contains('JSON.pretty_generate'));
    expect(script, contains('presence AUTH_CAPTCHA_SECRET'));
    expect(script, contains('blocker_keys'));
    expect(script, contains('auth_hibp_leaked_password_protection'));
    expect(script, contains('supabase_organization_plan'));
    expect(script, contains('supabase_pitr'));
    expect(script, isNot(contains(r'printf "%s" "$AUTH_CAPTCHA_SECRET"')));
    expect(script, isNot(contains(r'echo "$AUTH_CAPTCHA_SECRET"')));
  });

  test(
    'platform exception gate only allows signed Free-plan and PITR risk exceptions',
    () {
      final gate = File(
        'scripts/supabase_platform_exception_gate.sh',
      ).readAsStringSync();
      final template = File(
        'docs/release/SUPABASE_PLATFORM_EXCEPTIONS.example.json',
      ).readAsStringSync();
      final checklist = File(
        'docs/release/PRODUCTION_READINESS_CHECKLIST.md',
      ).readAsStringSync();

      expect(gate, contains('"supabase_organization_plan"'));
      expect(gate, contains('"supabase_pitr"'));
      expect(gate, contains('Release verification blockers remain'));
      expect(gate, contains('database_connectivity'));
      expect(gate, contains('non_exceptionable'));
      expect(gate, contains('release_owner_accepts_risk'));
      expect(gate, contains('expires_at'));
      expect(template, contains('"blocker_key": "supabase_organization_plan"'));
      expect(template, contains('"blocker_key": "supabase_pitr"'));
      expect(template, isNot(contains('auth_captcha_bot_protection')));
      expect(template, isNot(contains('auth_hibp_leaked_password_protection')));
      expect(checklist, contains('make supabase-platform-exception-gate'));
      expect(checklist, contains('platform exception-gate result'));

      final status = jsonEncode({
        'decision': 'NO-GO',
        'supabase_strict': 'fail',
        'blocker_keys': ['auth_captcha_bot_protection', 'supabase_pitr'],
      });
      final result = Process.runSync(
        './scripts/supabase_platform_exception_gate.sh',
        const [],
        environment: {'SUPABASE_PLATFORM_EXCEPTION_STATUS_JSON': status},
      );

      expect(result.exitCode, 1);
      expect(
        result.stderr,
        contains('Non-exceptionable strict blockers remain'),
      );
    },
  );

  test(
    'go-live gate reports NO-GO while non-exceptionable blockers remain',
    () {
      final gate = File('scripts/supabase_go_live_gate.sh').readAsStringSync();
      final checklist = File(
        'docs/release/PRODUCTION_READINESS_CHECKLIST.md',
      ).readAsStringSync();

      expect(gate, contains('GO-WITH-EXCEPTIONS'));
      expect(gate, contains('go_live_approved'));
      expect(gate, contains('SUPABASE_GO_LIVE_STATUS_JSON'));
      expect(checklist, contains('make supabase-go-live-gate'));

      final status = jsonEncode({
        'decision': 'NO-GO',
        'supabase_strict': 'fail',
        'blocker_keys': [
          'auth_captcha_bot_protection',
          'supabase_organization_plan',
        ],
      });
      final result = Process.runSync(
        './scripts/supabase_go_live_gate.sh',
        ['--json'],
        environment: {'SUPABASE_GO_LIVE_STATUS_JSON': status},
      );

      expect(result.exitCode, 1);
      final decoded =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(decoded['decision'], 'NO-GO');
      expect(decoded['go_live_approved'], isFalse);
      expect(
        (decoded['exception_gate'] as Map<String, dynamic>)['output'],
        contains('Non-exceptionable strict blockers remain'),
      );
    },
  );

  test('go-live gate reports database connectivity as verification blocked', () {
    final status = jsonEncode({
      'decision': 'NO-GO',
      'supabase_strict': 'fail',
      'blocker_keys': ['database_connectivity'],
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
      (decoded['exception_gate'] as Map<String, dynamic>)['output'],
      contains('Release verification blockers remain: database_connectivity'),
    );
    final actions = decoded['required_next_actions'] as List<dynamic>;
    expect(
      actions,
      contains(
        'Restore trusted linked query mode or an allow-listed Supavisor/direct database path.',
      ),
    );
    expect(
      actions,
      contains(
        'Rerun make release-status-json and make supabase-go-live-gate-json from that trusted path.',
      ),
    );
    expect(
      actions,
      isNot(contains('Resolve non-exceptionable strict blockers.')),
    );
  });

  test('Supabase platform packet is redacted and actionable', () {
    final script = File(
      'scripts/supabase_platform_go_live_packet.sh',
    ).readAsStringSync();
    final checklist = File(
      'docs/release/PRODUCTION_READINESS_CHECKLIST.md',
    ).readAsStringSync();
    final runbook = File(
      'docs/SUPABASE_OPERATIONS_RUNBOOK.md',
    ).readAsStringSync();

    expect(checklist, contains('make supabase-platform-packet'));
    expect(runbook, contains('make supabase-platform-packet-json'));
    expect(script, contains('auth_captcha_bot_protection'));
    expect(script, contains('auth_hibp_leaked_password_protection'));
    expect(script, contains('supabase_organization_plan'));
    expect(script, contains('supabase_pitr'));
    expect(
      script,
      contains('https://supabase.com/docs/guides/auth/auth-captcha'),
    );
    expect(script, isNot(contains(r'echo "$AUTH_CAPTCHA_SECRET"')));
    expect(script, isNot(contains(r'printf "%s" "$AUTH_CAPTCHA_SECRET"')));

    final fixture = jsonEncode({
      'decision': 'NO-GO',
      'supabase_strict': 'fail',
      'inputs': {
        'auth_captcha_secret': 'missing',
        'auth_captcha_provider': 'missing',
        'auth_captcha_site_key': 'missing',
      },
      'blocker_keys': [
        'auth_captcha_bot_protection',
        'auth_hibp_leaked_password_protection',
        'supabase_organization_plan',
        'supabase_pitr',
      ],
      'platform': {
        'auth_captcha_bot_protection': {
          'status': 'blocked',
          'operator_owned': true,
          'input_secret': 'missing',
          'input_provider': 'missing',
          'input_site_key': 'missing',
        },
        'auth_hibp_leaked_password_protection': {
          'status': 'blocked',
          'operator_owned': true,
          'requires_paid_plan': true,
        },
        'supabase_organization_plan': {
          'status': 'blocked',
          'operator_owned': true,
        },
        'supabase_pitr': {
          'status': 'blocked',
          'operator_owned': true,
          'may_require_billing': true,
        },
      },
      'blockers': [
        'CAPTCHA/bot protection is disabled.',
        'HIBP leaked-password protection is disabled.',
        'Supabase organization is on the Free plan.',
        'PITR is disabled.',
      ],
    });

    final result = Process.runSync(
      './scripts/supabase_platform_go_live_packet.sh',
      ['--json'],
      environment: {
        'SUPABASE_PLATFORM_PACKET_STATUS_JSON': fixture,
        'SUPABASE_PROJECT_REF': 'example-ref',
      },
    );

    expect(result.exitCode, 0);
    expect(result.stderr, isEmpty);
    expect(result.stdout, isNot(contains('provider-live-secret')));
    final decoded = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(decoded['decision'], 'NO-GO');
    expect(
      decoded['secret_handling'],
      contains('No secret values are printed'),
    );
    final actions = decoded['operator_actions'] as List<dynamic>;
    expect(actions, hasLength(4));
    expect(
      actions.map((action) => action['key']),
      containsAll([
        'auth_captcha_bot_protection',
        'auth_hibp_leaked_password_protection',
        'supabase_organization_plan',
        'supabase_pitr',
      ]),
    );
    expect(
      actions.map((action) => action['verify_command']),
      everyElement(contains('make')),
    );
  });

  test('post-operator checklist is redacted and fixture-testable', () {
    final script = File(
      'scripts/supabase_post_operator_checklist.sh',
    ).readAsStringSync();
    final checklist = File(
      'docs/release/PRODUCTION_READINESS_CHECKLIST.md',
    ).readAsStringSync();
    final runbook = File(
      'docs/SUPABASE_OPERATIONS_RUNBOOK.md',
    ).readAsStringSync();

    expect(script, contains('SUPABASE_POST_OPERATOR_STATUS_JSON'));
    expect(script, contains('auth_captcha_bot_protection'));
    expect(script, contains('auth_hibp_leaked_password_protection'));
    expect(script, contains('supabase_organization_plan'));
    expect(script, contains('supabase_pitr'));
    expect(script, contains('final_verification'));
    expect(checklist, contains('make supabase-post-operator-checklist'));
    expect(runbook, contains('make supabase-post-operator-checklist-json'));
    expect(script, isNot(contains(r'echo "$AUTH_CAPTCHA_SECRET"')));
    expect(script, isNot(contains(r'printf "%s" "$AUTH_CAPTCHA_SECRET"')));

    final fixture = jsonEncode({
      'decision': 'NO-GO',
      'supabase_strict': 'fail',
      'inputs': {
        'auth_captcha_secret': 'missing',
        'auth_captcha_provider': 'missing',
        'auth_captcha_site_key': 'missing',
      },
      'blocker_keys': [
        'auth_captcha_bot_protection',
        'auth_hibp_leaked_password_protection',
        'supabase_organization_plan',
        'supabase_pitr',
      ],
    });
    final result = Process.runSync(
      './scripts/supabase_post_operator_checklist.sh',
      ['--json'],
      environment: {
        'SUPABASE_POST_OPERATOR_STATUS_JSON': fixture,
        'SUPABASE_PROJECT_REF': 'example-ref',
      },
    );

    expect(result.exitCode, 0);
    expect(result.stderr, isEmpty);
    expect(result.stdout, isNot(contains('provider-live-secret')));
    final decoded = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(decoded['current_decision'], 'NO-GO');
    expect(decoded['secret_handling'], contains('presence/missing'));
    expect(decoded['checklist'], hasLength(4));
    expect(
      decoded['final_verification'],
      contains('make supabase-go-live-gate'),
    );
  });

  test('acceptance matrix maps evidence to release requirements', () {
    final script = File(
      'scripts/supabase_acceptance_matrix.sh',
    ).readAsStringSync();
    final bundle = File(
      'scripts/supabase_go_live_evidence_bundle.sh',
    ).readAsStringSync();
    final checklist = File(
      'docs/release/PRODUCTION_READINESS_CHECKLIST.md',
    ).readAsStringSync();
    final runbook = File(
      'docs/SUPABASE_OPERATIONS_RUNBOOK.md',
    ).readAsStringSync();

    expect(script, contains('SUPA-001'));
    expect(script, contains('SUPA-012'));
    expect(script, contains('overall_status'));
    expect(script, contains('status_counts'));
    expect(script, contains('schema_inventory.json'));
    expect(script, contains('go_live_gate.json'));
    expect(script, contains('release_secret_scan.txt'));
    expect(script, contains('post_operator_checklist.json'));
    expect(script, isNot(contains(r'cat .env')));
    expect(bundle, contains('acceptance_matrix.json'));
    expect(bundle, contains('latest-test'));
    expect(bundle, contains(r'cp -R "$bundle_dir"/. "$latest_dir"/'));
    expect(checklist, contains('make supabase-acceptance-matrix'));
    expect(runbook, contains('make supabase-acceptance-matrix-json'));

    final tempDir = Directory.systemTemp.createTempSync('acceptance_matrix_');
    try {
      File('${tempDir.path}/release_status.json').writeAsStringSync(
        jsonEncode({
          'decision': 'NO-GO',
          'supabase_strict': 'fail',
          'blocker_keys': [
            'auth_captcha_bot_protection',
            'auth_hibp_leaked_password_protection',
            'supabase_organization_plan',
            'supabase_pitr',
          ],
        }),
      );
      File('${tempDir.path}/go_live_gate.json').writeAsStringSync(
        jsonEncode({
          'decision': 'NO-GO',
          'approval_status': 'blocked',
          'go_live_approved': false,
        }),
      );
      File('${tempDir.path}/schema_inventory.json').writeAsStringSync(
        jsonEncode({
          'contract': {
            'summary': {
              'expected_objects': 160,
              'remote_objects': 160,
              'extra_objects': 0,
              'missing_objects': 0,
              'tables': 28,
              'rls_enabled_tables': 28,
              'functions': 57,
              'functions_with_search_path': 57,
            },
          },
        }),
      );
      File('${tempDir.path}/post_operator_checklist.json').writeAsStringSync(
        jsonEncode({
          'checklist': List.generate(4, (_) => {'key': 'x'}),
        }),
      );
      File('${tempDir.path}/operational_report.json').writeAsStringSync(
        jsonEncode({
          'tables': [1, 2, 3],
        }),
      );
      File('${tempDir.path}/supabase_ready.txt').writeAsStringSync(
        [
          'checking Edge Function auth contract',
          'checking deployed Edge Function endpoints',
          'checking Edge Function secret names',
        ].join('\n'),
      );
      File('${tempDir.path}/edge_auth_contract_uat.txt').writeAsStringSync(
        '[collect-edge-auth-uat] Edge Function auth contract UAT passed',
      );
      File('${tempDir.path}/advisor_warnings.txt').writeAsStringSync('ok');
      File('${tempDir.path}/release_secret_scan.txt').writeAsStringSync('ok');
      File('${tempDir.path}/commands.tsv').writeAsStringSync(
        [
          'advisor_warning_inventory\tadvisor_warnings.txt\t0\tstart\tfinish',
          'edge_auth_contract_uat\tedge_auth_contract_uat.txt\t0\tstart\tfinish',
          'code_owned_readiness\tsupabase_ready.txt\t0\tstart\tfinish',
          'operational_report_json\toperational_report.json\t0\tstart\tfinish',
          'release_secret_scan\trelease_secret_scan.txt\t0\tstart\tfinish',
          'platform_exception_gate\tplatform_exception_gate.txt\t1\tstart\tfinish',
          'post_operator_checklist_json\tpost_operator_checklist.json\t0\tstart\tfinish',
        ].join('\n'),
      );

      final result = Process.runSync(
        './scripts/supabase_acceptance_matrix.sh',
        ['--json', '--bundle-dir', tempDir.path],
      );

      expect(result.exitCode, 0);
      final decoded =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(decoded['overall_status'], 'blocked');
      final requirements = decoded['requirements'] as List<dynamic>;
      expect(requirements, hasLength(12));
      expect(
        requirements.where((item) => item['status'] == 'blocked'),
        isNotEmpty,
      );
      expect(requirements.where((item) => item['status'] == 'fail'), isEmpty);
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('acceptance matrix treats database connectivity as blocked verification', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'acceptance_matrix_connectivity_',
    );
    try {
      File('${tempDir.path}/release_status.json').writeAsStringSync(
        jsonEncode({
          'decision': 'NO-GO',
          'supabase_strict': 'fail',
          'blocker_keys': ['database_connectivity'],
        }),
      );
      File('${tempDir.path}/go_live_gate.json').writeAsStringSync(
        jsonEncode({
          'decision': 'NO-GO',
          'approval_status': 'blocked',
          'go_live_approved': false,
        }),
      );
      File('${tempDir.path}/schema_inventory.json').writeAsStringSync(
        jsonEncode({
          'contract': {
            'summary': {
              'expected_objects': 160,
              'remote_objects': 160,
              'extra_objects': 0,
              'missing_objects': 0,
              'tables': 28,
              'rls_enabled_tables': 28,
              'functions': 57,
              'functions_with_search_path': 57,
            },
          },
        }),
      );
      File('${tempDir.path}/post_operator_checklist.json').writeAsStringSync(
        jsonEncode({
          'checklist': List.generate(4, (_) => {'key': 'x'}),
        }),
      );
      File('${tempDir.path}/operational_report.json').writeAsStringSync(
        jsonEncode({
          'tables': [1, 2, 3],
        }),
      );
      File('${tempDir.path}/supabase_ready.txt').writeAsStringSync(
        'failed to connect to postgres: tenant allow_list rejected runner',
      );
      File('${tempDir.path}/edge_auth_contract_uat.txt').writeAsStringSync(
        '[collect-edge-auth-uat] Edge Function auth contract UAT passed',
      );
      File('${tempDir.path}/advisor_warnings.txt').writeAsStringSync('ok');
      File('${tempDir.path}/release_secret_scan.txt').writeAsStringSync('ok');
      File('${tempDir.path}/platform_exception_gate.txt').writeAsStringSync(
        '[platform-exceptions][FAIL] Release verification blockers remain: database_connectivity',
      );
      File('${tempDir.path}/commands.tsv').writeAsStringSync(
        [
          'advisor_warning_inventory\tadvisor_warnings.txt\t0\tstart\tfinish',
          'edge_auth_contract_uat\tedge_auth_contract_uat.txt\t0\tstart\tfinish',
          'code_owned_readiness\tsupabase_ready.txt\t1\tstart\tfinish',
          'operational_report_json\toperational_report.json\t0\tstart\tfinish',
          'release_secret_scan\trelease_secret_scan.txt\t0\tstart\tfinish',
          'platform_exception_gate\tplatform_exception_gate.txt\t1\tstart\tfinish',
          'post_operator_checklist_json\tpost_operator_checklist.json\t0\tstart\tfinish',
        ].join('\n'),
      );

      final result = Process.runSync(
        './scripts/supabase_acceptance_matrix.sh',
        ['--json', '--bundle-dir', tempDir.path],
      );

      expect(result.exitCode, 0);
      final decoded =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(decoded['overall_status'], 'blocked');
      final requirements = decoded['requirements'] as List<dynamic>;
      final byId = {
        for (final item in requirements.cast<Map<String, dynamic>>())
          item['id'] as String: item,
      };
      expect(byId['SUPA-005']?['status'], 'blocked');
      expect(byId['SUPA-006']?['status'], 'blocked');
      expect(byId['SUPA-009']?['status'], 'blocked');
      expect(
        byId['SUPA-012']?['blocker_keys'],
        contains('database_connectivity'),
      );
      expect(
        byId['SUPA-012']?['next_action'],
        contains('Restore trusted linked query mode'),
      );
      expect(requirements.where((item) => item['status'] == 'fail'), isEmpty);
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('release status JSON mode is parseable and redacted', () {
    final result = Process.runSync(
      './scripts/release_status.sh',
      ['--json'],
      environment: {
        'RELEASE_STATUS_STRICT_COMMAND':
            'printf "%s\\n" "[supabase-ready][FAIL] 4 release blocker(s) remain:" "  - HIBP leaked-password protection is disabled." "  - CAPTCHA/bot protection is disabled." "  - Supabase organization is on the Free plan." "  - PITR is disabled." && exit 2',
      },
    );

    expect(result.exitCode, 0);
    expect(result.stderr, isEmpty);
    final decoded = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(decoded['decision'], 'NO-GO');
    expect(decoded['supabase_strict'], 'fail');
    expect(decoded['inputs'], isA<Map<String, dynamic>>());
    final inputs = decoded['inputs'] as Map<String, dynamic>;
    expect(inputs['auth_captcha_secret'], 'missing');
    expect(inputs.values, isNot(contains('demo-secret')));
    expect(
      decoded['blocker_keys'],
      contains('auth_hibp_leaked_password_protection'),
    );
    expect(decoded['blocker_keys'], contains('auth_captcha_bot_protection'));
    expect(decoded['blocker_keys'], contains('supabase_organization_plan'));
    expect(decoded['blocker_keys'], contains('supabase_pitr'));
    final platform = decoded['platform'] as Map<String, dynamic>;
    expect(
      (platform['auth_captcha_bot_protection']
          as Map<String, dynamic>)['status'],
      'blocked',
    );
    expect(
      (platform['auth_hibp_leaked_password_protection']
          as Map<String, dynamic>)['requires_paid_plan'],
      isTrue,
    );
    expect(
      decoded['blockers'],
      contains('CAPTCHA/bot protection is disabled.'),
    );
    expect(
      decoded['blockers'],
      contains('HIBP leaked-password protection is disabled.'),
    );
    expect(decoded['blockers'], contains('PITR is disabled.'));
  });

  test(
    'release status reports database connectivity without false platform pass',
    () {
      final result = Process.runSync(
        './scripts/release_status.sh',
        ['--json'],
        environment: {
          'RELEASE_STATUS_STRICT_COMMAND':
              'printf "%s\\n" "failed to connect to postgres: server error (FATAL: (EADDRNOTALLOWED) address not in tenant allow_list)" && exit 2',
        },
      );

      expect(result.exitCode, 0);
      expect(result.stderr, isEmpty);
      final decoded =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(decoded['decision'], 'NO-GO');
      expect(decoded['blocker_keys'], contains('database_connectivity'));
      expect(
        decoded['blockers'],
        contains(
          'Database readiness check could not reach Postgres. Use linked query mode from a trusted network, or set SUPABASE_READINESS_DATABASE_URL or DATABASE_POOLER_URL to an allowed Dashboard Supavisor pooler URL for this runner.',
        ),
      );
      final gateResult = Process.runSync(
        './scripts/supabase_go_live_gate.sh',
        ['--json'],
        environment: {'SUPABASE_GO_LIVE_STATUS_JSON': jsonEncode(decoded)},
      );
      expect(gateResult.exitCode, 1);
      final gateJson =
          jsonDecode(gateResult.stdout as String) as Map<String, dynamic>;
      expect(gateJson['decision'], 'NO-GO');
      expect(gateJson['go_live_approved'], isFalse);
      expect(
        (gateJson['exception_gate'] as Map<String, dynamic>)['output'],
        contains('Release verification blockers remain: database_connectivity'),
      );
      expect(
        gateJson['required_next_actions'],
        contains(
          'Restore trusted linked query mode or an allow-listed Supavisor/direct database path.',
        ),
      );
      expect(
        gateJson['required_next_actions'],
        isNot(contains('Resolve non-exceptionable strict blockers.')),
      );
      final platform = decoded['platform'] as Map<String, dynamic>;
      expect(
        (platform['auth_captcha_bot_protection']
            as Map<String, dynamic>)['status'],
        'unknown',
      );
      expect(
        (platform['auth_hibp_leaked_password_protection']
            as Map<String, dynamic>)['status'],
        'unknown',
      );
      expect(
        (platform['supabase_organization_plan']
            as Map<String, dynamic>)['status'],
        'unknown',
      );
      expect(
        (platform['supabase_pitr'] as Map<String, dynamic>)['status'],
        'unknown',
      );
    },
  );
}
