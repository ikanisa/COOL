require 'minitest/autorun'
class LegacyBankSchedulerSnapshotSourceTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  SQL = File.read(File.join(ROOT, 'scripts/tests/legacy_bank_scheduler_snapshot.sql'))
  def test_no_ambiguous_plpgsql_aggregation_identifiers
    refute_match(/string_agg\(h,|order by h\)/, SQL)
    assert_includes SQL, "string_agg(hashes.h, '' order by hashes.h)"
  end
  def test_snapshot_includes_three_private_receipts_and_per_job_history
    %w[postcommit_observations final_verifications canonical_history metadata_sha256].each { |key| assert_includes SQL, "'#{key}'" }
    assert_includes SQL, "c.relname not in ('legacy_bank_scheduler_retirements', 'legacy_bank_scheduler_observations', 'legacy_bank_scheduler_verifications')"
    assert_includes SQL, 'to_jsonb(j)'
    assert_includes SQL, 'to_jsonb(d)'
    assert_match(/\nrollback;\s*\z/, SQL)
    refute_match(/^commit;|(?:insert into|update|delete from) cron\./i, SQL)
  end
end
