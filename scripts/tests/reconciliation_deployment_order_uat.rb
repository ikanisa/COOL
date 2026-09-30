require 'open3'
require 'json'
require 'digest'

# Isolated full-schema compatibility proof. Both installation orders execute
# inside a rollback transaction; source is never replaced in a hosted project.
ROOT = File.expand_path('../..', __dir__)
PROJECT = 'collect_fin_concurrency_qa_20260929'
CONTAINER = "supabase_db_#{PROJECT}"
PSQL = ['docker', 'exec', '-i', CONTAINER, 'psql', '-XqAt', '-U', 'postgres',
        '-d', 'postgres', '-v', 'ON_ERROR_STOP=1'].freeze
NUMBERED = File.join(ROOT, 'supabase/migrations/20260929170000_governed_reconciliation_workflow.sql')
STAGED = File.join(ROOT, 'deploy/hardening/reconciliation_approval_v2.sql')
FINANCIAL = File.read(File.join(ROOT, 'scripts/tests/financial_concurrency_snapshot.sql'))

def command(args, input = nil)
  output, error, status = Open3.capture3(*args, stdin_data: input.to_s)
  raise(error.empty? ? output : error) unless status.success?
  [output, error]
end

labels = JSON.parse(command(['docker', 'inspect', CONTAINER, '--format', '{{json .Config.Labels}}'])[0])
ports = JSON.parse(command(['docker', 'inspect', CONTAINER, '--format', '{{json .HostConfig.PortBindings}}'])[0])
config = File.read(File.join(ROOT, '.cache/financial-concurrency-20260929/supabase/config.toml'))
raise 'Unverified fixture' unless labels['com.supabase.cli.project'] == PROJECT &&
  labels['com.docker.compose.project'] == PROJECT && ports.dig('5432/tcp', 0, 'HostPort') == '55722' &&
  config.include?("project_id = \"#{PROJECT}\"") && config.include?('port = 55722')
raise 'Exact140 fixture required' unless command(PSQL, 'select count(*)::text || chr(58) || max(version) from supabase_migrations.schema_migrations;')[0].strip == '140:20260929170000'

numbered = File.read(NUMBERED)
legacy_table = numbered[/create table if not exists collect_security\.reconciliation_reviews \(.*?\n\);/m]
raise 'Expected predecessor-compatible table declaration missing' unless legacy_table && !legacy_table.include?('session_id')
def in_transaction_body(source)
  raise 'Expected explicit source transaction' unless source.match?(/\Abegin;\s*/i) && source.match?(/commit;\s*\z/i)
  source.sub(/\Abegin;\s*/i, '').sub(/commit;\s*\z/i, '')
end
sources = { numbered: in_transaction_body(numbered), staged: in_transaction_body(File.read(STAGED)) }
baseline = JSON.parse(command(PSQL, FINANCIAL)[0])

prepare = <<~SQL
  begin;
  set local statement_timeout='30s';
  set local lock_timeout='5s';
  do $$ begin
    if current_setting('collect.reconciliation_qa',true) is distinct from 'isolated_clone'
      or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
      or (select count(*) from supabase_migrations.schema_migrations)<>140
      or (select max(version) from supabase_migrations.schema_migrations)<>'20260929170000'
      or exists(select 1 from collect_security.reconciliation_reviews)
      or (select count(*) from public.payments where transaction_id='RACE2500')<>1 then
      raise exception 'Guarded empty140 reviews and synthetic RACE2500 required'; end if;
  end $$;
  create temporary table retained_legacy_review(body jsonb not null);
  drop table collect_security.reconciliation_reviews cascade;
  #{legacy_table}
  alter table collect_security.reconciliation_reviews add unique(payment_id,evidence_sha256,source_reference);
  insert into collect_security.reconciliation_reviews(id,payment_id,payment_fingerprint,evidence_sha256,
    source_reference,occurred_at,proposal_reason,proposed_by,proposed_at,approved_by,approved_at,approval_reason)
  select '99840000-0000-4000-8000-000000000041',p.id,
    collect_security.reconciliation_fingerprint(p),repeat('b',64),'SYNTHETIC-LEGACY-ORDER-140',
    '2026-09-28T12:00:00Z','Synthetic preserved legacy statement',p.contributor_user_id,
    clock_timestamp()-interval '1 hour',p.receiver_user_id,clock_timestamp()-interval '5 minutes',
    'Synthetic preserved legacy approval' from public.payments p where p.transaction_id='RACE2500';
  insert into retained_legacy_review select to_jsonb(r) from collect_security.reconciliation_reviews r;
