import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const migrationPath =
      'supabase/migrations/20260501130000_app_config_public_read_hardening.sql';
  const repositoryPath = 'lib/core/config/app_config_repository.dart';
  const sqlVerificationPath =
      'supabase/tests/app_config_public_read_hardening.sql';

  late String migrationSql;
  late String repositoryDart;
  late String verificationSql;

  setUpAll(() {
    migrationSql = File(migrationPath).readAsStringSync();
    repositoryDart = File(repositoryPath).readAsStringSync();
    verificationSql = File(sqlVerificationPath).readAsStringSync();
  });

  test('migration removes broad app_config client reads', () {
    expect(
      migrationSql,
      contains('drop policy if exists "Public read app_config"'),
    );
    expect(migrationSql, contains('create policy app_config_select_admin'));
    expect(migrationSql, contains('using (public.is_admin_user())'));
    expect(
      migrationSql,
      contains('add column if not exists is_public boolean'),
    );
  });

  test('public runtime config is exposed only through an allowlisted RPC', () {
    expect(
      migrationSql,
      contains('create or replace function public.get_public_app_config'),
    );
    expect(migrationSql, contains('security definer'));
    expect(migrationSql, contains('where ac.is_public = true'));
    expect(migrationSql, contains('grant execute on function'));
    expect(migrationSql, contains('to anon, authenticated'));
    expect(migrationSql, isNot(contains("'savings_momo_code'")));
  });

  test('runtime repository no longer selects app_config directly', () {
    expect(repositoryDart, contains("_client.rpc('get_public_app_config'"));
    expect(repositoryDart, contains('publicAppConfigValue'));
    expect(repositoryDart, contains('publicAppConfigAll'));
    expect(repositoryDart, isNot(contains("_client.from('app_config')")));
  });

  test('SQL verification covers sensitive and expected public keys', () {
    expect(
      verificationSql,
      contains('Public read app_config policy must not exist'),
    );
    expect(verificationSql, contains('savings_momo_code must not be exposed'));
    expect(verificationSql, contains('support_whatsapp must remain available'));
  });
}
