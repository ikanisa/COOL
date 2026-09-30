require 'open3'
require 'json'
require 'digest'

# Exact task-local141 only. Every SQL operation either reads or rolls back.
# --source-only validates the immutable inputs/derived variant without Docker.
ROOT = File.expand_path('../..', __dir__)
PROJECT = 'collect_fin_concurrency_qa_20260929'
CONTAINER = "supabase_db_#{PROJECT}"
APPLICATION = 'collect_reconciliation_post141_rollback'
PSQL = ['docker', 'exec', '-i', CONTAINER, 'psql', '-XqAt',
        '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1',
        '-v', 'VERBOSITY=verbose'].freeze
INPUTS = {
  'deploy/hardening/reconciliation_approval_v2.sql' => '0371a10c99d28fa7cd24fbc03421a83c84914b55ae2e621f61ddec0e25a1e552',
  'scripts/tests/reconciliation_workflow_uat.sql' => '40e4231e4db13a0ed21b76ef7ba3944b9863b925af9ced4c4bb323f9c7c2f002',
  'supabase/migrations/20260929180000_notification_registration_sessions.sql' => 'b8335e9b70339a1a67d50db245147b483610a3a4c76f223bd7a17cfc4876a2bb'
}.freeze
SUPERSEDED = 'reconciliation_staged_installer_superseded_use_numbered_migrations'
SCHEMAS = "'public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations'"

def replace_once(source, old, replacement)
  raise "Expected exactly one source anchor: #{old}" unless source.scan(old).length == 1
  source.sub(old, replacement)
end

def fixture_guard
  <<~SQL
    do $fixture$ begin
      if current_database()<>'postgres' or current_user<>'postgres'
        or current_setting('collect.reconciliation_qa',true) is distinct from 'isolated_clone'
        or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
        or (select count(*) from supabase_migrations.schema_migrations)<>141
        or (select max(version) from supabase_migrations.schema_migrations)<>'20260929180000'
        or to_regprocedure('public._lock_notification_session_gate()') is null
        or exists(select 1 from public.notification_device_tokens)
        or exists(select 1 from public.notification_deliveries)
        or exists(select 1 from pg_stat_activity where pid<>pg_backend_pid()
          and backend_type='client backend' and state is distinct from 'idle') then
        raise exception 'Exact quiet isolated141 owner fixture with inactive providers required'; end if;
      if exists(select 1 from auth.users where id::text like '99900000-%'
          or phone in ('250788909001','250788909002','250788909003','250788909099'))
        or exists(select 1 from auth.sessions where id::text like '99900000-%' or user_id::text like '99900000-%')
        or exists(select 1 from public.profiles where id::text like '99900000-%')
        or exists(select 1 from collect_hybrid.member_records where id::text like '99900000-%')
        or exists(select 1 from public.collections where id::text like '99900000-%' or slug='reconciliation-140-synthetic')
        or exists(select 1 from public.payments where id::text like '99900000-%' or transaction_id='RECONCILE1401234')
        or exists(select 1 from collect_security.reconciliation_reviews where id::text like '99900000-%') then
        raise exception 'Original140 UAT synthetic identity namespace must be unused'; end if;
      if has_function_privilege('service_role','public.process_provider_finality_event(uuid,text,text,uuid,text,text,text,text,bigint,timestamptz,text,text,text)','EXECUTE')
        or has_function_privilege('service_role','public.confirm_provider_payment(uuid,text,text,text,text,bigint,timestamptz,text)','EXECUTE')
        or has_function_privilege('service_role','public.reject_provider_payment(uuid,text,text)','EXECUTE')
        or has_function_privilege('authenticated','public.finalize_approved_reconciliation_v2(uuid)','EXECUTE')
        or has_function_privilege('anon','public.finalize_approved_reconciliation_v2(uuid)','EXECUTE')
        or not has_function_privilege('service_role','public.finalize_approved_reconciliation_v2(uuid)','EXECUTE')
        or has_schema_privilege('service_role','collect_security','USAGE')
        or has_table_privilege('authenticated','collect_security.reconciliation_reviews','INSERT,UPDATE,DELETE') then
        raise exception 'Governed financial finalization grant boundary changed'; end if;
      if position('perform public._lock_notification_session_gate();' in
          pg_get_functiondef('collect_security.require_reconciliation_actor()'::regprocedure))=0
        or position('perform public._lock_notification_session_gate();' in
          pg_get_functiondef('public.finalize_approved_reconciliation_v2(uuid)'::regprocedure))=0 then
        raise exception 'Integrated141 reconciliation gate wrappers are missing'; end if;
    end $fixture$;
  SQL
