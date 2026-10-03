import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('current product documents define Rwanda MoMo USSD scope', () {
    for (final path in [
      'docs/PRODUCT.md',
      'docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md',
      'README.md',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('Rwanda'), reason: path);
      expect(source, contains('MoMo'), reason: path);
      expect(source, contains('USSD'), reason: path);
      expect(source.toLowerCase(), isNot(contains('diaspora')), reason: path);
      expect(
        source.toLowerCase(),
        isNot(contains('bank transfer')),
        reason: path,
      );
    }
  });

  test('environment keeps production credentials server-side', () {
    final environment = File('docs/ENVIRONMENT.md').readAsStringSync();
    final example = File('.env.example').readAsStringSync();

    for (final secret in <String>[
      'FCM_SERVICE_ACCOUNT_JSON',
      'APNS_PRIVATE_KEY_BASE64',
      'GOOGLE_PLAY_SERVICE_ACCOUNT_JSON',
    ]) {
      expect(environment, contains(secret));
      expect(example, contains('$secret='));
    }
    expect(
      environment,
      contains('Android production builds set both SMS switches to `true`'),
    );
    expect(environment, contains('PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER'));
    expect(example, contains('PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER='));
    expect(environment, contains('no `READ_SMS`, `SEND_SMS`'));
    expect(environment, isNot(contains('STRIPE_SECRET_KEY')));
    expect(environment, isNot(contains('PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON')));
  });

  test('Android production build requires the linked Play project number', () {
    final build = File(
      'scripts/android_play_store_build.sh',
    ).readAsStringSync();

    expect(build, contains('PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER_VALUE'));
    expect(
      build,
      contains('must be the positive project number linked to Collect'),
    );
    expect(build, contains('export PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER='));
  });

  test('Edge Function documentation and config expose the exact allowlist', () {
    final docs = File('docs/SUPABASE_FUNCTIONS.md').readAsStringSync();
    final config = File('supabase/config.toml').readAsStringSync();
    const expected = <String>[
      'auth-send-whatsapp-otp',
      'collect-notification-operator',
      'prepare-roster-import',
      'send-notification',
      'dispatch-notifications',
      'ingest-payment-sms',
      'parse-payment-sms',
      'verify-play-integrity',
    ];

    for (final function in expected) {
      expect(docs, contains('`$function`'), reason: function);
      expect(config, contains('[functions.$function]'), reason: function);
    }
    for (final retired in <String>[
      'stripe-webhook',
      'stripe-create-customer',
    ]) {
      expect(config, isNot(contains('[functions.$retired]')), reason: retired);
    }
  });

  test(
    'deployment script enforces current and retired function inventories',
    () {
      final deploy = File('scripts/supabase_deploy.sh').readAsStringSync();
      for (final function in <String>[
        'auth-send-whatsapp-otp',
        'dispatch-notifications',
        'ingest-bank-email',
        'ingest-bank-sms',
        'ingest-bank-statement',
        'ingest-payment-sms',
        'parse-payment-sms',
        'send-notification',
        'verify-play-integrity',
      ]) {
        expect(deploy, contains(function), reason: function);
      }
      expect(deploy, contains('RETIRED_FUNCTIONS'));
      expect(deploy, contains('stripe-webhook'));
      expect(deploy, contains('parse-payment-sms'));
      expect(deploy, contains('functions delete'));
    },
  );

  test('production readiness requires MoMo, push, and Play controls', () {
    final readiness = File(
      'scripts/supabase_production_readiness.sh',
    ).readAsStringSync();

    expect(readiness, contains('FCM_SERVICE_ACCOUNT_JSON'));
    expect(readiness, contains('APNS_PRIVATE_KEY_BASE64'));
    expect(readiness, contains('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON'));
    expect(readiness, contains('check_rwanda_momo_sql_privileges'));
    expect(readiness, contains('Production Auth has a fixed SMS test OTP'));
    expect(readiness, contains('sms_test_otp_valid_until'));
    expect(readiness, isNot(contains('STRIPE_SECRET_KEY')));
    expect(readiness, isNot(contains('STRIPE_WEBHOOK_SECRET')));
    expect(readiness, isNot(contains('PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON')));
  });

  test('production Auth hardening clears fixed OTP overrides', () {
    final hardening = File(
      'scripts/supabase_apply_auth_hardening.sh',
    ).readAsStringSync();

    expect(hardening, contains('sms_test_otp: nil'));
    expect(hardening, contains('sms_test_otp_valid_until: nil'));
    expect(hardening, contains('https://collect.ikanisa.com'));
    expect(hardening, contains('https://admin.collect.ikanisa.com'));
    expect(hardening, isNot(contains('https://easymo.vercel.app')));
  });

  test('advisor inventory pins the reviewed current RPC ceiling', () {
    final inventory = File(
      'scripts/supabase_advisors_warning_inventory.sh',
    ).readAsStringSync();

    expect(
      inventory,
      contains('"authenticated_security_definer_function_executable" => 132'),
    );
    expect(inventory, contains('update_current_profile()'));
  });

  test('Rwanda MoMo linked readiness check verifies the active boundary', () {
    final uat = File(
      'scripts/rwanda_momo_readiness_uat.sql',
    ).readAsStringSync();
    expect(uat, contains("country_code = 'RW'"));
    expect(uat, contains("currency_code = 'RWF'"));
    expect(uat, contains('RWANDA_MOMO_READINESS_UAT_PASS'));
    expect(uat, contains('retired payment routines remain executable'));
  });

  test('linked database UAT has an HTTPS Management API fallback', () {
    final helpers = File('scripts/supabase_cli_helpers.sh').readAsStringSync();
    final deploy = File('scripts/supabase_deploy.sh').readAsStringSync();
    final linkedUat = File('scripts/collect_linked_uat.sh').readAsStringSync();
    final adminUat = File(
      'scripts/collect_admin_security_uat.sh',
    ).readAsStringSync();

    expect(helpers, contains('supabase_management_query_file'));
    expect(helpers, contains('/database/query'));
    expect(helpers, contains('supabase_management_apply_pending_migrations'));
    expect(helpers, contains('codex-management-api'));
    expect(helpers, isNot(contains('local version name path body')));
    expect(
      helpers,
      contains('Remote migration version history does not exactly match'),
    );
    expect(deploy, contains('tenant allow_list'));
    expect(deploy, contains('supabase_management_apply_pending_migrations'));
    expect(linkedUat, contains('supabase_management_query_file'));
    expect(adminUat, contains('supabase_management_query_file'));
  });

  test('current bank queues have permission-gated SLA support', () {
    final migration = File(
      'supabase/migrations/20260831084239_expand_admin_queue_sla_support.sql',
    ).readAsStringSync();

    for (final queue in <String>[
      'admin_list_bank_destinations',
      'admin_list_bank_destination_change_requests',
      'admin_list_bank_transfer_intents',
      'admin_list_bank_transactions',
      'admin_list_bank_evidence',
      'admin_list_reconciliation_runs',
      'admin_list_reconciliation_exceptions',
      'admin_list_bank_allocation_requests',
      'admin_list_journal_entries',
    ]) {
      expect(migration, contains("when '$queue'"), reason: queue);
    }
    expect(migration, contains("assert_admin_permission('bank_details.read')"));
    expect(
      migration,
      contains("assert_admin_permission('bank_transactions.read')"),
    );
    expect(
      migration,
      contains("assert_admin_permission('bank_reconciliation.read')"),
    );
  });

  test('Google Play packet records the pending Rwanda SMS approval gate', () {
    final packet =
        jsonDecode(
              File(
                'docs/release/GOOGLE_PLAY_CONSOLE_AUDIT_PACKET.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final appContent = Map<String, dynamic>.from(packet['app_content'] as Map);
    final permissions = Map<String, dynamic>.from(
      appContent['permissions'] as Map,
    );
    final values = List<String>.from(
      permissions['production_permissions'] as List,
    );

    expect(permissions['restricted_sms_permissions_in_production'], isTrue);
    expect(
      permissions['sms_permissions_declaration_status'],
      'required_pending_play_approval',
    );
    expect(values, contains('android.permission.RECEIVE_SMS'));
    expect(values, isNot(contains('android.permission.READ_SMS')));
    expect(values, contains('android.permission.CALL_PHONE'));
  });

  test('release gates distinguish public production and internal receiver', () {
    final play = File(
      'scripts/google_play_optimization_gate.sh',
    ).readAsStringSync();
    final mobile = File(
      'scripts/flutter_mobile_release_gate.sh',
    ).readAsStringSync();
    final upload = File(
      'scripts/google_play_production_upload.sh',
    ).readAsStringSync();

    expect(
      play,
      contains('expected_apk_restricted = ["android.permission.RECEIVE_SMS"]'),
    );
    expect(play, contains('restricted_sms_declaration'));
    expect(play, contains('android_group_creation_attestation'));
    expect(mobile, contains('production_receive_only'));
    expect(upload, contains('google_play_sms_declaration_not_approved'));
  });
}
