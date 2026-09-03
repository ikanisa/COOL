require 'minitest/autorun'
require 'tmpdir'
require_relative '../audits/collect_migration_history_review'

class CollectMigrationHistoryReviewTest < Minitest::Test
  def with_fixture
    Dir.mktmpdir('collect-history-review-') do |dir|
      File.write(File.join(dir,'202605230012_local_name.sql'), "select 1;\n")
      yield dir
    end
  end

  def test_preserves_mismatch_without_exporting_statement_bodies
    with_fixture do |dir|
      result = CollectMigrationHistoryReview.compare([
        {'version'=>'202605230012','name'=>'remote_name','statements'=>['select 2;']}
      ], dir).first
      assert_equal 'remote_name', result[:remote_name]
      refute result[:exact_joined_text_match]
      refute result[:whitespace_comment_insensitive_match]
      refute_includes JSON.generate(result), 'select 2'
      assert_equal Digest::SHA256.hexdigest('select 2;'), result[:remote_joined_sha256]
    end
  end

  def test_text_normalization_is_separate_from_raw_digest
    with_fixture do |dir|
      result = CollectMigrationHistoryReview.compare([
        {'version'=>'202605230012','name'=>'remote_name','statements'=>['select 1;']}
      ], dir).first
      refute result[:exact_joined_text_match]
      assert result[:whitespace_comment_insensitive_match]
    end
  end

  def test_missing_history_is_not_silently_accepted
    with_fixture do |dir|
      assert_raises(RuntimeError) do
        CollectMigrationHistoryReview.compare([{'version'=>'202605230012','name'=>'remote','statements'=>[]}],dir)
      end
      assert_raises(RuntimeError) do
        CollectMigrationHistoryReview.compare([{'version'=>'../bad','name'=>'remote','statements'=>['select 1;']}],dir)
      end
    end
  end
end
