require 'minitest/autorun'
require 'digest'
require 'json'

# Source contract assertions only: PostgreSQL execution is a separate gate.
class LegacyBankSchedulerRetirementSourceTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  SQL = File.read(File.join(ROOT, 'supabase/migrations/20260930110000_retire_legacy_bank_scheduler.sql'))
  UAT = File.read(File.join(ROOT, 'scripts/tests/legacy_bank_scheduler_retirement_uat.sql'))
  LEGACY = File.read(File.join(ROOT, 'supabase/migrations/20260820162240_bank_transfer_only_financial_control_plane.sql'))
  COMMAND = "select public.run_daily_bank_reconciliation(current_date, 'scheduled daily reconciliation');"

  def test_exact_command_is_bound_to_original_migration_and_saved_hosted_metadata
    assert_includes LEGACY, "$cron$#{COMMAND}$cron$"
    assert_includes SQL, "$command$#{COMMAND}$command$"
    assert_includes SQL, Digest::SHA256.hexdigest(COMMAND)
    snapshot = JSON.parse(File.read(File.join(ROOT, 'docs/release/hosted-readback-2026-09-30/catalog-readback.json')))
    jobs = snapshot.fetch('cron_jobs').select { |j| j.fetch('name') == 'collect-daily-bank-reconciliation' }
    assert_equal 1, jobs.length
    assert_equal Digest::MD5.hexdigest(COMMAND), jobs.first.fetch('command_md5')
    assert_equal '30 21 * * *', jobs.first.fetch('schedule')
  end

  def test_only_disables_jobs_without_deleting_history_or_financial_data
    executable = SQL.lines.reject { |line| line.lstrip.start_with?('--') }.join
    assert_equal 1, executable.scan(/cron\.alter_job\(candidate.jobid, active := false\)/).length
    refute_match(/cron\.(?:un)?schedule\(|delete from|truncate table|drop table|update (?:public|cron)\./i, executable)
    refute_match(/(?:insert into|update|delete from) public\./i, executable)
    assert_includes SQL, "where jobname = 'collect-daily-bank-reconciliation' order by jobid"
  end

  def test_unknown_identity_and_all_routing_fields_fail_before_any_disable
    %w[command schedule username database nodename nodeport].each { |name| assert_includes SQL, "j.#{name}" }
    assert_includes SQL, "j.username not in ('postgres', 'supabase_admin')"
    assert_includes SQL, 'j.database is distinct from current_database()'
    assert_operator SQL.index("raise exception 'bank_scheduler_identity_review_required'"), :<, SQL.index('perform cron.alter_job')
    assert_includes SQL, 'lock table cron.job in share row exclusive mode'
    assert_operator SQL.index('lock table cron.job in share row exclusive mode'), :<, SQL.index('create table if not exists')
    assert_includes SQL, "set_config('row_security', 'off', true)"
  end

  def test_paused_and_drained_scheduler_required_without_global_configuration_changes
    assert_includes SQL, "current_setting('cron.launch_active_jobs', true) is distinct from 'off'"
    assert_includes SQL, "raise exception 'bank_scheduler_drain_required'"
    refute_match(/set_config\('cron\.|alter system|pg_cancel_backend|pg_terminate_backend/i, SQL)
    assert_operator SQL.index("raise exception 'bank_scheduler_drain_required'"), :<, SQL.index('perform cron.alter_job')
  end

  def test_private_bounded_audit_has_no_raw_command_or_client_access
    definition = SQL[/create table if not exists.*?\n\);/m]
    refute_nil definition
    assert_includes definition, 'command_sha256 text not null'
    refute_match(/^\s+(?:command|payload|credentials|metadata|token|secret)\s/i, definition)
    assert_includes definition, 'unique (job_owner, database_name)'
    assert_includes definition, "job_owner in ('postgres', 'supabase_admin')"
    assert_includes definition, 'database_name = current_database()'
    assert_includes SQL, 'enable row level security'
    assert_equal 3, SQL.scan(/revoke all .*? from public, anon, authenticated, service_role;/).length
    executable = SQL.lines.reject { |line| line.lstrip.start_with?('--') }.join
    refute_match(/^grant |^create policy |security definer/i, executable)
  end

  def test_update_delete_and_truncate_are_immutable
    assert_includes SQL, 'before update or delete on collect_hybrid.legacy_bank_scheduler_retirements'
    assert_includes SQL, 'before truncate on collect_hybrid.legacy_bank_scheduler_retirements'
    assert_includes SQL, "raise exception 'bank_scheduler_retirement_immutable'"
  end

  def test_replay_validates_existing_receipt_before_no_op_and_fails_on_reactivation
    assert_includes SQL, 'j.active is distinct from false'
    assert_includes SQL, 'left join cron.job j on j.jobid = r.job_id'
    assert_includes SQL, "raise exception 'bank_scheduler_retirement_drift'"
    assert_operator SQL.index("raise exception 'bank_scheduler_retirement_drift'"), :<, SQL.index('already_retired := already_retired + 1')
    assert_includes SQL, "'active_jobs', 0"
    refute_match(/on conflict.*do update/i, SQL)
  end

  def test_rollback_uat_is_exact143_isolated_and_cannot_launch_jobs
    assert_includes UAT, "current_setting('collect.legacy_bank_scheduler_qa', true) is distinct from 'isolated_clone'"
    assert_includes UAT, "current_setting('cron.launch_active_jobs', true) is distinct from 'off'"
    assert_includes UAT, "current_setting('pg_net.batch_size', true) is distinct from '0'"
    assert_includes UAT, 'schema_migrations) <> 143'
    assert_includes UAT, "<> '20260930110000'"
    assert_match(/\nrollback;\s*\z/, UAT)
    refute_match(/^commit;|disable trigger|setval\(|cron\.schedule\(/i, UAT)
  end

  def test_uat_covers_live_roles_drift_history_and_every_business_table
    %w[anon authenticated service_role].each { |role| assert_includes UAT, "set local role #{role};" }
    %w[identity_review_required retirement_drift drain_required].each { |name| assert_includes UAT, "bank_scheduler_#{name}" }
    assert_includes UAT, "n.nspname in ('public', 'collect_hybrid')"
    assert_includes UAT, 'every business and historical financial table preserves all row hashes'
    assert_includes UAT, 'every original run-history row remains unchanged'
    assert_includes UAT, 'every original job row remains unchanged'
    assert_includes UAT, 'review failures never partly retire another valid candidate'
  end
end
