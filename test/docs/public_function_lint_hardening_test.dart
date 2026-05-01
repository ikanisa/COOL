import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const migrationPath =
      'supabase/migrations/20260501120000_public_function_lint_hardening.sql';
  const inviteCodeCleanupPath =
      'supabase/migrations/20260501121500_generate_invite_code_lint_cleanup.sql';
  const lifecycleAuditPath =
      'supabase/migrations/20260501123000_group_lifecycle_backfill_audit.sql';
  const rollbackRunbookPath =
      'docs/rollback/public-function-hardening-rollback-2026-05-01.md';

  late String sql;
  late String inviteCodeCleanupSql;
  late String lifecycleAuditSql;
  late String rollbackRunbook;

  setUpAll(() {
    sql = File(migrationPath).readAsStringSync();
    inviteCodeCleanupSql = File(inviteCodeCleanupPath).readAsStringSync();
    lifecycleAuditSql = File(lifecycleAuditPath).readAsStringSync();
    rollbackRunbook = File(rollbackRunbookPath).readAsStringSync();
  });

  test('restores lifecycle and note columns used by admin RPCs', () {
    expect(sql, contains('add column if not exists is_active boolean'));
    expect(sql, contains('add column if not exists is_closed boolean'));
    expect(sql, contains('add column if not exists notes text'));
  });

  test('repairs MoMo lint hazards without stale intent_type field access', () {
    expect(sql, contains('for update of mr'));
    expect(sql, isNot(contains('v_intent.intent_type')));
    expect(sql, contains("v_intent.metadata ->> 'intent_type'"));
  });

  test(
    'purge mock batch no longer depends on temp tables or purged schemas',
    () {
      expect(sql, isNot(contains('tmp_mock_user_ids')));
      expect(sql, isNot(contains('delete from public.cool_status')));
      expect(sql, isNot(contains('delete from public.cool_events')));
      expect(sql, contains('v_auth_user_ids uuid[]'));
    },
  );

  test('drops stale removed-surface RPCs with exact signatures', () {
    expect(
      sql,
      contains('drop function if exists public.get_rayon_member_registry'),
    );
    expect(
      sql,
      contains('drop function if exists public.award_cool_achievement'),
    );
  });

  test(
    'admin group RPCs use live groups tables and audit sensitive writes',
    () {
      expect(
        sql,
        contains('create or replace function public.get_admin_groups_summary'),
      );
      expect(sql, isNot(contains('public.contribution_groups')));
      expect(sql, contains("'admin_create_savings_group'"));
      expect(sql, contains("'admin_update_savings_group'"));
      expect(sql, contains("'admin_allocate_savings_contribution'"));
      expect(sql, contains('public.admin_audit_log'));
    },
  );

  test('generate_invite_code cleanup removes unreachable fallback return', () {
    expect(inviteCodeCleanupSql, contains('while v_attempts < 100 loop'));
    expect(inviteCodeCleanupSql, contains('raise exception'));
    expect(inviteCodeCleanupSql, isNot(contains('return null')));
  });

  test('group lifecycle defaults are auditable', () {
    expect(
      lifecycleAuditSql,
      contains('group_lifecycle_backfill_default_open'),
    );
    expect(lifecycleAuditSql, contains("'admin_action'"));
    expect(lifecycleAuditSql, contains('public.admin_audit_log'));
    expect(
      lifecycleAuditSql,
      contains('Existing groups had no prior lifecycle columns'),
    );
  });

  test('forward rollback runbook exists for applied production hardening', () {
    expect(rollbackRunbook, contains('compensates forward'));
    expect(rollbackRunbook, contains('supabase db lint'));
    expect(rollbackRunbook, isNot(contains('supabase db reset')));
    expect(rollbackRunbook, isNot(contains('supabase migration repair')));
  });
}
