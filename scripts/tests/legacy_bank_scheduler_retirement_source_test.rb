require 'minitest/autorun'
require 'digest'
require 'json'

# These are regression checks for high-impact installer invariants, not SQL
# execution proof. Root must execute normal-owner UAT and blocking races.
class LegacyBankSchedulerRetirementSourceTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  SQL = File.read(File.join(ROOT, 'supabase/migrations/20260930110000_retire_legacy_bank_scheduler.sql'))
  EXECUTABLE = SQL.lines.reject { |line| line.lstrip.start_with?('--') }.join
  UAT = File.read(File.join(ROOT, 'scripts/tests/legacy_bank_scheduler_retirement_uat.sql'))
  COMMAND = "select public.run_daily_bank_reconciliation(current_date, 'scheduled daily reconciliation');"

  def test_normal_owner_uses_only_owner_api_without_privilege_workarounds
    assert_match(/\Abegin isolation level serializable;/, SQL)
    assert_includes SQL, "current_setting('transaction_isolation') <> 'serializable'"
    assert_includes SQL, "schedule := '30 21 * * *'"
    assert_includes SQL, 'active := false'
    refute_match(/lock table cron\.|(?:insert into|update|delete from|truncate) cron\.|cron\.(?:un)?schedule\(|alter system|pg_cancel_backend|pg_terminate_backend|^grant |security definer/i, EXECUTABLE)
    refute_match(/set_config\('cron\.|set (?:local )?cron\./i, EXECUTABLE)
    refute_match(/(?:select|perform) public\.run_daily_bank_reconciliation\(/i, EXECUTABLE.gsub("$command$#{COMMAND}$command$", 'BOUND_COMMAND'))
  end

  def test_identity_binds_original_command_and_every_routing_field
    original = File.read(File.join(ROOT, 'supabase/migrations/20260820162240_bank_transfer_only_financial_control_plane.sql'))
    assert_includes original, "$cron$#{COMMAND}$cron$"
    assert_includes SQL, "$command$#{COMMAND}$command$"
    assert_includes SQL, Digest::SHA256.hexdigest(COMMAND)
    %w[command schedule username database nodename nodeport].each { |field| assert_includes SQL, "candidate.#{field} is distinct from" }
    assert_includes SQL, 'candidate.username is distinct from current_user::text'
    assert_includes SQL, "where jobname = 'collect-daily-bank-reconciliation') <> 1"
    assert_includes SQL, "set_config('row_security', 'off', true)"
  end

  def test_pause_never_claims_verified_completion_and_has_bounded_private_storage
    ending = SQL[SQL.rindex('-- Installing 143')..]
    assert_includes ending, 'select collect_hybrid.retire_legacy_bank_scheduler();'
    refute_includes ending, 'select collect_hybrid.verify_legacy_bank_scheduler_retirement();'
    assert_includes SQL, "state = 'paused_pending_verification'"
    assert_includes SQL, "retirement_version text not null unique"
    assert_equal 3, SQL.scan(/enable row level security;/).length
    assert_equal 5, SQL.scan(/revoke all on (?:function|collect_hybrid\.)/).length
    refute_match(/^\s+(?:command|payload|credentials|token|secret|return_message)\s/i, SQL)
    assert_includes SQL, 'before update or delete'
    assert_includes SQL, 'before truncate'
  end

  def test_postcommit_observation_prevents_counting_uncommitted_time
    assert_includes SQL, 'receipt.paused_xid = pg_catalog.txid_current()'
    assert_includes SQL, 'observation.observation_xid = pg_catalog.txid_current()'
    assert_includes SQL, "if elapsed < 30 then raise exception 'bank_scheduler_observation_interval_required'"
    assert_includes SQL, 'observation_seconds numeric not null check (observation_seconds >= 30)'
    assert_includes SQL, "'state', 'awaiting_observation_interval'"
    assert_includes SQL, 'observation.readback_sha256'
    assert_includes SQL, "encode(extensions.digest(readback::text, 'sha256'), 'hex')"
  end

  def test_both_observations_recheck_identity_history_launcher_and_quiescence
    %w[inactive_metadata_sha256 history_rows history_sha256 cron_timezone launcher_pid launcher_started_at].each do |field|
      assert_includes SQL, "receipt.#{field} is distinct from"
    end
    assert_includes SQL, "backend_type = 'pg_cron launcher'"
    assert_includes SQL, "current_setting('cron.log_run', true) is distinct from 'on'"
    assert_includes SQL, "time '21:25:00'"
    assert_includes SQL, "time '21:35:00'"
    assert_includes SQL, "observed - interval '5 minutes'"
    assert_includes SQL, 'nonterminal <> 0 or live_commands <> 0'
    assert_includes SQL, "d.status not in ('succeeded', 'failed')"
    refute_includes EXECUTABLE, "current_setting('cron.launch_active_jobs', true)"
  end

  def test_uat_uses_actual_normal_owner_apis_and_rolls_back_everything
    assert_includes UAT, "current_user <> 'postgres'"
    assert_includes UAT, "(select rolsuper from pg_roles where rolname = current_user)"
    %w[INSERT UPDATE DELETE MAINTAIN].each { |right| assert_includes UAT, "'cron.job', '#{right}'" }
    assert_includes UAT, "'cron.alter_job(bigint,text,text,text,text,boolean)'"
    refute_match(/(?:insert into|update|delete from) cron\./i, UAT.gsub("'update cron.job set active = false'", 'NEGATIVE_PRIVILEGE_ASSERTION'))
    assert_match(/\nrollback;\s*\z/, UAT)
    %w[anon authenticated service_role].each { |role| assert_includes UAT, "set local role #{role};" }
    assert_includes UAT, 'every business and historical financial table preserves all row hashes'
    assert_includes UAT, 'every original run-history row remains unchanged'
    assert_includes UAT, 'all three exact immutable receipts remain unchanged'
  end
end
