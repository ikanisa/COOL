import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const migrationPath =
      'supabase/migrations/20260501131500_payment_intent_status_transition_hardening.sql';
  const rlsTestPath = 'supabase/tests/rls_tenant_payment_status_contract.sql';
  const sendNotificationPath = 'supabase/functions/send-notification/index.ts';
  const securityPath = 'supabase/functions/_shared/security.ts';
  const reconciliationPath =
      'supabase/functions/parse-momo-sms/reconciliation.ts';

  late String migrationSql;
  late String rlsSql;
  late String sendNotificationTs;
  late String securityTs;
  late String reconciliationTs;

  setUpAll(() {
    migrationSql = File(migrationPath).readAsStringSync();
    rlsSql = File(rlsTestPath).readAsStringSync();
    sendNotificationTs = File(sendNotificationPath).readAsStringSync();
    securityTs = File(securityPath).readAsStringSync();
    reconciliationTs = File(reconciliationPath).readAsStringSync();
  });

  test('send-notification uses shared constant-time bearer comparison', () {
    expect(securityTs, contains('export function constantTimeEquals'));
    expect(
      sendNotificationTs,
      contains('constantTimeEquals(serviceRoleKey, token)'),
    );
    expect(sendNotificationTs, isNot(contains('token === serviceRoleKey')));
  });

  test('payment intent migration blocks client-side status confirmation', () {
    expect(
      migrationSql,
      contains('drop policy if exists "payment_intents_update_auth"'),
    );
    expect(
      migrationSql,
      contains('create policy payment_intents_update_admin'),
    );
    expect(migrationSql, contains('enforce_payment_intent_status_transition'));
    expect(migrationSql, contains("new.status := 'fulfilled'"));
    expect(migrationSql, contains('authorized admin action'));
  });

  test(
    'SMS reconciliation writes canonical fulfilled payment intent status',
    () {
      expect(reconciliationTs, contains('.eq("user_id", rawSms.user_id)'));
      expect(reconciliationTs, contains('status: "fulfilled"'));
      expect(reconciliationTs, isNot(contains('status: "completed"')));
      expect(reconciliationTs, isNot(contains('.eq("creator_id"')));
    },
  );

  test('pgTAP contract covers tenant RLS and payment transitions', () {
    expect(rlsSql, contains('create extension if not exists pgtap'));
    expect(rlsSql, contains('groups has RLS enabled'));
    expect(
      rlsSql,
      contains('private group reads are scoped through is_group_member'),
    );
    expect(rlsSql, contains('payment_intents_update_auth'));
    expect(rlsSql, contains('trg_enforce_payment_intent_status_transition'));
    expect(
      rlsSql,
      contains('manual payment review allocation requires pending intents'),
    );
  });
}
