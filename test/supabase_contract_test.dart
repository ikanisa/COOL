import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260925190000_rwanda_momo_only.sql',
  ).readAsStringSync();
  final deploy = File('scripts/supabase_deploy.sh').readAsStringSync();
  final readiness = File(
    'scripts/supabase_production_readiness.sh',
  ).readAsStringSync();

  test('Edge Function source inventory contains Rwanda MoMo support only', () {
    final functions =
        Directory('supabase/functions')
            .listSync()
            .whereType<Directory>()
            .where(
              (directory) => File('${directory.path}/index.ts').existsSync(),
            )
            .map((directory) => directory.path.split('/').last)
            .toList()
          ..sort();
    expect(functions, [
      'auth-send-whatsapp-otp',
      'collect-notification-operator',
      'dispatch-notifications',
      'ingest-payment-sms',
      'parse-payment-sms',
      'prepare-roster-import',
      'send-notification',
      'verify-play-integrity',
    ]);
  });

  test('migration limits profile rules and member API to Rwanda MoMo', () {
    expect(migration, contains("country_code = 'RW'"));
    expect(migration, contains("currency_code = 'RWF'"));
    expect(migration, contains('profiles_rwanda_momo_only'));
    expect(
      migration,
      contains('update_current_member_profile(text,text,text,text)'),
    );
    expect(migration, contains('update_rwanda_momo_group_profile'));
    expect(migration, contains("required_rail <> 'rwanda'"));
  });

  test('retired payment routines and tables lose client execution', () {
    expect(migration, contains("p.proname ~ '(bank|diaspora|stripe|sepa)'"));
    expect(migration, contains('revoke all on function'));
    expect(migration, contains('revoke all on table'));
    expect(readiness, contains('check_rwanda_momo_sql_privileges'));
    expect(readiness, contains('retired payment routine grant'));
  });

  test('member routes and payment source expose MoMo USSD only', () {
    final router = File('lib/app/router.dart').readAsStringSync();
    final flow = File(
      'lib/features/payments/contribution_flow_screen.dart',
    ).readAsStringSync();
    expect(router, isNot(contains('/settings/bank-transfer')));
    expect(flow, contains('MomoUssdLauncher'));
    expect(flow, contains('rwanda_momo'));
    expect(
      File('lib/features/payments/contribution_bank_flow.dart').existsSync(),
      isFalse,
    );
  });

  test('Admin surface has Rwanda scope and no bank workflow', () {
    final scope = File('lib/admin/core/admin_runtime.dart').readAsStringSync();
    final router = File('lib/admin/admin_router.dart').readAsStringSync();
    expect(scope, contains('enum AdminCountryScope { rwanda }'));
    expect(router, isNot(contains('/admin/bank-destinations')));
    expect(
      File('lib/admin/core/bank_transfer_admin_runtime.dart').existsSync(),
      isFalse,
    );
  });

  test('deployment retires external payment endpoints', () {
    expect(deploy, contains('RETIRED_FUNCTIONS'));
    expect(deploy, contains('functions delete'));
    expect(deploy, contains('ingest-bank-email'));
    expect(deploy, contains('ingest-bank-sms'));
    expect(deploy, contains('ingest-bank-statement'));
    expect(readiness, contains('ingest-payment-sms'));
  });

  test('Android production retains consented receipt and USSD permissions', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android.permission.RECEIVE_SMS'));
    expect(manifest, contains('android.permission.CALL_PHONE'));
    expect(manifest, isNot(contains('android.permission.READ_SMS')));
    expect(manifest, isNot(contains('android.permission.SEND_SMS')));
  });
}
