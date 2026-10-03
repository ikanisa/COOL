-- database postgres (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;create database collect_c34_restore_d46459070fb1 template template0;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;
select jsonb_build_object(
 'schemas',(select jsonb_agg(jsonb_build_object('name',n.nspname,'owner',pg_get_userbyid(n.nspowner),'acl',
  (select jsonb_agg(jsonb_build_array(case when a.grantee=0 then 'PUBLIC' else pg_get_userbyid(a.grantee)end,
   pg_get_userbyid(a.grantor),a.privilege_type,a.is_grantable)order by a.grantee,a.grantor,a.privilege_type,a.is_grantable)
   from aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner)))a))order by n.nspname)
  from pg_namespace n where n.nspname not like 'pg_%'and n.nspname<>'information_schema'),
 'relations',(select jsonb_agg(jsonb_build_object('schema',n.nspname,'name',c.relname,'kind',c.relkind,
  'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,
  'options',c.reloptions,'acl',(select jsonb_agg(jsonb_build_array(case when a.grantee=0 then 'PUBLIC'else pg_get_userbyid(a.grantee)end,
   pg_get_userbyid(a.grantor),a.privilege_type,a.is_grantable)order by a.grantee,a.grantor,a.privilege_type,a.is_grantable)
   from aclexplode(coalesce(c.relacl,acldefault(case when c.relkind='S'then 's'::"char"else 'r'::"char"end,c.relowner)))a))
   order by n.nspname,c.relname)from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname not like 'pg_%'and n.nspname<>'information_schema'and c.relkind in('r','p','S','v','m')),
 'columns',(select jsonb_agg(jsonb_build_object('schema',n.nspname,'relation',c.relname,'name',a.attname,'ordinal',a.attnum,
  'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'identity',a.attidentity,'generated',a.attgenerated,
  'default',pg_get_expr(d.adbin,d.adrelid))order by n.nspname,c.relname,a.attnum)
  from pg_attribute a join pg_class c on c.oid=a.attrelid join pg_namespace n on n.oid=c.relnamespace
  left join pg_attrdef d on d.adrelid=c.oid and d.adnum=a.attnum where a.attnum>0 and not a.attisdropped
  and n.nspname not like 'pg_%'and n.nspname<>'information_schema'and c.relkind in('r','p','S','v','m')),
 'functions',(select jsonb_agg(jsonb_build_object('schema',n.nspname,'name',p.proname,'arguments',pg_get_function_identity_arguments(p.oid),
  'owner',pg_get_userbyid(p.proowner),'definition',pg_get_functiondef(p.oid),'acl',
  (select jsonb_agg(jsonb_build_array(case when a.grantee=0 then 'PUBLIC'else pg_get_userbyid(a.grantee)end,
   pg_get_userbyid(a.grantor),a.privilege_type,a.is_grantable)order by a.grantee,a.grantor,a.privilege_type,a.is_grantable)
   from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner)))a))order by n.nspname,p.proname,pg_get_function_identity_arguments(p.oid))
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname not like 'pg_%'
  and n.nspname<>'information_schema'and p.prokind<>'a'),
 'constraints',(select jsonb_agg(jsonb_build_object('schema',n.nspname,'relation',c.relname,'name',x.conname,
  'definition',pg_get_constraintdef(x.oid,true),'validated',x.convalidated)order by n.nspname,c.relname,x.conname)
  from pg_constraint x join pg_class c on c.oid=x.conrelid join pg_namespace n on n.oid=c.relnamespace
  where n.nspname not like 'pg_%'and n.nspname<>'information_schema'),
 'indexes',(select jsonb_agg(jsonb_build_object('schema',n.nspname,'relation',c.relname,'name',i.relname,
  'definition',pg_get_indexdef(i.oid),'owner',pg_get_userbyid(i.relowner))order by n.nspname,c.relname,i.relname)from pg_index x join pg_class i on i.oid=x.indexrelid
  join pg_class c on c.oid=x.indrelid join pg_namespace n on n.oid=c.relnamespace
  where n.nspname not like 'pg_%'and n.nspname<>'information_schema'),
 'views',(select jsonb_agg(jsonb_build_object('schema',n.nspname,'name',c.relname,'definition',pg_get_viewdef(c.oid,true))order by n.nspname,c.relname)from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname not like 'pg_%'and n.nspname<>'information_schema'and c.relkind in('v','m')),
 'types',(select jsonb_agg(jsonb_build_object('schema',n.nspname,'name',t.typname,'kind',t.typtype,'owner',pg_get_userbyid(t.typowner),'base',format_type(t.typbasetype,t.typtypmod),'not_null',t.typnotnull,'default',t.typdefault,'enum',(select jsonb_agg(e.enumlabel order by e.enumsortorder)from pg_enum e where e.enumtypid=t.oid))order by n.nspname,t.typname)from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname not like 'pg_%'and n.nspname<>'information_schema'and t.typtype in('e','d')),
 'triggers',(select jsonb_agg(jsonb_build_object('schema',n.nspname,'relation',c.relname,'name',t.tgname,
  'definition',pg_get_triggerdef(t.oid,true),'enabled',t.tgenabled)order by n.nspname,c.relname,t.tgname)
  from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
  where not t.tgisinternal and n.nspname not like 'pg_%'and n.nspname<>'information_schema'),
 'policies',(select jsonb_agg(jsonb_build_object('schema',schemaname,'relation',tablename,'name',policyname,
  'permissive',permissive,'roles',roles,'command',cmd,'using',qual,'check',with_check)order by schemaname,tablename,policyname)from pg_policies),
 'default_acl',(select jsonb_agg(jsonb_build_object('owner',pg_get_userbyid(d.defaclrole),'schema',n.nspname,'kind',d.defaclobjtype,
  'acl',(select jsonb_agg(jsonb_build_array(case when a.grantee=0 then 'PUBLIC'else pg_get_userbyid(a.grantee)end,
  pg_get_userbyid(a.grantor),a.privilege_type,a.is_grantable)order by a.grantee,a.grantor,a.privilege_type,a.is_grantable)
  from aclexplode(d.defaclacl)a))order by pg_get_userbyid(d.defaclrole),n.nspname,d.defaclobjtype)
  from pg_default_acl d left join pg_namespace n on n.oid=d.defaclnamespace),
 'extensions',(select jsonb_agg(jsonb_build_array(e.extname,e.extversion,n.nspname,pg_get_userbyid(e.extowner))order by e.extname)
  from pg_extension e join pg_namespace n on n.oid=e.extnamespace),
 'roles',(select jsonb_agg(jsonb_build_array(rolname,rolsuper,rolinherit,rolcreaterole,rolcreatedb,rolcanlogin,rolreplication,rolbypassrls,rolconfig)
  order by rolname)from pg_roles),
 'database',(select jsonb_build_object('encoding',pg_encoding_to_char(encoding),'collate',datcollate,'ctype',datctype,
  'owner',pg_get_userbyid(datdba))from pg_database where datname=current_database())
);

