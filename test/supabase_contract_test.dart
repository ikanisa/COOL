import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/202605230001_collect_baseline.sql',
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
  final realtimeInvalidation = File(
    'supabase/migrations/202605250001_app_realtime_invalidation.sql',
  ).readAsStringSync();
  final smsFirstGroupPaymentIntents = File(
    'supabase/migrations/202605270001_sms_first_group_payment_intents.sql',
  ).readAsStringSync();
  final adminPaymentEventServerPaging = File(
    'supabase/migrations/20260612110000_admin_payment_event_server_paging.sql',
  ).readAsStringSync();
  final dropLegacyPaymentEventQueueOverloads = File(
    'supabase/migrations/20260612111500_drop_legacy_payment_event_queue_overloads.sql',
  ).readAsStringSync();
  final revokeAnonAdminQueuePaging = File(
    'supabase/migrations/20260612113000_revoke_anon_admin_queue_paging.sql',
  ).readAsStringSync();
  final schemaInventoryScript = File(
    'scripts/supabase_schema_inventory.sh',
  ).readAsStringSync();
  final contributionIntentSenderHash = File(
    'supabase/migrations/20260601230000_preserve_contribution_sender_hash.sql',
  ).readAsStringSync();
  final mobileStateRlsInitPlanHardening = File(
    'supabase/migrations/20260602050000_harden_mobile_state_rls_initplan.sql',
  ).readAsStringSync();
  final mobileProductionStateSupport = File(
    'supabase/migrations/20260531190000_mobile_production_state_support.sql',
  ).readAsStringSync();
  final updateCollectionProfileRpc = File(
    'supabase/migrations/20260607130500_update_collection_profile_rpc.sql',
  ).readAsStringSync();
  final hardenedMobileProfileRpcs = File(
    'supabase/migrations/20260611111500_harden_mobile_profile_rpcs.sql',
  ).readAsStringSync();
  final adminWhatsappOperatorLogin = File(
    'supabase/migrations/20260611171920_admin_whatsapp_operator_login.sql',
  ).readAsStringSync();
  final adminWhatsappOperatorPhoneLookup = File(
    'supabase/migrations/20260611184934_fix_admin_whatsapp_bootstrap_phone_lookup.sql',
  ).readAsStringSync();
  final disabledBrowserAdminBootstrap = File(
    'supabase/migrations/20260612103000_disable_browser_admin_bootstrap.sql',
  ).readAsStringSync();
  final hardenedNotificationRlsInitPlan = File(
    'supabase/migrations/20260611113000_harden_notification_rls_initplan.sql',
  ).readAsStringSync();
  final tightenedNotificationRpcGrants = File(
    'supabase/migrations/20260611114500_tighten_notification_rpc_grants.sql',
  ).readAsStringSync();
  final readiness = File(
    'scripts/supabase_production_readiness.sh',
  ).readAsStringSync();
  final schemaInventory = File(
    'scripts/supabase_schema_inventory.sh',
  ).readAsStringSync();

  String migrationSection(String text, String start, String end) {
    final startIndex = text.indexOf(start);
    final endIndex = text.indexOf(end, startIndex + start.length);
    expect(startIndex, isNonNegative, reason: 'missing section start: $start');
    expect(endIndex, isNonNegative, reason: 'missing section end: $end');
    return text.substring(startIndex, endIndex);
  }

  test('migration exposes contribution intent RPC without instruction copy', () {
    final contributionIntentFunction = migrationSection(
      smsFirstGroupPaymentIntents,
      'create or replace function create_contribution_intent',
      'create or replace function join_group_by_slug',
    );
    final senderHashMigrationFunction = migrationSection(
      contributionIntentSenderHash,
      'create or replace function create_contribution_intent',
      'revoke execute on function create_contribution_intent',
    );
    final contributionIntentReturn = migrationSection(
      contributionIntentFunction,
      'returns table (',
      ')\nlanguage plpgsql',
    );

    expect(smsFirstGroupPaymentIntents, contains('create_contribution_intent'));
    expect(smsFirstGroupPaymentIntents, contains('receiver_momo_number text'));
    expect(
      smsFirstGroupPaymentIntents,
      contains(
        'grant execute on function create_contribution_intent(uuid, bigint, text)',
      ),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains(
        'drop function if exists create_payment_intent_with_instructions(uuid, bigint, text, text)',
      ),
    );
    expect(contributionIntentFunction, isNot(contains('p_anonymity_choice')));
    expect(contributionIntentFunction, isNot(contains('anonymity_choice')));
    expect(
      senderHashMigrationFunction,
      contains("nullif(trim(p_sender_phone_hash), '')"),
    );
    expect(
      senderHashMigrationFunction,
      contains('intent_row.sender_phone_hash'),
    );
    expect(contributionIntentSenderHash, contains('to authenticated'));
    expect(contributionIntentReturn, isNot(contains('contribution_code')));
    expect(
      smsFirstGroupPaymentIntents,
      isNot(
        contains(
          'grant execute on function create_payment_intent_with_instructions',
        ),
      ),
    );
  });

  test('current group creation RPC does not expose campaign fields', () {
    final groupCreationFunction = migrationSection(
      smsFirstGroupPaymentIntents,
      'create or replace function create_group_with_owner',
      'create or replace function create_payment_intent',
    );

    expect(
      smsFirstGroupPaymentIntents,
      contains('create or replace function create_group_with_owner'),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains(
        'grant execute on function create_group_with_owner(text, text, text, text, text)',
      ),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains('revoke execute on function create_collection_with_owner'),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains('drop function if exists create_collection_with_owner'),
    );
    expect(groupCreationFunction, isNot(contains('target_amount_rwf')));
    expect(groupCreationFunction, isNot(contains('cover_image_url')));
  });

  test('public profile and contribution views expose only Collect IDs', () {
    expect(
      smsFirstGroupPaymentIntents,
      contains("'Collect ID ' || public_id as public_label"),
    );
    expect(smsFirstGroupPaymentIntents, contains('null::text as avatar_url'));
    expect(
      smsFirstGroupPaymentIntents,
      contains("'Collect ID ' || p.contributor_public_id"),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains('revoke update (display_name, avatar_url, anonymity_default)'),
    );
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
    expect(otp, contains('whatsappAuthTemplateComponents'));
    expect(otp, contains('otpDeliveryUnavailable'));
    expect(otp, contains('PublicHookError'));
    expect(otp, contains('Invalid OTP hook payload'));
    expect(otp, contains('console.error("WhatsApp OTP hook failed"'));
    expect(otp, isNot(contains('error: safeErrorMessage(error)')));
    expect(otp, contains('sub_type: "url"'));
    expect(otp, contains('index: "0"'));
    expect(config, contains('[functions.auth-send-whatsapp-otp]'));
    expect(config, contains('verify_jwt = false'));
    expect(
      File('scripts/supabase_apply_auth_hardening.sh').readAsStringSync(),
      contains('sms_otp_exp: 600'),
    );
    expect(
      File('scripts/supabase_production_readiness.sh').readAsStringSync(),
      contains('Phone OTP expiry must be 600 seconds'),
    );
    expect(
      ingest,
      contains('"x-collect-signature": requireEnv("INTERNAL_FUNCTION_SECRET")'),
    );
  });

  test(
    'admin WhatsApp OTP login does not bootstrap platform owner in browser',
    () {
      final adminRuntime = File(
        'lib/admin/core/admin_runtime.dart',
      ).readAsStringSync();

      expect(adminRuntime, contains("'+250788767816'"));
      expect(adminRuntime, contains('OtpChannel.whatsapp'));
      expect(
        adminRuntime,
        isNot(contains('admin_bootstrap_whatsapp_operator')),
      );
      expect(
        adminRuntime,
        contains('Use the registered admin WhatsApp number.'),
      );

      expect(adminWhatsappOperatorLogin, contains("'+250788767816'"));
      expect(adminWhatsappOperatorPhoneLookup, contains('from auth.users u'));
      expect(
        disabledBrowserAdminBootstrap,
        contains(
          'create or replace function admin_bootstrap_whatsapp_operator()',
        ),
      );
      expect(
        disabledBrowserAdminBootstrap,
        contains('from public, anon, authenticated'),
      );
      expect(disabledBrowserAdminBootstrap, contains('to service_role'));
      expect(
        disabledBrowserAdminBootstrap,
        contains('admin_bootstrap_whatsapp_operator is disabled'),
      );
    },
  );

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
      contains('leaked-password protection may require a paid Supabase plan'),
    );
    expect(
      readiness,
      contains('leaked-credential protection is disabled; treat as optional'),
    );
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
    expect(
      readiness,
      contains(
        'Supabase organization is on the Free plan; treat as operational capacity',
      ),
    );
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

  test('payment event admin queues expose server paging contract', () {
    for (final functionName in [
      'admin_list_payment_events',
      'admin_list_allocations',
      'admin_list_unallocated',
    ]) {
      expect(
        adminPaymentEventServerPaging,
        contains('create or replace function $functionName('),
      );
    }

    expect(
      adminPaymentEventServerPaging,
      contains('p_limit integer default 25'),
    );
    expect(
      adminPaymentEventServerPaging,
      contains('p_offset integer default 0'),
    );
    expect(
      adminPaymentEventServerPaging,
      contains("p_sort text default 'created_at_desc'"),
    );
    expect(adminPaymentEventServerPaging, contains('limit v_limit'));
    expect(adminPaymentEventServerPaging, contains('offset v_offset'));
    expect(adminPaymentEventServerPaging, contains("'total'"));
    expect(adminPaymentEventServerPaging, contains("'amount_desc'"));
    expect(
      adminPaymentEventServerPaging,
      contains(
        'grant execute on function admin_list_payment_events(text, text, integer, integer, text)',
      ),
    );
    expect(
      dropLegacyPaymentEventQueueOverloads,
      contains('drop function if exists admin_list_payment_events(text, text)'),
    );
    expect(
      dropLegacyPaymentEventQueueOverloads,
      contains('drop function if exists admin_list_allocations(text, text)'),
    );
    expect(
      dropLegacyPaymentEventQueueOverloads,
      contains('drop function if exists admin_list_unallocated(text, text)'),
    );
    expect(
      revokeAnonAdminQueuePaging,
      contains(
        'revoke execute on function admin_list_payment_events(text, text, integer, integer, text)',
      ),
    );
    expect(revokeAnonAdminQueuePaging, contains('from public, anon'));
    expect(
      revokeAnonAdminQueuePaging,
      contains(
        'grant execute on function admin_list_payment_events(text, text, integer, integer, text)',
      ),
    );
    expect(revokeAnonAdminQueuePaging, contains('to authenticated'));
    expect(
      schemaInventoryScript,
      contains('"function|admin_list_payment_events"'),
    );
    expect(
      schemaInventoryScript,
      contains('logical_overload_replacements.include?(object_key)'),
    );
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
      contains("'payments_admin', 'payment_events.reparse'"),
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
    expect(smsFirstGroupPaymentIntents, contains("'payments.allocate'"));
    expect(readiness, isNot(contains("'payments.allocate', 'EXECUTE'")));
    expect(
      smsFirstGroupPaymentIntents,
      contains('revoke execute on function admin_review_public_request'),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains('revoke execute on function admin_moderate_collection'),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains('drop function if exists admin_moderate_collection'),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains('drop function if exists admin_list_public_requests'),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains('drop table if exists public_collection_requests'),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains('create or replace function admin_list_collections'),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains('create or replace function admin_get_collection'),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains("'Collect ID ' || p.public_id"),
    );
    expect(
      smsFirstGroupPaymentIntents,
      isNot(contains('coalesce(p.display_name')),
    );
    expect(smsFirstGroupPaymentIntents, contains("'Pending payment intents'"));
    expect(smsFirstGroupPaymentIntents, contains("'SMS exceptions'"));
    expect(
      smsFirstGroupPaymentIntents,
      contains('create or replace function admin_list_allocations'),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains(
        "return admin_list_payment_events(p_search, coalesce(p_status, 'allocated'))",
      ),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains(
        "e.allocation_status in ('unallocated', 'ambiguous', 'needs_review')",
      ),
    );
    expect(smsFirstGroupPaymentIntents, contains("'public_requests.read'"));
    expect(smsFirstGroupPaymentIntents, contains("name = 'group_ops_admin'"));
    expect(
      smsFirstGroupPaymentIntents,
      contains('delete from admin_permissions'),
    );
    expect(
      smsFirstGroupPaymentIntents,
      isNot(contains('Pending public requests')),
    );
    expect(
      readiness,
      isNot(contains("'admin_moderate_collection', 'EXECUTE'")),
    );
    expect(
      adminRoleTightening,
      contains('select public.is_platform_admin(auth.uid())'),
    );
    expect(readiness, contains('collect_admin_security_uat.sh'));
    expect(adminUat, contains('support_admin unexpectedly revealed raw SMS'));
    expect(
      adminUat,
      contains('read_only_admin unexpectedly requested reparse'),
    );
    expect(adminUat, contains('Rollback UAT payments admin reparse'));
    expect(adminUat, contains('rollback admin/security UAT passed'));
  });

  test('public payment feeds use safe views instead of base table reads', () {
    final repository = File(
      'lib/shared/repositories/collect_repository.dart',
    ).readAsStringSync();

    expect(
      smsFirstGroupPaymentIntents,
      contains('drop view if exists public_contributions_view'),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains('create view public_contributions_view'),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains('drop view if exists member_contributions_view'),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains('create view member_contributions_view'),
    );
    expect(repository, contains("from('public_contributions_view')"));
    expect(repository, contains("from('member_contributions_view')"));
    expect(repository, isNot(contains("from('payments')")));
  });

  test('member data views expose SMS-first group fields only', () {
    final memberSummaryView = migrationSection(
      smsFirstGroupPaymentIntents,
      'create view member_collection_summary_view',
      'create view member_collections_view',
    );
    final memberCollectionsView = migrationSection(
      smsFirstGroupPaymentIntents,
      'create view member_collections_view',
      'create view member_contributions_view',
    );
    final memberContributionsView = migrationSection(
      smsFirstGroupPaymentIntents,
      'create view member_contributions_view',
      'revoke update (display_name, avatar_url, anonymity_default)',
    );

    for (final viewSql in [
      memberSummaryView,
      memberCollectionsView,
      memberContributionsView,
    ]) {
      expect(viewSql, isNot(contains('category')));
      expect(viewSql, isNot(contains('cover_image_url')));
      expect(viewSql, isNot(contains('target_amount_rwf')));
      expect(viewSql, isNot(contains('public_status')));
      expect(viewSql, isNot(contains('is_recurring')));
      expect(viewSql, isNot(contains('recurring_rule')));
      expect(viewSql, isNot(contains('anonymity_choice')));
      expect(viewSql, isNot(contains('display_name')));
      expect(viewSql, isNot(contains('avatar_url')));
    }

    expect(
      smsFirstGroupPaymentIntents,
      contains('revoke select (display_name, avatar_url, anonymity_default)'),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains('revoke select (anonymity_choice)'),
    );
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
      'public_contributions_view',
      'member_collection_summary_view',
      'member_collections_view',
      'member_contributions_view',
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
    expect(readiness, contains('check_db_lint'));
    expect(readiness, contains('check_migration_history'));
    expect(readiness, contains('SUPABASE_READY_REQUIRE_POOLER_COMMANDS'));
    expect(readiness, contains('scripts/supabase_schema_inventory.sh'));
    expect(readiness, contains('send-notification'));
    expect(
      readiness,
      contains("('authenticated', 'app_realtime_events', 'SELECT')"),
    );
    expect(readiness, contains('information_schema.column_privileges'));
    expect(readiness, contains('missing column grant:'));
    expect(advisorGate, contains('supabase_cli db advisors'));
    expect(advisorGate, contains(r'--type "$type"'));
    expect(advisorGate, contains('SUPABASE_ADVISORS_LEVEL:-error'));
    expect(advisorGate, contains('SUPABASE_ADVISORS_FAIL_ON:-error'));
    expect(warningInventory, contains('allowed_security_max'));
    expect(warningInventory, contains('pg_graphql_anon_table_exposed'));
    expect(
      warningInventory,
      contains('"authenticated_security_definer_function_executable" => 46'),
    );
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
    expect(evidenceBundle, contains('post_operator_checklist'));
    expect(evidenceBundle, contains('acceptance_matrix'));
    expect(evidenceBundle, contains('.cache/supabase_go_live_evidence'));
    expect(evidenceBundle, isNot(contains(r'cat .env')));
    expect(edgeAuthUat, contains('"send-notification" => :internal'));
    expect(goLiveGate, contains('go_live_approved'));
    expect(goLiveGate, contains('SUPABASE_GO_LIVE_STATUS_JSON'));
    expect(goLiveGate, contains('SUPABASE_GO_LIVE_READINESS_JSON'));
    expect(goLiveGate, contains('scripts/supabase_production_readiness.sh'));
    expect(goLiveGate, contains('linked_supabase_production_readiness'));
    expect(goLiveGate, contains('linked_supabase_sms_first_migration'));
    expect(
      goLiveGate,
      contains('20260601230000_preserve_contribution_sender_hash.sql'),
    );
    expect(
      postOperatorChecklist,
      contains('SUPABASE_POST_OPERATOR_STATUS_JSON'),
    );
    expect(postOperatorChecklist, contains('android_sms_access_uat'));
    expect(postOperatorChecklist, contains('evidence_record_command'));
    expect(
      postOperatorChecklist,
      contains('make record-android-sms-uat-evidence ARGS='),
    );
    expect(postOperatorChecklist, contains('--raw-sms-not-public'));
    expect(postOperatorChecklist, contains('--no-phone-or-momo'));
    expect(postOperatorChecklist, contains('--no-transaction-ids'));
    expect(postOperatorChecklist, contains('record_command'));
    expect(
      postOperatorChecklist,
      contains('make record-release-approval ARGS='),
    );
    expect(postOperatorChecklist, contains('--sanitized-evidence'));
    expect(postOperatorChecklist, contains('--no-production-customer-data'));
    expect(postOperatorChecklist, contains('record_out_of_scope_command'));
    expect(
      postOperatorChecklist,
      contains('linked_supabase_sms_first_migration'),
    );
    expect(
      postOperatorChecklist,
      contains('20260601230000_preserve_contribution_sender_hash.sql'),
    );
    expect(postOperatorChecklist, contains('admin_pwa_live_url'));
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
    expect(runbook, contains('scripts/collect_linked_uat.sh'));
    expect(runbook, contains('make supabase-go-live-gate-json'));
    expect(runbook, contains('make supabase-post-operator-checklist'));
    expect(runbook, contains('Android SMS Access UAT'));
    expect(checklist, contains('Current Readiness'));
    expect(checklist, contains('Production Blockers'));
    expect(checklist, contains('release_owner_signoff'));
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
      smsFirstGroupPaymentIntents,
      contains('create view member_collections_view'),
    );
    expect(smsFirstGroupPaymentIntents, contains('record_sms_access_consent'));
    expect(repository, contains("from('member_collections_view')"));
    expect(repository, contains("'update_collection_profile'"));
    expect(
      repository,
      isNot(contains("from('parsed_payment_events_review_view')")),
    );
    expect(repository, contains("'record_sms_access_consent'"));
    expect(repository, isNot(contains("from('collections')")));
    expect(repository, isNot(contains("from('public_collection_requests')")));
    expect(repository, isNot(contains("from('receiver_mode_consents')")));
    expect(readiness, contains("'member_collections_view', 'SELECT'"));
    expect(readiness, contains("'member_contributions_view', 'SELECT'"));
    expect(
      readiness,
      isNot(contains("'parsed_payment_events_review_view', 'SELECT'")),
    );
    expect(
      readiness,
      isNot(contains("'member_public_collection_requests_view', 'SELECT'")),
    );
    expect(readiness, contains("'record_sms_access_consent', 'EXECUTE'"));
  });

  test('payment intents are confirmed only by MoMo SMS allocation', () {
    final repository = File(
      'lib/shared/repositories/collect_repository.dart',
    ).readAsStringSync();

    expect(
      smsFirstGroupPaymentIntents,
      contains('add column if not exists contributor_public_id char(6)'),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains(
        'create index if not exists payment_intents_member_sms_match_idx',
      ),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains('create or replace function allocate_parsed_payment_event'),
    );
    expect(smsFirstGroupPaymentIntents, contains('auto_member_intent'));
    expect(smsFirstGroupPaymentIntents, isNot(contains('auto_code')));
    expect(
      smsFirstGroupPaymentIntents,
      isNot(contains('detected_collection_code')),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains('alter column contribution_code drop not null'),
    );
    expect(
      smsFirstGroupPaymentIntents,
      isNot(contains('generate_contribution_code()')),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains(
        'revoke execute on function report_payment_intent_paid(uuid, text)',
      ),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains(
        'revoke execute on function manual_allocate_parsed_payment_event(uuid, uuid, uuid, text)',
      ),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains('drop function if exists manual_allocate_parsed_payment_event'),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains(
        'revoke execute on function admin_manual_allocate_payment(uuid, uuid, uuid, text)',
      ),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains('drop function if exists admin_manual_allocate_payment'),
    );
    expect(repository, isNot(contains("'report_payment_intent_paid'")));
    expect(repository, isNot(contains("'request-public-collection'")));
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
    expect(linkedUat, contains('allocation was not idempotent'));
    expect(
      linkedUat,
      contains(
        'from create_contribution_intent(uat_group_id, 5000, contributor_hash)',
      ),
    );
    expect(linkedUat, contains('payment intent sender hash was not stored'));
    expect(linkedUat, contains("expires_at = now() - interval '3 hours'"));
    expect(linkedUat, contains('expired intent should not auto-match'));
    expect(linkedUat, contains('ambiguous event was posted automatically'));
    expect(linkedUat, contains('SUPABASE_LINKED_QUERY_TIMEOUT_SECONDS'));
    expect(linkedUat, contains('run_with_timeout'));
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
      smsFirstGroupPaymentIntents,
      contains('drop view if exists parsed_payment_events_review_view'),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains('revoke all on parsed_payment_events_review_view'),
    );
    expect(
      repository,
      isNot(contains("from('parsed_payment_events_review_view')")),
    );
    expect(
      ledger,
      contains('contributionsForCollectionProvider(widget.collectionId)'),
    );
    expect(ledger, contains('item.collectionId == widget.collectionId'));
    expect(ingest, contains('collection_id: collectionId'));
    expect(parser, contains('collection_id: rawSms.collection_id'));
  });

  test('SMS parser and admin queues do not record payer names', () {
    final parser = File(
      'supabase/functions/parse-payment-sms/index.ts',
    ).readAsStringSync();
    final parserSchema = File(
      'supabase/functions/_shared/sms_schema.ts',
    ).readAsStringSync();
    final models = File(
      'lib/shared/models/collect_models.dart',
    ).readAsStringSync();

    expect(parserSchema, isNot(contains('sender_name')));
    expect(parserSchema, isNot(contains('receiver_name')));
    expect(parserSchema, isNot(contains('raw_reference')));
    expect(parserSchema, isNot(contains('explanation')));
    expect(parser, contains('sender_name: null'));
    expect(parser, contains('Do not extract payer names'));
    expect(
      smsFirstGroupPaymentIntents,
      contains('update parsed_payment_events\nset sender_name = null'),
    );
    expect(
      smsFirstGroupPaymentIntents,
      contains("select to_jsonb(e) - 'sender_name'"),
    );
    expect(
      smsFirstGroupPaymentIntents,
      isNot(contains("coalesce(e.sender_name, 'Unknown sender')")),
    );
    expect(smsFirstGroupPaymentIntents, isNot(contains('e.sender_name ilike')));
    expect(models, contains("senderLabel: 'MoMo SMS'"));
  });

  test(
    'member summary view is scoped and public directory summary is removed',
    () {
      expect(
        smsFirstGroupPaymentIntents,
        contains('drop view if exists collection_summary_view'),
      );
      expect(
        smsFirstGroupPaymentIntents,
        contains('create view member_collection_summary_view'),
      );
      expect(
        smsFirstGroupPaymentIntents,
        contains('where public.user_can_read_collection(c.id, auth.uid())'),
      );
    },
  );

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
    ]) {
      expect(File('supabase/functions/$name/index.ts').existsSync(), isTrue);
    }
    for (final name in [
      'manual-allocate-payment',
      'request-public-collection',
      'review-public-collection',
    ]) {
      expect(File('supabase/functions/$name/index.ts').existsSync(), isFalse);
    }
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

  test('SMS parser requires OpenAI structured parsing', () {
    final parser = File(
      'supabase/functions/parse-payment-sms/index.ts',
    ).readAsStringSync();
    final parserSchema = File(
      'supabase/functions/_shared/sms_schema.ts',
    ).readAsStringSync();
    final liveParserUat = File(
      'scripts/collect_live_parser_uat.sh',
    ).readAsStringSync();

    expect(parser, isNot(contains('fallbackParse')));
    expect(parser, isNot(contains('collect.local_heuristic.v1')));
    expect(parser, isNot(contains('detected_collection_code')));
    expect(parserSchema, isNot(contains('detected_collection_code')));
    expect(parser, contains('OpenAI parse failed'));
    expect(parser, contains('allocation_status: allocationStatus'));
    expect(liveParserUat, contains('live parser UAT passed'));
    expect(liveParserUat, contains('OpenAI returned 429'));
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
      'lib/core/security/sms_access_channel.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/shared/repositories/collect_repository.dart',
    ).readAsStringSync();

    expect(receiver, contains('if (!prefs.getBoolean(SMS_ACCESS_ENABLED_KEY'));
    expect(receiver, contains('pending_sms'));
    expect(receiver, isNot(contains('Log.i("CollectSmsReceiver", body')));
    expect(mainActivity, contains('"collect/sms_access"'));
    expect(mainActivity, contains('"setEnabled"'));
    expect(mainActivity, contains('requestPermissions(SMS_PERMISSIONS'));
    expect(mainActivity, contains('onRequestPermissionsResult'));
    expect(mainActivity, contains('"drainPendingSms"'));
    expect(channel, contains("MethodChannel('collect/sms_access')"));
    expect(repository, contains('syncPendingSmsAccess'));
    expect(repository, contains('drainPendingSms'));
    final app = File('lib/app/app.dart').readAsStringSync();
    expect(app, contains('WidgetsBindingObserver'));
    expect(app, contains('AppLifecycleState.resumed'));
    expect(app, contains('syncPendingSmsAccess'));
    expect(repository, contains('unawaited(syncPendingSmsAccess())'));
  });

  test('Supabase realtime uses safe invalidation events only', () {
    final mobileRepository = File(
      'lib/shared/repositories/collect_repository.dart',
    ).readAsStringSync();
    final adminRuntime = File(
      'lib/admin/core/admin_runtime.dart',
    ).readAsStringSync();
    final realtimeClient = File(
      'lib/core/supabase/realtime_invalidation.dart',
    ).readAsStringSync();

    expect(
      realtimeInvalidation,
      contains('create table if not exists app_realtime_events'),
    );
    expect(
      realtimeInvalidation,
      contains('alter table app_realtime_events enable row level security'),
    );
    expect(
      realtimeInvalidation,
      contains('grant select on app_realtime_events to authenticated'),
    );
    expect(
      realtimeInvalidation,
      contains(
        'revoke execute on function emit_app_realtime_event() from public, anon, authenticated',
      ),
    );
    expect(
      schemaInventory,
      contains('create policy\\s+"?([^"\\n]+?)"?\\s+on\\s+'),
    );
    expect(schemaInventory, contains('events.sort_by(&:first)'));
    expect(schemaInventory, contains('drop function(?: if exists)?'));
    expect(
      File('scripts/supabase_advisors_warning_inventory.sh').readAsStringSync(),
      contains('"pg_graphql_authenticated_table_exposed" => 18'),
    );
    expect(
      realtimeInvalidation,
      contains(
        'alter publication supabase_realtime add table public.app_realtime_events',
      ),
    );
    expect(
      realtimeInvalidation,
      isNot(contains('add table public.raw_payment_sms')),
    );
    expect(realtimeInvalidation, isNot(contains('record_id')));
    expect(realtimeInvalidation, isNot(contains('source_table')));
    expect(realtimeInvalidation, isNot(contains('tg_table_name')));
    expect(
      realtimeInvalidation,
      contains(
        "select attach_app_realtime_event_trigger('raw_payment_sms', 'sms_events')",
      ),
    );
    expect(
      realtimeInvalidation,
      contains(
        "select attach_app_realtime_event_trigger('parsed_payment_events', 'sms_events')",
      ),
    );
    expect(
      realtimeInvalidation,
      contains(
        "select attach_app_realtime_event_trigger('payment_allocations', 'allocations')",
      ),
    );
    expect(
      realtimeInvalidation,
      contains(
        "select attach_app_realtime_event_trigger('admin_user_roles', 'admin_roles')",
      ),
    );
    expect(
      realtimeInvalidation,
      contains(
        "select attach_app_realtime_event_trigger('system_settings', 'settings')",
      ),
    );

    expect(realtimeClient, contains("table: 'app_realtime_events'"));
    expect(realtimeClient, contains('PostgresChangeEvent.insert'));
    expect(realtimeClient, contains('collectMobileRealtimeAreas'));
    expect(realtimeClient, contains('collectAdminRealtimeAreas'));
    expect(realtimeClient, isNot(contains('raw_body')));
    expect(realtimeClient, isNot(contains('momo_number')));

    expect(mobileRepository, contains('_ensureRealtimeSync'));
    expect(mobileRepository, contains('collectMobileRealtimeAreas'));
    expect(mobileRepository, contains('loadInitial()'));
    expect(adminRuntime, contains('adminRealtimeSubscriptionProvider'));
    expect(adminRuntime, contains('adminRealtimeTickProvider'));
    expect(adminRuntime, contains('collectAdminRealtimeAreas'));
  });

  test('mobile production state RPCs stay authenticated and safe', () {
    final repository = File(
      'lib/shared/repositories/collect_repository.dart',
    ).readAsStringSync();
    expect(repository, contains('supabase == null'));
    expect(repository, contains('CollectRepository(supabase: supabase)'));
    expect(
      repository,
      isNot(contains('CollectRepository.fixture(\n        supabase:')),
    );

    expect(
      mobileProductionStateSupport,
      contains('create table if not exists mobile_account_deletion_requests'),
    );
    expect(
      mobileProductionStateSupport,
      contains('create table if not exists mobile_support_requests'),
    );
    expect(
      mobileProductionStateSupport,
      contains('create or replace function ensure_current_profile'),
    );
    expect(
      mobileProductionStateSupport,
      contains('create or replace function request_account_deletion'),
    );
    expect(
      mobileProductionStateSupport,
      contains('create or replace function create_mobile_support_request'),
    );
    expect(
      mobileProductionStateSupport,
      contains('create or replace function list_collection_collect_ids'),
    );
    expect(
      mobileProductionStateSupport,
      contains('create or replace function update_collection_receiver'),
    );
    expect(
      updateCollectionProfileRpc,
      contains('create or replace function update_collection_profile'),
    );
    expect(
      hardenedMobileProfileRpcs,
      contains('create or replace function ensure_current_profile'),
    );
    expect(
      hardenedMobileProfileRpcs,
      contains('set whatsapp_phone = trim(p_whatsapp_phone)'),
    );
    expect(
      hardenedMobileProfileRpcs,
      contains('create or replace function update_collection_profile'),
    );
    expect(hardenedMobileProfileRpcs, contains('accent_color_hex'));
    expect(hardenedMobileProfileRpcs, contains('recurring_cadence'));
    expect(
      hardenedMobileProfileRpcs,
      contains('public_status = next_public_status'),
    );
    expect(
      hardenedMobileProfileRpcs,
      contains('visibility = next_public_status'),
    );
    expect(hardenedMobileProfileRpcs, isNot(contains('is_public =')));
    expect(
      updateCollectionProfileRpc,
      contains(
        'grant execute on function update_collection_profile(uuid, text, text, text, text, boolean, text)',
      ),
    );
    expect(
      hardenedNotificationRlsInitPlan,
      contains('user_id = (select auth.uid())'),
    );
    expect(
      hardenedNotificationRlsInitPlan,
      isNot(contains('user_id = auth.uid()')),
    );
    expect(
      tightenedNotificationRpcGrants,
      contains(
        'revoke execute on function enqueue_notification_event(uuid, text, text, text, uuid, text)',
      ),
    );
    expect(
      tightenedNotificationRpcGrants,
      contains(
        'grant execute on function enqueue_notification_event(uuid, text, text, text, uuid, text)',
      ),
    );
    expect(tightenedNotificationRpcGrants, contains('to service_role'));
    expect(
      mobileProductionStateSupport,
      contains('create or replace function get_owner_group_health'),
    );
    expect(
      readiness,
      contains("('authenticated', 'ensure_current_profile', 'EXECUTE')"),
    );
    expect(
      readiness,
      contains("('authenticated', 'create_mobile_support_request', 'EXECUTE')"),
    );
    expect(
      readiness,
      contains("('authenticated', 'register_notification_device', 'EXECUTE')"),
    );
    expect(
      readiness,
      contains("('authenticated', 'mark_notification_event_read', 'EXECUTE')"),
    );
    expect(
      readiness,
      isNot(contains("('authenticated', 'enqueue_notification_event'")),
    );
    expect(
      readiness,
      contains("('authenticated', 'get_owner_group_health', 'EXECUTE')"),
    );
    expect(
      mobileStateRlsInitPlanHardening,
      contains('user_id = (select auth.uid())'),
    );
    expect(
      mobileStateRlsInitPlanHardening,
      contains('is_platform_admin((select auth.uid()))'),
    );
    expect(
      mobileProductionStateSupport,
      contains(
        'grant execute on function ensure_current_profile(text) to authenticated',
      ),
    );
    expect(
      mobileProductionStateSupport,
      contains(
        'grant execute on function request_account_deletion(text) to authenticated',
      ),
    );
    expect(mobileProductionStateSupport, isNot(contains('raw_body')));
    expect(mobileProductionStateSupport, isNot(contains('display_name')));
  });
}
