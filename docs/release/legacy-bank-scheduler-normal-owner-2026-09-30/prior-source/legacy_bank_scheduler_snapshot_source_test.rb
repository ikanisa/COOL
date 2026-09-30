require 'minitest/autorun'
require 'digest'
require 'json'

# A targeted source regression guard, not PostgreSQL execution or SQL acceptance.
class LegacyBankSchedulerSnapshotSourceTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  PACKET = File.join(ROOT, 'docs/release/legacy-bank-scheduler-retirement-2026-09-30')
  PATH = 'scripts/tests/legacy_bank_scheduler_snapshot.sql'
  CURRENT = File.read(File.join(ROOT, PATH))
  ORIGINAL = File.read(File.join(PACKET, 'source-snapshot', PATH))

  def test_correction_is_limited_to_static_history_aggregate_qualification
    old = "'cron_history', (select jsonb_build_object('rows', count(*), 'sha256', encode(extensions.digest(coalesce(string_agg(h, '' order by h), ''), 'sha256'), 'hex'))"
    corrected = old.sub("string_agg(h, '' order by h)", "string_agg(hashes.h, '' order by hashes.h)")
    assert_equal 1, ORIGINAL.scan(old).length
    assert_equal ORIGINAL.sub(old, corrected), CURRENT
  end

  def test_static_history_query_cannot_bind_the_local_digest_variable
    history = CURRENT[/    'cron_history',.*?    'retirement_audit'/m]
    refute_nil history
    assert_includes CURRENT, 'h text;'
    assert_includes history, "string_agg(hashes.h, '' order by hashes.h)"
    refute_match(/string_agg\(h,|order by h\)/, history)
    assert_includes history, 'cron.job_run_details d) hashes)'
  end

  def test_frozen_migration_and_rollback_uat_are_unchanged
    expected = {
      'supabase/migrations/20260930110000_retire_legacy_bank_scheduler.sql' => 'a3e29f1314a4a94d1ef2bd19709aa745dca5f0e456bb70dab769d6b42c92ba85',
      'scripts/tests/legacy_bank_scheduler_retirement_uat.sql' => 'a190bffc1212c410a200e6b99d4db6910bf0cea5d948f535e7bb1640c4d25952'
    }
    expected.each { |path, sha| assert_equal sha, Digest::SHA256.file(File.join(ROOT, path)).hexdigest }
  end

  def test_original_packet_artifacts_remain_exactly_hash_bound
    assert_equal '442406af246108ac06926e290b513e7fb9572167c273cefc59cec2bd83b857de',
      Digest::SHA256.file(File.join(PACKET, 'artifact-manifest.json')).hexdigest
    entries = JSON.parse(File.read(File.join(PACKET, 'artifact-manifest.json'))).fetch('files')
    entries.each { |item| assert_equal item.fetch('sha256'), Digest::SHA256.file(File.join(PACKET, item.fetch('path'))).hexdigest, item.fetch('path') }
  end

  def test_corrected_snapshot_remains_guarded_and_rollback_only
    assert_includes CURRENT, "current_setting('collect.legacy_bank_scheduler_qa', true) is distinct from 'isolated_clone'"
    assert_includes CURRENT, "current_setting('cron.launch_active_jobs', true) is distinct from 'off'"
    assert_includes CURRENT, "current_setting('pg_net.batch_size', true) is distinct from '0'"
    assert_includes CURRENT, 'schema_migrations) = 142'
    assert_includes CURRENT, 'schema_migrations) = 143'
    assert_match(/\nrollback;\s*\z/, CURRENT)
    refute_match(/^commit;|alter system|cron\.alter_job|update cron\.job/i, CURRENT)
  end
end