-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(jsonb_build_array(n.nspname,c.relname,c.relkind)order by n.nspname,c.relname),'[]')from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname not like 'pg_%'and n.nspname<>'information_schema'and c.relkind in('r','p','S');
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "auth"."audit_log_entries" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "auth"."custom_oauth_providers" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "auth"."flow_state" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "auth"."identities" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "auth"."instances" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "auth"."mfa_amr_claims" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "auth"."mfa_challenges" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "auth"."mfa_factors" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "auth"."oauth_authorizations" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "auth"."oauth_client_states" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "auth"."oauth_clients" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "auth"."oauth_consents" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "auth"."one_time_tokens" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "auth"."refresh_tokens" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select jsonb_build_object('last_value',s.last_value,'is_called',s.is_called)from "auth"."refresh_tokens_id_seq" s;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "auth"."saml_providers" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "auth"."saml_relay_states" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "auth"."schema_migrations" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "auth"."sessions" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "auth"."sso_domains" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "auth"."sso_providers" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "auth"."users" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "auth"."webauthn_challenges" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "auth"."webauthn_credentials" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_admin_access"."email_approvals" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_admin_access"."operator_auth_policy" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_admin_access"."whatsapp_approvals" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_auth_security"."otp_phone_locks" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_automation"."operating_policy" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_automation"."policy_requests" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_gateway"."admin_requests" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_gateway"."devices" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_gateway"."dispatch_arms" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_gateway"."health_observations" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_gateway"."requests" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_gateway"."segment_callbacks" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."collection_balances" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."group_creation_requests" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."legacy_bank_scheduler_observations" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."legacy_bank_scheduler_retirements" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."legacy_bank_scheduler_verifications" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."member_account_claims" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."member_balances" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."member_momo_identities" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."member_receiving_assignments" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."member_records" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."momo_balance_snapshots" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."momo_journal_entries" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."momo_journal_lines" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."momo_reconciliation_exceptions" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."momo_reversal_requests" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."payer_identity_reconciliation" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."payment_provider_rejections" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."receipt_business_event_heads" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."receipt_business_events" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."receipt_monitor_acknowledgements" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."receipt_monitor_consumers" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."receipt_monitor_observed_events" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."receiving_assignment_requests" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."roster_batches" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."roster_import_commits" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."roster_import_editor_drafts" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."roster_import_extractions" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."roster_import_recovery_intents" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."roster_import_results" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."roster_import_revisions" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."roster_import_sources" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."roster_recovery_budget" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."roster_recovery_guard_inventory" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."roster_recovery_transfers" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."roster_resource_completions" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."roster_resource_policy" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."roster_resource_reservations" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."roster_source_verifications" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."sms_notification_attempts" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."sms_notification_claim_requests" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."sms_notification_confirmations" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."sms_notification_outbox" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."sms_operator_heartbeats" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."sms_receipt_member_consents" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_hybrid"."sms_receipt_policies" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_operator_audit"."shadow_events" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_ops"."exception_actions" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_ops"."exception_observations" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_ops"."exceptions" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_receipt_actions"."cancellations" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_receipt_actions"."revisions" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_security"."operational_metric_buckets" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_security"."otp_policy" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_security"."reconciliation_reviews" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_security"."runtime_control_events" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_security"."runtime_control_heads" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_security"."shadow_supervisor_lease" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_security"."shadow_supervisor_runs" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_security"."shadow_supervisor_samples" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_security"."signed_otp_evidence" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select jsonb_build_object('last_value',s.last_value,'is_called',s.is_called)from "collect_security"."signed_otp_evidence_id_seq" s;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_security"."signed_otp_requests" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_supervisor"."identities" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_supervisor"."owner_requests" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "collect_supervisor"."requests" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "cron"."job" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "cron"."job_run_details" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."account_request_reason_options" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."admin_navigation_items" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."admin_notes" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."admin_permissions" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."admin_queue_filter_options" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."admin_queue_signals" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."admin_queue_sla_policies" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."admin_queue_specs" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."admin_role_permissions" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."admin_roles" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."admin_sensitive_access_logs" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."admin_user_roles" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."app_realtime_events" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."audit_logs" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."bank_allocation_change_requests" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."bank_destination_change_requests" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."bank_evidence_events" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."bank_statement_imports" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."bank_statement_lines" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."bank_transaction_allocations" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."bank_transactions" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."bank_transfer_destinations" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."bank_transfer_intents" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."brand_entities" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."collection_category_subtypes" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."collection_invites" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."collection_members" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."collection_purpose_templates" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."collection_receivers" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."collection_reports" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."collection_share_secrets" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."collection_type_catalog" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."collection_type_country_rules" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."collections" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."daily_bank_closes" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."feature_flags" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."journal_entries" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."journal_lines" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."ledger_entries" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."member_obligations" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."mobile_account_deletion_requests" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."mobile_support_requests" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."moderation_flags" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."native_action_capabilities" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."notification_channels" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."notification_deliveries" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."notification_delivery_attempts" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."notification_device_tokens" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."notification_event_types" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."notification_events" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."notification_preferences" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."notification_template_versions" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."notification_templates" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."otp_rate_limits" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."parsed_payment_events" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."payment_allocations" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."payment_entrypoints" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."payment_evidence_links" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."payment_intents" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."payment_provider_confirmations" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."payments" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."policy_acceptance_events" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."policy_document_sections" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."policy_documents" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."profile_country_rules" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."profiles" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."provider_finality_requests" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."raw_payment_evidence" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."raw_payment_sms" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."receiver_mode_consents" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."reconciliation_exceptions" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."reconciliation_matches" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."reconciliation_runs" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."recurring_periods" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."support_channels" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "public"."system_settings" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "supabase_functions"."hooks" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select jsonb_build_object('last_value',s.last_value,'is_called',s.is_called)from "supabase_functions"."hooks_id_seq" s;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "supabase_functions"."migrations" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "supabase_migrations"."schema_migrations" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate "C"),'[]')from "vault"."secrets" t;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select to_jsonb(o)from collect_hybrid.sms_notification_outbox o where payment_id='99880000-0000-4000-8000-000000050002';
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select to_jsonb(o)from collect_hybrid.sms_notification_outbox o where id='d68c242b-504f-442e-b8dd-bb3da9831e00';
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;select to_jsonb(not exists(select 1 from collect_hybrid.momo_journal_entries e left join collect_hybrid.momo_journal_lines l on l.journal_entry_id=e.id group by e.id,e.amount_rwf having count(*)<>2 or sum(case when l.direction='debit'then l.amount_rwf else -l.amount_rwf end)<>0 or min(l.amount_rwf)<>e.amount_rwf or max(l.amount_rwf)<>e.amount_rwf));
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
begin;set local role authenticated;select set_config('request.jwt.claims','{"sub": "99710000-0000-4000-8000-000000000001", "session_id": "99710000-0000-4000-8000-000000010001", "role": "authenticated", "aal": "aal1"}',true);select public.admin_cancel_unstarted_receipt_v1('0ab08ad1-a1b8-4a4e-b9a6-d958c4d4d233','d68c242b-504f-442e-b8dd-bb3da9831e00',1,'operator_cancelled');commit;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
begin;set local role authenticated;select set_config('request.jwt.claims','{"sub": "99710000-0000-4000-8000-000000000001", "session_id": "99710000-0000-4000-8000-000000010001", "role": "authenticated", "aal": "aal1"}',true);select public.admin_configure_unattended_operating_policy_v1('ab549cda-68c3-4aab-86bd-3fb468d6f3a5',1,'Shadow',false,'operator_reviewed_configuration');;commit;
-- database collect_c34_restore_d46459070fb1 (local synthetic/schema-only)
begin;set local role authenticated;select set_config('request.jwt.claims','{"sub": "99710000-0000-4000-8000-000000000001", "session_id": "99710000-0000-4000-8000-000000010001", "role": "authenticated", "aal": "aal1"}',true);select public.admin_enroll_gateway_device_v1('384117e2-34be-4542-a90a-c569ca9dd1b5','e4b1472d-38c1-4022-8c91-12497d539279','MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEaxfR8uEsQkf4vOblY6RA8ncDfYEt6zOg9KE5RdiYwpZP40Li/hp/m47n60p8D54WK84zV2sxXs7LtkBoN79R9Q==','5cd252fb0ce8932436faf8ccd1040981b89ee4ad6b9fe9e2a2b7e71aacb27cd3','cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc');;commit;
-- database postgres (local synthetic/schema-only)
set timezone='UTC';set search_path=public,extensions,auth;drop database collect_c34_restore_d46459070fb1 with(force);
