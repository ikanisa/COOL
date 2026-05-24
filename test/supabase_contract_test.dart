import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/202605230001_collect_baseline.sql',
  ).readAsStringSync();
  final finalPaymentIntentHardening = File(
    'supabase/migrations/202605230006_finalize_payment_intent_hardening.sql',
  ).readAsStringSync();
  final clientSafeViews = File(
    'supabase/migrations/202605230009_add_client_safe_views.sql',
  ).readAsStringSync();
  final adminFilterContracts = File(
    'supabase/migrations/202605230017_admin_list_filter_contracts.sql',
  ).readAsStringSync();
  final adminRoleTightening = File(
    'supabase/migrations/20260523203132_tighten_admin_role_permissions.sql',
  ).readAsStringSync();
  final viewSecurityInvoker = File(
    'supabase/migrations/20260523204235_set_views_security_invoker.sql',
  ).readAsStringSync();
  final helperSearchPaths = File(
    'supabase/migrations/20260523205502_set_helper_function_search_paths.sql',
  ).readAsStringSync();
  final splitPermissiveSelectPolicies = File(
    'supabase/migrations/20260523210723_split_permissive_select_policies.sql',
  ).readAsStringSync();
  final revokeAnonPlatformAdminHelper = File(
    'supabase/migrations/20260523212244_revoke_anon_platform_admin_helper.sql',
  ).readAsStringSync();
  final disableGraphqlIntrospection = File(
    'supabase/migrations/20260523213113_disable_graphql_introspection.sql',
  ).readAsStringSync();

  test('migration exposes contribution intent instruction RPC', () {
    expect(migration, contains('create_payment_intent_with_instructions'));
    expect(migration, contains('receiver_momo_number text'));
    expect(migration, contains('payment_instruction_templates'));
    expect(migration, contains('instruction_body text'));
    expect(
      migration,
      contains(
        'grant execute on function create_payment_intent_with_instructions',
      ),
    );
  });

  test('migration supports private collection invite tokens', () {
    expect(migration, contains('create_collection_invite'));
    expect(migration, contains('invite_token_hash text unique not null'));
    expect(migration, contains('digest(plain_token'));
    expect(
      migration,
      contains('grant execute on function create_collection_invite'),
    );
  });

  test(
    'migration supports media URLs and recurring metadata on collection creation',
    () {
      expect(migration, contains('cover_image_url text default null'));
      expect(migration, contains('is_recurring boolean default false'));
      expect(migration, contains('recurring_rule jsonb default null'));
      expect(migration, contains('insert into recurring_periods'));
    },
  );

  test('public profile view only exposes avatars for display-name identity', () {
    expect(
      migration,
      contains(
        "case when anonymity_default = 'display_name' then avatar_url else null end as avatar_url",
      ),
    );
    expect(
      migration,
      contains(
        "when anonymity_default = 'anonymous' then 'Anonymous supporter'",
      ),
    );
    expect(migration, contains("else 'User #' || public_id"));
  });

  test('profile grants keep raw identity fields off broad public reads', () {
    expect(
      migration,
      contains('create or replace function get_current_profile'),
    );
    expect(
      migration,
      contains('revoke all on profiles from anon, authenticated'),
    );
    expect(migration, isNot(contains('grant select (')));
    expect(
      migration,
      contains(
        'grant execute on function get_current_profile() to authenticated',
      ),
    );
  });

  test('database function execution is explicitly scoped', () {
    expect(
      migration,
      contains(
        'revoke execute on all functions in schema public from public, anon, authenticated',
      ),
    );
    expect(
      migration,
      contains(
        'grant execute on all functions in schema public to service_role',
      ),
    );
    expect(
      migration,
      contains(
        'grant execute on function public.user_can_read_collection(uuid, uuid) to anon, authenticated',
      ),
    );
    expect(
      revokeAnonPlatformAdminHelper,
      contains(
        'revoke execute on function public.current_user_is_platform_admin() from anon',
      ),
    );
    expect(
      migration,
      contains(
        'create or replace function allocate_parsed_payment_event(event_id uuid)',
      ),
    );
    expect(
      migration,
      isNot(
        contains(
          'grant execute on function allocate_parsed_payment_event(uuid) to authenticated',
        ),
      ),
    );
  });

  test('migration keeps raw SMS and ledger protected', () {
    expect(
      migration,
      contains('alter table raw_payment_sms enable row level security'),
    );
    expect(migration, contains('create policy "raw sms service writes"'));
    expect(migration, contains('create trigger ledger_entries_prevent_update'));
    expect(migration, contains('create trigger ledger_entries_prevent_delete'));
  });

  test('SMS ingestion requires an authorized receiver MOMO route', () {
    final ingest = File(
      'supabase/functions/ingest-payment-sms/index.ts',
    ).readAsStringSync();

    expect(migration, contains('user_can_ingest_receiver_sms'));
    expect(
      ingest,
      contains('receiver_momo_number or collection_id is required'),
    );
    expect(ingest, contains('user_can_ingest_receiver_sms'));
    expect(ingest, contains('Receiver is not authorized for this MOMO number'));
  });

  test('service-only and OTP hook functions require shared secrets', () {
    final shared = File(
      'supabase/functions/_shared/supabase.ts',
    ).readAsStringSync();
    final otp = File(
      'supabase/functions/auth-send-whatsapp-otp/index.ts',
    ).readAsStringSync();
    final config = File('supabase/config.toml').readAsStringSync();
    final ingest = File(
      'supabase/functions/ingest-payment-sms/index.ts',
    ).readAsStringSync();

    expect(shared, contains('requireEnv("INTERNAL_FUNCTION_SECRET")'));
    expect(shared, isNot(contains('if (!expected) return')));
    expect(otp, contains('requireEnv("SEND_SMS_HOOK_SECRET")'));
    expect(otp, contains('new Webhook(standardWebhookSecret).verify'));
    expect(otp, contains('payload.sms?.otp'));
    expect(config, contains('[functions.auth-send-whatsapp-otp]'));
    expect(config, contains('verify_jwt = false'));
    expect(
      ingest,
      contains('"x-collect-signature": requireEnv("INTERNAL_FUNCTION_SECRET")'),
    );
  });

  test('WhatsApp OTP auth can pass CAPTCHA tokens when enabled', () {
    final authScreen = File(
      'lib/features/auth/auth_screen.dart',
    ).readAsStringSync();
    final appEnv = File('lib/app/env/app_env.dart').readAsStringSync();

    expect(appEnv, contains('AUTH_CAPTCHA_ENABLED'));
    expect(appEnv, contains('AUTH_CAPTCHA_PROVIDER'));
    expect(appEnv, contains('AUTH_CAPTCHA_SITE_KEY'));
    expect(authScreen, contains('env.authCaptchaEnabled'));
    expect(authScreen, contains('captchaToken: captchaToken.isEmpty'));
    expect(authScreen, contains('Complete CAPTCHA verification first.'));
  });

  test('Supabase CAPTCHA hardening requires complete provider inputs', () {
    final hardening = File(
      'scripts/supabase_apply_auth_hardening.sh',
    ).readAsStringSync();
    final readiness = File(
      'scripts/supabase_production_readiness.sh',
    ).readAsStringSync();

    expect(
      hardening,
      contains('AUTH_CAPTCHA_PROVIDER is required when AUTH_CAPTCHA_SECRET'),
    );
    expect(
      hardening,
      contains('AUTH_CAPTCHA_SITE_KEY is required when AUTH_CAPTCHA_SECRET'),
    );
    expect(hardening, contains('hcaptcha|turnstile'));
    expect(hardening, contains('password_hibp_enabled: true'));
    expect(
      hardening,
      contains('HIBP leaked-password protection requires a paid Supabase plan'),
    );
    expect(readiness, contains('HIBP leaked-password protection is disabled.'));
    expect(
      readiness,
      contains(
        'AUTH_CAPTCHA_SITE_KEY is missing for CAPTCHA-enabled client builds.',
      ),
    );
    expect(
      readiness,
      contains(
        'AUTH_CAPTCHA_PROVIDER does not match live Supabase CAPTCHA provider.',
      ),
    );
    expect(readiness, contains('Supabase organization is on the Free plan.'));
  });

  test('PITR add-on helper requires explicit billable confirmation', () {
    final makefile = File('Makefile').readAsStringSync();
    final pitr = File('scripts/supabase_apply_pitr.sh').readAsStringSync();

    expect(makefile, contains('supabase-pitr-enable:'));
    expect(
      pitr,
      contains(r'PITR_ADDON_VARIANT="${PITR_ADDON_VARIANT:-pitr_7}"'),
    );
    expect(pitr, contains('CONFIRM_ENABLE_PITR'));
    expect(
      pitr,
      contains('PITR is billable. Re-run with CONFIRM_ENABLE_PITR='),
    );
    expect(pitr, contains(r'\"addon_type\":\"pitr\"'));
  });

  test('operational report covers database health and performance signals', () {
    final makefile = File('Makefile').readAsStringSync();
    final report = File(
      'scripts/supabase_operational_report.sh',
    ).readAsStringSync();

    expect(makefile, contains('supabase-operational-report:'));
    expect(report, contains('pg_stat_user_tables'));
    expect(report, contains('pg_stat_user_indexes'));
    expect(report, contains('pg_statio_user_tables'));
    expect(report, contains('pg_stat_statements'));
    expect(report, contains('indexes_without_scans'));
    expect(report, contains('slow_queries'));
  });

  test('admin list RPC filters consume shared table controls', () {
    for (final functionName in [
      'admin_list_users',
      'admin_list_unallocated',
      'admin_list_ledger',
      'admin_list_receivers',
      'admin_list_audit_logs',
      'admin_list_feature_flags',
      'admin_list_settings',
      'admin_list_admin_users',
    ]) {
      expect(
        adminFilterContracts,
        contains('create or replace function $functionName'),
      );
    }

    expect(adminFilterContracts, contains("p_status = 'admin'"));
    expect(adminFilterContracts, contains("p_status = 'enabled'"));
    expect(adminFilterContracts, contains("p_status = 'sensitive'"));
    expect(adminFilterContracts, contains("p_status = 'logged'"));
    expect(adminFilterContracts, contains('or ar.name = p_status'));
    expect(adminFilterContracts, contains("'id', coalesce(nullif(p_id, '')"));
  });

  test('admin roles are least-privilege by operational lane', () {
    final readiness = File(
      'scripts/supabase_production_readiness.sh',
    ).readAsStringSync();
    final adminUat = File(
      'scripts/collect_admin_security_uat.sh',
    ).readAsStringSync();

    expect(
      adminRoleTightening,
      contains("'compliance_admin', 'sms.raw.reveal'"),
    );
    expect(
      adminRoleTightening,
      contains("'payments_admin', 'payments.allocate'"),
    );
    expect(
      adminRoleTightening,
      contains("'moderation_admin', 'public_requests.review'"),
    );
    expect(adminRoleTightening, contains("'read_only_admin', 'settings.read'"));
    expect(
      adminRoleTightening,
      isNot(contains("'read_only_admin', 'payments.allocate'")),
    );
    expect(
      adminRoleTightening,
      isNot(contains("'support_admin', 'sms.raw.reveal'")),
    );
    expect(
      adminRoleTightening,
      isNot(contains("'operations_admin', 'payments.allocate'")),
    );
    expect(
      adminRoleTightening,
      isNot(contains("'moderation_admin', 'payment_events.reparse'")),
    );
    expect(
      adminRoleTightening,
      contains("public.has_admin_permission('public_requests.review'"),
    );
    expect(
      adminRoleTightening,
      contains("public.has_admin_permission('payments.allocate'"),
    );
    expect(
      adminRoleTightening,
      contains('select public.is_platform_admin(auth.uid())'),
    );
    expect(readiness, contains('collect_admin_security_uat.sh'));
    expect(adminUat, contains('support_admin unexpectedly revealed raw SMS'));
    expect(
      adminUat,
      contains('read_only_admin unexpectedly allocated payment'),
    );
    expect(adminUat, contains('Rollback UAT payments admin allocation'));
    expect(adminUat, contains('rollback admin/security UAT passed'));
  });

  test('public payment feeds use safe views instead of base table reads', () {
    final repository = File(
      'lib/shared/repositories/collect_repository.dart',
    ).readAsStringSync();

    expect(migration, contains('create view public_contributions_view'));
    expect(
      clientSafeViews,
      contains('create or replace view member_contributions_view'),
    );
    expect(repository, contains("from('public_contributions_view')"));
    expect(repository, contains("from('member_contributions_view')"));
    expect(repository, isNot(contains("from('payments')")));
  });

  test('Supabase advisor security errors are gated', () {
    final makefile = File('Makefile').readAsStringSync();
    final readiness = File(
      'scripts/supabase_production_readiness.sh',
    ).readAsStringSync();
    final config = File('supabase/config.toml').readAsStringSync();
    final advisorGate = File(
      'scripts/supabase_advisors_gate.sh',
    ).readAsStringSync();
    final warningInventory = File(
      'scripts/supabase_advisors_warning_inventory.sh',
    ).readAsStringSync();
    final schemaInventory = File(
      'scripts/supabase_schema_inventory.sh',
    ).readAsStringSync();
    final evidenceBundle = File(
      'scripts/supabase_go_live_evidence_bundle.sh',
    ).readAsStringSync();
    final edgeAuthUat = File(
      'scripts/collect_edge_auth_contract_uat.sh',
    ).readAsStringSync();
    final goLiveGate = File(
      'scripts/supabase_go_live_gate.sh',
    ).readAsStringSync();
    final postOperatorChecklist = File(
      'scripts/supabase_post_operator_checklist.sh',
    ).readAsStringSync();
    final acceptanceMatrix = File(
      'scripts/supabase_acceptance_matrix.sh',
    ).readAsStringSync();
    final runbook = File(
      'docs/SUPABASE_OPERATIONS_RUNBOOK.md',
    ).readAsStringSync();
    final checklist = File(
      'docs/release/PRODUCTION_READINESS_CHECKLIST.md',
    ).readAsStringSync();

    for (final viewName in [
      'public_profiles_view',
      'collection_summary_view',
      'public_collections_view',
      'public_contributions_view',
      'member_collection_summary_view',
      'parsed_payment_events_review_view',
      'member_collections_view',
      'member_contributions_view',
      'member_public_collection_requests_view',
    ]) {
      expect(
        viewSecurityInvoker,
        contains('alter view public.$viewName set (security_invoker = true);'),
      );
    }

    expect(makefile, contains('supabase-advisors:'));
    expect(makefile, contains('supabase-advisor-warnings:'));
    expect(makefile, contains('supabase-schema-inventory:'));
    expect(makefile, contains('supabase-schema-inventory-json:'));
    expect(makefile, contains('supabase-go-live-evidence:'));
    expect(makefile, contains('supabase-go-live-gate:'));
    expect(makefile, contains('supabase-go-live-gate-json:'));
    expect(makefile, contains('supabase-edge-auth-uat:'));
    expect(makefile, contains('supabase-post-operator-checklist:'));
    expect(makefile, contains('supabase-post-operator-checklist-json:'));
    expect(makefile, contains('supabase-acceptance-matrix:'));
    expect(makefile, contains('supabase-acceptance-matrix-json:'));
    expect(readiness, contains('scripts/supabase_advisors_gate.sh'));
    expect(
      readiness,
      contains('scripts/supabase_advisors_warning_inventory.sh'),
    );
    expect(readiness, contains('information_schema.column_privileges'));
    expect(readiness, contains('missing column grant:'));
    expect(advisorGate, contains('supabase_cli db advisors'));
    expect(advisorGate, contains(r'--type "$type"'));
    expect(advisorGate, contains('SUPABASE_ADVISORS_LEVEL:-error'));
    expect(advisorGate, contains('SUPABASE_ADVISORS_FAIL_ON:-error'));
    expect(warningInventory, contains('allowed_security_max'));
    expect(warningInventory, contains('pg_graphql_anon_table_exposed'));
    expect(warningInventory, contains('performance warnings=0'));
    expect(schemaInventory, contains('pg_policies'));
    expect(schemaInventory, contains('information_schema.role_table_grants'));
    expect(schemaInventory, contains('search_path_pinned'));
    expect(schemaInventory, contains('extra_objects'));
    expect(schemaInventory, contains('missing_objects'));
    expect(schemaInventory, isNot(contains('select * from')));
    expect(evidenceBundle, contains('release_status.json'));
    expect(evidenceBundle, contains('release_status_json_retry'));
    expect(evidenceBundle, contains('database_connectivity'));
    expect(evidenceBundle, contains('go_live_gate.json'));
    expect(evidenceBundle, contains('platform_packet.json'));
    expect(evidenceBundle, contains('platform_exception_gate.txt'));
    expect(evidenceBundle, contains('post_operator_checklist.json'));
    expect(evidenceBundle, contains('acceptance_matrix.json'));
    expect(evidenceBundle, contains('schema_inventory.json'));
    expect(evidenceBundle, contains('advisor_warnings.txt'));
    expect(evidenceBundle, contains('operational_report.json'));
    expect(evidenceBundle, contains('supabase_ready.txt'));
    expect(evidenceBundle, contains('edge_auth_contract_uat.txt'));
    expect(evidenceBundle, contains('release_secret_scan.txt'));
    expect(evidenceBundle, contains('commands.tsv'));
    expect(evidenceBundle, contains('summary.json'));
    expect(evidenceBundle, contains('go_live_gate'));
    expect(evidenceBundle, contains('platform_exception_gate'));
    expect(evidenceBundle, contains('post_operator_checklist'));
    expect(evidenceBundle, contains('acceptance_matrix'));
    expect(evidenceBundle, contains('.cache/supabase_go_live_evidence'));
    expect(evidenceBundle, isNot(contains(r'cat .env')));
    expect(goLiveGate, contains('GO-WITH-EXCEPTIONS'));
    expect(goLiveGate, contains('SUPABASE_GO_LIVE_STATUS_JSON'));
    expect(goLiveGate, contains('supabase_platform_exception_gate.sh'));
    expect(
      postOperatorChecklist,
      contains('SUPABASE_POST_OPERATOR_STATUS_JSON'),
    );
    expect(postOperatorChecklist, contains('AUTH_CAPTCHA_PROVIDER'));
    expect(
      postOperatorChecklist,
      contains('auth_hibp_leaked_password_protection'),
    );
    expect(postOperatorChecklist, contains('supabase_pitr'));
    expect(postOperatorChecklist, contains('final_verification'));
    expect(
      postOperatorChecklist,
      isNot(contains(r'echo "$AUTH_CAPTCHA_SECRET"')),
    );
    expect(acceptanceMatrix, contains('SUPA-001'));
    expect(acceptanceMatrix, contains('edge_auth_contract_uat'));
    expect(
      acceptanceMatrix,
      contains(
        'Remote public schema contains only repo-owned required objects',
      ),
    );
    expect(
      acceptanceMatrix,
      contains('Every public base table has row-level security enabled'),
    );
    expect(
      acceptanceMatrix,
      contains('Final Supabase go-live gate approves release'),
    );
    expect(
      acceptanceMatrix,
      contains('Acceptance matrix references redacted evidence files'),
    );
    expect(acceptanceMatrix, isNot(contains(r'cat .env')));
    expect(edgeAuthUat, contains('auth-send-whatsapp-otp'));
    expect(edgeAuthUat, contains('verify_jwt'));
    expect(edgeAuthUat, contains('authErrorStatus'));
    expect(edgeAuthUat, contains('requireInternalRequest(req)'));
    expect(edgeAuthUat, contains('requireUser('));
    expect(edgeAuthUat, contains('Edge Function auth contract UAT passed'));
    expect(runbook, contains('make supabase-schema-inventory'));
    expect(runbook, contains('make supabase-go-live-evidence'));
    expect(runbook, contains('make supabase-go-live-gate'));
    expect(runbook, contains('make supabase-post-operator-checklist'));
    expect(runbook, contains('make supabase-acceptance-matrix'));
    expect(checklist, contains('Supabase live schema inventory'));
    expect(checklist, contains('Supabase go-live evidence bundle'));
    expect(checklist, contains('Supabase final go-live gate'));
    expect(checklist, contains('Post-operator verification'));
    expect(checklist, contains('Acceptance matrix'));
    expect(config, contains('schemas = ["public"]'));
    expect(config, isNot(contains('"graphql_public"')));
    expect(
      disableGraphqlIntrospection,
      contains(
        'comment on schema public is e\'@graphql({"introspection": false})\'',
      ),
    );
    expect(viewSecurityInvoker, contains('grant select ('));
    expect(viewSecurityInvoker, contains('on public.profiles to anon'));
    expect(viewSecurityInvoker, contains('payments public posted or scoped'));
    expect(
      viewSecurityInvoker,
      contains('ledger public collection credit or scoped'),
    );
    for (final functionName in [
      'mask_phone(text)',
      '_admin_row(uuid, text, text, text, text, timestamptz, jsonb)',
      'normalize_slug(text)',
      'touch_updated_at()',
      'generate_public_id()',
      'generate_contribution_code()',
      'prevent_client_admin_escalation()',
      'prevent_ledger_mutation()',
    ]) {
      expect(
        helperSearchPaths,
        contains('alter function public.$functionName set search_path'),
      );
    }
    expect(
      splitPermissiveSelectPolicies,
      contains('alter policy "admin user roles read admins"'),
    );
    expect(
      splitPermissiveSelectPolicies,
      contains('alter policy "raw sms metadata scoped read"'),
    );
    for (final policyName in [
      'members manage admins',
      'receivers manage admins',
      'payment instructions platform admin manage',
      'invites manage admins',
      'recurring periods manage admins',
      'obligations manage admins',
    ]) {
      expect(
        splitPermissiveSelectPolicies,
        contains('drop policy if exists "$policyName"'),
      );
    }
    expect(splitPermissiveSelectPolicies, isNot(contains('for all')));
  });

  test('Flutter client reads scoped views instead of private base tables', () {
    final repository = File(
      'lib/shared/repositories/collect_repository.dart',
    ).readAsStringSync();
    final readiness = File(
      'scripts/supabase_production_readiness.sh',
    ).readAsStringSync();

    expect(
      clientSafeViews,
      contains('create or replace view member_collections_view'),
    );
    expect(
      clientSafeViews,
      contains('create or replace view member_public_collection_requests_view'),
    );
    expect(clientSafeViews, contains('record_receiver_mode_consent'));
    expect(repository, contains("from('member_collections_view')"));
    expect(
      repository,
      isNot(contains("from('parsed_payment_events_review_view')")),
    );
    expect(repository, contains("'record_receiver_mode_consent'"));
    expect(repository, isNot(contains("from('collections')")));
    expect(repository, isNot(contains("from('public_collection_requests')")));
    expect(repository, isNot(contains("from('receiver_mode_consents')")));
    expect(readiness, contains("'member_collections_view', 'SELECT'"));
    expect(readiness, contains("'member_contributions_view', 'SELECT'"));
    expect(
      readiness,
      contains("'member_public_collection_requests_view', 'SELECT'"),
    );
    expect(readiness, contains("'record_receiver_mode_consent', 'EXECUTE'"));
  });

  test('payment intent paid reporting is RPC-only', () {
    final repository = File(
      'lib/shared/repositories/collect_repository.dart',
    ).readAsStringSync();

    expect(
      migration,
      contains('create or replace function report_payment_intent_paid'),
    );
    expect(
      migration,
      contains('revoke all on payment_intents from anon, authenticated'),
    );
    expect(
      migration,
      contains('grant select on payment_intents to authenticated'),
    );
    expect(
      migration,
      contains(
        'grant execute on function report_payment_intent_paid(uuid, text) to authenticated',
      ),
    );
    expect(
      migration,
      isNot(
        contains(
          'create policy "payment intents update contributor txn or admin"',
        ),
      ),
    );
    expect(
      finalPaymentIntentHardening,
      contains(
        'drop policy if exists "payment intents update contributor txn or admin" on payment_intents',
      ),
    );
    expect(
      finalPaymentIntentHardening,
      contains('revoke update on payment_intents from anon, authenticated'),
    );
    expect(repository, contains("'report_payment_intent_paid'"));
    expect(
      repository,
      isNot(contains(".from('payment_intents')\n          .update")),
    );
  });

  test('payment posting binds events and intents to target collection', () {
    expect(
      migration,
      contains('Payment intent does not belong to target collection'),
    );
    expect(
      migration,
      contains('Parsed event receiver is not configured for target collection'),
    );
    expect(
      migration,
      contains('cr.receiver_user_id = event_row.receiver_user_id'),
    );
    expect(
      migration,
      contains('cr.momo_number_hash = event_row.receiver_phone_hash'),
    );
  });

  test('linked rollback UAT covers payment edge-case safety', () {
    final linkedUat = File('scripts/collect_linked_uat.sh').readAsStringSync();

    expect(
      linkedUat,
      contains('missing receiver authorization unexpectedly passed'),
    );
    expect(
      linkedUat,
      contains('Rollback UAT duplicate transaction no double-post check'),
    );
    expect(
      linkedUat,
      contains('duplicate transaction created a second payment'),
    );
    expect(
      linkedUat,
      contains('duplicate transaction created a second ledger entry'),
    );
    expect(linkedUat, contains("expires_at = now() - interval '3 hours'"));
    expect(linkedUat, contains('expired intent should not auto-match'));
    expect(
      linkedUat,
      contains('expired intent event was posted automatically'),
    );
  });

  test('parsed payment review events are collection-scoped', () {
    final repository = File(
      'lib/shared/repositories/collect_repository.dart',
    ).readAsStringSync();
    final ledger = File(
      'lib/features/ledger/ledger_screen.dart',
    ).readAsStringSync();
    final ingest = File(
      'supabase/functions/ingest-payment-sms/index.ts',
    ).readAsStringSync();
    final parser = File(
      'supabase/functions/parse-payment-sms/index.ts',
    ).readAsStringSync();

    expect(
      migration,
      contains(
        'collection_id uuid references collections(id) on delete set null',
      ),
    );
    expect(
      migration,
      contains('create view parsed_payment_events_review_view'),
    );
    expect(migration, contains('ppe.collection_id = c.id'));
    expect(
      migration,
      contains('ppe.receiver_phone_hash = cr.momo_number_hash'),
    );
    expect(
      migration,
      contains('parsed_payment_events_review_view to authenticated'),
    );
    expect(
      repository,
      isNot(contains("from('parsed_payment_events_review_view')")),
    );
    expect(
      ledger,
      contains('contributionsForCollectionProvider(collectionId)'),
    );
    expect(ingest, contains('collection_id: collectionId'));
    expect(parser, contains('collection_id: rawSms.collection_id'));
  });

  test('public summary view does not expose private collection totals', () {
    expect(migration, contains('create view collection_summary_view'));
    expect(
      migration,
      contains(
        "where c.public_status = 'public_approved'\n  and c.archived_at is null",
      ),
    );
    expect(migration, contains('create view member_collection_summary_view'));
    expect(
      migration,
      contains('where public.user_can_read_collection(c.id, auth.uid())'),
    );
  });

  test('collection receiver details are hydrated separately under RLS', () {
    final repository = File(
      'lib/shared/repositories/collect_repository.dart',
    ).readAsStringSync();

    expect(repository, contains('_attachAuthorizedReceivers'));
    expect(repository, contains("from('collection_receivers')"));
    expect(repository, isNot(contains("select('*, collection_receivers")));
  });

  test('Edge Functions are present for critical backend operations', () {
    for (final name in [
      'auth-send-whatsapp-otp',
      'ingest-payment-sms',
      'parse-payment-sms',
      'allocate-payment',
      'manual-allocate-payment',
      'request-public-collection',
      'review-public-collection',
    ]) {
      expect(File('supabase/functions/$name/index.ts').existsSync(), isTrue);
    }
  });

  test('public collection review function uses SQL RPC argument names', () {
    final reviewFunction = File(
      'supabase/functions/review-public-collection/index.ts',
    ).readAsStringSync();

    expect(migration, contains('p_admin_note text default null'));
    expect(reviewFunction, contains('review_public_collection'));
    expect(
      reviewFunction,
      contains('p_admin_note: payload.admin_note ?? null'),
    );
    expect(
      reviewFunction,
      isNot(contains('\n      admin_note: payload.admin_note ?? null')),
    );
  });

  test('SMS parser function does not persist raw parsed phone fields', () {
    final parser = File(
      'supabase/functions/parse-payment-sms/index.ts',
    ).readAsStringSync();

    expect(parser, contains('sanitizeParsedJson(parsed)'));
    expect(parser, contains('sender_phone: parsed.sender_phone ? "[hashed]"'));
    expect(
      parser,
      contains('receiver_phone: parsed.receiver_phone ? "[hashed]"'),
    );
  });

  test('SMS parser has conservative fallback for provider throttling', () {
    final parser = File(
      'supabase/functions/parse-payment-sms/index.ts',
    ).readAsStringSync();
    final liveParserUat = File(
      'scripts/collect_live_parser_uat.sh',
    ).readAsStringSync();

    expect(
      parser,
      contains('fallbackParse(rawSms.raw_sender, rawSms.raw_body)'),
    );
    expect(parser, contains('response.status === 429'));
    expect(parser, contains('collect.local_heuristic.v1'));
    expect(parser, contains('allocation_status: allocationStatus'));
    expect(liveParserUat, contains('live parser UAT passed'));
    expect(liveParserUat, contains('ledger_count'));
  });

  test('Android internal SMS receiver is consent gated and drainable', () {
    final receiver = File(
      'android/app/src/internal_receiver/kotlin/app/cool/mobile/receiver_sms/CollectSmsReceiver.kt',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/app/cool/mobile/MainActivity.kt',
    ).readAsStringSync();
    final channel = File(
      'lib/core/security/receiver_mode_channel.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/shared/repositories/collect_repository.dart',
    ).readAsStringSync();

    expect(receiver, contains('if (!prefs.getBoolean(RECEIVER_ENABLED_KEY'));
    expect(receiver, contains('pending_sms'));
    expect(receiver, isNot(contains('Log.i("CollectSmsReceiver", body')));
    expect(mainActivity, contains('"collect/receiver_mode"'));
    expect(mainActivity, contains('"setEnabled"'));
    expect(mainActivity, contains('"drainPendingSms"'));
    expect(channel, contains("MethodChannel('collect/receiver_mode')"));
    expect(repository, contains('syncPendingReceiverSms'));
    expect(repository, contains('drainPendingSms'));
  });
}