end

def preamble
  "set application_name='#{APPLICATION}'; set timezone='UTC'; " \
    "set statement_timeout='30s'; set lock_timeout='5s'; " \
    "set collect.reconciliation_qa='isolated_clone';\n"
end

def run_sql(sql)
  Open3.capture3(*PSQL, stdin_data: preamble + sql)
end

def must_run(sql)
  output, error, status = run_sql(sql)
  raise "SQL failed (#{status.exitstatus}): #{error.empty? ? output : error}" unless status.success?
  [output, error]
end

# Hash every ordinary/partitioned table in the app/private/Auth/realtime/registry
# schemas, plus catalog definitions and grants. Raw row values are never emitted.
# Sequence counters are deliberately excluded: nextval is not transactional.
def snapshot
  output, = must_run(<<~SQL)
    begin isolation level repeatable read;
    #{fixture_guard}
    do $snapshot$ declare r record; row_count bigint; row_digest text; bodies jsonb:='{}'; begin
      for r in select format('%I.%I',n.nspname,c.relname) as relation
        from pg_class c join pg_namespace n on n.oid=c.relnamespace
        where n.nspname in (#{SCHEMAS}) and c.relkind in ('r','p') order by 1 loop
        execute format('select count(*),encode(extensions.digest(coalesce(string_agg(to_jsonb(t)::text,E''\\n'' order by to_jsonb(t)::text),''''),''sha256''),''hex'') from %s t',r.relation)
          into row_count,row_digest;
        bodies:=bodies||jsonb_build_object(r.relation,jsonb_build_object('rows',row_count,'sha256',row_digest));
      end loop;
      perform set_config('collect.post141_snapshot',bodies::text,true);
    end $snapshot$;
    with controls(family,body) as (
      select 'schema',jsonb_build_object('name',n.nspname,'acl',n.nspacl,'owner',n.nspowner)
        from pg_namespace n where n.nspname in (#{SCHEMAS})
      union all select 'relation',jsonb_build_object('name',c.oid::regclass::text,'kind',c.relkind,
        'acl',c.relacl,'owner',c.relowner,'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity)
        from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in (#{SCHEMAS})
      union all select 'routine',jsonb_build_object('name',p.oid::regprocedure::text,
        'acl',p.proacl,'owner',p.proowner,'definition',pg_get_functiondef(p.oid))
        from pg_proc p join pg_namespace n on n.oid=p.pronamespace
        where n.nspname in (#{SCHEMAS}) and p.prokind in ('f','p')
      union all select 'trigger',jsonb_build_object('table',t.tgrelid::regclass::text,'name',t.tgname,
        'enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid)) from pg_trigger t
        join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in (#{SCHEMAS})
      union all select 'column',jsonb_build_object('table',a.attrelid::regclass::text,'name',a.attname,
        'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'acl',a.attacl,
        'default',pg_get_expr(d.adbin,d.adrelid)) from pg_attribute a
        join pg_class c on c.oid=a.attrelid join pg_namespace n on n.oid=c.relnamespace
        left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
        where n.nspname in (#{SCHEMAS}) and a.attnum>0 and not a.attisdropped
      union all select 'constraint',jsonb_build_object('table',c.conrelid::regclass::text,'name',c.conname,
        'definition',pg_get_constraintdef(c.oid)) from pg_constraint c
        join pg_namespace n on n.oid=c.connamespace where n.nspname in (#{SCHEMAS})
      union all select 'index',jsonb_build_object('table',i.indrelid::regclass::text,'definition',pg_get_indexdef(i.indexrelid))
        from pg_index i join pg_class c on c.oid=i.indrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in (#{SCHEMAS})
      union all select 'policy',jsonb_build_object('table',p.polrelid::regclass::text,'name',p.polname,
        'roles',p.polroles,'command',p.polcmd,'permissive',p.polpermissive,
        'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid))
        from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in (#{SCHEMAS})
    ) select jsonb_build_object('tables',current_setting('collect.post141_snapshot')::jsonb,
      'controls_sha256',encode(extensions.digest(coalesce(string_agg(family||':'||body::text,E'\n' order by family,body::text),''),'sha256'),'hex')) from controls;
    rollback;
  SQL
  JSON.parse(output.strip)
end

raise 'Use no arguments or --source-only' unless ARGV.empty? || ARGV == ['--source-only']
sources = INPUTS.to_h do |path, expected|
  source = File.read(File.join(ROOT, path))
  raise "Frozen input changed: #{path}" unless Digest::SHA256.hexdigest(source) == expected
  [path, source]
end
staged = sources.fetch(INPUTS.keys[0])
original = sources.fetch(INPUTS.keys[1])
expected_guard = <<~SQL
  begin;
  -- Historical staged140 installer: never overwrite the gate-aware141 routines.
  -- Serialize with141 deployment so this check cannot race its installation.
  select pg_advisory_xact_lock(193517,141);
  do $$ declare newest_version text; begin
    if to_regclass('supabase_migrations.schema_migrations') is not null then
      execute 'select max(version) from supabase_migrations.schema_migrations' into newest_version;
    end if;
    if to_regprocedure('public._lock_notification_session_gate()') is not null
       or coalesce(newest_version,'') >= '20260929180000' then
      raise exception '#{SUPERSEDED}' using errcode='55000';
    end if;
  end $$;
SQL
raise 'Staged refusal must precede every DDL/DML statement' unless staged.start_with?(expected_guard)
raise 'Staged transaction shape changed' unless staged.scan(/^commit;\s*$/i).length == 1 && staged.match?(/\ncommit;\s*\z/i)
rollback_staged = staged.sub(/\ncommit;\s*\z/i, "\nrollback;\n")
raise 'Original workflow must end in rollback with no commit' unless original.match?(/\nrollback;\s*\z/i) && !original.match?(/^commit;/i)
integrated = replace_once(original,
  '(select count(*) from supabase_migrations.schema_migrations)<>140',
  '(select count(*) from supabase_migrations.schema_migrations)<>141')
integrated = replace_once(integrated,
  "(select max(version) from supabase_migrations.schema_migrations)<>'20260929170000'",
  "(select max(version) from supabase_migrations.schema_migrations)<>'20260929180000'")
integrated = replace_once(integrated,
  'Verified isolated 140-migration fixture and unused synthetic identities required',
  'Verified isolated integrated141 fixture for original140 workflow and unused synthetic identities required')
integrated = replace_once(integrated, "set local lock_timeout='5s';", "set local lock_timeout='5s';\n#{fixture_guard}")
integrated = replace_once(integrated, 'RECONCILIATION_WORKFLOW_UAT_PASS', 'RECONCILIATION_WORKFLOW_INTEGRATED141_UAT_PASS')
integrated = "-- Explicit integrated141 variant; immutable original140 SHA256 #{INPUTS.values[1]}.\n" + integrated
source_evidence = {
  source_sha256: INPUTS,
  harness_sha256: Digest::SHA256.file(__FILE__).hexdigest,
  rollback_staged_sha256: Digest::SHA256.hexdigest(rollback_staged),
  integrated_workflow_sha256: Digest::SHA256.hexdigest(integrated),
  integrated_variant_changes: ['141-only count/version/message guard', 'additional isolated141/provider/ACL/identity guards',
                               'distinct integrated141 pass marker and provenance comment'],
  original140_script_modified: false,
  staged_refusal_precedes_mutations: true
}
if ARGV == ['--source-only']
  puts JSON.pretty_generate(source_evidence.merge(status: 'source_contracts_passed', db_calls: 0,
    sql_execution_verified: false, expected_workflow_assertions: 58))
  exit
end

raise 'Set COLLECT_RECONCILIATION_QA=isolated_clone' unless ENV['COLLECT_RECONCILIATION_QA'] == 'isolated_clone'
inspect_out, inspect_error, inspect_status = Open3.capture3('docker', 'inspect', CONTAINER)
raise inspect_error unless inspect_status.success?
container = JSON.parse(inspect_out).fetch(0)
labels = container.fetch('Config').fetch('Labels')
bindings = container.fetch('HostConfig').fetch('PortBindings').fetch('5432/tcp')
config = File.read(File.join(ROOT, '.cache/financial-concurrency-20260929/supabase/config.toml'))
db_config = config[/^\[db\]\s*\n(.*?)(?=^\[|\z)/m, 1]
raise 'Task-local fixture provenance mismatch' unless container.dig('State','Running') == true &&
  labels['com.supabase.cli.project'] == PROJECT && labels['com.docker.compose.project'] == PROJECT &&
  config.match?(/^project_id = "#{PROJECT}"$/) && db_config&.match?(/^port = 55722$/) &&
  bindings.is_a?(Array) && !bindings.empty? && bindings.all? { |binding| binding['HostPort'] == '55722' }

baseline = snapshot
output, error, status = run_sql(fixture_guard + rollback_staged)
after_refusal = snapshot
raise 'Staged attempt changed data, routine definitions or ACLs' unless after_refusal == baseline
raise "Expected exact55000 superseded failure, received #{status.exitstatus}: #{error}" unless
  status.exitstatus == 3 && error.match?(/ERROR:\s+55000:\s+#{SUPERSEDED}(?:\r?\n|\z)/)

workflow_output, workflow_error, workflow_status = run_sql(integrated)
after_workflow = snapshot
raise 'Workflow rollback changed data, routine definitions or ACLs' unless after_workflow == baseline
raise "Integrated141 workflow failed: #{workflow_error}" unless workflow_status.success?
marker = workflow_output.lines.map(&:strip).grep(/^RECONCILIATION_WORKFLOW_INTEGRATED141_UAT_PASS\|/)
raise "Expected exactly58 unchanged workflow assertions: #{marker.inspect}" unless
  marker == ['RECONCILIATION_WORKFLOW_INTEGRATED141_UAT_PASS|58']
raise 'Original dated140 source changed during execution' unless
  Digest::SHA256.file(File.join(ROOT, INPUTS.keys[1])).hexdigest == INPUTS.values[1]

puts JSON.pretty_generate(source_evidence.merge(
  status: 'pass', fixture: PROJECT, migration_count: 141, last_migration: '20260929180000',
  labels_and_port_verified: true, all_sql_rolled_back: true,
  staged_installer: { exit_code: status.exitstatus, expected_sqlstate: '55000', message: SUPERSEDED,
    data_and_controls_unchanged: true, stdout: output, stderr: error },
  integrated_workflow: { exit_code: workflow_status.exitstatus, assertions: 58,
    original140_assertions_preserved: true, data_and_controls_unchanged: true,
    stdout: workflow_output, stderr: workflow_error },
  baseline: baseline, after_refusal: after_refusal, after_workflow: after_workflow,
  sequence_counters_restored: false,
  sequence_note: 'Rollback does not restore nextval counters; no setval or trigger-disable cleanup is used.',
  hosted_auth_requests: 0, provider_calls: 0, deployments: 0))
