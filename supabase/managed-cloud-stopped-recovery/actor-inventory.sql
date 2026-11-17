-- Read-only point-in-time actor inventory. It does not prove that an executor
-- stopped, that all code paths are known, or that a cutover is authorized.
-- PostgreSQL 17's pg_auth_members.set_option is required. Roles with expired
-- passwords can still have sessions or other authentication/issuance paths.
WITH RECURSIVE reachable(login_oid,role_oid) AS (
 SELECT oid,oid FROM pg_catalog.pg_roles WHERE rolcanlogin
 UNION
 SELECT r.login_oid,m.roleid FROM reachable r
 JOIN pg_catalog.pg_auth_members m ON m.member=r.role_oid
 WHERE m.set_option
), target AS (
 SELECT to_regprocedure('private.collect_fence_register(uuid,text,text)') AS register_fn,
  to_regprocedure('private.collect_fence_assert_work(uuid,bigint,text)') AS work_fn,
  to_regprocedure('private.collect_fence_close(uuid,bigint,text,text,text,integer,integer)') AS close_fn,
  to_regclass('private.collect_fence_admissions') AS admission_table,
  to_regclass('private.collect_fence_control') AS control_table,
  to_regnamespace('private') AS private_schema
), observed AS (
 SELECT l.oid AS login_oid,l.rolname AS login_name,l.rolvaliduntil,
  r.oid AS role_oid,r.rolsuper,r.rolcreaterole,r.rolbypassrls,
  CASE WHEN t.private_schema IS NULL THEN NULL ELSE has_schema_privilege(r.oid,t.private_schema,'USAGE') END AS private_usage,
  CASE WHEN t.private_schema IS NULL THEN NULL ELSE has_schema_privilege(r.oid,t.private_schema,'CREATE') END AS private_create,
  CASE WHEN t.register_fn IS NULL THEN NULL ELSE has_function_privilege(r.oid,t.register_fn,'EXECUTE') END AS register_exec,
  CASE WHEN t.work_fn IS NULL THEN NULL ELSE has_function_privilege(r.oid,t.work_fn,'EXECUTE') END AS work_exec,
  CASE WHEN t.close_fn IS NULL THEN NULL ELSE has_function_privilege(r.oid,t.close_fn,'EXECUTE') END AS close_exec,
  CASE WHEN t.admission_table IS NULL THEN NULL ELSE has_table_privilege(r.oid,t.admission_table,'SELECT') END AS admission_select,
  CASE WHEN t.admission_table IS NULL THEN NULL ELSE has_table_privilege(r.oid,t.admission_table,'UPDATE') END AS admission_update,
  EXISTS(SELECT 1 FROM pg_catalog.pg_auth_members a WHERE a.member=r.oid AND a.admin_option) AS has_role_admin_option,
  EXISTS(SELECT 1 FROM pg_catalog.pg_class c WHERE c.oid=t.control_table AND c.relowner=r.oid) AS owns_control
 FROM reachable x JOIN pg_catalog.pg_roles l ON l.oid=x.login_oid
 JOIN pg_catalog.pg_roles r ON r.oid=x.role_oid CROSS JOIN target t
), grouped AS (
 SELECT login_oid,login_name,rolvaliduntil,count(*) AS reachable_roles,
  bool_or(rolsuper) AS reachable_superuser,bool_or(rolcreaterole) AS reachable_createrole,
  bool_or(rolbypassrls) AS reachable_bypassrls,bool_or(has_role_admin_option) AS reachable_role_admin_option,
  bool_or(private_create) AS reachable_private_create,bool_or(owns_control) AS reachable_control_owner,
  bool_or(private_usage AND register_exec) AS reachable_direct_register,
  bool_or(private_usage AND work_exec) AS reachable_direct_work_assert,
  bool_or(private_usage AND close_exec) AS reachable_direct_close,
  bool_or(private_usage AND admission_select) AS reachable_admission_select_grant,
  bool_or(private_usage AND admission_update) AS reachable_admission_update_grant
 FROM observed GROUP BY login_oid,login_name,rolvaliduntil
), sessions AS (
 SELECT usesysid,count(*) AS client_sessions
 FROM pg_catalog.pg_stat_activity WHERE backend_type='client backend' GROUP BY usesysid
)
SELECT jsonb_build_object(
 'format','collect.managed-admission-actor-inventory.v1',
 'observed_at',statement_timestamp(),'database_name',current_database(),
 'session_user',session_user,'current_user',current_user,
 'postgres_major',current_setting('server_version_num')::integer/10000,
 'catalogue_targets_present',(SELECT register_fn IS NOT NULL AND work_fn IS NOT NULL AND close_fn IS NOT NULL
  AND admission_table IS NOT NULL AND control_table IS NOT NULL AND private_schema IS NOT NULL FROM target),
 'login_roles',coalesce((SELECT jsonb_agg(jsonb_build_object(
  'login_role',g.login_name,'reachable_role_count',g.reachable_roles,
  'password_valid_until',g.rolvaliduntil,
  'password_expired',CASE WHEN g.rolvaliduntil IS NULL THEN NULL ELSE g.rolvaliduntil<=statement_timestamp() END,
  'observed_client_sessions',coalesce(s.client_sessions,0),
  'reachable_superuser',g.reachable_superuser,'reachable_createrole',g.reachable_createrole,
  'reachable_bypassrls',g.reachable_bypassrls,'reachable_role_admin_option',g.reachable_role_admin_option,
  'reachable_private_create',g.reachable_private_create,'reachable_control_owner',g.reachable_control_owner,
  'reachable_direct_register',g.reachable_direct_register,'reachable_direct_work_assert',g.reachable_direct_work_assert,
  'reachable_direct_close',g.reachable_direct_close,'reachable_admission_select_grant',g.reachable_admission_select_grant,
  'reachable_admission_update_grant',g.reachable_admission_update_grant) ORDER BY g.login_name)
  FROM grouped g LEFT JOIN sessions s ON s.usesysid=g.login_oid),'[]'::jsonb),
 'project_identity_verified',false,'provider_issuance_closed',false,'executor_stopped_verified',false,
 'security_definer_paths_complete',false,'session_inventory_complete',false,'cutover_authorized',false,
 'limitations',jsonb_build_array('single statement snapshot; grants and sessions can change immediately',
  'temporary credentials or other authentication can reactivate a login; password expiry is not role expiry',
  'SET ROLE and inherited privilege observations do not enumerate security-definer or dynamic SQL call paths',
  'RLS, connection poolers, provider and external service actors need independent review',
  'client-session counts do not prove that prior workers or external effects have stopped')) AS inventory;