SQL

verify = <<~SQL
  do $$ declare r collect_security.reconciliation_reviews; begin
    select * into strict r from collect_security.reconciliation_reviews
      where id='99840000-0000-4000-8000-000000000041';
    if (to_jsonb(r)-'proposed_session_id'-'approved_session_id') is distinct from
      (select body from retained_legacy_review) or r.proposed_session_id is not null or r.approved_session_id is not null then
      raise exception 'Legacy review bytes changed or session evidence fabricated'; end if;
    if exists(select 1 from pg_constraint where conrelid='collect_security.reconciliation_reviews'::regclass
      and contype='u' and pg_get_constraintdef(oid)='UNIQUE (payment_id, evidence_sha256, source_reference)') then
      raise exception 'Expired-evidence uniqueness not removed'; end if;
    if has_function_privilege('service_role','public.process_provider_finality_event(uuid,text,text,uuid,text,text,text,text,bigint,timestamptz,text,text,text)','EXECUTE')
      or has_function_privilege('service_role','public.confirm_provider_payment(uuid,text,text,text,text,bigint,timestamptz,text)','EXECUTE')
      or has_function_privilege('service_role','public.reject_provider_payment(uuid,text,text)','EXECUTE')
      or has_function_privilege('authenticated','public.finalize_approved_reconciliation_v2(uuid)','EXECUTE')
      or has_function_privilege('anon','public.finalize_approved_reconciliation_v2(uuid)','EXECUTE')
      or not has_function_privilege('service_role','public.finalize_approved_reconciliation_v2(uuid)','EXECUTE')
      or has_schema_privilege('service_role','collect_security','USAGE')
      or has_table_privilege('authenticated','collect_security.reconciliation_reviews','UPDATE') then
      raise exception 'Reconciliation bypass grant reopened'; end if;
    begin
      update collect_security.reconciliation_reviews set proposal_reason='Changed legacy provenance'
        where id=r.id;
      raise exception 'Legacy immutable evidence writable';
    exception when sqlstate '55000' then null; end;
  end $$;
SQL

legacy_denial = <<~SQL
  set local role service_role;
  select set_config('request.jwt.claims','{"role":"service_role"}',true);
  do $$ declare refused boolean:=false; begin
    begin perform public.finalize_approved_reconciliation_v2('99840000-0000-4000-8000-000000000041');
    exception when sqlstate '22023' then
      if sqlerrm<>'reconciliation_approved_evidence_required' then raise; end if;
      refused:=true;
    end;
    if not refused then raise exception 'Legacy review finalized without actual sessions'; end if;
  end $$;
  reset role;
SQL

results = []
[['staged', 'numbered'], ['numbered', 'staged']].each do |order|
  body = "set collect.reconciliation_qa='isolated_clone';\n" + prepare
  order.each do |name|
    body += sources.fetch(name.to_sym) + "\n" + verify
  end
  body += legacy_denial + FINANCIAL + "\nrollback;\n"
  output, error = command(PSQL, body)
  snapshot_line = output.lines.find { |line| line.include?('"financial_sha256"') }
  raise 'Financial snapshot missing' unless snapshot_line
  raise 'Financial/evidence rows changed' unless JSON.parse(snapshot_line) == baseline
  raise 'Rollback did not restore empty current review table' unless
    command(PSQL, 'select count(*) from collect_security.reconciliation_reviews;')[0].strip == '0'
  raise 'Rollback changed financial baseline' unless JSON.parse(command(PSQL, FINANCIAL)[0]) == baseline
  results << { order: order, status: 'pass', legacy_review_bytes_preserved: true,
               no_session_backfill: true, immutable_evidence: true,
               direct_finality_grants_denied: true, legacy_finalization_denied: true,
               financial_evidence_unchanged: true, rolled_back: true,
               warnings: error.lines.map(&:strip).reject(&:empty?) }
end
puts JSON.pretty_generate({ status: 'pass', fixture: PROJECT, migration_count: 140,
  numbered_sha256: Digest::SHA256.file(NUMBERED).hexdigest,
  staged_sha256: Digest::SHA256.file(STAGED).hexdigest,
  scope: 'synthetic predecessor-shaped review and actual source installation orders under rollback',
  provider_calls: false, results: results })
